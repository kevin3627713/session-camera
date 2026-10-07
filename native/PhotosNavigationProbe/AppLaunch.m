#import "ProbeBridge.h"
#import <objc/runtime.h>
#include <dlfcn.h>
#include <string.h>

// The same launch-request superclass used by Shortcuts' WFAppLaunchRequest.
// Resolve classes at runtime; the request keeps this process's real identity.
@interface INCAppLaunchRequest : NSObject
- (instancetype)initWithBundleIdentifier:(NSString *)identifier options:(NSDictionary *)options
    URL:(NSURL *)url userActivity:(NSUserActivity *)activity retainsSiri:(BOOL)retainsSiri;
- (void)performWithService:(id)service retainsSiri:(BOOL)retainsSiri
    completionHandler:(void (^)(BOOL, NSError *))completion;
@end
@interface FBSOpenApplicationService : NSObject
+ (instancetype)serviceWithDefaultShellEndpoint;
@end

static NSString *PNBoundedString(NSString *value) {
    return value.length > 4096 ? [[value substringToIndex:4096] stringByAppendingString:@"…"] : value;
}

// Preserve the original NSError, including nested rejection reasons, in JSON.
// Depth and collection bounds also handle cycles and non-JSON userInfo values.
static id PNErrorJSON(id value, NSUInteger depth) {
    if (!value || value == NSNull.null) return NSNull.null;
    if ([value isKindOfClass:NSString.class]) return PNBoundedString(value);
    if ([value isKindOfClass:NSNumber.class]) return value;
    if (!depth) return @"[depth limit]";
    if ([value isKindOfClass:NSError.class]) {
        NSError *error = value;
        return @{@"domain": error.domain ?: @"", @"code": @(error.code),
                 @"description": PNBoundedString(error.localizedDescription ?: @""),
                 @"failureReason": PNBoundedString(error.localizedFailureReason ?: @""),
                 @"userInfo": PNErrorJSON(error.userInfo, depth - 1)};
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary new];
        NSUInteger count = 0;
        for (id key in value) {
            if (count++ == 32) { result[@"[truncated]"] = @YES; break; }
            result[PNBoundedString([key description])] = PNErrorJSON(value[key], depth - 1);
        }
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray new];
        for (id item in value) {
            if (result.count == 16) { [result addObject:@"[truncated]"]; break; }
            [result addObject:PNErrorJSON(item, depth - 1)];
        }
        return result;
    }
    return PNBoundedString([value description]);
}

static BOOL PNMethodMatches(Class type, SEL selector, BOOL classMethod, char returnType, const char *arguments) {
    Method method = classMethod ? class_getClassMethod(type, selector) : class_getInstanceMethod(type, selector);
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    NSUInteger count = strlen(arguments);
    if (signature.numberOfArguments != count + 2 || signature.methodReturnType[0] != returnType) return NO;
    for (NSUInteger i = 0; i < count; i++) {
        char actual = [signature getArgumentTypeAtIndex:i + 2][0];
        if (arguments[i] == 'B') { if (actual != 'B' && actual != 'c') return NO; }
        else if (actual != arguments[i]) return NO;
    }
    return YES;
}

@interface PNAppLaunchOperation : NSObject
@property(nonatomic, strong) INCAppLaunchRequest *request;
@property(nonatomic, strong) FBSOpenApplicationService *service;
@property(nonatomic, strong) NSMutableDictionary *metadata;
@property(nonatomic, copy) void (^completion)(NSDictionary *);
@property(nonatomic) BOOL finished;
- (void)finishAccepted:(BOOL)accepted error:(NSError *)error stage:(NSString *)stage message:(NSString *)message;
@end

static NSMutableSet *PNAppLaunchOperations(void) {
    static NSMutableSet *operations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ operations = [NSMutableSet new]; });
    return operations; // Accessed only on the main queue.
}

