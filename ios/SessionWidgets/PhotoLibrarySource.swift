import Foundation
import Photos
import UIKit
import CryptoKit
import ImageIO
import os
import Darwin

enum WidgetPhotoDiagnostics {
    private static let logger = Logger(subsystem: "com.kevin3627713.sessioncamera.widgets", category: "PhotoPipeline")
    static var memoryMiB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
    static func record(_ phase: String) {
        // No asset IDs, album names or photo bytes enter the system log.
        logger.info("phase=\(phase, privacy: .public) memoryMiB=\(memoryMiB, privacy: .public)")
    }
    static func dimensions(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return CGSize(width: CGFloat(width.doubleValue), height: CGFloat(height.doubleValue))
    }
    static func testImage() -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.systemRed.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        }.pngData()
    }
}

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
            ? foldersByID()[pieces[1]]
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
            let folders = foldersByID()
            albums = PhotoFolderTraversal.albums(root: pieces[1]) { id in
                guard let folder = folders[id] else { return [] }
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
        assets.enumerateObjects { asset, _, _ in result.append(asset.localIdentifier) }
        return result
    }

    static func imageData(assetID: String, size: CGSize, timeout: TimeInterval = 8) async -> Data? {
        WidgetPhotoDiagnostics.record("image-access-check")
        // Recheck access and the asset before consulting the extension's cache.
        // Cached bytes must never bypass a removed asset or revoked permission.
        guard status == .authorized || status == .limited,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return nil }
        let target = pixelSize(for: size)
        let cacheKey = PhotoImageCache.key(asset: asset, target: target)
        if let cached = PhotoImageCache.read(key: cacheKey, target: target) {
            WidgetPhotoDiagnostics.record("image-cache-hit")
            return cached
        }
        let data: Data? = await withCheckedContinuation { continuation in
            let request = PhotoImageRequest(continuation, target: target)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.normalizedCropRect = cropRect(assetSize: CGSize(width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight)), target: target)
            options.isNetworkAccessAllowed = true
            WidgetPhotoDiagnostics.record("image-request-start")
            let identifier = PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, info in
                request.receive(image, info: info)
            }
            request.setIdentifier(identifier)
            DispatchQueue.global().asyncAfter(deadline: .now() + max(0.1, timeout)) { request.finish(nil) }
        }
        if let data { PhotoImageCache.write(data, key: cacheKey) }
        WidgetPhotoDiagnostics.record(data == nil ? "image-request-unavailable" : "image-request-complete")
        return data
    }

    static func cropRect(assetSize: CGSize, target: CGSize) -> CGRect {
        guard assetSize.width > 0, assetSize.height > 0, target.width > 0, target.height > 0 else { return .zero }
        let ratio = (target.width / target.height) / (assetSize.width / assetSize.height)
        let width = min(1, ratio), height = min(1, 1 / ratio)
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
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
        if let pixels = image.cgImage {
            WidgetPhotoDiagnostics.record("image-final-\(pixels.width)x\(pixels.height)-\(pixels.bitsPerPixel)bpp")
        }
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
    static func key(asset: PHAsset, target: CGSize) -> String {
        key(assetID: asset.localIdentifier, modified: asset.modificationDate?.timeIntervalSince1970 ?? 0, target: target)
    }
    static func key(assetID: String, modified: TimeInterval, target: CGSize) -> String {
        let value = "\(assetID)|\(modified)|\(Int(target.width))x\(Int(target.height))"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func read(key: String, target: CGSize) -> Data? {
        let url = directory.appendingPathComponent(key + ".jpg")
        guard let data = try? Data(contentsOf: url),
              WidgetPhotoDiagnostics.dimensions(data) == target else { return nil }
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
