import CoreImage
import ImageIO
import XCTest
@testable import PhotoCore

final class PhotoRenderingTests: XCTestCase {
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
        XCTAssertEqual(metadata[kCGImagePropertyOrientation] as? Int, 1)
    }
}
