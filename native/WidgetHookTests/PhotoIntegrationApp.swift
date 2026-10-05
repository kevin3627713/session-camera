import SwiftUI
import Photos
import AppIntents
import WidgetKit

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
        let initialStatus = PhotoLibrarySource.status.rawValue
        do {
            // Request the access level explicitly even after simctl pre-grants it:
            // PhotoKit initializes its read/write authorization state here.
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            try require(PhotoLibrarySource.status == .authorized, "Full Photos authorization")
            func image(_ color: UIColor, pixels: CGFloat = 64) -> UIImage {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                return UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format).image { context in
                    color.setFill(); context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
                    if pixels > 64 {
                        // Fine detail distinguishes a full-quality request from
                        // PhotoKit's tiny provisional thumbnail, even if upscaled.
                        UIColor.white.setFill()
                        for x in stride(from: 0, to: Int(pixels), by: 12) {
                            context.fill(CGRect(x: x, y: 0, width: 6, height: Int(pixels / 3)))
                        }
                    }
                }
            }
            let red = image(.red, pixels: 1800), blue = image(.blue, pixels: 1800)
            let green = image(.green), yellow = image(.yellow)
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
            let pixels = data.flatMap(UIImage.init(data:))?.cgImage
            try require(pixels?.width == 480 && pixels?.height == 480, "Small widget receives three-times point resolution")
            var detailContrast = 0
            if let pixels {
                for row in [80, 400] {
                    var line = [UInt8](repeating: 0, count: 480 * 4)
                    line.withUnsafeMutableBytes { bytes in
                        let context = CGContext(data: bytes.baseAddress, width: 480, height: 1, bitsPerComponent: 8,
                                                bytesPerRow: 480 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                        context.draw(pixels, in: CGRect(x: 0, y: -row, width: 480, height: 480))
                    }
                    let green = stride(from: 1, to: line.count, by: 4).map { Int(line[$0]) }
                    detailContrast = max(detailContrast, green.max()! - green.min()!)
                }
            }
            try require(detailContrast > 160, "Real PhotoKit result retains fine stripe detail rather than an upscaled blurred thumbnail")
            let large = await PhotoLibrarySource.imageData(assetID: redID, size: CGSize(width: 360, height: 380))
            let largePixels = large.flatMap(UIImage.init(data:))?.cgImage
            try require(largePixels?.width == 1080 && largePixels?.height == 1140, "Large widget receives full bounded Retina resolution")
            let target = PhotoLibrarySource.pixelSize(for: CGSize(width: 160, height: 160))
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [picks[0].assetID], options: nil).firstObject!
            let key = PhotoImageCache.key(asset: asset, target: target)
            try require(PhotoImageCache.read(key: key, target: target) == data, "Final-quality JPEG survives beyond one timeline request")
            try require(PhotoImageCache.read(key: key, target: CGSize(width: 1080, height: 1140)) == nil, "Cache rejects a mismatched widget size")
            let repeatData = await PhotoLibrarySource.imageData(assetID: picks[0].assetID, size: CGSize(width: 160, height: 160))
            try require(repeatData == data, "Re-added widget can reuse a stable high-quality cached photo")
            let bounded = PhotoLibrarySource.pixelSize(for: CGSize(width: 1000, height: 2000))
            try require(bounded == CGSize(width: 600, height: 1200), "Requested image dimensions have a bounded longest edge")
            let wideCrop = PhotoLibrarySource.cropRect(assetSize: CGSize(width: 6000, height: 1000), target: target)
            try require(abs(wideCrop.width - 1.0 / 6) < 0.0001 && wideCrop.height == 1,
                        "Panorama request asks PhotoKit for the centered crop before UIImage rendering")
            let tallCrop = PhotoLibrarySource.cropRect(assetSize: CGSize(width: 1000, height: 6000), target: target)
            try require(tallCrop.width == 1 && abs(tallCrop.height - 1.0 / 6) < 0.0001,
                        "Portrait request bounds its crop before UIImage rendering")

            let accepted: Data? = await withCheckedContinuation { continuation in
                let request = PhotoImageRequest(continuation, target: target)
                request.receive(image(.red), info: [PHImageResultIsDegradedKey: true])
                request.receive(blue, info: [PHImageResultIsDegradedKey: false])
                request.finish(nil) // A later timeout must not resume twice.
                request.receive(red, info: nil) // A late callback must not replace it.
            }
            var center = [UInt8](repeating: 0, count: 4)
            if let cgImage = accepted.flatMap(UIImage.init(data:))?.cgImage {
                center.withUnsafeMutableBytes { bytes in
                    let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.draw(cgImage, in: CGRect(x: -240, y: -240, width: 480, height: 480))
                }
            }
            try require(center[2] > 200 && center[0] < 40, "Degraded first callback is ignored and final blue image wins once")
            let cancelled: Data? = await withCheckedContinuation { continuation in
                let request = PhotoImageRequest(continuation, target: target)
                request.receive(red, info: [PHImageCancelledKey: true])
                request.receive(blue, info: nil)
            }
            try require(cancelled == nil, "Cancelled image cannot be accepted or revived by a later callback")

            var configuration = CameraWidgetConfiguration()
            configuration.style = .photos
            configuration.source = resolved[1]
            configuration.identity = identity[0]
            configuration.intervalMinutes = 60
            let provider = CameraWidgetProvider(preset: .blank)
            let now = Date()
            let unavailable = await provider.makeTimeline(for: configuration, size: CGSize(width: 160, height: 160), now: now,
                                                          loadImage: { _, _, _ in nil })
            try require(unavailable.entries.count == 1 && unavailable.entries[0].message != nil,
                        "Failed current photo has a visible message rather than a blank photo entry")
            try require(unavailable.policy == .after(now.addingTimeInterval(300)),
                        "Failed current photo retries after five minutes instead of six periods")
            var loads = 0
            let partial = await provider.makeTimeline(for: configuration, size: CGSize(width: 160, height: 160), now: now,
                                                      loadImage: { _, _, _ in loads += 1; return loads == 1 ? data : nil })
            try require(loads == 1 && partial.entries.count == 1 && partial.entries.allSatisfy { $0.imageData != nil },
                        "Timeline loads and returns only the current photo rather than preloading six images")
            let next = PhotoSchedule.plan(assetIDs: folder, instanceID: identity[0].id, sourceID: resolved[1].id,
                                          minutes: 60, now: now)[1].date
            try require(partial.policy == .after(next),
                        "Single-photo timeline requests reload at its instance-specific next boundary")
            configuration.photoDiagnostic = .library
            loads = 0
            let libraryCheck = await provider.makeTimeline(for: configuration, size: CGSize(width: 160, height: 160),
                                                           loadImage: { _, _, _ in loads += 1; return data })
            try require(loads == 0 && libraryCheck.entries[0].imageData == nil && libraryCheck.entries[0].message?.contains("可用照片：2") == true,
                        "Library diagnostic reports scoped asset count without requesting a photo")
            configuration.photoDiagnostic = .request
            let requestCheck = await provider.makeTimeline(for: configuration, size: CGSize(width: 160, height: 160),
                                                           loadImage: { _, _, _ in data })
            try require(requestCheck.entries[0].imageData == nil && requestCheck.entries[0].message?.contains("480 × 480") == true,
                        "Request diagnostic returns dimensions as text without passing photo bytes to the view")
            configuration.photoDiagnostic = .off
            configuration.source = nil
            let unconfigured = await provider.makeTimeline(for: configuration, size: CGSize(width: 160, height: 160))
            try require(unconfigured.entries[0].style == .photos && unconfigured.entries[0].message?.contains("选择相册") == true,
                        "Re-added photo widget missing its source displays configuration guidance")
            configuration.source = resolved[1]
            configuration.identity = nil
            let unidentified = await provider.makeTimeline(for: configuration, size: CGSize(width: 160, height: 160))
            try require(unidentified.entries[0].message?.contains("独立编号") == true,
                        "Missing identity displays guidance instead of sharing another widget sequence")
            configuration.source = nil
            configuration.photoDiagnostic = .rendering
            loads = 0
            let renderCheck = await provider.makeTimeline(for: configuration, size: CGSize(width: 160, height: 160),
                                                          loadImage: { _, _, _ in loads += 1; return data })
            try require(loads == 0 && renderCheck.entries[0].imageData.flatMap(UIImage.init(data:))?.cgImage?.width == 64,
                        "Rendering diagnostic supplies a tiny synthetic image without a source, identity or PhotoKit request")
            try require(CameraWidgetConfiguration().photoDiagnostic == .off,
                        "Diagnostics are disabled by default for existing and new widgets")
            // Seed a valid file for an ID that PhotoKit does not contain. Unlike
            // deleting a real asset, this needs no system confirmation dialog.
            let missingID = UUID().uuidString + "/L0/001"
            let missingKey = PhotoImageCache.key(assetID: missingID, modified: 0, target: target)
            PhotoImageCache.write(data!, key: missingKey)
            try require(PhotoImageCache.read(key: missingKey, target: target) == data,
                        "Synthetic missing-asset fixture has a valid cached JPEG")
            let missing = await PhotoLibrarySource.imageData(assetID: missingID, size: CGSize(width: 160, height: 160))
            try require(missing == nil, "Cached JPEG cannot make a missing PhotoKit asset accessible")
            try require(!KeepWidgetOnHomeScreen.openAppWhenRun && CameraWidgetConfiguration().tapBehavior == .none, "Default tap does not request app opening")
            _ = try await KeepWidgetOnHomeScreen().perform()
            try require(PhotoLibrarySource.assetIDs(sourceID: "folder:deleted-id").isEmpty, "Deleted sources do not fall back to another album")
            report = ["success": true, "checks": checks, "count": checks.count, "os": ProcessInfo.processInfo.operatingSystemVersionString]
        } catch {
            report = ["success": false, "checks": checks, "error": error.localizedDescription,
                      "initialAuthorization": initialStatus, "authorization": PhotoLibrarySource.status.rawValue,
                      "bundleID": Bundle.main.bundleIdentifier ?? "missing"]
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("widget-photo-integration.json"), options: .atomic)
        }
    }
}
