import AVFoundation
import Combine
import ImageIO
import Photos
import UIKit

enum CaptureKind: String, Codable { case photo, video }
enum SaveState { case saving, saved, failed }

struct SessionCapture: Identifiable {
    let ticket: CaptureTicket
    let kind: CaptureKind
    let originalURL: URL
    var displayURL: URL
    var thumbnail: UIImage?
    var assetID: String?
    var saveState: SaveState = .saving
    var adjustments = PhotoAdjustments()
    var id: UUID { ticket.captureID }
}

enum CameraFailure: LocalizedError {
    case permission, unavailable, expired, invalidImage, missingAsset, saveFailed
    var errorDescription: String? {
        switch self {
        case .permission: return "请在设置中允许相机及照片访问。照片可选「有限访问」。"
        case .unavailable: return "相机暂不可用，请关闭其他使用相机的应用后重试。"
        case .expired: return "本次拍摄已结束，请返回相机重新拍摄。"
        case .invalidImage: return "无法处理这张照片。原图仍然保留。"
        case .missingAsset: return "无法访问这张本次照片。请确认照片权限或它是否已在系统照片中删除。"
        case .saveFailed: return "未能保存到系统照片。原文件已保留，可重试。"
        }
    }
}

/// Crash recovery has no gallery API. Old files can be retried in the background,
/// but no persisted record can become an item in the current session gallery.
actor CaptureVault {
    static let shared = CaptureVault()
    private let root: URL

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask)[0]
            .appendingPathComponent("SessionCamera", isDirectory: true)
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    private func marker(_ file: URL) -> URL { file.appendingPathExtension("pending") }

    func persist(data: Data, id: UUID) throws -> URL {
        try prepare()
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
        // Write the marker first: a crash must never treat an unsaved file as saved.
        try Data().write(to: marker(url), options: .atomic)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }

    func persist(movie: URL, id: UUID) throws -> URL {
        try prepare()
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("mov")
        try Data().write(to: marker(url), options: .atomic)
        try FileManager.default.moveItem(at: movie, to: url)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], atPath: url.path)
        return url
    }

    func markSaved(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: marker(url).path) {
            try FileManager.default.removeItem(at: marker(url))
        }
    }

    func pendingFiles() throws -> [URL] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).filter {
                ["jpg", "mov"].contains($0.pathExtension) &&
                FileManager.default.fileExists(atPath: marker($0).path)
            }
    }

    func discardIfSaved(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: marker(url).path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func cleanupPreviousSavedFiles() throws {
        try prepare()
        for url in try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil) where ["jpg", "mov"].contains(url.pathExtension) {
            discardIfSaved(url)
        }
    }

    func writeEdited(_ data: Data, id: UUID) throws -> URL {
        try prepare()
        let url = root.appendingPathComponent("edit-\(id.uuidString)-\(UUID().uuidString).jpg")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var captures: [SessionCapture] = []
    @Published private(set) var sessionID = UUID()
    @Published var message: String?
    @Published private(set) var pendingRecoveryCount = 0
    @Published private(set) var photosAllowed = false
    private var ledger = SessionLedger()
    private var saving = Set<URL>()
    private var recovering = false
    private var editing = Set<UUID>()
    private let vault = CaptureVault.shared

    init() { sessionID = ledger.sessionID }

    func issueTicket() -> CaptureTicket { ledger.issueTicket() }
    func isCurrent(_ ticket: CaptureTicket) -> Bool { ledger.contains(ticket) }
    func capture(_ id: UUID) -> SessionCapture? { captures.first { $0.id == id } }

    func prepareLibrary() async {
        // Suppress all hardware/permission work in XCTest's hosted process.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) {
                    continuation.resume(returning: $0)
                }
            }
        }
        photosAllowed = status == .authorized || status == .limited ||
            PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized
        do { try await vault.cleanupPreviousSavedFiles() }
        catch { message = error.localizedDescription }
        await retryPending()
    }

    func refreshPermissions() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photosAllowed = status == .authorized || status == .limited ||
            PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized
    }

    func receive(photo data: Data, ticket: CaptureTicket) {
        Task {
            do {
                let url = try await vault.persist(data: data, id: ticket.captureID)
                await registerAndSave(url: url, kind: .photo, ticket: ticket)
            } catch { message = error.localizedDescription }
        }
    }

    func receive(movie url: URL, ticket: CaptureTicket) {
        Task {
            do {
                let persisted = try await vault.persist(movie: url, id: ticket.captureID)
                await registerAndSave(url: persisted, kind: .video, ticket: ticket)
            } catch { message = error.localizedDescription }
        }
    }

    private func registerAndSave(url: URL, kind: CaptureKind, ticket: CaptureTicket) async {
        let thumbnail = await Task.detached(priority: .userInitiated) {
            MediaThumbnails.make(url: url, kind: kind)
        }.value
        if ledger.admit(ticket) {
            captures.append(SessionCapture(ticket: ticket, kind: kind, originalURL: url,
                                           displayURL: url, thumbnail: thumbnail))
        }
        await save(url, kind: kind, ticket: ticket)
    }

    private func save(_ url: URL, kind: CaptureKind, ticket: CaptureTicket?) async {
        guard saving.insert(url).inserted else { return }
        defer { saving.remove(url) }
        do {
            let assetID = try await PhotosWriter.add(url: url, kind: kind)
            try await vault.markSaved(url)
            if let ticket, ledger.contains(ticket),
               let index = captures.firstIndex(where: { $0.ticket == ticket }) {
                captures[index].assetID = assetID
                captures[index].saveState = .saved
            } else {
                await vault.discardIfSaved(url)
            }
        } catch {
            if let ticket, ledger.contains(ticket),
               let index = captures.firstIndex(where: { $0.ticket == ticket }) {
                captures[index].saveState = .failed
            }
            message = error.localizedDescription
        }
    }

    func retryPending() async {
        guard !recovering else { return }
        recovering = true
        defer { recovering = false }
        do {
            let files = try await vault.pendingFiles()
            for url in files {
                let current = captures.first { $0.originalURL == url }
                await save(url, kind: url.pathExtension == "mov" ? .video : .photo,
                           ticket: current?.ticket)
            }
            pendingRecoveryCount = (try await vault.pendingFiles()).count
        } catch { message = error.localizedDescription }
    }

    func resetSession() {
        let previous = captures
        ledger.reset() // Invalidate callbacks BEFORE clearing views or touching files.
        sessionID = ledger.sessionID
        captures.removeAll()
        editing.removeAll()
        Task {
            for item in previous {
                await vault.discardIfSaved(item.originalURL)
                if item.displayURL != item.originalURL {
                    await vault.discardIfSaved(item.displayURL)
                }
            }
        }
    }

    func hide(_ item: SessionCapture) {
        guard ledger.contains(item.ticket), !editing.contains(item.id) else { return }
        ledger.remove(item.ticket)
        captures.removeAll { $0.id == item.id }
        Task {
            await vault.discardIfSaved(item.originalURL)
            if item.displayURL != item.originalURL { await vault.discardIfSaved(item.displayURL) }
        }
    }

    func edit(_ item: SessionCapture, adjustments: PhotoAdjustments) async throws {
        guard ledger.contains(item.ticket) else { throw CameraFailure.expired }
        guard let assetID = item.assetID, item.kind == .photo else { throw CameraFailure.missingAsset }
        guard editing.insert(item.id).inserted else { return }
        defer { editing.remove(item.id) }
        let data = try await Task.detached(priority: .userInitiated) {
            try PhotoRenderer.jpeg(url: item.originalURL, adjustments: adjustments)
        }.value
        guard ledger.contains(item.ticket) else { throw CameraFailure.expired }
        try await PhotosWriter.edit(assetID: assetID, jpeg: data, adjustments: adjustments,
                                    stillCurrent: { self.ledger.contains(item.ticket) })
        guard ledger.contains(item.ticket) else { throw CameraFailure.expired }
        let editedURL = try await vault.writeEdited(data, id: item.id)
        guard ledger.contains(item.ticket),
              let index = captures.firstIndex(where: { $0.id == item.id }) else {
            await vault.discardIfSaved(editedURL)
            throw CameraFailure.expired
        }
        let previousURL = captures[index].displayURL
        captures[index].displayURL = editedURL
        captures[index].thumbnail = MediaThumbnails.make(url: editedURL, kind: .photo)
        captures[index].adjustments = adjustments
        if previousURL != item.originalURL { await vault.discardIfSaved(previousURL) }
    }
}

