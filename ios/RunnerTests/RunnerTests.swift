import Flutter
import UIKit
import XCTest
import CoreImage
import ImageIO
@testable import Runner

class RunnerTests: XCTestCase {

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
