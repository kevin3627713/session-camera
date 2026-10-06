import Flutter
import UIKit
import SwiftUI

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nativeChannel: FlutterMethodChannel?
  private var privacyCover: UIView?
  private var photoNavigationCover: UIView?
  private var photoNavigationToken: UUID?
  private var photoNavigationAssetID: String?
  private var preparedPhotoURL: URL?
  private var openingPhotos = false
  private var photoNavigationError: String?
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
        // A photo widget launch should transfer to Photos before starting the
        // camera. If this bridge arrives first, routing can cover the camera.
        guard self.photoNavigationToken == nil else { reply(nil); return }
        self.presentCamera { reply(nil) }
      }
    }
    if let url = launchOptions?[.url] as? URL, let id = PhotoWidgetLink.assetID(from: url) {
      preparePhotoNavigation(assetID: id)
    }
    return result
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if let id = PhotoWidgetLink.assetID(from: url) {
      preparePhotoNavigation(assetID: id)
      return true
    }
    if url.scheme == "sessioncamera", url.host == "photos" { return false }
    // Consume the URL natively instead of Flutter's named-route mechanism.
    if url.scheme == "sessioncamera", url.host == "camera" {
      clearPhotoNavigation()
      photoNavigationError = nil
      presentCamera()
      return true
    }
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
    if photoNavigationToken != nil {
      showPhotoNavigationCover()
      openPreparedPhotoIfActive()
    } else {
      presentCamera { [weak self] in self?.showPhotoNavigationError() }
    }
  }

  private func presentCamera(completion: (() -> Void)? = nil) {
    guard UIApplication.shared.applicationState == .active,
          photoNavigationToken == nil,
          let controller = window?.rootViewController else { completion?(); return }
    guard controller.presentedViewController == nil else { completion?(); return }
    let camera = UIHostingController(rootView: CameraScreen(store: sessionStore))
    camera.modalPresentationStyle = .fullScreen
    camera.isModalInPresentation = true
    controller.present(camera, animated: false, completion: completion)
  }

  private func preparePhotoNavigation(assetID: String) {
    if photoNavigationAssetID == assetID, photoNavigationToken != nil { return }
    let token = UUID()
    photoNavigationToken = token
    photoNavigationAssetID = assetID
    preparedPhotoURL = nil
    openingPhotos = false
    photoNavigationError = nil
    showPhotoNavigationCover()
    // Cloud mappings are computed only on an explicit photo-widget tap.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = Result { try SystemPhotosNavigation.resolveURL(for: assetID) }
      DispatchQueue.main.async {
        guard let self, self.photoNavigationToken == token else { return }
        switch result {
        case .success(let url):
          self.preparedPhotoURL = url
          self.openPreparedPhotoIfActive()
        case .failure(let error): self.finishPhotoNavigation(error: error.localizedDescription)
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
      guard let self, self.photoNavigationToken == token else { return }
      self.finishPhotoNavigation(error: "照片打开超时，请重试")
    }
  }

  private func openPreparedPhotoIfActive() {
    guard UIApplication.shared.applicationState == .active, !openingPhotos,
          let token = photoNavigationToken, let id = photoNavigationAssetID,
          let url = preparedPhotoURL else { return }
    openingPhotos = true
    SystemPhotosNavigation.open(url, assetID: id) { [weak self] accepted in
      guard let self, self.photoNavigationToken == token else { return }
      // UIKit's acknowledgement means Photos accepted the URL; it cannot
      // verify which image the private Photos navigation UI ultimately shows.
      self.finishPhotoNavigation(error: accepted ? nil : "系统照片未能打开这张照片")
    }
  }

  private func showPhotoNavigationCover() {
    guard photoNavigationCover == nil, UIApplication.shared.applicationState == .active, let window else { return }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .black
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.color = .white
    spinner.startAnimating()
    let label = UILabel()
    label.text = "正在打开照片"
    label.textColor = .white
    label.font = .systemFont(ofSize: 15)
    let stack = UIStackView(arrangedSubviews: [spinner, label])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(stack)
    NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
                                 stack.centerYAnchor.constraint(equalTo: cover.centerYAnchor)])
    window.addSubview(cover)
    photoNavigationCover = cover
  }

  private func clearPhotoNavigation() {
    photoNavigationToken = nil
    photoNavigationAssetID = nil
    preparedPhotoURL = nil
    openingPhotos = false
    photoNavigationCover?.removeFromSuperview()
    photoNavigationCover = nil
  }

  private func finishPhotoNavigation(error: String?) {
    clearPhotoNavigation()
    photoNavigationError = error
    presentCamera { [weak self] in self?.showPhotoNavigationError() }
  }

  private func showPhotoNavigationError() {
    guard UIApplication.shared.applicationState == .active, let message = photoNavigationError,
          var controller = window?.rootViewController else { return }
    while let presented = controller.presentedViewController { controller = presented }
    guard !controller.isBeingDismissed else { return }
    photoNavigationError = nil
    let alert = UIAlertController(title: "无法打开照片", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    controller.present(alert, animated: true)
  }
}
