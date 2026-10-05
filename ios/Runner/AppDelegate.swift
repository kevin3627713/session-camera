import Flutter
import UIKit
import SwiftUI

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nativeChannel: FlutterMethodChannel?
  private var privacyCover: UIView?
  // A camera view may be recreated; the capture session belongs to this process.
  private let sessionStore = SessionStore()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      nativeChannel = FlutterMethodChannel(name: "session_camera/native", binaryMessenger: controller.binaryMessenger)
      nativeChannel?.setMethodCallHandler { [weak self, weak controller] call, reply in
        guard call.method == "openCamera" else { reply(FlutterMethodNotImplemented); return }
        guard let self, let controller else { reply(FlutterError(code: "no_controller", message: "相机启动失败", details: nil)); return }
        guard controller.presentedViewController == nil else { reply(nil); return }
        let camera = UIHostingController(rootView: CameraScreen(store: self.sessionStore))
        camera.modalPresentationStyle = .fullScreen
        camera.isModalInPresentation = true
        controller.present(camera, animated: false) { reply(nil) }
      }
    }
    return result
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // The native camera already opens on launch/resume. Do not route the
    // widget URL into Flutter's single-screen shell as a named route.
    if url.scheme == "sessioncamera", url.host == "camera" { return true }
    return super.application(app, open: url, options: options)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    // A synchronous opaque cover protects app-switcher snapshots, including an
    // editor or a full-screen video. Inactivity alone does not reset the session.
    if privacyCover == nil, let window {
      let cover = UIView(frame: window.bounds)
      cover.backgroundColor = .black
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(cover)
      privacyCover = cover
    }
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
