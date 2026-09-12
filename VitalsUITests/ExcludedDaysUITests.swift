import XCTest

/// Walks the Excluded Days feature end to end in the Pro settings scene: the
/// Settings row opens the screen, the pause switch starts a pause, and the
/// paused banner then follows the user across tabs and can resume from there.
///
/// `app.swipeUp()` is the scroll gesture here, deliberately. A coordinate
/// press-and-drag does not move this sheet at all (measured: sixteen of them
/// left the form exactly where it started), and `collectionViews.firstMatch`
/// resolves to a tab view behind the sheet rather than the form.
///
/// The banner is the half worth a UI test. It is the only piece of this feature
/// that renders outside the screen that owns it, and a pause nobody can see is
/// indistinguishable from averages that stopped working.
final class ExcludedDaysUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    func testSettingsRowOpensTheExcludedDaysScreen() {
        let app = launchSettings()
        openExcludedDays(app)

        XCTAssertTrue(
            app.switches["Pause averages"].waitForExistence(timeout: 10),
            "Pause switch missing from Excluded Days"
        )
        attach(app.screenshot(), name: "excluded-days-screen")
    }

    func testPausingShowsTheBannerOnEveryTabAndResumeClearsIt() {
        let app = launchSettings()
        openExcludedDays(app)

        let pause = app.switches["Pause averages"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "Pause switch missing")
        setSwitch(pause, on: true)
        XCTAssertEqual(pause.value as? String, "1", "Pause switch did not flip on")
        attach(app.screenshot(), name: "excluded-days-paused")

        // Back out of Settings entirely so the tabs are on screen.
        app.navigationBars["Excluded Days"].buttons.firstMatch.tap()
        let done = app.navigationBars["Settings"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Settings never came back")
        done.tap()

        let banner = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Averages paused")
        ).firstMatch
        XCTAssertTrue(
            banner.waitForExistence(timeout: 10),
            "Paused banner missing on Today"
        )
        attach(app.screenshot(), name: "paused-banner-today")

        app.buttons["History"].tap()
        XCTAssertTrue(banner.exists, "Paused banner missing on History")

        let resume = app.buttons["Resume"]
        XCTAssertTrue(resume.isHittable, "Resume button is not tappable")
        resume.tap()
        XCTAssertTrue(
            waitForDisappearance(of: banner, timeout: 10),
            "Resume left the paused banner on screen"
        )
        attach(app.screenshot(), name: "banner-resumed")
    }

    // MARK: - Helpers

    private func launchSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "settingsPro"
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 180),
            "Settings sheet never appeared"
        )
        _ = app.switches["Show Macros"].waitForExistence(timeout: 10)
        return app
    }

    private func openExcludedDays(_ app: XCUIApplication) {
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Excluded Days")
        ).firstMatch
        for _ in 0..<16 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "Excluded Days row never scrolled into view")
        row.tap()
        XCTAssertTrue(
            app.navigationBars["Excluded Days"].waitForExistence(timeout: 10),
            "Excluded Days row did not navigate"
        )
    }

    /// A SwiftUI Toggle in a Form answers a row tap, but the row's centre is the
    /// label, and the value it reports settles a beat after the gesture. Poll,
    /// then fall back to the switch itself before calling it a failure.
    private func setSwitch(_ element: XCUIElement, on: Bool, timeout: TimeInterval = 5) {
        let wanted = on ? "1" : "0"
        element.tap()
        if waitForValue(element, equals: wanted, timeout: timeout) { return }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        _ = waitForValue(element, equals: wanted, timeout: timeout)
    }

    private func waitForValue(_ element: XCUIElement, equals value: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == value { return true }
            usleep(150_000)
        }
        return element.value as? String == value
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(100_000)
        }
        return !element.exists
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
