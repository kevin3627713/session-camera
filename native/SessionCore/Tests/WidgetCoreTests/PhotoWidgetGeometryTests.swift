import XCTest
import CoreGraphics
@testable import WidgetCore

final class PhotoWidgetGeometryTests: XCTestCase {
    func testOffCenterFocusOnlyTranslatesWindow() {
        let source = CGSize(width: 4000, height: 3000), target = CGSize(width: 160, height: 160)
        let center = PhotoWidgetGeometry.crop(assetSize: source, target: target)
        let left = PhotoWidgetGeometry.crop(assetSize: source, target: target,
            suggestedPixelCrop: CGRect(x: 0, y: 0, width: 800, height: 800))
        let right = PhotoWidgetGeometry.crop(assetSize: source, target: target,
            suggestedPixelCrop: CGRect(x: 3700, y: 2700, width: 200, height: 200))
        XCTAssertEqual(center.size, left.size)
        XCTAssertEqual(center.size, right.size)
        XCTAssertEqual(left.minX, 0)
        XCTAssertEqual(right.maxX, 1)
        XCTAssertEqual(center.minX, 0.125)
        XCTAssertEqual(left.minY, 0)
    }

    func testPortraitFocusMovesUpAndRatiosAreIndependent() {
        let suggestion = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let source = CGSize(width: 3000, height: 4000)
        let square = PhotoWidgetGeometry.crop(assetSize: source, target: CGSize(width: 160, height: 160), suggestedPixelCrop: suggestion)
        let wide = PhotoWidgetGeometry.crop(assetSize: source, target: CGSize(width: 340, height: 160), suggestedPixelCrop: suggestion)
        XCTAssertEqual(square.minY, 0)
        XCTAssertEqual(wide.minY, 0)
        XCTAssertEqual(square.width, 1)
        XCTAssertEqual(wide.width, 1)
        XCTAssertLessThan(wide.height, square.height)
        XCTAssertEqual(wide.height, 0.75 / (340.0 / 160), accuracy: 0.000001)
    }

    func testInvalidFocusAndDimensionsFailToCenterOrZero() {
        let source = CGSize(width: 4000, height: 3000), target = CGSize(width: 160, height: 160)
        let expected = PhotoWidgetGeometry.crop(assetSize: source, target: target)
        for suggestion in [CGRect.null, .zero, CGRect(x: -1, y: 0, width: 200, height: 200),
                           CGRect(x: 3900, y: 0, width: 200, height: 200),
                           CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1)] {
            XCTAssertEqual(PhotoWidgetGeometry.crop(assetSize: source, target: target, suggestedPixelCrop: suggestion), expected)
        }
        XCTAssertEqual(PhotoWidgetGeometry.crop(assetSize: .zero, target: target), .zero)
        XCTAssertEqual(PhotoWidgetGeometry.crop(assetSize: source, target: CGSize(width: CGFloat.infinity, height: 1)), .zero)
    }

    func testSuggestionPixelCoordinatesAreNormalizedWithoutChangingScale() {
        let source = CGSize(width: 4000, height: 3000), target = CGSize(width: 160, height: 160)
        let crop = PhotoWidgetGeometry.crop(assetSize: source, target: target,
            suggestedPixelCrop: CGRect(x: 800, y: 0, width: 2000, height: 2000))
        XCTAssertEqual(crop.minX, 0.075, accuracy: 0.000001)
        XCTAssertEqual(crop.width, 0.75)
        XCTAssertEqual(crop.height, 1)
        XCTAssertEqual(crop.minY, 0)
    }

    func testWidgetLinkRoundTripsAndRejectsOtherDestinations() {
        let id = "A123/L0/001?x=1&y=中文+%"
        XCTAssertEqual(PhotoWidgetLink.url(assetID: id).flatMap(PhotoWidgetLink.assetID), id)
        for raw in ["sessioncamera://camera", "sessioncamera://photos?asset=", "sessioncamera://photos?asset=a&asset=b",
                    "sessioncamera://photos?asset=a&url=https://example.com", "https://photos?asset=a",
                    "sessioncamera://photos/extra?asset=a"] {
            XCTAssertNil(PhotoWidgetLink.assetID(from: URL(string: raw)!))
        }
    }
}
