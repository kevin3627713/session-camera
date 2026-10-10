#import <Foundation/Foundation.h>
#import "../Shared/PhotoBridgeProtocol.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT void SCOpenWidgetPhotoInPhotos(NSString *assetID, NSString *cloudIdentifier, BOOL includeHidden,
    void (^completion)(BOOL accepted, NSError * _Nullable error));
NS_ASSUME_NONNULL_END
