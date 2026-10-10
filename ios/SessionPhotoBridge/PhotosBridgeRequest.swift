import Foundation
import CoreFoundation

/// NSExtensionItem may add system properties to userInfo during transport.
/// Validate our fields individually; the dictionary is not a three-key envelope.
struct PhotoBridgePayload {
    let assetID: String
    let cloudIdentifier: String
    let nonce: String
    let includeHidden: Bool

    init(_ input: [AnyHashable: Any]) throws {
        guard let asset = input[SCPhotoBridgeAssetKey] as? String,
              !asset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, asset.count <= 4096 else {
            throw Self.error(13, "照片中转缺少有效的照片标识")
        }
        guard let cloud = input[SCPhotoBridgeCloudKey] as? String,
              !cloud.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cloud.count <= 4096 else {
            throw Self.error(14, "照片中转缺少有效的系统照片标识")
        }
        guard let nonce = input[SCPhotoBridgeNonceKey] as? String, UUID(uuidString: nonce) != nil else {
            throw Self.error(15, "照片中转缺少有效的请求校验标识")
        }
        self.assetID = asset
        self.cloudIdentifier = cloud
        self.nonce = nonce
        if let value = input[SCPhotoBridgeIncludeHiddenKey] {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw Self.error(16, "照片中转的隐藏照片设置无效")
            }
            self.includeHidden = number.boolValue
        } else {
            // Requests from old timelines retain the original default-off policy.
            self.includeHidden = false
        }
    }

    private static func error(_ code: Int, _ message: String) -> NSError {
        NSError(domain: SCPhotoBridgeErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

#if !PHOTO_BRIDGE_PROTOCOL_TEST
@objc(SCPhotosBridgeRequest) final class PhotosBridgeRequest: NSObject {
    @objc(handleContext:) static func handleContext(_ context: NSObject) {
        // A principal-object callback can arrive before inputItems is populated.
        // Leave this context available for the later host callback in that case.
        guard let input = SCPhotoBridgeInput(context) else { return }
        guard SCPhotoBridgeClaimContext(context) else { return }
        Task.detached(priority: .userInitiated) {
            do {
                let payload = try PhotoBridgePayload(input)
                // Re-check permission, hidden/deleted status and both mappings
                // in this process immediately before dispatching.
                let url = try SystemPhotosAsset.resolveURL(for: payload.assetID, includeHidden: payload.includeHidden)
                guard url == SystemPhotosAsset.assetURL(forCloudIdentifier: payload.cloudIdentifier) else {
                    throw SystemPhotosAsset.Failure.assetMismatch
                }
                var error: NSError?
                guard SCPhotoBridgeDispatchURL(url, &error) else {
                    throw NSError(domain: SCPhotoBridgeErrorDomain, code: 12,
                                  userInfo: [NSLocalizedDescriptionKey: "系统未允许打开这张照片，请重试"])
                }
                #if WIDGET_BRIDGE_TEST
                NSLog("SCBRIDGE share accepted and completing request")
                #endif
                SCPhotoBridgeFinishContext(context, [SCPhotoBridgeNonceKey: payload.nonce, SCPhotoBridgeAcceptedKey: true], nil)
            } catch {
                #if WIDGET_BRIDGE_TEST
                NSLog("SCBRIDGE share cancelling code=%ld", (error as NSError).code)
                #endif
                SCPhotoBridgeFinishContext(context, nil, error as NSError)
            }
        }
    }
}
#endif
