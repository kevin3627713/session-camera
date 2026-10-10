import Foundation
import Photos
import UIKit
import CryptoKit
import ImageIO

// Inspect JPEG dimensions without decoding its pixels into memory.
enum PhotoImageMetadata {
    static func dimensions(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return CGSize(width: CGFloat(width.doubleValue), height: CGFloat(height.doubleValue))
    }
}

enum PhotoLibrarySource {
    static var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    static let accessibleID = "accessible"

    static func catalog(includeHidden: Bool = false) -> [PhotoSourceEntity] {
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
            guard (includeHidden || album.assetCollectionSubtype != .smartAlbumAllHidden),
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
            ? foldersByID()[pieces[1]]
            : PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [pieces[1]], options: nil).firstObject
        return PhotoSourceEntity(id: id, name: (pieces[0] == "folder" ? "文件夹 · " : "相册 · ") + (collection?.localizedTitle ?? "已删除的来源"))
    }

    static func assetIDs(sourceID: String, includeHidden: Bool = false) -> [String] {
        guard status == .authorized || status == .limited else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.includeHiddenAssets = includeHidden
        if sourceID == accessibleID {
            return identifiers(PHAsset.fetchAssets(with: options))
        }
        guard status == .authorized else { return [] }
        let pieces = sourceID.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return [] }
        let albums: [String]
        if pieces[0] == "folder" {
            // Full enumeration is retained for explicit library diagnostics and
            // integration fixtures. Production folder timelines use selection().
            albums = folderAlbumIDs(pieces[1])
        } else if pieces[0] == "album" { albums = [pieces[1]] }
        else { return [] }
        var result = Set<String>()
        for id in albums {
            autoreleasepool {
                guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject,
                      (includeHidden || album.assetCollectionSubtype != .smartAlbumAllHidden) else { return }
                result.formUnion(identifiers(PHAsset.fetchAssets(in: album, options: options)))
            }
        }
        return result.sorted()
    }

    static func selection(sourceID: String, instanceID: String, minutes: Int, now: Date,
                          includeHidden: Bool = false) -> String? {
        guard let window = PhotoSchedule.window(instanceID: instanceID, sourceID: sourceID, minutes: minutes, now: now),
              status == .authorized || status == .limited else { return nil }
        guard sourceID.hasPrefix("folder:") else {
            // Preserve the existing album/limited-library shuffle behavior.
            return PhotoSchedule.plan(assetIDs: assetIDs(sourceID: sourceID, includeHidden: includeHidden), instanceID: instanceID,
                                      sourceID: sourceID, minutes: minutes, now: now, count: 1).first?.assetID
        }
        guard status == .authorized else { return nil }
        let albums = autoreleasepool { folderAlbumIDs(String(sourceID.dropFirst("folder:".count))) }
        guard !albums.isEmpty else { return nil }
        let key = PhotoFolderSelectionCache.key(instanceID: instanceID, sourceID: sourceID, minutes: minutes,
                                               includeHidden: includeHidden)
        let previous = PhotoFolderSelectionCache.read(key: key)
        // Validate membership and access before reusing a small cached selection;
        // no asset-count queries are needed for a reload in the same period.
        if let previous, previous.tick == window.tick,
           folderContains(previous.assetID, albums: Set(albums), includeHidden: includeHidden) {
            return previous.assetID
        }
        let counts = albums.map { id in autoreleasepool { albumAssets(id, includeHidden: includeHidden)?.count ?? 0 } }
        let picked = PhotoFolderSampler.select(counts: counts, seed: window.seed, excluding: previous?.assetID) { bucket, offset in
            autoreleasepool {
                guard let assets = albumAssets(albums[bucket], includeHidden: includeHidden), offset < assets.count else { return nil }
                let asset = assets.object(at: offset)
                guard (includeHidden || !asset.isHidden), asset.mediaType == .image else { return nil }
                return asset.localIdentifier
            }
        }
        guard let picked, status == .authorized,
              folderContains(picked, albums: Set(albums), includeHidden: includeHidden) else { return nil }
        PhotoFolderSelectionCache.write(.init(tick: window.tick, assetID: picked), key: key)
        return picked
    }

    private static func folderAlbumIDs(_ root: String) -> [String] {
        let folders = foldersByID()
        return PhotoFolderTraversal.albums(root: root) { id in
            guard let folder = folders[id] else { return [] }
            var children: [(id: String, folder: Bool)] = []
            PHCollection.fetchCollections(in: folder, options: nil).enumerateObjects { collection, _, _ in
                children.append((collection.localIdentifier, collection is PHCollectionList))
            }
            return children
        }
    }

    private static func albumAssets(_ id: String, includeHidden: Bool) -> PHFetchResult<PHAsset>? {
        guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject,
              (includeHidden || album.assetCollectionSubtype != .smartAlbumAllHidden) else { return nil }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.includeHiddenAssets = includeHidden
        return PHAsset.fetchAssets(in: album, options: options)
    }

    private static func folderContains(_ id: String, albums: Set<String>, includeHidden: Bool) -> Bool {
        autoreleasepool {
            let options = PHFetchOptions()
            options.includeHiddenAssets = includeHidden
            guard status == .authorized,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: options).firstObject,
                  (includeHidden || !asset.isHidden), asset.mediaType == .image else { return false }
            var contains = false
            PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil).enumerateObjects { album, _, stop in
                if albums.contains(album.localIdentifier) { contains = true; stop.pointee = true }
            }
            return contains
        }
    }

    private static func foldersByID() -> [String: PHCollectionList] {
        // The identifier-only collection-list query throws "PHQuery requires
        // a type" on iOS 18.6. Explicitly request folder collections instead.
        var result: [String: PHCollectionList] = [:]
        PHCollectionList.fetchCollectionLists(with: .folder, subtype: .any, options: nil).enumerateObjects { folder, _, _ in
            result[folder.localIdentifier] = folder
        }
        return result
    }

    private static func identifiers(_ assets: PHFetchResult<PHAsset>) -> [String] {
        var result: [String] = []
        for index in 0..<assets.count {
            autoreleasepool { result.append(assets.object(at: index).localIdentifier) }
        }
        return result
    }

    static func imageData(assetID: String, size: CGSize, timeout: TimeInterval = 8,
                          includeHidden: Bool = false) async -> Data? {
#if WIDGET_PHOTO_DIAGNOSTICS
        WidgetPhotoDiagnostics.record("image-access-check")
#endif
        // Recheck access and the asset before consulting the extension's cache.
        // Cached bytes must never bypass a removed asset or revoked permission.
        let accessOptions = PHFetchOptions()
        accessOptions.includeHiddenAssets = includeHidden
        guard status == .authorized || status == .limited,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: accessOptions).firstObject,
              (includeHidden || !asset.isHidden), asset.mediaType == .image else { return nil }
        let target = pixelSize(for: size)
        // The system Photos widget calls this exact selector. Reuse its existing
        // signals without loading pixels or running another analysis model.
        let suggested = SCSuggestedPhotoCrop(asset, target)
        let crop = PhotoWidgetGeometry.crop(assetSize: CGSize(width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight)),
                                            target: target, suggestedPixelCrop: suggested)
        // Analysis can update its recommendation independently of edit time.
        let cacheKey = PhotoImageCache.key(asset: asset, target: target, crop: crop)
        if let cached = PhotoImageCache.read(key: cacheKey, target: target) {
#if WIDGET_PHOTO_DIAGNOSTICS
            WidgetPhotoDiagnostics.record("image-cache-hit")
#endif
            return cached
        }
        let data: Data? = await withCheckedContinuation { continuation in
            let request = PhotoImageRequest(continuation, target: target)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.normalizedCropRect = crop
            options.isNetworkAccessAllowed = true
#if WIDGET_PHOTO_DIAGNOSTICS
            WidgetPhotoDiagnostics.record("image-request-start")
#endif
            let identifier = PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, info in
                request.receive(image, info: info)
            }
            request.setIdentifier(identifier)
            DispatchQueue.global().asyncAfter(deadline: .now() + max(0.1, timeout)) { request.finish(nil) }
        }
        if let data { PhotoImageCache.write(data, key: cacheKey) }
