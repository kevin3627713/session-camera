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

static BOOL PNCheckedMethod(NSMutableDictionary *checks, NSString *className, SEL selector, BOOL classMethod, char returnType, const char *arguments) {
    Class type = NSClassFromString(className);
    Method method = classMethod ? class_getClassMethod(type, selector) : class_getInstanceMethod(type, selector);
    BOOL matches = PNMethodMatches(type, selector, classMethod, returnType, arguments);
    NSString *key = [NSString stringWithFormat:@"%@[%@ %@]", classMethod ? @"+" : @"-", className, NSStringFromSelector(selector)];
    checks[key] = @{@"classAvailable": @(type != Nil), @"matches": @(matches),
        @"actualEncoding": method ? [NSString stringWithUTF8String:method_getTypeEncoding(method)] : @"missing"};
    return matches;
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

// System widgets use this parent runner with a database descriptor and a widget
// run request. Name lookup lets this isolated diagnostic reuse the user's
// shortcut without reading its private database or impersonating a system app.
@interface WFWorkflowDatabaseRunDescriptor : NSObject
- (instancetype)initWithName:(NSString *)name;
@end
@interface WFContentItem : NSObject
+ (instancetype)itemWithObject:(id)object;
@end
@interface WFContentCollection : NSObject
+ (instancetype)collectionWithItems:(NSArray *)items;
@end
@interface WFWorkflowRunRequest : NSObject
- (instancetype)initWithInput:(id)input presentationMode:(NSUInteger)mode;
- (void)setRunSource:(NSString *)source;
@end
@interface WFWorkflowRunnerClient : NSObject
- (instancetype)initWithDescriptor:(id)descriptor runRequest:(id)request delegateQueue:(dispatch_queue_t)queue;
- (void)setDelegate:(id)delegate;
- (id)runWorkflowWithRequest:(id)request descriptor:(id)descriptor completion:(void (^)(id))completion;
- (void)stop;
@end
@interface WFDevice : NSObject
+ (instancetype)currentDevice;
- (BOOL)hasSystemAperture;
@end
@interface WFWorkflowRunResult : NSObject
- (NSError *)error;
@end
@interface VCAccessSpecifier : NSObject
+ (instancetype)accessSpecifierForCurrentProcess;
- (BOOL)allowFullRuntimeAccess;
- (BOOL)allowReadAccessToShortcutsLibrary;
@end

@interface PNShortcutRunOperation : NSObject
@property(nonatomic, strong) WFWorkflowRunnerClient *runner;
@property(nonatomic, strong) dispatch_queue_t executionQueue;
@property(nonatomic, strong) NSMutableDictionary *metadata;
@property(nonatomic, copy) void (^completion)(NSDictionary *);
@property(nonatomic) BOOL finished;
@property(nonatomic) NSTimeInterval startTime;
- (void)finishWithError:(NSError *)error cancelled:(BOOL)cancelled stage:(NSString *)stage message:(NSString *)message;
@end

static NSMutableSet *PNShortcutRuns(void) {
    static NSMutableSet *operations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ operations = [NSMutableSet new]; });
    return operations; // Accessed only on the main queue.
}

@implementation PNShortcutRunOperation
- (void)finishWithError:(NSError *)error cancelled:(BOOL)cancelled stage:(NSString *)stage message:(NSString *)message {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self finishWithError:error cancelled:cancelled stage:stage message:message]; });
        return;
    }
    if (self.finished) return;
    self.finished = YES;
    NSMutableDictionary *result = [self.metadata mutableCopy];
    // A completed workflow still needs the owner's Photos UI observation.
    result[@"accepted"] = @([stage isEqual:@"workflow-completion"] && !error && !cancelled);
    result[@"cancelled"] = @(cancelled);
    result[@"stage"] = stage;
    result[@"elapsedSeconds"] = @(NSProcessInfo.processInfo.systemUptime - self.startTime);
    result[@"errorDomain"] = error.domain ?: @"PhotosNavigationProbe";
    result[@"errorCode"] = @(error.code);
    result[@"message"] = error.localizedDescription ?: message;
    result[@"originalError"] = PNErrorJSON(error, 8);
    void (^callback)(NSDictionary *) = self.completion;
    self.completion = nil;
    @try {
        [self.runner setDelegate:nil];
        if (![stage isEqual:@"workflow-completion"] && self.runner && self.executionQueue) {
            WFWorkflowRunnerClient *runner = self.runner;
            // Cancellation follows any in-flight synchronous runner connection.
            dispatch_async(self.executionQueue, ^{ @try { [runner stop]; } @catch (__unused NSException *exception) { } });
        }
    } @catch (__unused NSException *exception) { }
    self.runner = nil;
    [PNShortcutRuns() removeObject:self];
    if (callback) callback(result);
}
- (void)workflowRunnerClient:(id)client didFinishRunningWorkflowWithOutput:(id)output error:(NSError *)error cancelled:(BOOL)cancelled {
    [self finishWithError:error cancelled:cancelled stage:@"workflow-completion" message:@"执行器已完成；请核对实际照片与相册"];
}
- (void)workflowRunnerClient:(id)client didFinishRunningWorkflowWithAllResults:(id)output error:(NSError *)error cancelled:(BOOL)cancelled {
    [self finishWithError:error cancelled:cancelled stage:@"workflow-completion" message:@"执行器已完成；请核对实际照片与相册"];
}
@end

