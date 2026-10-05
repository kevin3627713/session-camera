import Flutter
import UIKit
import XCTest
import CoreImage
import ImageIO
import SwiftUI
@testable import Runner

class RunnerTests: XCTestCase {

  @MainActor
  func testBackgroundPreservesPhotosInFlightCallbacksAndViewRecreation() async throws {
    let store = SessionStore()
    let sessionID = store.sessionID
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = UIHostingController(rootView: CameraScreen(store: store))
    window.makeKeyAndVisible()
    // Mount the actual camera view so its notification handlers are subscribed.
    try await Task.sleep(nanoseconds: 100_000_000)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let data = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
      UIColor.blue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }.jpegData(compressionQuality: 0.9))
    let first = store.issueTicket()
    let inFlight = store.issueTicket()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      // Only remove this test's synthetic files, including failed-save markers.
      Task {
        let ids = Set([first.captureID.uuidString, inFlight.captureID.uuidString])
        let pending = (try? await CaptureVault.shared.pendingFiles()) ?? []
        let files = Set(store.captures.map(\.originalURL) + pending.filter {
          ids.contains($0.deletingPathExtension().lastPathComponent)
        })
        for file in files {
          try? await CaptureVault.shared.markSaved(file)
          await CaptureVault.shared.discardIfSaved(file)
        }
      }
    }
    store.receive(photo: data, ticket: first)
    for _ in 0..<250 {
      if store.capture(first.captureID)?.saveState != nil && store.capture(first.captureID)?.saveState != .saving { break }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    let original = try XCTUnwrap(store.capture(first.captureID)?.originalURL)
    // The second callback arrives after the real view receives background.
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    store.receive(photo: data, ticket: inFlight)
    for _ in 0..<250 {
      if store.capture(inFlight.captureID)?.saveState != nil && store.capture(inFlight.captureID)?.saveState != .saving { break }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertEqual(store.sessionID, sessionID)
    XCTAssertEqual(Set(store.captures.map(\.id)), Set([first.captureID, inFlight.captureID]))
    XCTAssertTrue(store.isCurrent(first))
    XCTAssertTrue(store.isCurrent(inFlight))
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    window.rootViewController = UIHostingController(rootView: CameraScreen(store: store))
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(store.sessionID, sessionID)
    XCTAssertEqual(store.captures.count, 2)
    let relaunched = SessionStore()
    XCTAssertNotEqual(relaunched.sessionID, sessionID)
    XCTAssertTrue(relaunched.captures.isEmpty)
    XCTAssertFalse(relaunched.isCurrent(first))
    XCTAssertFalse(relaunched.isCurrent(inFlight))
  }

  func testRotationIsBakedIntoImagePixels() throws {
    let input = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
      .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
    var adjustments = PhotoAdjustments()
    adjustments.quarterTurns = 1
    let rendered = try XCTUnwrap(PhotoRenderer.render(input, adjustments: adjustments))
    XCTAssertEqual(rendered.imageOrientation, .up)
    XCTAssertEqual(rendered.cgImage?.width, 240)
    XCTAssertEqual(rendered.cgImage?.height, 320)
  }

  func testCropAfterRotationUsesRotatedCoordinateSpace() throws {
    let input = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.9))
      .cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
    var adjustments = PhotoAdjustments()
    adjustments.quarterTurns = 1
    adjustments.cropRatio = 1
    adjustments.cropY = 1
    let rendered = try XCTUnwrap(PhotoRenderer.render(input, adjustments: adjustments))
    XCTAssertEqual(rendered.cgImage?.width, 300)
    XCTAssertEqual(rendered.cgImage?.height, 300)
  }

  func testCameraEXIFOrientationIsAppliedExactlyOnceInEditedJPEG() throws {
    let color = CIImage(color: CIColor(red: 0, green: 1, blue: 0))
      .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
    let pixels = try XCTUnwrap(CIContext().createCGImage(color, from: color.extent))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
    defer { try? FileManager.default.removeItem(at: file) }
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, pixels, [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let edited = try PhotoRenderer.jpeg(url: file, adjustments: PhotoAdjustments())
    let result = try XCTUnwrap(UIImage(data: edited))
    XCTAssertEqual(result.cgImage?.width, 240)
    XCTAssertEqual(result.cgImage?.height, 320)
    XCTAssertEqual(result.imageOrientation, .up)
  }
}