@MainActor
enum PhotosWriter {
    static func add(url: URL, kind: CaptureKind) async throws -> String {
        let readStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard readStatus == .authorized || readStatus == .limited ||
              PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
            throw CameraFailure.permission
        }
        var identifier: String?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: kind == .photo ? .photo : .video,
                                    fileURL: url, options: nil)
                identifier = request.placeholderForCreatedAsset?.localIdentifier
            }) { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? CameraFailure.saveFailed) }
            }
        }
        guard let identifier else { throw CameraFailure.saveFailed }
        return identifier
    }

    static func edit(assetID: String, jpeg: Data, adjustments: PhotoAdjustments,
                     stillCurrent: @escaping @MainActor () -> Bool) async throws {
        guard stillCurrent() else { throw CameraFailure.expired }
        // The only Photos read in the app. No collection, all-assets or date query.
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject,
              asset.canPerform(.content) else { throw CameraFailure.missingAsset }
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = false
        options.canHandleAdjustmentData = { $0.formatIdentifier == "com.kevin3627713.sessioncamera" }
        let input: PHContentEditingInput = try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                if let input { continuation.resume(returning: input) }
                else { continuation.resume(throwing: CameraFailure.missingAsset) }
            }
        }
        guard stillCurrent() else { throw CameraFailure.expired }
        let output = PHContentEditingOutput(contentEditingInput: input)
        try jpeg.write(to: output.renderedContentURL, options: .atomic)
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: "com.kevin3627713.sessioncamera", formatVersion: "1.0",
            data: try JSONEncoder().encode(adjustments))
        guard stillCurrent() else { throw CameraFailure.expired }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest(for: asset).contentEditingOutput = output
            }) { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? CameraFailure.saveFailed) }
            }
        }
    }
}

enum MediaThumbnails {
    static func make(url: URL, kind: CaptureKind) -> UIImage? {
        if kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900, height: 900)
            guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
            return UIImage(cgImage: image)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