@implementation PNAppLaunchOperation
- (void)finishAccepted:(BOOL)accepted error:(NSError *)error stage:(NSString *)stage message:(NSString *)message {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self finishAccepted:accepted error:error stage:stage message:message]; });
        return;
    }
    if (self.finished) return;
    self.finished = YES;
    NSMutableDictionary *result = [self.metadata mutableCopy];
    result[@"accepted"] = @(accepted);
    result[@"stage"] = stage;
    result[@"errorDomain"] = error.domain ?: @"PhotosNavigationProbe";
    result[@"errorCode"] = @(error.code);
    result[@"message"] = error.localizedDescription ?: message;
    result[@"originalError"] = PNErrorJSON(error, 8);
    void (^callback)(NSDictionary *) = self.completion;
    self.completion = nil;
    self.request = nil;
    self.service = nil;
    [PNAppLaunchOperations() removeObject:self];
    if (callback) callback(result);
}
@end

void PNFrontBoardDispatch(NSURL *url, NSString *callerContext, void (^completion)(NSDictionary *)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ PNFrontBoardDispatch(url, callerContext, completion); });
        return;
    }
    PNAppLaunchOperation *operation = [PNAppLaunchOperation new];
    operation.completion = completion;
    operation.metadata = [@{@"engine": @"INCAppLaunchRequest → FrontBoard",
        @"bundle": NSBundle.mainBundle.bundleIdentifier ?: @"unknown",
        @"targetBundle": @"com.apple.mobileslideshow", @"callerContext": callerContext,
        @"selector": @"performWithService:retainsSiri:completionHandler:"} mutableCopy];
    [PNAppLaunchOperations() addObject:operation];
    @try {
        if (![url isKindOfClass:NSURL.class] ||
            ![@[@"photos", @"photos-navigation", @"photos-redirect"] containsObject:url.scheme.lowercaseString] ||
            !url.host.length || [url.absoluteString lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 16384) {
            [operation finishAccepted:NO error:nil stage:@"validation" message:@"只接受 Photos 测试链接"];
            return;
        }
        static void *intentsHandle, *frontBoardHandle;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            intentsHandle = dlopen("/System/Library/PrivateFrameworks/IntentsCore.framework/IntentsCore", RTLD_LAZY);
            frontBoardHandle = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
        });
        Class requestType = NSClassFromString(@"INCAppLaunchRequest");
        Class serviceType = NSClassFromString(@"FBSOpenApplicationService");
        SEL initializer = @selector(initWithBundleIdentifier:options:URL:userActivity:retainsSiri:);
        SEL perform = @selector(performWithService:retainsSiri:completionHandler:);
        if (!intentsHandle || !frontBoardHandle || !requestType || !serviceType ||
            !PNMethodMatches(requestType, initializer, NO, '@', "@@@@B") ||
            !PNMethodMatches(requestType, perform, NO, 'v', "@B@") ||
            !PNMethodMatches(serviceType, @selector(serviceWithDefaultShellEndpoint), YES, '@', "")) {
            [operation finishAccepted:NO error:nil stage:@"availability" message:@"此系统的直接启动接口不可用或签名不匹配"];
            return;
        }
        operation.service = [serviceType serviceWithDefaultShellEndpoint];
        operation.request = [[requestType alloc] initWithBundleIdentifier:@"com.apple.mobileslideshow"
            options:@{} URL:url userActivity:nil retainsSiri:NO];
        if (!operation.request || !operation.service) {
            [operation finishAccepted:NO error:nil stage:@"initialization" message:@"无法创建系统照片启动请求"];
            return;
        }
        __weak PNAppLaunchOperation *weakOperation = operation;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [weakOperation finishAccepted:NO error:nil stage:@"timeout" message:@"直接启动请求超时"];
        });
        [operation.request performWithService:operation.service retainsSiri:NO completionHandler:^(BOOL accepted, NSError *error) {
            [weakOperation finishAccepted:accepted error:error stage:@"dispatch" message:@""];
        }];
    } @catch (NSException *exception) {
        [operation finishAccepted:NO error:nil stage:@"exception" message:[NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]];
    }
}