#if WIDGET_PHOTO_DIAGNOSTICS
        WidgetPhotoDiagnostics.record(data == nil ? "image-request-unavailable" : "image-request-complete")
#endif
        return data
    }

    static func cropRect(assetSize: CGSize, target: CGSize) -> CGRect {
        PhotoWidgetGeometry.crop(assetSize: assetSize, target: target)
    }

    static func pixelSize(for size: CGSize) -> CGSize {
        // iPhones use up to three physical pixels per point. Bound the longest
        // edge and encode a cropped image to keep decoded widget memory small.
        let width = size.width.isFinite && size.width > 1 ? size.width : 180
        let height = size.height.isFinite && size.height > 1 ? size.height : 180
        let scale = min(3, 1200 / max(width, height))
        return CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
    }
}

// A few IDs per widget, rather than a persisted inventory of the folder. Kept
// inside the extension's cache and always revalidated against current PhotoKit.
enum PhotoFolderSelectionCache {
    struct Record: Codable { let tick: Int64; let assetID: String }
    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WidgetFolderSelection-v1", isDirectory: true)
    }
    static func key(instanceID: String, sourceID: String, minutes: Int, includeHidden: Bool = false) -> String {
        // Keep the old key for default-off widgets; opt-in selections are separate.
        let value = "\(instanceID)\u{0}\(sourceID)\u{0}\(minutes)" + (includeHidden ? "\u{0}include-hidden" : "")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func read(key: String) -> Record? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".json")),
              data.count < 8192 else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
    static func write(_ record: Record, key: String) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: directory.appendingPathComponent(key + ".json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            let newest = files.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            for file in newest.dropFirst(64) { try? manager.removeItem(at: file) }
        } catch {
            // Cache availability must not prevent a fresh selection.
        }
    }
}

