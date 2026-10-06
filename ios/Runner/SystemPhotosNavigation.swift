import Foundation
import Photos
import UIKit

/// Compatibility route for existing sessioncamera://photos links.
/// Current widgets use the headless Share bridge instead.
enum SystemPhotosNavigation {
    typealias Failure = SystemPhotosAsset.Failure
    static func assetURL(forCloudIdentifier id: String) -> URL? { SystemPhotosAsset.assetURL(forCloudIdentifier: id) }
    static func resolveURL(for id: String) throws -> URL { try SystemPhotosAsset.resolveURL(for: id) }
    static func resolveURL(for id: String, cloudMapping: (String) throws -> PHCloudIdentifier,
                           localMapping: (PHCloudIdentifier) throws -> String) throws -> URL {
        try SystemPhotosAsset.resolveURL(for: id, cloudMapping: cloudMapping, localMapping: localMapping)
    }
    static func checkAccess(_ id: String) throws { try SystemPhotosAsset.checkAccess(id) }
    @MainActor static func open(_ url: URL, assetID: String, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard (try? checkAccess(assetID)) != nil, UIApplication.shared.applicationState == .active,
              UIApplication.shared.canOpenURL(url) else { completion(false); return }
        UIApplication.shared.open(url, options: [:]) { accepted in
            Task { @MainActor in completion(accepted) }
        }
    }
}
