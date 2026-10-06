#import <Foundation/Foundation.h>

@interface NSExtension : NSObject
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
@end

__attribute__((constructor)) static void SCLogWidgetRegistration(void) {
    NSError *error = nil;
    Class type = NSClassFromString(@"NSExtension");
    NSString *identifier = [NSBundle.mainBundle.bundleIdentifier stringByAppendingString:@".widget"];
    id extension = [type respondsToSelector:@selector(extensionWithIdentifier:error:)]
        ? [type extensionWithIdentifier:identifier error:&error] : nil;
    NSLog(@"SCBRIDGE test widget registration=%@ error=%@", extension, error);
}
