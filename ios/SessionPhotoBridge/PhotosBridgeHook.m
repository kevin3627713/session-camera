#import "PhotosBridgeHook.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openURL:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
@end

NSDictionary *SCPhotoBridgeInput(NSObject *context) {
    @try {
        if (![context respondsToSelector:@selector(inputItems)]) return nil;
        NSArray *items = [(NSExtensionContext *)context inputItems];
        if (![items isKindOfClass:NSArray.class] || items.count != 1 || ![items.firstObject isKindOfClass:NSExtensionItem.class]) return nil;
        NSDictionary *value = ((NSExtensionItem *)items.firstObject).userInfo;
        // Ignore empty/system-only placeholders until our request is attached.
        if (![value isKindOfClass:NSDictionary.class] ||
            (!value[SCPhotoBridgeAssetKey] && !value[SCPhotoBridgeCloudKey] && !value[SCPhotoBridgeNonceKey])) return nil;
        return [value copy];
    } @catch (__unused NSException *exception) { return nil; }
}

BOOL SCPhotoBridgeClaimContext(NSObject *context) {
    static const char handled;
    // The private implementation and principal controller can refer to the same
    // public extension context. Claim that object once across both entry points.
    NSObject *owner = context;
    @try {
        if ([context respondsToSelector:@selector(extensionContext)]) {
            id publicContext = [(id)context extensionContext];
            if ([publicContext isKindOfClass:NSObject.class]) owner = publicContext;
        }
    } @catch (__unused NSException *exception) { }
    @synchronized (owner) {
        if (objc_getAssociatedObject(owner, &handled)) return NO;
        objc_setAssociatedObject(owner, &handled, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
}

BOOL SCPhotoBridgeDispatchURL(NSURL *url, NSError **error) {
    @try {
        // The Swift resolver creates the only accepted route from real PhotoKit
        // mappings. Do not turn this extension into a general URL launcher.
        if (![url.scheme isEqualToString:@"photos-navigation"] || ![url.host isEqualToString:@"asset"]) return NO;
        Class type = NSClassFromString(@"LSApplicationWorkspace");
        if (!type || ![type respondsToSelector:@selector(defaultWorkspace)]) return NO;
        LSApplicationWorkspace *workspace = [type defaultWorkspace];
        if (![workspace respondsToSelector:@selector(openURL:withOptions:error:)]) return NO;
        return [workspace openURL:url withOptions:@{} error:error];
    } @catch (__unused NSException *exception) { return NO; }
}

void SCPhotoBridgeFinishContext(NSObject *context, NSDictionary *result, NSError *error) {
    @try {
        if (error) {
            if ([context respondsToSelector:@selector(cancelRequestWithError:)]) [(NSExtensionContext *)context cancelRequestWithError:error];
        } else if ([context respondsToSelector:@selector(completeRequestReturningItems:completionHandler:)]) {
            NSExtensionItem *item = [NSExtensionItem new];
            item.userInfo = result ?: @{};
            [(NSExtensionContext *)context completeRequestReturningItems:@[item] completionHandler:nil];
        }
    } @catch (__unused NSException *exception) { }
}

static void SCHandleContext(id context) {
    Class handler = NSClassFromString(@"SCPhotosBridgeRequest");
    SEL selector = NSSelectorFromString(@"handleContext:");
    if ([handler respondsToSelector:selector]) ((void (*)(id, SEL, id))objc_msgSend)(handler, selector, context);
}

static void (*SCOriginalHostCallback)(id, SEL, id);
static void SCHostCallback(id context, SEL selector, id callback) {
    SCOriginalHostCallback(context, selector, callback);
    SCHandleContext(context);
}
__attribute__((constructor)) static void SCInstallPhotosBridgeHook(void) {
    Class type = NSClassFromString(@"EXExtensionContextImplementation");
    SEL selector = NSSelectorFromString(@"_willPerformHostCallback:");
    Method method = type ? class_getInstanceMethod(type, selector) : NULL;
    NSMethodSignature *signature = method ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)] : nil;
    if (signature.numberOfArguments != 3 || strcmp(signature.methodReturnType, @encode(void)) != 0 ||
        [signature getArgumentTypeAtIndex:2][0] != '@') return;
    SCOriginalHostCallback = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)SCHostCallback);
}

@interface SessionPhotosBridgeController : UIViewController
@end
@implementation SessionPhotosBridgeController
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context { SCHandleContext(context); }
- (void)viewDidLoad { [super viewDidLoad]; if (self.extensionContext) SCHandleContext(self.extensionContext); }
@end