// Every mutable field is protected by lock; timeout and PhotoKit callbacks
// may arrive on different queues.
final class PhotoImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var identifier: PHImageRequestID?
    private let target: CGSize
    init(_ continuation: CheckedContinuation<Data?, Never>, target: CGSize) {
        self.continuation = continuation
        self.target = target
    }
    func receive(_ image: UIImage?, info: [AnyHashable: Any]?) {
        if info?[PHImageCancelledKey] as? Bool == true || info?[PHImageErrorKey] != nil {
            finish(nil)
            return
        }
        // A degraded callback is provisional, even if it contains a UIImage.
        // Finishing here used to cancel the subsequent high-quality delivery.
        guard info?[PHImageResultIsDegradedKey] as? Bool != true else { return }
        guard let image else { finish(nil); return }
        lock.lock()
        let completed = continuation == nil
        lock.unlock()
        guard !completed else { return }
#if WIDGET_PHOTO_DIAGNOSTICS
        if let pixels = image.cgImage {
            WidgetPhotoDiagnostics.record("image-final-\(pixels.width)x\(pixels.height)-\(pixels.bitsPerPixel)bpp")
        }
#endif
        let data = autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            format.preferredRange = .standard
            let scale = max(target.width / image.size.width, target.height / image.size.height)
            let rect = CGRect(x: (target.width - image.size.width * scale) / 2,
                              y: (target.height - image.size.height * scale) / 2,
                              width: image.size.width * scale, height: image.size.height * scale)
            return UIGraphicsImageRenderer(size: target, format: format).image { _ in
                image.draw(in: rect)
            }.jpegData(compressionQuality: 0.92)
        }
        finish(data)
    }
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

// Only final-quality, cropped JPEGs are cached in the extension container.
// Removing/re-adding a widget can reuse them without an App Group. The key
// includes edit time and size, so a changed photo or widget size is reloaded.
enum PhotoImageCache {
    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WidgetPhotosHQ-v1", isDirectory: true)
    }
    static func key(asset: PHAsset, target: CGSize, crop: CGRect = .zero) -> String {
        key(assetID: asset.localIdentifier, modified: asset.modificationDate?.timeIntervalSince1970 ?? 0, target: target, crop: crop)
    }
    static func key(assetID: String, modified: TimeInterval, target: CGSize, crop: CGRect = .zero) -> String {
        let position = [crop.minX, crop.minY, crop.width, crop.height].map { String(format: "%.6f", Double($0)) }.joined(separator: ",")
        let value = "system-crop-v1|\(assetID)|\(modified)|\(Int(target.width))x\(Int(target.height))|\(position)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func read(key: String, target: CGSize) -> Data? {
        let url = directory.appendingPathComponent(key + ".jpg")
        guard let data = try? Data(contentsOf: url),
              PhotoImageMetadata.dimensions(data) == target else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }
    static func write(_ data: Data, key: String) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(key + ".jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            let records = files.compactMap { url -> (URL, Date, Int)? in
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
                return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
            }.sorted { $0.1 > $1.1 }
            var bytes = 0
            for (index, record) in records.enumerated() {
                bytes += record.2
                if index >= 32 || bytes > 24 * 1024 * 1024 { try? manager.removeItem(at: record.0) }
            }
        } catch {
            // A full/unavailable cache must not prevent a fresh photo display.
        }
    }
}
