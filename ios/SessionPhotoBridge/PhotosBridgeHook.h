#import <Foundation/Foundation.h>
#import "../Shared/PhotoBridgeProtocol.h"
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSDictionary * _Nullable SCPhotoBridgeInput(NSObject *context);
FOUNDATION_EXPORT BOOL SCPhotoBridgeClaimContext(NSObject *context);
FOUNDATION_EXPORT BOOL SCPhotoBridgeDispatchURL(NSURL *url, NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT void SCPhotoBridgeFinishContext(NSObject *context, NSDictionary * _Nullable result, NSError * _Nullable error);
NS_ASSUME_NONNULL_END
