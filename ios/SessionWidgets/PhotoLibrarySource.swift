import Foundation
import Photos
import UIKit

enum PhotoLibrarySource {
    static var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    static let accessibleID = "accessible"

    static func catalog() -> [PhotoSourceEntity] {
        guard status == .authorized || status == .limited else { return [] }
        let accessible = PhotoSourceEntity(id: accessibleID, name: status == .limited ? "已授权的照片（有限访问）" : "所有可访问照片")
        guard status == .authorized else { return [accessible] }
        var entities: [PhotoSourceEntity] = [], seen = Set<String>()
        func visit(_ collections: PHFetchResult<PHCollection>, path: String) {
            collections.enumerateObjects { collection, _, _ in
                guard seen.insert(collection.localIdentifier).inserted else { return }
                let name = path + (collection.localizedTitle ?? "未命名")
                if let folder = collection as? PHCollectionList {
                    entities.append(PhotoSourceEntity(id: "folder:" + folder.localIdentifier, name: "文件夹 · " + name))
                    visit(PHCollection.fetchCollections(in: folder, options: nil), path: name + " / ")
                } else if let album = collection as? PHAssetCollection {
                    entities.append(PhotoSourceEntity(id: "album:" + album.localIdentifier, name: "相册 · " + name))
                }
            }
        }
        visit(PHCollection.fetchTopLevelUserCollections(with: nil), path: "")
        PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil).enumerateObjects { album, _, _ in
            guard album.assetCollectionSubtype != .smartAlbumAllHidden,
                  seen.insert(album.localIdentifier).inserted else { return }
            entities.append(PhotoSourceEntity(id: "album:" + album.localIdentifier, name: "系统相册 · " + (album.localizedTitle ?? "未命名")))
        }
        return [accessible] + entities.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func resolve(_ id: String) -> PhotoSourceEntity {
        if id == accessibleID {
            return PhotoSourceEntity(id: id, name: status == .limited ? "已授权的照片（有限访问）" : "所有可访问照片")
        }
        let pieces = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2, status == .authorized else { return PhotoSourceEntity(id: id, name: "来源不可用，请检查照片权限") }
        let collection: PHCollection? = pieces[0] == "folder"
            ? PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [pieces[1]], options: nil).firstObject
            : PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [pieces[1]], options: nil).firstObject
        return PhotoSourceEntity(id: id, name: (pieces[0] == "folder" ? "文件夹 · " : "相册 · ") + (collection?.localizedTitle ?? "已删除的来源"))
    }

    static func assetIDs(sourceID: String) -> [String] {
        guard status == .authorized || status == .limited else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.includeHiddenAssets = false
        if sourceID == accessibleID {
            return identifiers(PHAsset.fetchAssets(with: options))
        }
        guard status == .authorized else { return [] }
        let pieces = sourceID.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return [] }
        let albums: [String]
        if pieces[0] == "folder" {
            albums = PhotoFolderTraversal.albums(root: pieces[1]) { id in
                guard let folder = PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [id], options: nil).firstObject else { return [] }
                var children: [(id: String, folder: Bool)] = []
                PHCollection.fetchCollections(in: folder, options: nil).enumerateObjects { collection, _, _ in
                    children.append((collection.localIdentifier, collection is PHCollectionList))
                }
                return children
            }
        } else if pieces[0] == "album" { albums = [pieces[1]] }
        else { return [] }
        var result = Set<String>()
        for id in albums {
            guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject,
                  album.assetCollectionSubtype != .smartAlbumAllHidden else { continue }
            result.formUnion(identifiers(PHAsset.fetchAssets(in: album, options: options)))
        }
        return result.sorted()
    }

    private static func identifiers(_ assets: PHFetchResult<PHAsset>) -> [String] {
        var result: [String] = []
        assets.enumerateObjects { asset, _, _ in result.append(asset.localIdentifier) }
        return result
    }

    static func imageData(assetID: String, size: CGSize) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let request = PhotoImageRequest(continuation)
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let scale = min(2, 720 / max(max(size.width, size.height), 1))
            let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
            let identifier = PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, info in
                if let image {
                    let data = autoreleasepool { image.jpegData(compressionQuality: 0.86) }
                    request.finish(data)
                } else if info?[PHImageCancelledKey] as? Bool == true || info?[PHImageErrorKey] != nil {
                    request.finish(nil)
                }
            }
            request.setIdentifier(identifier)
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) { request.finish(nil) }
        }
    }
}

private final class PhotoImageRequest {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var identifier: PHImageRequestID?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
    func setIdentifier(_ value: PHImageRequestID) {
        lock.lock()
        let completed = continuation == nil
        identifier = value
        lock.unlock()
        if completed { PHImageManager.default().cancelImageRequest(value) }
    }
    func finish(_ data: Data?) {
        lock.lock()
        let pending = continuation, identifier = identifier
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        if let identifier { PHImageManager.default().cancelImageRequest(identifier) }
        pending.resume(returning: data)
    }
}
