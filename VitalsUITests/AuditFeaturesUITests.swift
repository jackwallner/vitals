import XCTest

/// Audit of the 1.9 features (goal notifications, deep links, recalibration,
/// instant goal save). Needs the DEBUG-only `AuditHooks` launch variables for the
/// background paths. Output goes to `VITALS_AUDIT_DIR` on the host.
final class AuditFeaturesUITests: XCTestCase {
    static let dir = ProcessInfo.processInfo.environment["VITALS_AUDIT_DIR"]
        ?? "/private/tmp/claude-501/-Users-jackwallner-vitals/1cbaa671-a7f8-402c-9b2c-baaef02fa451/scratchpad/audit"
    var dump: String { Self.dir + "/dump-\(name.filter(\.isLetter)).json" }

    override func setUp() { continueAfterFailure = false }

    // MARK: Launch

    @discardableResult
    func launch(_ env: [String: String] = [:], dumpNotifications: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_RC_APP_USER_ID"] = "uitest-vitals-\(UUID().uuidString)"
        app.launchEnvironment["VITALS_SEED_HEALTH"] = "1"
        app.launchEnvironment["VITALS_FORCE_SETUP_COMPLETE"] = "1"
        if dumpNotifications { app.launchEnvironment["VITALS_AUDIT_DUMP"] = dump }
        for (key, value) in env { app.launchEnvironment[key] = value }
        app.launch()
        grantHealthKitAccess(in: app)
        dismissBlockingSheets(in: app)
        return app
    }

