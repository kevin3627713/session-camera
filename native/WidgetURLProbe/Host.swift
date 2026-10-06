import UIKit
import Photos

@main final class ProbeHost: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        NSLog("SCURLPROBE host launch")
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        let label = UILabel(frame: CGRect(x: 30, y: 160, width: 330, height: 200))
        label.textColor = .white
        label.numberOfLines = 0
        label.text = "Preparing synthetic Photos fixture"
        label.accessibilityIdentifier = "probe-status"
        controller.view.addSubview(label)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        Task { @MainActor in
            guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
                label.text = "Photos authorization required"
                return
            }
            let fixtures: [(UIColor, String)] = [(.systemRed, "URL ROUTE TARGET"), (.systemBlue, "DECOY PHOTO")]
            let images = fixtures.map { color, text in
                UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1000)).image { context in
                    color.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000))
                    (text as NSString).draw(at: CGPoint(x: 50, y: 450), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 70), .foregroundColor: UIColor.white])
                }
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for (index, image) in images.enumerated() {
                        let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                        request.creationDate = Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60))
                    }
                }
                label.text = "Fixture ready"
                NSLog("SCURLPROBE synthetic fixture ready")
            } catch { label.text = "Fixture failed: \(error.localizedDescription)" }
        }
        return true
    }
    func applicationDidBecomeActive(_ application: UIApplication) { NSLog("SCURLPROBE host became active") }
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        NSLog("SCURLPROBE host received a widget URL")
        return true
    }
}
