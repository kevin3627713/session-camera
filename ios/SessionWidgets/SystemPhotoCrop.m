#import "SystemPhotoCrop.h"
#import <math.h>
#import <string.h>

CGRect SCSuggestedPhotoCrop(id asset, CGSize targetSize) {
    if (!asset || !isfinite(targetSize.width) || !isfinite(targetSize.height) ||
        targetSize.width <= 0 || targetSize.height <= 0) return CGRectNull;
    @try {
        SEL selector = NSSelectorFromString(@"suggestedCropForTargetSize:");
        if (![asset respondsToSelector:selector]) return CGRectNull;
        NSMethodSignature *signature = [asset methodSignatureForSelector:selector];
        // Never invoke a private selector with an assumed structure ABI.
        if (!signature || signature.numberOfArguments != 3 ||
            signature.methodReturnLength != sizeof(CGRect) ||
            strcmp(signature.methodReturnType, @encode(CGRect)) != 0 ||
            strcmp([signature getArgumentTypeAtIndex:2], @encode(CGSize)) != 0) return CGRectNull;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = asset;
        invocation.selector = selector;
        [invocation setArgument:&targetSize atIndex:2];
        [invocation invoke];
        CGRect crop = CGRectNull;
        [invocation getReturnValue:&crop];
        if (!isfinite(crop.origin.x) || !isfinite(crop.origin.y) ||
            !isfinite(crop.size.width) || !isfinite(crop.size.height) ||
            crop.size.width <= 0 || crop.size.height <= 0) return CGRectNull;
        return crop;
    } @catch (__unused NSException *exception) {
        // A private implementation can change independently of our IPA.
        return CGRectNull;
    }
}
