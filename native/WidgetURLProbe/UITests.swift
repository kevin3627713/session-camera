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
        // SpringBoard's tree also includes an offscreen App Library search.
        // Select the visible gallery field explicitly.
        let search = spring.searchFields["Search Widgets"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), spring.debugDescription)
        search.tap()
        search.typeText("URL Probe")
        let result = spring.staticTexts["URL Probe"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), spring.debugDescription)
        result.tap()
        let addWidget = spring.buttons["Add Widget"]
        if addWidget.waitForExistence(timeout: 4) {
            addWidget.tap()
        } else {
            // On iOS 18 the gallery preview is a remote view whose AX server
            // can be unavailable to XCTest. The captured iPhone 16 Pro screen
            // places the visible Add Widget button at this fixed bottom point.
            spring.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.94)).tap()
        }
        if spring.buttons["Done"].waitForExistence(timeout: 5) { spring.buttons["Done"].tap() }
        // A terminated containing app proves a route cannot reuse its foreground.
        host.terminate()
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        for route in ["DIRECT", "SENSITIVE", "SHARE", "MAIN BG"] {
            if spring.state != .runningForeground { XCUIDevice.shared.press(.home) }
            let button = spring.buttons[route].firstMatch
            XCTAssertFalse(spring.staticTexts["NO FIXTURE"].exists, "Widget could not obtain its synthetic photo: \(spring.debugDescription)")
            let screenshot = XCTAttachment(screenshot: spring.screenshot())
            screenshot.name = "Before \(route)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            if button.waitForExistence(timeout: 5) {
                button.tap()
            } else {
                let group = spring.otherElements["url-route-probe"].firstMatch
                let frame = group.exists ? group.frame : CGRect(x: 18, y: 88, width: 366, height: 174)
                let x: CGFloat = ["DIRECT", "SHARE"].contains(route) ? 0.34 : 0.68
                let y: CGFloat = ["DIRECT", "SENSITIVE"].contains(route) ? 0.43 : 0.67
                spring.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.minX + frame.width*x, dy: frame.minY + frame.height*y)).tap()
            }
            let enteredPhotos = photos.wait(for: .runningForeground, timeout: 15)
            if enteredPhotos {
                // Foreground state can precede the Photos window. Observe after
                // the cold-start transition instead of capturing its black launch.
                _ = photos.buttons["Edit"].waitForExistence(timeout: 30)
                print("SCURLPROBE UI settled route=\(route) photosForeground=\(photos.state == .runningForeground) hostState=\(host.state.rawValue) editVisible=\(photos.buttons["Edit"].exists)")
            }
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
