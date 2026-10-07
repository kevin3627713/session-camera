import Foundation
import Photos

struct ProbeAlbum: Identifiable, Equatable {
    let id: String
    let name: String
    let smart: Bool
}

enum ProbePhotoLibrary {
    static func options() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.includeHiddenAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }

    static func albums() -> [ProbeAlbum] {
        var result: [ProbeAlbum] = []
        for type in [PHAssetCollectionType.album, .smartAlbum] {
            PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil).enumerateObjects { album, _, _ in
                guard album.assetCollectionSubtype != .smartAlbumAllHidden else { return }
                result.append(.init(id: album.localIdentifier, name: album.localizedTitle ?? "未命名相册", smart: type == .smartAlbum))
            }
        }
        return result.sorted {
            if $0.smart != $1.smart { return !$0.smart }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func resolve(assetID: String, albumID: String) throws -> ProbeIdentifiers {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw failure("请选择完整照片访问权限，以取得相册标识")
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject,
              !asset.isHidden, asset.mediaType == .image,
              let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
              album.assetCollectionSubtype != .smartAlbumAllHidden,
              PHAsset.fetchAssets(in: album, options: options()).index(of: asset) != NSNotFound else {
            throw failure("照片或相册已不可访问，或照片已不在这个相册中，请重新选择")
        }
        let library = PHPhotoLibrary.shared()
        let mappings = library.cloudIdentifierMappings(forLocalIdentifiers: [assetID, albumID])
        var notes: [String] = []
        func cloud(_ id: String, _ label: String) -> String? {
            do {
                guard let mapping = mappings[id] else { throw failure("没有返回云标识映射") }
                let value = try mapping.get()
                guard let reverse = library.localIdentifierMappings(for: [value])[value],
                      try reverse.get() == id, !value.stringValue.isEmpty else {
                    throw failure("云标识回映射不一致")
                }
                return value.stringValue
            } catch {
                let e = error as NSError
                notes.append("\(label)：\(e.domain) \(e.code)，\(e.localizedDescription)")
                return nil
            }
        }
        let photoCloud = cloud(assetID, "照片云标识")
        let albumCloud = cloud(albumID, "相册云标识")
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { throw failure("照片权限已改变") }
        return ProbeIdentifiers(assetLocalID: assetID, albumLocalID: albumID,
                                albumName: album.localizedTitle ?? "", assetCloudID: photoCloud,
                                albumCloudID: albumCloud, mappingNotes: notes)
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "PhotosNavigationProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
