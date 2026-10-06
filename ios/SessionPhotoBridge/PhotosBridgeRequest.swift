import Foundation

@objc(SCPhotosBridgeRequest) final class PhotosBridgeRequest: NSObject {
    @objc(handleContext:) static func handleContext(_ context: NSObject) {
        guard SCPhotoBridgeClaimContext(context) else { return }
        let input = SCPhotoBridgeInput(context)
        Task.detached(priority: .userInitiated) {
            do {
                guard let input, input.count == 3,
                      let assetID = input[SCPhotoBridgeAssetKey] as? String, !assetID.isEmpty, assetID.count <= 4096,
                      let cloudID = input[SCPhotoBridgeCloudKey] as? String, !cloudID.isEmpty, cloudID.count <= 4096,
                      let nonce = input[SCPhotoBridgeNonceKey] as? String, UUID(uuidString: nonce) != nil else {
                    throw NSError(domain: SCPhotoBridgeErrorDomain, code: 11,
                                  userInfo: [NSLocalizedDescriptionKey: "照片中转请求无效"])
                }
                // Re-check permission, hidden/deleted status and both mappings
                // in this process immediately before dispatching.
                let url = try SystemPhotosAsset.resolveURL(for: assetID)
                guard url == SystemPhotosAsset.assetURL(forCloudIdentifier: cloudID) else {
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
                SCPhotoBridgeFinishContext(context, [SCPhotoBridgeNonceKey: nonce, SCPhotoBridgeAcceptedKey: true], nil)
            } catch {
                #if WIDGET_BRIDGE_TEST
                NSLog("SCBRIDGE share cancelling code=%ld", (error as NSError).code)
                #endif
                SCPhotoBridgeFinishContext(context, nil, error as NSError)
            }
        }
    }
}
