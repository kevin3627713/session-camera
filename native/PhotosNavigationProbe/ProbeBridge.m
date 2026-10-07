#import "ProbeBridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openURL:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
@end
@interface NSExtension : NSObject
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))callback;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *, NSArray *))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *, NSError *))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *))block;
- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)identifier;
@end

static BOOL PNAllowedURL(NSURL *url) {
    return [url isKindOfClass:NSURL.class] &&
        [@[@"photos", @"photos-navigation", @"photos-redirect"] containsObject:url.scheme.lowercaseString] &&
        url.host.length && [url.absoluteString lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 16384;
}
static NSDictionary *PNFailure(NSString *stage, NSError *error, NSString *message) {
    return @{@"accepted": @NO, @"stage": stage, @"errorDomain": error.domain ?: @"PhotosNavigationProbe",
             @"errorCode": @(error.code), @"message": error.localizedDescription ?: message,
             @"bundle": NSBundle.mainBundle.bundleIdentifier ?: @"unknown"};
}

NSDictionary *PNInspectURL(NSURL *url) {
    @try {
        static void *handle;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            handle = dlopen("/System/Library/PrivateFrameworks/PhotosUICore.framework/PhotosUICore", RTLD_LAZY);
        });
        Class type = NSClassFromString(@"PXProgrammaticNavigationDestination");
        SEL initializer = NSSelectorFromString(@"initWithURL:");
        if (!handle || !type || ![type instancesRespondToSelector:initializer])
            return @{@"available": @NO, @"message": @"系统导航解析器不可用；仍可测试 URL 派发"};
        id destination = ((id (*)(id, SEL, id))objc_msgSend)([type alloc], initializer, url);
        NSMutableDictionary *result = [@{@"available": @(destination != nil), @"class": NSStringFromClass(type)} mutableCopy];
        for (NSString *key in @[@"type", @"revealMode"]) {
            SEL selector = NSSelectorFromString(key);
            NSMethodSignature *signature = [destination methodSignatureForSelector:selector];
            if (signature.numberOfArguments == 2 && signature.methodReturnLength == sizeof(int64_t))
                result[key] = @(((int64_t (*)(id, SEL))objc_msgSend)(destination, selector));
        }
        for (NSString *key in @[@"assetUUID", @"assetLocalIdentifier", @"assetCloudIdentifier",
                                @"assetCollectionUUID", @"assetCollectionLocalIdentifier", @"assetCollectionCloudIdentifier",
                                @"collectionListUUID", @"publicDescription"]) {
            SEL selector = NSSelectorFromString(key);
            NSMethodSignature *signature = [destination methodSignatureForSelector:selector];
            if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') continue;
            id value = ((id (*)(id, SEL))objc_msgSend)(destination, selector);
            if (!value) { result[key] = NSNull.null; continue; }
            if ([value isKindOfClass:NSString.class]) result[key] = value;
            else if ([value respondsToSelector:@selector(stringValue)]) result[key] = [value stringValue] ?: @"";
            else result[key] = [value description];
        }
        return result;
    } @catch (NSException *exception) {
        return @{@"available": @NO, @"exception": exception.name, @"message": exception.reason ?: @"解析失败"};
    }
}

NSDictionary *PNWorkspaceDispatch(NSURL *url, BOOL sensitive) {
    @try {
        if (!PNAllowedURL(url)) return PNFailure(@"validation", nil, @"只接受 Photos 测试链接");
        Class type = NSClassFromString(@"LSApplicationWorkspace");
        if (!type || ![type respondsToSelector:@selector(defaultWorkspace)])
            return PNFailure(@"workspace", nil, @"LSApplicationWorkspace 不可用");
        LSApplicationWorkspace *workspace = [type defaultWorkspace];
        SEL selector = sensitive ? @selector(openSensitiveURL:withOptions:error:) : @selector(openURL:withOptions:error:);
        if (![workspace respondsToSelector:selector]) return PNFailure(@"selector", nil, NSStringFromSelector(selector));
        NSError *error = nil;
        BOOL accepted = sensitive ? [workspace openSensitiveURL:url withOptions:@{} error:&error] :
            [workspace openURL:url withOptions:@{} error:&error];
        NSMutableDictionary *result = [PNFailure(@"dispatch", error, @"") mutableCopy];
        result[@"accepted"] = @(accepted);
        result[@"selector"] = NSStringFromSelector(selector);
        return result;
    } @catch (NSException *exception) {
        return PNFailure(@"exception", nil, [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]);
    }
}

@interface PNShareRequest : NSObject
@property(nonatomic, strong) NSExtension *extension;
@property(nonatomic, strong) NSUUID *requestID;
@property(nonatomic, copy) NSString *nonce;
@property(nonatomic, copy) void (^completion)(NSDictionary *);
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL cancellationRequested;
- (void)finish:(NSDictionary *)result cancel:(BOOL)cancel;
@end
static NSMutableSet *PNRequests(void) {
    static NSMutableSet *requests;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ requests = [NSMutableSet new]; });
    return requests;
}
@implementation PNShareRequest
- (void)finish:(NSDictionary *)result cancel:(BOOL)cancel {
    void (^callback)(NSDictionary *);
    NSExtension *extension;
    NSUUID *requestID;
    @synchronized (self) {
        if (self.finished) return;
        self.finished = YES;
        self.cancellationRequested = cancel;
        callback = self.completion;
        self.completion = nil;
        extension = self.extension;
        requestID = self.requestID;
        self.extension = nil;
    }
    @try {
        [extension setRequestCompletionBlock:nil];
        [extension setRequestCancellationBlock:nil];
        [extension setRequestInterruptionBlock:nil];
        if (cancel && requestID) [extension cancelExtensionRequestWithIdentifier:requestID];
    } @catch (__unused NSException *exception) { }
    @synchronized (PNRequests()) { [PNRequests() removeObject:self]; }
    if (callback) callback(result);
}
@end

