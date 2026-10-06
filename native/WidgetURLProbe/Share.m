#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Dispatch.h"

static void SCDispatchInput(id context) {
    if (![context respondsToSelector:@selector(inputItems)]) return;
    NSExtensionItem *item = ((NSExtensionContext *)context).inputItems.firstObject;
    NSURL *url = item.userInfo[@"probeURL"];
    if (![url isKindOfClass:NSURL.class] || ![url.scheme isEqualToString:@"photos-navigation"]) return;
    static const char handled;
    if (objc_getAssociatedObject(context, &handled)) return;
    objc_setAssociatedObject(context, &handled, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSLog(@"SCURLPROBE share received input");
        SCProbeDispatch(@"direct", url);
    });
}

// The host callback is the headless entry observed in LiveContainer's current
// source. The research probe does not import its UI, App Groups or guest loader.
static void (*originalCallback)(id, SEL, id);
static void SCProbeHostCallback(id context, SEL selector, id callback) {
    SCDispatchInput(context);
    originalCallback(context, selector, callback);
}
__attribute__((constructor)) static void SCInstallProbeCallback(void) {
    Class type = NSClassFromString(@"EXExtensionContextImplementation");
    SEL selector = NSSelectorFromString(@"_willPerformHostCallback:");
    Method method = type ? class_getInstanceMethod(type, selector) : NULL;
    if (method) {
        originalCallback = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)SCProbeHostCallback);
    }
    NSLog(@"SCURLPROBE share callback installed=%d", method != NULL);
}

@interface ProbeShareController : UIViewController
@end
@implementation ProbeShareController
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    NSLog(@"SCURLPROBE share beginRequest");
    SCDispatchInput(context);
}
@end
