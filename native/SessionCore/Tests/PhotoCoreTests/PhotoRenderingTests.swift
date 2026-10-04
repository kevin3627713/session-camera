import CoreImage
import ImageIO
import XCTest
@testable import PhotoCore

final class PhotoRenderingTests: XCTestCase {
    func testWideCaptureMatchesPortraitViewfinderAfterEXIFRotation() throws {
        let original = try makeJPEG(width: 640, height: 480, orientation: 6)
        let data = try PhotoRendering.captureJPEG(original, aspect: .wide)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 360)
        XCTAssertEqual(image.height, 640)
        let decoded = try XCTUnwrap(CIImage(data: data, options: [.applyOrientationProperty: true]))
        XCTAssertEqual(decoded.extent.width, 360)
        XCTAssertEqual(decoded.extent.height, 640)
    }

    func testWideAndSquareCapturePreserveLandscapeOrientation() throws {
        let original = try makeJPEG(width: 640, height: 480, orientation: 1)
        for (aspect, width, height) in [(CaptureAspect.wide, 640, 360), (.square, 480, 480)] {
            let data = try PhotoRendering.captureJPEG(original, aspect: aspect)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, width)
            XCTAssertEqual(image.height, height)
        }
    }

    func testStandardCaptureRetainsOriginalCameraJPEGAndMetadata() throws {
        let original = try makeJPEG(width: 640, height: 480, orientation: 6)
        XCTAssertEqual(try PhotoRendering.captureJPEG(original, aspect: .standard), original)
    }

    private func makeJPEG(width: Int, height: Int, orientation: Int) throws -> Data {
        let input = CIImage(color: CIColor(red: 0.3, green: 0.6, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let image = try XCTUnwrap(CIContext().createCGImage(input, from: input.extent))
        let buffer = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(buffer, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return buffer as Data
    }

    func testQuarterTurnChangesPixelDimensionsWithoutOrientationMetadata() throws {
        let input = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
        var adjustments = PhotoAdjustments()
        adjustments.quarterTurns = 1
        let image = try XCTUnwrap(PhotoRendering.cgImage(input, adjustments: adjustments))
        XCTAssertEqual(image.width, 240)
        XCTAssertEqual(image.height, 320)
    }

    func testCropUsesCoordinateSpaceAfterRotation() throws {
        let input = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.9))
            .cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        var adjustments = PhotoAdjustments()
        adjustments.quarterTurns = 1
        adjustments.cropRatio = 1
        adjustments.cropY = 1
        let image = try XCTUnwrap(PhotoRendering.cgImage(input, adjustments: adjustments))
        XCTAssertEqual(image.width, 300)
        XCTAssertEqual(image.height, 300)
    }

    func testCameraEXIFIsBakedExactlyOnceIntoEditedJPEG() throws {
        let input = CIImage(color: CIColor(red: 0, green: 1, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
        let pixels = try XCTUnwrap(CIContext().createCGImage(input, from: input.extent))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, pixels, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let data = try PhotoRendering.jpeg(url: file, adjustments: PhotoAdjustments())
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let result = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(result.width, 240)
        XCTAssertEqual(result.height, 320)
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)) as NSDictionary
        // ImageIO can omit the default/up orientation. If present it must be up.
        let orientation = metadata[kCGImagePropertyOrientation] as? Int
        XCTAssertTrue(orientation == nil || orientation == 1)
        let decoded = try XCTUnwrap(CIImage(data: data, options: [.applyOrientationProperty: true]))
        XCTAssertEqual(decoded.extent.width, 240)
        XCTAssertEqual(decoded.extent.height, 320)
    }
}
