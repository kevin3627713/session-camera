import XCTest

final class PhotoBridgeUITests: XCTestCase {
    func testColdAndWarmPhotosWithoutLaunchingContainingApp() throws {
        continueAfterFailure = false
        let host = XCUIApplication(bundleIdentifier: "com.kevin3627713.sessioncamera.urlprobe")
        host.launch()
        XCTAssertTrue(host.staticTexts["Fixture ready"].waitForExistence(timeout: 20), host.debugDescription)
        XCUIDevice.shared.press(.home)
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = spring.icons["URL Probe"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10), spring.debugDescription)
        icon.press(forDuration: 1.3)
        let editHome = spring.buttons["Edit Home Screen"]
        XCTAssertTrue(editHome.waitForExistence(timeout: 5), spring.debugDescription)
        editHome.tap()
        spring.buttons["Edit"].tap()
        spring.buttons["Add Widget"].tap()
        let search = spring.searchFields["Search Widgets"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), spring.debugDescription)
        search.tap(); search.typeText("URL Probe")
        let result = spring.staticTexts["URL Probe"].firstMatch
        // The freshly registered widget may take longer to enter the gallery.
        if !result.waitForExistence(timeout: 30) {
            search.buttons["Clear text"].firstMatch.tap()
            search.typeText("URL Probe")
        }
        XCTAssertTrue(result.waitForExistence(timeout: 30), spring.debugDescription)
        result.tap()
        let addWidget = spring.buttons["Add Widget"]
        if addWidget.waitForExistence(timeout: 4) { addWidget.tap() }
        else { spring.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.94)).tap() }
        if spring.buttons["Done"].waitForExistence(timeout: 5) { spring.buttons["Done"].tap() }
        host.terminate()
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        photos.terminate()
        for mode in ["cold", "warm"] {
            let button = spring.buttons["OPEN PHOTO"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 15), spring.debugDescription)
            XCTAssertEqual(host.state, .notRunning)
            button.tap()
            XCTAssertTrue(photos.wait(for: .runningForeground, timeout: 20), spring.debugDescription)
            let proceed = photos.buttons["Continue"].firstMatch
            if proceed.waitForExistence(timeout: 5) { proceed.tap() }
            let pager = photos.scrollViews["OneUpMainPagingView"].firstMatch
            XCTAssertTrue(pager.waitForExistence(timeout: 30), photos.debugDescription)
            // Target red image is 10:13 PM; the blue decoy is 10:14 PM.
            // Apple's formatter inserts U+202F before PM on this simulator.
            let target = photos.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '10:13' AND label CONTAINS 'PM'")).firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 20), photos.debugDescription)
            XCTAssertTrue(photos.staticTexts["November 14, 2023"].exists, photos.debugDescription)
            XCTAssertEqual(host.state, .notRunning, "Containing camera app started")
            print("SCBRIDGE UI mode=\(mode) photosForeground=\(photos.state == .runningForeground) hostState=\(host.state.rawValue) targetTime=10:13PM")
            print("SCBRIDGE UI tree: \(photos.debugDescription)")
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "Photos target \(mode)"; image.lifetime = .keepAlways; add(image)
            XCUIDevice.shared.press(.home)
        }
    }
}
