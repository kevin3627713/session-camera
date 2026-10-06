#import "PhotoBridgeClient.h"

@interface NSExtension : NSObject
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))callback;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *, NSArray *))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *, NSError *))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *))block;
- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)identifier;
@end

static NSError *SCBridgeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SCPhotoBridgeErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface SCPhotoBridgeClientRequest : NSObject
@property(nonatomic, strong) NSExtension *extension;
@property(nonatomic, strong) NSUUID *requestID;
@property(nonatomic, copy) NSString *nonce;
@property(nonatomic, copy) void (^completion)(BOOL, NSError *);
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL cancellationRequested;
@end

static NSMutableSet *SCActiveRequests(void) {
    static NSMutableSet *requests;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ requests = [NSMutableSet new]; });
    return requests;
}

@implementation SCPhotoBridgeClientRequest
- (void)finish:(BOOL)accepted error:(NSError *)error cancel:(BOOL)cancel {
    void (^completion)(BOOL, NSError *);
    NSExtension *extension;
    NSUUID *requestID;
    @synchronized (self) {
        if (self.finished) return;
        self.finished = YES;
        self.cancellationRequested = cancel;
        completion = self.completion;
        self.completion = nil;
        extension = self.extension;
        requestID = self.requestID;
        self.extension = nil;
    }
    @try {
        [extension setRequestCompletionBlock:nil];
        [extension setRequestCancellationBlock:nil];
        [extension setRequestInterruptionBlock:nil];
        if (cancel && requestID) [extension cancelExtensionRequestWithIdentifier:requestID];
    } @catch (__unused NSException *exception) { }
    @synchronized (SCActiveRequests()) { [SCActiveRequests() removeObject:self]; }
#if WIDGET_BRIDGE_TEST
    NSLog(@"SCBRIDGE client finished accepted=%d code=%ld", accepted, (long)error.code);
#endif
    if (completion) completion(accepted, error);
}
@end

void SCOpenWidgetPhotoInPhotos(NSString *assetID, NSString *cloudIdentifier, void (^completion)(BOOL, NSError *)) {
    SCPhotoBridgeClientRequest *request = [SCPhotoBridgeClientRequest new];
    request.completion = completion;
    request.nonce = NSUUID.UUID.UUIDString;
    @synchronized (SCActiveRequests()) { [SCActiveRequests() addObject:request]; }
    @try {
        NSString *identifier = SCPhotoBridgeSiblingIdentifier(NSBundle.mainBundle.bundleURL);
        if (!identifier) {
            [request finish:NO error:SCBridgeError(1, @"照片中转扩展缺失，请重新签名并保留全部扩展") cancel:NO];
            return;
        }
        Class type = NSClassFromString(@"NSExtension");
        if (!type || ![type respondsToSelector:@selector(extensionWithIdentifier:error:)]) {
            [request finish:NO error:SCBridgeError(2, @"系统不支持照片中转") cancel:NO];
            return;
        }
        NSError *error = nil;
        NSExtension *extension = [type extensionWithIdentifier:identifier error:&error];
        for (NSString *name in @[@"beginExtensionRequestWithInputItems:completion:", @"setRequestCompletionBlock:",
                                 @"setRequestCancellationBlock:", @"setRequestInterruptionBlock:", @"cancelExtensionRequestWithIdentifier:"]) {
            if (![extension respondsToSelector:NSSelectorFromString(name)]) {
                [request finish:NO error:SCBridgeError(3, @"无法启动照片中转扩展，请检查签名是否保留全部扩展") cancel:NO];
                return;
            }
        }
        request.extension = extension;
        __weak SCPhotoBridgeClientRequest *weakRequest = request;
        [extension setRequestCompletionBlock:^(NSUUID *uuid, NSArray *items) {
            SCPhotoBridgeClientRequest *strongRequest = weakRequest;
            if (!strongRequest) return;
            NSExtensionItem *item = items.count == 1 && [items.firstObject isKindOfClass:NSExtensionItem.class] ? items.firstObject : nil;
            NSDictionary *result = item.userInfo;
            BOOL accepted = [result[SCPhotoBridgeNonceKey] isEqual:strongRequest.nonce] &&
                [result[SCPhotoBridgeAcceptedKey] isKindOfClass:NSNumber.class] && [result[SCPhotoBridgeAcceptedKey] boolValue];
            [strongRequest finish:accepted error:accepted ? nil : SCBridgeError(4, @"系统未允许打开这张照片，请重试") cancel:NO];
        }];
        [extension setRequestCancellationBlock:^(NSUUID *uuid, NSError *error) {
            // Asset validation errors carry the shared localized description.
            [weakRequest finish:NO error:error ?: SCBridgeError(5, @"照片中转已取消") cancel:NO];
        }];
        [extension setRequestInterruptionBlock:^(NSUUID *uuid) {
            [weakRequest finish:NO error:SCBridgeError(6, @"照片中转被系统中断，请重试") cancel:NO];
        }];
        NSExtensionItem *item = [NSExtensionItem new];
        item.userInfo = @{SCPhotoBridgeAssetKey: assetID, SCPhotoBridgeCloudKey: cloudIdentifier,
                          SCPhotoBridgeNonceKey: request.nonce};
        [extension beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *uuid) {
            // Retain until the start callback arrives, including after a timeout.
            // A late UUID must be cancelled only if cancellation was requested.
            BOOL alreadyFinished, cancel;
            @synchronized (request) {
                alreadyFinished = request.finished;
                cancel = request.cancellationRequested;
                request.requestID = uuid;
            }
            if (alreadyFinished) {
                if (cancel && uuid) [extension cancelExtensionRequestWithIdentifier:uuid];
                return;
            }
            if (!uuid) [request finish:NO error:SCBridgeError(7, @"照片中转启动失败，请检查扩展签名") cancel:NO];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [weakRequest finish:NO error:SCBridgeError(8, @"照片中转超时，请重试") cancel:YES];
        });
    } @catch (__unused NSException *exception) {
        [request finish:NO error:SCBridgeError(9, @"系统不支持此次照片中转") cancel:YES];
    }
}