    func waitForToday(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 40), "Today tab missing")
        XCTAssertTrue(
            app.staticTexts["Calories"].waitForExistence(timeout: 40),
            "Today never loaded\n\(app.debugDescription)"
        )
    }

    func openSettings(_ app: XCUIApplication) {
        let button = app.buttons["Settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForHittable(button, timeout: 15))
        button.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30), "Settings never opened")
    }

    // MARK: System UI

    var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    /// Taps Allow on the system notification permission alert if it shows up.
    @discardableResult
    func allowNotificationsIfAsked(timeout: TimeInterval = 8) -> Bool {
        let allow = springboard.alerts.buttons["Allow"]
        guard allow.waitForExistence(timeout: timeout) else { return false }
        allow.tap()
        return true
    }

    func bannerMatching(_ text: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            let candidate = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
            if candidate.exists { return candidate }
            _ = springboard.buttons["nonexistent"].waitForExistence(timeout: 0.5)
        }
        return nil
    }

    func readDump() -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dump)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    func shot(_ name: String, app: XCUIApplication? = nil) {
        let screenshot = (app ?? XCUIApplication()).screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: Self.dir + "/shot-\(name).png"))
    }

    func springShot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: Self.dir + "/shot-\(name).png"))
    }

    // MARK: Tests

    /// Feature 1 + 7 + settings toggle permission path. The step goal is set in
    /// Settings (saved on focus loss), then a Health step sample lands while the app
    /// is backgrounded and the banner must appear, then tap deep links to Steps.
    func testGoalReachedNotificationFiresInBackgroundAndDeepLinks() {
        let app = launch(["VITALS_AUDIT_BG_STEPS": "900,4"])
        waitForToday(app)
        openSettings(app)
        setGoal(app, current: "10000", to: "5000")
        // Goal Reached toggle: off then on drives the system permission alert.
        let toggle = app.switches["Goal Reached"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Goal Reached switch missing\n\(app.debugDescription)")
        scrollTo(toggle, in: app)
        toggle.tap()
        toggle.tap()
        let asked = allowNotificationsIfAsked()
        shot("t1-settings-notifications", app: app)
        XCTAssertTrue(asked, "toggling Goal Reached on never raised the system permission alert")
        app.buttons["Done"].firstMatch.tap()
        _ = app.buttons["Today"].waitForExistence(timeout: 10)
        sleep(2)
        XCUIDevice.shared.press(.home)
        let banner = bannerMatching("Step goal reached", timeout: 60)
        springShot("t1-banner")
        XCTAssertNotNil(banner, "no Step goal reached banner within 60s\n\(readDump())")
        banner?.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(
            app.navigationBars.staticTexts["Steps"].waitForExistence(timeout: 15)
                || app.staticTexts["Steps"].waitForExistence(timeout: 5),
            "tapping the notification did not land on Steps history\n\(app.debugDescription)"
        )
        shot("t1-after-tap", app: app)
    }

    /// Feature 3: first goal hit while notifications are undetermined shows the card
    /// (not a cold prompt); Turn On raises the system alert.
    func testPermissionCardAtFirstGoalHit() {
        let app = launch(["VITALS_SEED_TODAY_ACTIVE": "3"])
        waitForToday(app)
        shot("t2-today-before-card", app: app)
        let title = app.staticTexts["Know when you hit your goal"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "permission card never appeared\n\(app.debugDescription)")
        shot("t2-card", app: app)
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "system alert showed before the card was answered")
        app.buttons["Turn On"].tap()
        XCTAssertTrue(allowNotificationsIfAsked(), "Turn On never raised the system alert")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "card did not dismiss")
        sleep(2)
        shot("t2-after-allow", app: app)
        XCTAssertEqual(readDump()["authorization"] as? String, "2", "notifications not authorized after Turn On")
    }

    /// Feature 3 decline path: Not Now ends the ask for good.
    func testPermissionCardNotNowStaysAnswered() {
        let app = launch(["VITALS_SEED_TODAY_ACTIVE": "3"])
        waitForToday(app)
        XCTAssertTrue(app.staticTexts["Know when you hit your goal"].waitForExistence(timeout: 30))
        app.buttons["Not Now"].tap()
        sleep(2)
        XCTAssertFalse(app.staticTexts["Know when you hit your goal"].exists)
        app.terminate()
        let again = launch(["VITALS_SEED_TODAY_ACTIVE": "3"])
        waitForToday(again)
        sleep(8)
        XCTAssertFalse(again.staticTexts["Know when you hit your goal"].exists, "card came back after Not Now")
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
    }

    /// Feature 8, lower direction (default seed: calories ~2,140 a day against 2,500).
    func testRecalibrationLowerAcceptThenGoalPersists() {
        let app = launch()
        waitForToday(app)
        let title = app.staticTexts["Your calorie goal has been out of reach"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "lower card missing\n\(app.debugDescription)")
        shot("t3-lower-card", app: app)
        let accept = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Set to'")).firstMatch
        let label = accept.label
        accept.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed)
        shot("t3-after-accept", app: app)
        let value = label.replacingOccurrences(of: "Set to ", with: "").replacingOccurrences(of: ",", with: "")
        openSettings(app)
        let field = app.textFields.matching(NSPredicate(format: "value == %@", value)).firstMatch
        scrollTo(field, in: app)
        XCTAssertTrue(field.exists, "calorie goal field is not \(value) after accepting\n\(app.debugDescription)")
    }

    func testRecalibrationKeepSnoozes() {
        let app = launch()
        waitForToday(app)
        XCTAssertTrue(app.staticTexts["Your calorie goal has been out of reach"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Keep'")).firstMatch.tap()
        sleep(2)
        shot("t3-after-keep", app: app)
        app.terminate()
        let again = launch()
        waitForToday(again)
        sleep(10)
        XCTAssertFalse(again.staticTexts["Your calorie goal has been out of reach"].exists, "Keep did not snooze")
        shot("t3-relaunch-after-keep", app: again)
    }

    /// Feature 8, raise direction: 14 days well over the goal.
    func testRecalibrationRaise() {
        let app = launch(["VITALS_SEED_PAST_ACTIVE": "3", "VITALS_SEED_PAST_STEPS": "0.2"])
        waitForToday(app)
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You hit your calorie goal on'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 30), "raise card missing\n\(app.debugDescription)")
        shot("t3-raise-card", app: app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Raise to'")).firstMatch.tap()
        sleep(2)
        shot("t3-after-raise", app: app)
        XCTAssertFalse(title.exists)
    }

    /// Feature 7: goals persist the moment a field loses focus, with Settings still open.
    func testGoalsSaveWithoutClosingSettings() {
        let app = launch(dumpNotifications: false)
        waitForToday(app)
        openSettings(app)
        setGoal(app, current: "2500", to: "3100")
        app.terminate()
        let again = launch(dumpNotifications: false)
        waitForToday(again)
        openSettings(again)
        let field = again.textFields.matching(NSPredicate(format: "value == '3100'")).firstMatch
        scrollTo(field, in: again)
        XCTAssertTrue(field.exists, "typed goal was lost when the app was killed with Settings open")
        // Toggle off persists too.
        let toggle = again.switches["Calorie Goal"]
        scrollTo(toggle, in: again)
        toggle.tap()
        again.terminate()
        let third = launch(dumpNotifications: false)
        waitForToday(third)
        openSettings(third)
        XCTAssertEqual(third.switches["Calorie Goal"].value as? String, "0", "Calorie Goal toggle off was not saved")
    }

    // MARK: Helpers

    func setGoal(_ app: XCUIApplication, current: String, to value: String) {
        let field = app.textFields.matching(
            NSPredicate(format: "value == %@ OR placeholderValue == %@", current, current)
        ).firstMatch
        scrollTo(field, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "goal field \(current) missing")
        field.tap()
        let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2)
        field.typeText(clear + value)
        let done = app.buttons["Done"].firstMatch
        let kbDone = app.toolbars.buttons["Done"]
        if kbDone.exists { kbDone.tap() } else { done.tap() }
    }

    func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let form = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        for _ in 0..<14 where !(element.exists && element.isHittable) {
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func dismissBlockingSheets(in app: XCUIApplication) {
        let deadline = Date.now.addingTimeInterval(20)
        while Date.now < deadline {
            for label in ["Maybe later", "Not now", "Close"] where app.buttons[label].exists {
                app.buttons[label].tap()
                _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.4)
            }
            if app.buttons["Today"].exists, app.buttons["History"].exists { return }
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.5)
        }
    }

    func grantHealthKitAccess(in app: XCUIApplication) {
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
            for query in [app.buttons, app.cells, app.staticTexts] {
                let el = query["Full History"]
                if el.exists, el.isHittable { el.tap(); break }
            }
            guard waitForHittable(allowButton(), timeout: 12) else { return }
            let allow = allowButton()
            guard allow.exists else { return }
            allow.tap()
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 2)
        }
    }
}
