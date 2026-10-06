import XCTest

final class ProbeUITests: XCTestCase {
    func testActualWidgetRoutes() throws {
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
        if spring.buttons["Edit"].exists {
            spring.buttons["Edit"].tap()
            spring.buttons["Add Widget"].tap()
        } else {
            let add = spring.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add'")).firstMatch
            XCTAssertTrue(add.exists, spring.debugDescription)
            add.tap()
        }
        let search = spring.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), spring.debugDescription)
        search.tap()
        search.typeText("URL Probe")
        let result = spring.staticTexts["URL Probe"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), spring.debugDescription)
        result.tap()
        let addWidget = spring.buttons["Add Widget"]
        XCTAssertTrue(addWidget.waitForExistence(timeout: 10), spring.debugDescription)
        addWidget.tap()
        if spring.buttons["Done"].waitForExistence(timeout: 5) { spring.buttons["Done"].tap() }
        // A terminated containing app proves a route cannot reuse its foreground.
        host.terminate()
        XCUIDevice.shared.press(.home)
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        for route in ["DIRECT", "SENSITIVE", "SHARE"] {
            XCUIDevice.shared.press(.home)
            let button = spring.buttons[route].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 30), spring.debugDescription)
            let screenshot = XCTAttachment(screenshot: spring.screenshot())
            screenshot.name = "Before \(route)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            button.tap()
            let enteredPhotos = photos.wait(for: .runningForeground, timeout: 15)
            let openedHost = host.state == .runningForeground
            print("SCURLPROBE UI route=\(route) photosForeground=\(enteredPhotos) hostForeground=\(openedHost) hostState=\(host.state.rawValue)")
            print("SCURLPROBE UI tree \(route): \(enteredPhotos ? photos.debugDescription : spring.debugDescription)")
            let after = XCTAttachment(screenshot: spring.screenshot())
            after.name = "After \(route)"
            after.lifetime = .keepAlways
            add(after)
            photos.terminate()
            host.terminate()
        }
    }
}
