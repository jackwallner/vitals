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

    /// The banner is a standing notice, so the thing that matters most is that
    /// it is absent when nothing is paused. A bar that is always there teaches
    /// people to stop reading it.
    func testNoBannerUntilSomethingIsPaused() {
        let app = launchSettings()
        dismissSettings(app)

        XCTAssertFalse(pausedBanner(app).exists, "Banner showing on Today with nothing paused")
        XCTAssertFalse(app.buttons["Resume"].exists, "Resume showing with nothing paused")

        app.buttons["History"].tap()
        XCTAssertFalse(pausedBanner(app).exists, "Banner showing on History with nothing paused")

        app.buttons["Vitals+"].tap()
        XCTAssertFalse(pausedBanner(app).exists, "Banner showing on Vitals+ with nothing paused")
        attach(app.screenshot(), name: "no-banner-unpaused")
    }

    /// The banner's other job: it is the way back to the screen that started the
    /// pause, from wherever the user happens to be.
    func testBannerOpensTheExcludedDaysScreen() {
        let app = launchSettings()
        openExcludedDays(app)
        setSwitch(app.switches["Pause averages"], on: true)
        dismissSettings(app, fromExcludedDays: true)

        let banner = pausedBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Paused banner missing")
        banner.tap()
        XCTAssertTrue(
            app.navigationBars["Excluded Days"].waitForExistence(timeout: 10),
            "Tapping the banner did not open Excluded Days"
        )
        attach(app.screenshot(), name: "banner-opens-screen")

        // And the pause it reports is the one the screen shows.
        XCTAssertEqual(app.switches["Pause averages"].value as? String, "1")
        app.navigationBars["Excluded Days"].buttons["Done"].tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Banner gone after closing the sheet")
    }

    /// Tapping a date on the calendar is the primary gesture of the whole
    /// feature: it has to both take and show.
    func testTappingACalendarDayExcludesIt() {
        let app = launchSettings()
        openExcludedDays(app)

        XCTAssertTrue(
            app.staticTexts["No days excluded"].waitForExistence(timeout: 10),
            "Excluded Days did not start empty"
        )

        let dayCell = calendarDay(app, dayOfMonth: 1)
        XCTAssertTrue(dayCell.exists, "No tappable day cell found in the calendar")
        dayCell.tap()

        XCTAssertTrue(
            app.staticTexts["1 Excluded Day"].waitForExistence(timeout: 10),
            "Tapping a calendar day did not add it to the excluded list"
        )
        attach(app.screenshot(), name: "calendar-day-excluded")

        dayCell.tap()
        XCTAssertTrue(
            app.staticTexts["No days excluded"].waitForExistence(timeout: 10),
            "Tapping the day again did not put it back"
        )
    }

    /// The shortcut people will actually find: long-press the day in History
    /// that looks wrong, exclude it there, and see the figures say so.
    func testExcludingADayFromHistoryMarksItAndSaysSo() {
        let app = launchSettings()
        dismissSettings(app)

        app.buttons["History"].tap()
        // By identifier, not a "Calories" label prefix: the average cards above
        // the chart match that prefix too, and a tap on one of those goes nowhere.
        let caloriesCard = app.buttons["chart-card-link-Calories"]
        XCTAssertTrue(caloriesCard.waitForExistence(timeout: 20), "Calories chart card missing")

        // The History tab is still settling its first load when the card appears,
        // and a tap that lands mid-layout is dropped. Retry until the push lands.
        let recentDays = app.staticTexts["Recent Days"]
        for _ in 0..<3 where !recentDays.waitForExistence(timeout: 5) {
            if caloriesCard.isHittable { caloriesCard.tap() }
        }
        XCTAssertTrue(recentDays.waitForExistence(timeout: 10), "Calories history never opened")
        for _ in 0..<8 where !recentDays.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(recentDays.isHittable, "Recent Days never scrolled into view")

        let row = app.descendants(matching: .any)
            .matching(identifier: "recent-day-row")
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "No Recent Days row to long-press")
        row.press(forDuration: 1.0)

        let exclude = app.buttons["Exclude from Averages"]
        XCTAssertTrue(exclude.waitForExistence(timeout: 10), "Long-press menu missing the exclude action")
        exclude.tap()

        XCTAssertTrue(
            app.staticTexts["1 day excluded from these figures"].waitForExistence(timeout: 10),
            "History did not report the excluded day"
        )
        XCTAssertTrue(app.staticTexts["EXCLUDED"].exists, "Excluded row is not badged")
        attach(app.screenshot(), name: "history-excluded-day")
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

    /// Leaves the Settings sheet, from the Excluded Days screen or the sheet root.
    private func dismissSettings(_ app: XCUIApplication, fromExcludedDays: Bool = false) {
        if fromExcludedDays {
            app.navigationBars["Excluded Days"].buttons.firstMatch.tap()
        }
        let done = app.navigationBars["Settings"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Settings Done button missing")
        done.tap()
        XCTAssertTrue(
            waitForDisappearance(of: app.navigationBars["Settings"], timeout: 10),
            "Settings sheet did not dismiss"
        )
    }

    private func pausedBanner(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Averages paused")).firstMatch
    }

    /// MultiDatePicker labels each cell with its full weekday and date
    /// ("Tuesday, September 1"), so the label is built from the same calendar
    /// the picker opens on rather than hard-coded.
    private func calendarDay(_ app: XCUIApplication, dayOfMonth: Int) -> XCUIElement {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: Date())
        components.day = dayOfMonth
        guard let date = calendar.date(from: components) else { return app.buttons.firstMatch }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return app.buttons[formatter.string(from: date)]
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
