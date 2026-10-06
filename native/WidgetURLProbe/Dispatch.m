#import "Dispatch.h"
#import <objc/runtime.h>
#include <unistd.h>

// Research fixtures only. These declarations describe the observed iOS 18 ABI.
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openURL:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
@end
@interface NSExtension : NSObject
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))callback;
@end

BOOL SCProbeDispatch(NSString *route, NSURL *url) {
    NSLog(@"SCURLPROBE dispatch route=%@ bundle=%@ pid=%d", route, NSBundle.mainBundle.bundleIdentifier, getpid());
    @try {
        if ([route isEqualToString:@"share"]) {
            static NSExtension *extension;
            NSError *error = nil;
            Class type = NSClassFromString(@"NSExtension");
            if (!type || ![type respondsToSelector:@selector(extensionWithIdentifier:error:)]) return NO;
            extension = [type extensionWithIdentifier:@"com.kevin3627713.sessioncamera.urlprobe.share" error:&error];
            NSLog(@"SCURLPROBE share discovery=%d error=%@", extension != nil, error);
            if (!extension || ![extension respondsToSelector:@selector(beginExtensionRequestWithInputItems:completion:)]) return NO;
            NSExtensionItem *item = [NSExtensionItem new];
            item.userInfo = @{ @"probeURL": url };
            [extension beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *request) {
                NSLog(@"SCURLPROBE share request started=%d", request != nil);
            }];
            return YES; // Discovery/start request is not proof of navigation.
        }
        Class type = NSClassFromString(@"LSApplicationWorkspace");
        if (!type || ![type respondsToSelector:@selector(defaultWorkspace)]) return NO;
        LSApplicationWorkspace *workspace = [type defaultWorkspace];
        NSError *error = nil;
        BOOL accepted = NO;
        if ([route isEqualToString:@"sensitive"] && [workspace respondsToSelector:@selector(openSensitiveURL:withOptions:error:)]) {
            accepted = [workspace openSensitiveURL:url withOptions:@{} error:&error];
        } else if ([workspace respondsToSelector:@selector(openURL:withOptions:error:)]) {
            accepted = [workspace openURL:url withOptions:@{} error:&error];
        }
        NSLog(@"SCURLPROBE workspace accepted=%d error=%@", accepted, error);
        return accepted;
    } @catch (NSException *error) {
        NSLog(@"SCURLPROBE exception=%@", error.name);
        return NO;
    }
}
