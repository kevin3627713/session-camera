#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
// Pixel coordinates, matching PHAsset.suggestedCropForTargetSize:. CGRectNull
// means the private method is unavailable, incompatible, or failed.
FOUNDATION_EXPORT CGRect SCSuggestedPhotoCrop(id asset, CGSize targetSize);
NS_ASSUME_NONNULL_END
