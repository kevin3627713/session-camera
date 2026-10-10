import Foundation
import Photos

/// Resolves only the requested, currently accessible photo under the caller's
/// explicit hidden-photo policy. Existing camera routes keep the default off.
enum SystemPhotosAsset {
    enum Failure: LocalizedError, Equatable {
        case access, missingAsset, identifierUnavailable, assetMismatch
        var errorDescription: String? {
            switch self {
            case .access: return "没有这张照片的读取权限"
            case .missingAsset: return "照片已删除或无法访问"
            case .identifierUnavailable: return "暂时无法取得照片标识，请稍后重试"
            case .assetMismatch: return "无法确认对应的原照片，请稍后重试"
            }
        }
    }

    static func assetURL(forCloudIdentifier identifier: String) -> URL? {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "photos-navigation"
        components.host = "asset"
        components.queryItems = [URLQueryItem(name: "cloud-identifier", value: identifier)]
        return components.url
    }

    static func resolveURL(for identifier: String, includeHidden: Bool = false) throws -> URL {
        try checkAccess(identifier, includeHidden: includeHidden)
        let library = PHPhotoLibrary.shared()
        let url = try resolveURL(for: identifier, cloudMapping: { id in
            guard let result = library.cloudIdentifierMappings(forLocalIdentifiers: [id])[id] else {
                throw Failure.identifierUnavailable
            }
            return try result.get()
        }, localMapping: { cloud in
            guard let result = library.localIdentifierMappings(for: [cloud])[cloud] else {
                throw Failure.identifierUnavailable
            }
            return try result.get()
        })
        try checkAccess(identifier, includeHidden: includeHidden)
        return url
    }

    static func resolveURL(for identifier: String, cloudMapping: (String) throws -> PHCloudIdentifier,
                           localMapping: (PHCloudIdentifier) throws -> String) throws -> URL {
        guard !identifier.isEmpty else { throw Failure.identifierUnavailable }
        do {
            let cloud = try cloudMapping(identifier)
            guard try localMapping(cloud) == identifier else { throw Failure.assetMismatch }
            guard let url = assetURL(forCloudIdentifier: cloud.stringValue) else { throw Failure.identifierUnavailable }
            return url
        } catch let error as Failure { throw error }
        catch { throw Failure.identifierUnavailable }
    }

    static func checkAccess(_ identifier: String, includeHidden: Bool = false) throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { throw Failure.access }
        let options = PHFetchOptions()
        options.includeHiddenAssets = includeHidden
        guard !identifier.isEmpty,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: options).firstObject,
              (includeHidden || !asset.isHidden), asset.mediaType == .image else { throw Failure.missingAsset }
    }
}