static void PNDispatchShare(NSURL *url, BOOL sensitive, NSString *engine, NSString *shortcutName, void (^completion)(NSDictionary *)) {
    PNShareRequest *request = [PNShareRequest new];
    request.completion = completion;
    request.nonce = NSUUID.UUID.UUIDString;
    @synchronized (PNRequests()) { [PNRequests() addObject:request]; }
    @try {
        if (!PNAllowedURL(url)) { [request finish:PNFailure(@"validation", nil, @"无效链接") cancel:NO]; return; }
        NSURL *infoURL = [NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"PlugIns/PhotosNavigationShare.appex/Info.plist"];
        NSString *identifier = [NSDictionary dictionaryWithContentsOfURL:infoURL][@"CFBundleIdentifier"];
        if (!identifier.length) { [request finish:PNFailure(@"discovery", nil, @"中转扩展缺失，请重签并保留扩展") cancel:NO]; return; }
        Class type = NSClassFromString(@"NSExtension");
        if (![type respondsToSelector:@selector(extensionWithIdentifier:error:)]) {
            [request finish:PNFailure(@"discovery", nil, @"NSExtension 不可用") cancel:NO]; return;
        }
        NSError *error = nil;
        NSExtension *extension = [type extensionWithIdentifier:identifier error:&error];
        for (NSString *selector in @[@"beginExtensionRequestWithInputItems:completion:", @"setRequestCompletionBlock:",
                                    @"setRequestCancellationBlock:", @"setRequestInterruptionBlock:", @"cancelExtensionRequestWithIdentifier:"]) {
            if (![extension respondsToSelector:NSSelectorFromString(selector)]) {
                [request finish:PNFailure(@"discovery", error, @"中转扩展启动接口不可用") cancel:NO]; return;
            }
        }
        request.extension = extension;
        __weak PNShareRequest *weakRequest = request;
        __weak NSExtension *weakExtension = extension;
        [extension setRequestCompletionBlock:^(NSUUID *uuid, NSArray *items) {
            PNShareRequest *owner = weakRequest;
            if (!owner) return;
            NSDictionary *result;
            for (id item in items) {
                if (![item isKindOfClass:NSExtensionItem.class]) continue;
                NSDictionary *value = [item userInfo];
                if ([value[@"probeNonce"] isEqual:owner.nonce] && [value[@"probeResult"] isKindOfClass:NSDictionary.class]) {
                    result = value[@"probeResult"]; break;
                }
            }
            [owner finish:result ?: PNFailure(@"reply", nil, @"中转扩展返回数据无效") cancel:NO];
        }];
        [extension setRequestCancellationBlock:^(NSUUID *uuid, NSError *error) {
            [weakRequest finish:PNFailure(@"cancelled", error, @"中转请求取消") cancel:NO];
        }];
        [extension setRequestInterruptionBlock:^(NSUUID *uuid) {
            [weakRequest finish:PNFailure(@"interrupted", nil, @"中转请求中断") cancel:NO];
        }];
        NSExtensionItem *item = [NSExtensionItem new];
        item.userInfo = @{@"probeNonce": request.nonce, @"probeURL": url.absoluteString, @"probeSensitive": @(sensitive),
                          @"probeEngine": engine, @"probeShortcutName": shortcutName ?: @""};
        [extension beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *uuid) {
            BOOL finished, cancel;
            @synchronized (request) {
                finished = request.finished; cancel = request.cancellationRequested; request.requestID = uuid;
            }
            if (finished) { if (cancel && uuid) [weakExtension cancelExtensionRequestWithIdentifier:uuid]; return; }
            if (!uuid) [request finish:PNFailure(@"start", nil, @"中转扩展启动失败") cancel:NO];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ([engine isEqual:@"workspace"] ? 15 : 20) * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [weakRequest finish:PNFailure(@"timeout", nil, @"中转请求超时") cancel:YES];
        });
    } @catch (NSException *exception) {
        [request finish:PNFailure(@"exception", nil, exception.reason ?: exception.name) cancel:YES];
    }
}

void PNDispatchThroughShare(NSURL *url, BOOL sensitive, void (^completion)(NSDictionary *)) {
    PNDispatchShare(url, sensitive, @"workspace", nil, completion);
}

void PNDispatchFrontBoardThroughShare(NSURL *url, void (^completion)(NSDictionary *)) {
    PNDispatchShare(url, NO, @"frontboard", nil, completion);
}

void PNDispatchShortcutRunnerThroughShare(NSURL *url, NSString *shortcutName, void (^completion)(NSDictionary *)) {
    PNDispatchShare(url, NO, @"shortcut-runner", shortcutName, completion);
}
