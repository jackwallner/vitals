import XCTest

/// Landscape on wide phones. A Plus or Pro Max held sideways is regular width,
/// so `UnfoldedSplit` puts Today on the left and History on the right and
/// drops the History tab. A standard-width phone stays one column with three
/// tabs. Every test attaches screenshots for visual review and asserts the
/// layout from element frames, so a pane that overlaps, clips or vanishes
/// fails here rather than in a review.
///
/// Run on both shapes, a Pro Max (split) and a Pro (single column), each on a
/// freshly erased simulator so the Health sheet appears and the seed loads.
/// Tests read the window's short side to know which layout to expect.
/// XCTest screenshots of a rotated simulator come back rotated and cropped;
/// capture landscape frames with `xcrun simctl io <udid> screenshot` instead.
final class LandscapeSplitUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Plus and Pro Max phones (430 pt wide or more in portrait) are regular
    /// width in landscape; narrower phones stay compact. `EXPECT_SPLIT=0|1`
    /// (`TEST_RUNNER_EXPECT_SPLIT` on the xcodebuild line) overrides.
    private var expectsSplit: Bool {
        if let forced = ProcessInfo.processInfo.environment["EXPECT_SPLIT"] { return forced == "1" }
        let frame = XCUIApplication().windows.firstMatch.frame
        return min(frame.width, frame.height) >= 428
    }

    // MARK: - Tests

    func testRotateFromTodayAndBack() {
        let app = launchSeeded()
        waitForTodayContent(app)
        shot("portrait-today", app)
        XCTAssertTrue(app.buttons["History"].exists, "portrait lost the History tab")

        rotate(.landscapeLeft, app)
        shot("landscape-today", app)
        assertLandscapeLayout(app)

        rotate(.portrait, app)
        shot("portrait-again", app)
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 5), "History tab missing after rotating back")
        assertTodayContent(app, inLeftHalf: false)
        tapTab("History", app)
        XCTAssertTrue(historyPaneMarker(app).waitForExistence(timeout: 15), "History tab empty after rotating back")
        shot("portrait-history", app)
    }

    func testRotateWhileOnHistoryTab() {
        let app = launchSeeded()
        waitForTodayContent(app)
        tapTab("History", app)
        XCTAssertTrue(historyPaneMarker(app).waitForExistence(timeout: 15), "History tab empty in portrait")

        rotate(.landscapeRight, app)
        shot("landscape-from-history", app)
        assertLandscapeLayout(app)

        rotate(.portrait, app)
        shot("portrait-from-history", app)
        // Split moved the selection to Today; portrait must still show a real tab.
        XCTAssertTrue(
            app.buttons["Calorie progress"].firstMatch.isHittable || historyPaneMarker(app).isHittable,
            "no tab content visible after rotating back"
        )
    }

    func testLaunchAlreadyLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launchSeeded()
        waitForTodayContent(app)
        settle()
        shot("cold-landscape", app)
        assertLandscapeLayout(app)
    }

    func testUpgradeTabInLandscape() {
        let app = launchSeeded()
        waitForTodayContent(app)
        rotate(.landscapeLeft, app)
        tapTab("Upgrade", app)
        let window = app.windows.firstMatch.frame
        let purchase = app.buttons["paywall-purchase"].firstMatch
        XCTAssertTrue(purchase.waitForExistence(timeout: 20), "no purchase button on Upgrade in landscape")
        // Hold long enough for the simctl frame grabber to catch the settled paywall.
        sleep(5)
        shot("landscape-upgrade", app)
        XCTAssertTrue(purchase.isHittable, "purchase button not tappable in landscape")
        // The CTA glow inflates the accessibility frame's height, so check the
        // 50pt capsule's top edge and width rather than the whole frame.
        XCTAssertLessThanOrEqual(purchase.frame.minY + 50, window.maxY, "purchase button off screen: \(purchase.frame) in \(window)")
        XCTAssertGreaterThanOrEqual(purchase.frame.minX, window.minX, "purchase button off screen: \(purchase.frame) in \(window)")
        // Drag inside the left pane so the History pane in a split stays put.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.1)))
        sleep(4)
        shot("landscape-upgrade-plans", app)
        XCTAssertTrue(purchase.isHittable, "purchase button lost after scrolling the plans")
        if expectsSplit {
            XCTAssertLessThanOrEqual(purchase.frame.maxX, window.midX + 2, "paywall spilled into the History pane")
            XCTAssertTrue(historyPaneMarker(app).isHittable, "History pane hidden behind the paywall")
        }
        tapTab("Today", app)
        assertLandscapeLayout(app)
    }

    func testSettingsAndMetricDetailInLandscape() {
        let app = launchSeeded()
        waitForTodayContent(app)
        rotate(.landscapeLeft, app)

        openSettings(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20), "Settings did not open in landscape")
        shot("landscape-settings", app)
        scrollDown(app, times: 4)
        shot("landscape-settings-scrolled", app)
        XCTAssertTrue(app.buttons["Done"].firstMatch.isHittable || app.buttons["Close"].firstMatch.isHittable,
                      "no way to close Settings in landscape")
        (app.buttons["Done"].firstMatch.exists ? app.buttons["Done"].firstMatch : app.buttons["Close"].firstMatch).tap()
        settle()

        let calories = app.buttons["Calorie progress"].firstMatch
        XCTAssertTrue(calories.waitForExistence(timeout: 10), "Calorie ring missing in landscape")
        calories.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Calories"].waitForExistence(timeout: 15), "Calories detail did not open")
        settle()
        shot("landscape-calories-detail", app)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.isHittable, "no back button on Calories detail in landscape")
        back.tap()
        settle()
        assertLandscapeLayout(app)
    }

    func testDeepLinksInLandscape() {
        let app = launchSeeded()
        waitForTodayContent(app)
        rotate(.landscapeLeft, app)
        openLink("metric/steps", app)
        XCTAssertTrue(app.navigationBars.staticTexts["Steps"].waitForExistence(timeout: 15), "steps link did not open Steps")
        shot("landscape-dl-steps", app)
        openLink("today", app)
        settle()
        shot("landscape-dl-today", app)
        assertLandscapeLayout(app)
    }

    func testVitalsPlusUserInLandscape() {
        let app = launchSeeded()
        waitForTodayContent(app)
        buyOnTestStore(app)
        rotate(.landscapeLeft, app)
        shot("landscape-pro-today", app)
        assertLandscapeLayout(app, freeUser: false)
        tapTab("Vitals+", app)
        settle()
        shot("landscape-pro-tab", app)
        tapTab("Today", app)
        assertLandscapeLayout(app, freeUser: false)
    }

    func testLargeTextInLandscape() {
        let app = launchSeeded(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        waitForTodayContent(app)
        rotate(.landscapeLeft, app)
        shot("landscape-large-text", app)
        let window = app.windows.firstMatch.frame
        for tab in tabsExpected() {
            let button = app.buttons[tab]
            XCTAssertTrue(button.exists, "\(tab) tab missing at large text in landscape")
            XCTAssertTrue(window.contains(button.frame), "\(tab) tab off screen at large text")
        }
        scrollDown(app, times: 3)
        shot("landscape-large-text-scrolled", app)
    }

    // MARK: - Layout assertions

    private func tabsExpected() -> [String] {
        expectsSplit ? ["Today", "Upgrade"] : ["Today", "History", "Upgrade"]
    }

    /// Split: Today in the left half, History in the right half, no History
    /// tab, the tab capsule inside the left pane. Single column: three tabs,
    /// Today content visible.
    private func assertLandscapeLayout(_ app: XCUIApplication, freeUser: Bool = true,
                                       file: StaticString = #filePath, line: UInt = #line) {
        clearPitch(app)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "not landscape: \(window)", file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, "app not running after rotation", file: file, line: line)

        guard expectsSplit else {
            XCTAssertTrue(app.buttons["History"].exists, "standard phone lost the History tab in landscape", file: file, line: line)
            assertTodayContent(app, inLeftHalf: false, file: file, line: line)
            return
        }

        XCTAssertFalse(app.buttons["History"].exists, "split still shows a History tab", file: file, line: line)
        assertTodayContent(app, inLeftHalf: true, file: file, line: line)

        let historyMarker = historyPaneMarker(app)
        XCTAssertTrue(historyMarker.waitForExistence(timeout: 15), "History pane empty in split\n\(app.debugDescription)",
                      file: file, line: line)
        XCTAssertTrue(historyMarker.isHittable, "History pane not visible in split", file: file, line: line)
        XCTAssertGreaterThanOrEqual(historyMarker.frame.minX, window.midX - 2,
                                    "History content crosses into the Today pane: \(historyMarker.frame)", file: file, line: line)
        XCTAssertLessThanOrEqual(historyMarker.frame.maxX, window.maxX + 1,
                                 "History content runs off the right edge: \(historyMarker.frame)", file: file, line: line)

        let today = app.buttons["Today"]
        XCTAssertTrue(today.isHittable, "Today tab not tappable in split", file: file, line: line)
        XCTAssertLessThanOrEqual(today.frame.maxX, window.midX + 2, "tab capsule spills into History: \(today.frame)",
                                 file: file, line: line)
        _ = freeUser
    }

    private func assertTodayContent(_ app: XCUIApplication, inLeftHalf: Bool,
                                    file: StaticString = #filePath, line: UInt = #line) {
        // The calorie ring is Today's own; a "Calories" label also titles a History chart.
        let calories = app.buttons["Calorie progress"].firstMatch
        XCTAssertTrue(calories.waitForExistence(timeout: 15), "Today content missing", file: file, line: line)
        guard inLeftHalf else { return }
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(calories.frame.maxX, window.midX + 2,
                                 "Today content crosses into the History pane: \(calories.frame)", file: file, line: line)
    }

    /// History's period picker: drawn with or without data, and only by History.
    private func historyPaneMarker(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["30D"].firstMatch
    }

    // MARK: - Driving the app

    private func launchSeeded(staleProCache: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        if staleProCache { app.launchEnvironment["VITALS_STALE_PRO_CACHE"] = "1" }
        app.launchEnvironment["VITALS_RC_APP_USER_ID"] = "uitest-vitals-\(UUID().uuidString)"
        app.launchEnvironment["VITALS_SEED_HEALTH"] = "1"
        app.launchEnvironment["VITALS_FORCE_SETUP_COMPLETE"] = "1"
        app.launchEnvironment["VITALS_UPGRADE_TAB"] = "feature_led"
        app.launchArguments += arguments
        app.launch()
        grantHealthKitAccess(app)
        return app
    }

    private func waitForTodayContent(_ app: XCUIApplication) {
        let deadline = Date.now.addingTimeInterval(30)
        while Date.now < deadline {
            clearPitch(app)
            if app.buttons["Today"].exists, app.staticTexts["Calories"].firstMatch.exists {
                // Seeded data must load, or every layout below is judged on an
                // error card. A simulator holding an old Health decision for the
                // app never shows the permission sheet: erase it before the run.
                XCTAssertFalse(app.staticTexts["Couldn't refresh Health data"].waitForExistence(timeout: 4),
                               "seeded Health data did not load; erase the simulator and rerun")
                return
            }
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.5)
        }
        XCTFail("Today never loaded\n\(app.debugDescription)")
    }

    private func rotate(_ orientation: UIDeviceOrientation, _ app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        settle()
        clearPitch(app)
    }

    private func settle() {
        _ = XCUIApplication().buttons["nonexistent"].waitForExistence(timeout: 2.5)
    }

    private func tapTab(_ label: String, _ app: XCUIApplication) {
        clearPitch(app)
        let tab = app.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(label) tab missing")
        XCTAssertTrue(waitForHittable(tab, timeout: 10), "\(label) tab not tappable")
        tab.tap()
    }

    /// Buys from the Upgrade tab on the RevenueCat Test Store, then returns to Today.
    private func buyOnTestStore(_ app: XCUIApplication) {
        tapTab("Upgrade", app)
        let purchase = app.buttons["paywall-purchase"].firstMatch
        XCTAssertTrue(purchase.waitForExistence(timeout: 30), "no purchase button on Upgrade")
        XCTAssertTrue(waitForHittable(purchase, timeout: 15), "purchase button not tappable")
        purchase.tap()
        let confirm = app.buttons["Test valid purchase"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 90), "Test Store sheet never appeared")
        confirm.tap()
        XCTAssertTrue(app.buttons["Vitals+"].waitForExistence(timeout: 60), "purchase did not unlock Vitals+")
        clearPitch(app)
        tapTab("Today", app)
    }

    private func openSettings(_ app: XCUIApplication) {
        clearPitch(app)
        let labeled = app.buttons["Settings"]
        if labeled.waitForExistence(timeout: 5), waitForHittable(labeled, timeout: 15) {
            labeled.tap()
            return
        }
        XCTFail("Settings control missing in landscape\n\(app.debugDescription)")
    }

    private func openLink(_ path: String, _ app: XCUIApplication) {
        app.open(URL(string: "totalcalories://\(path)")!)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "\(path) did not bring the app forward")
        settle()
        clearPitch(app)
    }

    private func scrollDown(_ app: XCUIApplication, times: Int) {
        let window = app.windows.firstMatch
        for _ in 0..<times {
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.3))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    /// The trial pitch and other timed sheets can land at any moment.
    private func clearPitch(_ app: XCUIApplication) {
        let deadline = Date.now.addingTimeInterval(6)
        while Date.now < deadline {
            let dismiss = app.buttons.matching(
                NSPredicate(format: "label IN {'Not now', 'No thanks', 'Maybe later', 'Close'}")
            ).firstMatch
            guard dismiss.exists else { return }
            if dismiss.isHittable { dismiss.tap() }
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.5)
        }
    }

    /// iOS 27 asks how much history to share and keeps Allow disabled until a range is
    /// picked. In landscape the short sheet lists "Past 30 Days" first and leaves
    /// "Full History" below the fold, so scroll to it before falling back.
    private func pickHistoryRange(_ app: XCUIApplication) {
        func option(_ label: String) -> XCUIElement? {
            // The row's label carries its description too, so match the title prefix.
            for query in [app.buttons, app.cells, app.staticTexts] {
                let element = query.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
                if element.exists { return element }
            }
            return nil
        }
        guard let first = option("Past 30 Days") ?? option("Full History") else { return }
        if option("Full History") == nil { first.swipeUp() }
        let pick = option("Full History") ?? option("Past 30 Days")
        pick?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func grantHealthKitAccess(_ app: XCUIApplication) {
        func allowButton() -> XCUIElement {
            app.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label == %@ OR label == %@",
                "UIA.Health.Allow.Button", "Allow", "Continue")).firstMatch
        }
        guard allowButton().waitForExistence(timeout: 25) else { return }
        for _ in 0..<6 {
            if !allowButton().exists { return }
            let master = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
            if master.waitForExistence(timeout: 1),
               master.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Turn On All")).firstMatch.exists {
                master.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            pickHistoryRange(app)
            guard waitForHittable(allowButton(), timeout: 12) else { return }
            let allow = allowButton()
            guard allow.exists else { return }
            allow.tap()
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 2)
        }
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isHittable == true"),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(expectsSplit ? "max" : "std")-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
