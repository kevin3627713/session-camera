#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const SCPhotoBridgeAssetKey;
FOUNDATION_EXPORT NSString * const SCPhotoBridgeCloudKey;
FOUNDATION_EXPORT NSString * const SCPhotoBridgeNonceKey;
FOUNDATION_EXPORT NSString * const SCPhotoBridgeIncludeHiddenKey;
FOUNDATION_EXPORT NSString * const SCPhotoBridgeAcceptedKey;
FOUNDATION_EXPORT NSString * const SCPhotoBridgeErrorDomain;

// Read the embedded sibling's actual identifier, including independent re-sign
// mappings. Do not assume the signer preserves a particular identifier suffix.
FOUNDATION_EXPORT NSString * _Nullable SCPhotoBridgeSiblingIdentifier(NSURL *widgetBundleURL);
NS_ASSUME_NONNULL_END
