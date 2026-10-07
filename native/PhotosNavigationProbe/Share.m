#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ProbeBridge.h"

static BOOL PNHookInstalled;
static void PNHandleContext(id context) {
    @try {
        if (![context respondsToSelector:@selector(inputItems)]) return;
        NSDictionary *input;
        for (id item in [(NSExtensionContext *)context inputItems]) {
            if (![item isKindOfClass:NSExtensionItem.class]) continue;
            NSDictionary *value = [item userInfo];
            if ([value[@"probeNonce"] isKindOfClass:NSString.class]) { input = value; break; }
        }
        if (!input) return; // System-only items can precede the real input.
        id owner = context;
        if ([context respondsToSelector:@selector(extensionContext)]) {
            id publicContext = [context extensionContext];
            if (publicContext) owner = publicContext;
        }
        static const char handled;
        @synchronized (owner) {
            if (objc_getAssociatedObject(owner, &handled)) return;
            objc_setAssociatedObject(owner, &handled, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (![input[@"probeURL"] isKindOfClass:NSString.class] ||
            ![input[@"probeSensitive"] isKindOfClass:NSNumber.class] ||
            ![[NSUUID alloc] initWithUUIDString:input[@"probeNonce"]]) {
            [(NSExtensionContext *)owner cancelRequestWithError:[NSError errorWithDomain:@"PhotosNavigationProbe" code:2
                userInfo:@{NSLocalizedDescriptionKey: @"诊断中转请求无效"}]];
            return;
        }
        NSURL *url = [NSURL URLWithString:input[@"probeURL"]];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableDictionary *result = [PNWorkspaceDispatch(url, [input[@"probeSensitive"] boolValue]) mutableCopy];
            result[@"hostHookInstalled"] = @(PNHookInstalled);
            NSExtensionItem *reply = [NSExtensionItem new];
            reply.userInfo = @{@"probeNonce": input[@"probeNonce"], @"probeResult": result};
            [(NSExtensionContext *)owner completeRequestReturningItems:@[reply] completionHandler:nil];
        });
    } @catch (NSException *exception) {
        if ([context respondsToSelector:@selector(cancelRequestWithError:)])
            [(NSExtensionContext *)context cancelRequestWithError:[NSError errorWithDomain:@"PhotosNavigationProbe" code:3
                userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name}]];
    }
}
static void (*PNOriginalCallback)(id, SEL, id);
static void PNHostCallback(id context, SEL selector, id callback) {
    PNOriginalCallback(context, selector, callback);
    PNHandleContext(context);
}
__attribute__((constructor)) static void PNInstallHook(void) {
    Class type = NSClassFromString(@"EXExtensionContextImplementation");
    SEL selector = NSSelectorFromString(@"_willPerformHostCallback:");
    Method method = type ? class_getInstanceMethod(type, selector) : NULL;
    NSMethodSignature *signature = method ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)] : nil;
    if (signature.numberOfArguments != 3 || signature.methodReturnType[0] != 'v' ||
        [signature getArgumentTypeAtIndex:2][0] != '@') return;
    PNOriginalCallback = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)PNHostCallback);
    PNHookInstalled = YES;
}
@interface PhotosNavigationShareController : UIViewController
@end
@implementation PhotosNavigationShareController
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context { PNHandleContext(context); }
- (void)viewDidLoad { [super viewDidLoad]; if (self.extensionContext) PNHandleContext(self.extensionContext); }
@end
