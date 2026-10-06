#import "PhotoBridgeProtocol.h"

NSString * const SCPhotoBridgeAssetKey = @"assetID";
NSString * const SCPhotoBridgeCloudKey = @"cloudIdentifier";
NSString * const SCPhotoBridgeNonceKey = @"requestNonce";
NSString * const SCPhotoBridgeAcceptedKey = @"accepted";
NSString * const SCPhotoBridgeErrorDomain = @"SessionPhotoBridge";

NSString *SCPhotoBridgeSiblingIdentifier(NSURL *widgetBundleURL) {
    NSURL *plugins = widgetBundleURL.URLByDeletingLastPathComponent;
    NSURL *application = plugins.URLByDeletingLastPathComponent;
    if (![widgetBundleURL.pathExtension isEqualToString:@"appex"] ||
        ![plugins.lastPathComponent isEqualToString:@"PlugIns"] ||
        ![application.pathExtension isEqualToString:@"app"]) return nil;
    NSURL *sibling = [plugins URLByAppendingPathComponent:@"SessionPhotoBridge.appex" isDirectory:YES];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[sibling URLByAppendingPathComponent:@"Info.plist"]];
    NSDictionary *extension = info[@"NSExtension"];
    NSString *identifier = info[@"CFBundleIdentifier"];
    if (![extension isKindOfClass:NSDictionary.class] ||
        ![extension[@"NSExtensionPointIdentifier"] isEqual:@"com.apple.share-services"] ||
        ![extension[@"NSExtensionPrincipalClass"] isEqual:@"SessionPhotosBridgeController"] ||
        ![identifier isKindOfClass:NSString.class] || identifier.length == 0) return nil;
    return identifier;
}
