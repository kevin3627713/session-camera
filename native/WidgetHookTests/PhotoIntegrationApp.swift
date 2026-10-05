import SwiftUI
import Photos
import AppIntents

// Independent simulator host. It is never compiled into the camera/extension.
@main
struct PhotoIntegrationApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Testing widget Photos integration").task { await run() }
        }
    }

    @MainActor private func run() async {
        var checks: [String] = []
        func require(_ condition: Bool, _ name: String) throws {
            if !condition { throw NSError(domain: "WidgetIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            checks.append(name)
        }
        var report: [String: Any]
        do {
            try require(PhotoLibrarySource.status == .authorized, "Full Photos authorization")
            func image(_ color: UIColor) -> UIImage {
                UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
                    color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
                }
            }
            let red = image(.red), blue = image(.blue), green = image(.green), yellow = image(.yellow)
            var redID = "", blueID = "", hiddenID = "", outsideID = "", albumID = "", folderID = ""
            try await PHPhotoLibrary.shared().performChanges {
                let a = PHAssetChangeRequest.creationRequestForAsset(from: red).placeholderForCreatedAsset!
                let b = PHAssetChangeRequest.creationRequestForAsset(from: blue).placeholderForCreatedAsset!
                let hidden = PHAssetChangeRequest.creationRequestForAsset(from: yellow)
                hidden.isHidden = true
                let c = hidden.placeholderForCreatedAsset!
                let d = PHAssetChangeRequest.creationRequestForAsset(from: green).placeholderForCreatedAsset!
                redID = a.localIdentifier; blueID = b.localIdentifier; hiddenID = c.localIdentifier; outsideID = d.localIdentifier
                let albumA = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Widget fixture A")
                albumA.addAssets([a, c] as NSArray)
                let albumB = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Widget fixture B")
                albumB.addAssets([a, b] as NSArray)
                let albumAP = (albumA.placeholderForCreatedAssetCollection as PHObjectPlaceholder?)!
                let albumBP = (albumB.placeholderForCreatedAssetCollection as PHObjectPlaceholder?)!
                albumID = albumAP.localIdentifier
                let child = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: "Widget nested fixture")
                child.addChildCollections([albumBP] as NSArray)
                let childP = (child.placeholderForCreatedCollectionList as PHObjectPlaceholder?)!
                let root = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: "Widget root fixture")
                root.addChildCollections([albumAP, childP] as NSArray)
                folderID = (root.placeholderForCreatedCollectionList as PHObjectPlaceholder?)!.localIdentifier
            }
            let album = PhotoLibrarySource.assetIDs(sourceID: "album:" + albumID)
            try require(album == [redID], "Album selects only its non-hidden photos")
            let folder = PhotoLibrarySource.assetIDs(sourceID: "folder:" + folderID)
            try require(Set(folder) == [redID, blueID], "Folder includes nested albums and deduplicates photos")
            try require(!folder.contains(hiddenID) && !folder.contains(outsideID), "Hidden and unrelated photos excluded")
            let catalog = PhotoLibrarySource.catalog()
            try require(catalog.contains { $0.id == "folder:" + folderID }, "Folder appears in native entity choices")
            try require(catalog.contains { $0.name.contains("Widget root fixture / Widget nested fixture / Widget fixture B") }, "Nested album path appears in choices")
            let resolved = try await PhotoSourceQuery().entities(for: ["album:" + albumID, "folder:" + folderID])
            try require(resolved.count == 2 && resolved[0].name.contains("Widget fixture A"), "Persisted sources resolve by identifier")
            let first = try await WidgetIdentityQuery().defaultResult()!
            let second = try await WidgetIdentityQuery().defaultResult()!
            try require(first.id != second.id, "New widget identities are unique")
            let identity = try await WidgetIdentityQuery().entities(for: [first.id])
            try require(identity[0].id == first.id, "Widget identity survives entity resolution")
            let picks = PhotoSchedule.plan(assetIDs: folder, instanceID: first.id, sourceID: folderID, minutes: 15, now: Date())
            try require(picks.count == 6 && picks.allSatisfy { folder.contains($0.assetID) }, "Scheduled photos stay inside selected folder")
            let data = await PhotoLibrarySource.imageData(assetID: picks[0].assetID, size: CGSize(width: 160, height: 160))
            try require(data.flatMap(UIImage.init(data:)) != nil, "Actual PhotoKit image request produces displayable data")
            try require(!KeepWidgetOnHomeScreen.openAppWhenRun && CameraWidgetConfiguration().tapBehavior == .none, "Default tap does not request app opening")
            _ = try await KeepWidgetOnHomeScreen().perform()
            try require(PhotoLibrarySource.assetIDs(sourceID: "folder:deleted-id").isEmpty, "Deleted sources do not fall back to another album")
            report = ["success": true, "checks": checks, "count": checks.count, "os": ProcessInfo.processInfo.operatingSystemVersionString]
        } catch {
            report = ["success": false, "checks": checks, "error": error.localizedDescription]
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("widget-photo-integration.json"), options: .atomic)
        }
    }
}
