#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "WidgetBackgroundHook.h"

// Inspect the actual iOS 18 simulator framework, not the fake unit-test classes.
// A passing report proves runtime availability, not transparent rendering.
static BOOL Inspect(const char *name, NSString *selectorName) {
    Class cls = NSClassFromString(@(name));
    Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(selectorName)) : NULL;
    printf("%s %s: %s\n", name, selectorName.UTF8String,
           method ? method_getTypeEncoding(method) : "UNAVAILABLE");
    return method != NULL;
}
int main(void) {
    @autoreleasepool {
        printf("Actual simulator OS: %s\n", NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
        BOOL available = Inspect("_TtCC9WidgetKit24WidgetExtensionXPCServer14ExportedObject", @"getAllCurrentDescriptorsWithCompletion:");
        available &= Inspect("_TtC9WidgetKit21DescriptorFetchResult", @"initWithCoder:");
        for (NSString *name in @[@"CHSBaseDescriptor", @"CHSControlDescriptor", @"CHSWidgetDescriptor"]) {
            BOOL present = NSClassFromString(name) != Nil;
            printf("%s: %s\n", name.UTF8String, present ? "AVAILABLE" : "UNAVAILABLE");
            available &= present;
        }
        for (NSString *selector in @[@"kind", @"setBackgroundRemovable:", @"setTransparent:", @"setPreferredBackgroundStyle:", @"setSupportsVibrantContent:"]) {
            available &= Inspect("CHSMutableWidgetDescriptor", selector);
        }
        BOOL installed = SCInstallWidgetBackgroundHook();
        printf("Production hook installation: %s\n", installed ? "YES" : "NO");
        // Preserve a diagnostic artifact even when this simulator lacks a
        // private class. The camera's normal-widget fallback remains usable.
        printf("Runtime compatibility: %s; iOS 18.7.8 device rendering remains unverified.\n", available && installed ? "AVAILABLE" : "FALLBACK");
    }
    return 0;
}
