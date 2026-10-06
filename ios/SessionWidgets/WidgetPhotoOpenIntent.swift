import AppIntents
import Foundation

struct OpenWidgetPhoto: AppIntent {
    static var title: LocalizedStringResource = "在系统照片中打开"
    static var isDiscoverable = false
    static var openAppWhenRun = false
    @Parameter(title: "照片") var assetID: String
    @Parameter(title: "小组件编号") var instanceID: String
    init() {}
    init(assetID: String, instanceID: String) { self.assetID = assetID; self.instanceID = instanceID }

    func perform() async throws -> some IntentResult {
        let attempt = WidgetPhotoOpenStatus.begin(instanceID: instanceID)
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try SystemPhotosAsset.resolveURL(for: assetID)
            }.value
            guard let cloudID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value else {
                throw SystemPhotosAsset.Failure.identifierUnavailable
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                SCOpenWidgetPhotoInPhotos(assetID, cloudID) { accepted, error in
                    if accepted { continuation.resume() }
                    else { continuation.resume(throwing: error ?? NSError(domain: "SessionPhotoBridge", code: 10,
                        userInfo: [NSLocalizedDescriptionKey: "无法在系统照片中打开，请重试"])) }
                }
            }
            WidgetPhotoOpenStatus.finish(instanceID: instanceID, attempt: attempt, assetID: assetID, message: nil)
        } catch {
            WidgetPhotoOpenStatus.finish(instanceID: instanceID, attempt: attempt, assetID: assetID,
                                       message: error.localizedDescription)
        }
        // Returning reloads this widget. Never open the camera as a fallback.
        return .result()
    }
}

enum WidgetPhotoOpenStatus {
    private static let lock = NSLock()
    private static func key(_ instanceID: String) -> String { "photoOpenStatus." + instanceID }
    static func begin(instanceID: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let attempt = UUID().uuidString
        UserDefaults.standard.set(["attempt": attempt], forKey: key(instanceID))
        return attempt
    }
    static func finish(instanceID: String, attempt: String, assetID: String, message: String?) {
        lock.lock(); defer { lock.unlock() }
        guard UserDefaults.standard.dictionary(forKey: key(instanceID))?["attempt"] as? String == attempt else { return }
        if let message {
            UserDefaults.standard.set(["attempt": attempt, "assetID": assetID, "message": message,
                "expires": Date().addingTimeInterval(90).timeIntervalSince1970], forKey: key(instanceID))
        } else { UserDefaults.standard.removeObject(forKey: key(instanceID)) }
    }
    static func message(instanceID: String, assetID: String, now: Date = Date()) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let value = UserDefaults.standard.dictionary(forKey: key(instanceID)),
              value["assetID"] as? String == assetID,
              let expires = value["expires"] as? Double, expires > now.timeIntervalSince1970 else { return nil }
        return value["message"] as? String
    }
}