void PNShortcutRunnerDispatch(NSURL *url, NSString *shortcutName, NSString *callerContext, void (^completion)(NSDictionary *)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ PNShortcutRunnerDispatch(url, shortcutName, callerContext, completion); });
        return;
    }
    PNShortcutRunOperation *operation = [PNShortcutRunOperation new];
    operation.completion = completion;
    operation.startTime = NSProcessInfo.processInfo.systemUptime;
    operation.executionQueue = dispatch_queue_create("PhotosNavigationProbe.ShortcutExecution", DISPATCH_QUEUE_SERIAL);
    operation.metadata = [@{@"engine": @"WFWorkflowRunnerClient (widget request)",
        @"bundle": NSBundle.mainBundle.bundleIdentifier ?: @"unknown", @"callerContext": callerContext,
        @"shortcutName": shortcutName ?: @"", @"runSource": @"widget",
        @"input": @"Complete Photos URL as text", @"usesShortcutsURLScheme": @NO,
        @"selector": @"runWorkflowWithRequest:descriptor:completion:"} mutableCopy];
    [PNShortcutRuns() addObject:operation];
    @try {
        if (![url isKindOfClass:NSURL.class] ||
            ![@[@"photos", @"photos-navigation", @"photos-redirect"] containsObject:url.scheme.lowercaseString] ||
            !url.host.length || [url.absoluteString lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 16384 ||
            ![shortcutName isKindOfClass:NSString.class] || !shortcutName.length ||
            [shortcutName lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 1024) {
            [operation finishWithError:nil cancelled:NO stage:@"validation" message:@"照片链接或快捷指令名称无效"];
            return;
        }
        static void *workflowHandle, *clientHandle, *contentHandle;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            contentHandle = dlopen("/System/Library/PrivateFrameworks/ContentKit.framework/ContentKit", RTLD_LAZY);
            clientHandle = dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient", RTLD_LAZY);
            workflowHandle = dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_LAZY);
        });
        Class descriptorType = NSClassFromString(@"WFWorkflowDatabaseRunDescriptor");
        Class itemType = NSClassFromString(@"WFContentItem");
        Class collectionType = NSClassFromString(@"WFContentCollection");
        Class requestType = NSClassFromString(@"WFWorkflowRunRequest");
        Class runnerType = NSClassFromString(@"WFWorkflowRunnerClient");
        NSMutableDictionary *checks = [NSMutableDictionary new];
        BOOL available = workflowHandle && clientHandle && contentHandle;
        available &= PNCheckedMethod(checks, @"WFWorkflowDatabaseRunDescriptor", @selector(initWithName:), NO, '@', "@");
        available &= PNCheckedMethod(checks, @"WFContentItem", @selector(itemWithObject:), YES, '@', "@");
        available &= PNCheckedMethod(checks, @"WFContentCollection", @selector(collectionWithItems:), YES, '@', "@");
        available &= PNCheckedMethod(checks, @"WFWorkflowRunRequest", @selector(initWithInput:presentationMode:), NO, '@', "@Q");
        available &= PNCheckedMethod(checks, @"WFWorkflowRunRequest", @selector(setRunSource:), NO, 'v', "@");
        available &= PNCheckedMethod(checks, @"WFWorkflowRunnerClient", @selector(initWithDescriptor:runRequest:delegateQueue:), NO, '@', "@@@");
        available &= PNCheckedMethod(checks, @"WFWorkflowRunnerClient", @selector(setDelegate:), NO, 'v', "@");
        available &= PNCheckedMethod(checks, @"WFWorkflowRunnerClient", @selector(runWorkflowWithRequest:descriptor:completion:), NO, '@', "@@@");
        available &= PNCheckedMethod(checks, @"WFWorkflowRunnerClient", @selector(stop), NO, 'v', "");
        operation.metadata[@"interfaceChecks"] = checks;
        operation.metadata[@"frameworksLoaded"] = @{@"WorkflowKit": @(workflowHandle != NULL),
            @"VoiceShortcutClient": @(clientHandle != NULL), @"ContentKit": @(contentHandle != NULL)};
        if (!available) {
            [operation finishWithError:nil cancelled:NO stage:@"availability" message:@"此系统的快捷指令执行器不可用或方法签名不匹配"];
            return;
        }
        Class accessType = NSClassFromString(@"VCAccessSpecifier");
        if (PNMethodMatches(accessType, @selector(accessSpecifierForCurrentProcess), YES, '@', "") &&
            PNMethodMatches(accessType, @selector(allowFullRuntimeAccess), NO, 'B', "") &&
            PNMethodMatches(accessType, @selector(allowReadAccessToShortcutsLibrary), NO, 'B', "")) {
            VCAccessSpecifier *access = [accessType accessSpecifierForCurrentProcess];
            operation.metadata[@"callerCapabilities"] = @{@"fullRuntimeAccess": @([access allowFullRuntimeAccess]),
                @"shortcutsLibraryReadAccess": @([access allowReadAccessToShortcutsLibrary])};
        }
        NSUInteger mode = 0;
        Class deviceType = NSClassFromString(@"WFDevice");
        if (PNMethodMatches(deviceType, @selector(currentDevice), YES, '@', "") &&
            PNMethodMatches(deviceType, @selector(hasSystemAperture), NO, 'B', "")) {
            mode = [[deviceType currentDevice] hasSystemAperture] ? 1 : 0;
        }
        operation.metadata[@"presentationMode"] = @(mode);
        WFWorkflowDatabaseRunDescriptor *descriptor = [[descriptorType alloc] initWithName:shortcutName];
        WFContentItem *item = [itemType itemWithObject:url.absoluteString];
        WFContentCollection *input = item ? [collectionType collectionWithItems:@[item]] : nil;
        WFWorkflowRunRequest *request = input ? [[requestType alloc] initWithInput:input presentationMode:mode] : nil;
        [request setRunSource:@"widget"];
        operation.runner = descriptor && request ? [[runnerType alloc] initWithDescriptor:descriptor runRequest:request delegateQueue:dispatch_get_main_queue()] : nil;
        if (!operation.runner) {
            [operation finishWithError:nil cancelled:NO stage:@"initialization" message:@"无法创建名称查询、文本输入或执行器"];
            return;
        }
        [operation.runner setDelegate:operation];
        __weak PNShortcutRunOperation *weakOperation = operation;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [weakOperation finishWithError:nil cancelled:NO stage:@"timeout" message:@"快捷指令执行器请求超时"];
        });
        WFWorkflowRunnerClient *runner = operation.runner;
        // The shared runner's request entry avoids its start() progress assertion
        // on an immediate XPC failure. Own the client until completion/timeout.
        dispatch_async(operation.executionQueue, ^{
            @try {
                [runner runWorkflowWithRequest:request descriptor:descriptor completion:^(id result) {
                    // Device versions may use this callback as well as the delegate.
                    NSMethodSignature *signature = [result methodSignatureForSelector:@selector(error)];
                    if (signature.numberOfArguments == 2 && signature.methodReturnType[0] == '@') {
                        NSError *error = [(WFWorkflowRunResult *)result error];
                        if ([error isKindOfClass:NSError.class]) {
                            [weakOperation finishWithError:error cancelled:NO stage:@"workflow-completion" message:@""];
                        }
                    }
                }];
            } @catch (NSException *exception) {
                [weakOperation finishWithError:nil cancelled:NO stage:@"exception" message:[NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]];
            }
        });
    } @catch (NSException *exception) {
        [operation finishWithError:nil cancelled:NO stage:@"exception" message:[NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]];
    }
}
