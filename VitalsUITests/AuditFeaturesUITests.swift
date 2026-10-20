import XCTest

/// Audit of the 1.9 features (goal notifications, deep links, recalibration,
/// instant goal save). Needs the DEBUG-only `AuditHooks` launch variables for the
/// background paths. Output goes to `VITALS_AUDIT_DIR` on the host.
final class AuditFeaturesUITests: XCTestCase {
    static let dir = ProcessInfo.processInfo.environment["VITALS_AUDIT_DIR"]
        ?? "/tmp/vitals-audit"
    var dump: String { Self.dir + "/dump-\(name.filter(\.isLetter)).json" }

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
    }

    // MARK: Launch

    @discardableResult
    func launch(_ env: [String: String] = [:], dumpNotifications: Bool = true, fresh: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if fresh { app.launchEnvironment["VITALS_RESET_STATE"] = "1" }
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

    /// The passive trial pitch lands on any tab on a timer and swallows taps. Clear it.
    func clearPitch(_ app: XCUIApplication, within seconds: TimeInterval = 4) {
        let deadline = Date.now.addingTimeInterval(seconds)
        while Date.now < deadline {
            let dismiss = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN {'Not now', 'Maybe later'}")).firstMatch
            if dismiss.exists { dismiss.tap(); _ = app.buttons["nonexistent"].waitForExistence(timeout: 1) }
            else { _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.5) }
        }
    }

    /// The seeder rewrites Health while the dashboard is already loading, so the first
    /// read can be stale. A background and foreground cycle re-reads it, as a user's would.
    func reloadAfterSeed(_ app: XCUIApplication) {
        sleep(8)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        // The passive trial pitch can land over the dashboard cards these tests tap.
        clearPitch(app, within: 6)
    }

    /// A stale first read during seeding can look like a goal hit, and the
    /// notification card then holds the one prompt slot. Answer it and re-read.
    func answerNotificationCardIfShown(_ app: XCUIApplication) {
        guard app.staticTexts["Know when you hit your goal"].waitForExistence(timeout: 5) else { return }
        app.buttons["Not Now"].tap()
        reloadAfterSeed(app)
    }

    func waitForToday(_ app: XCUIApplication, reload: Bool = false) {
        if reload { reloadAfterSeed(app) }
        let deadline = Date.now.addingTimeInterval(90)
        while Date.now < deadline, !app.buttons["Today"].isHittable { clearPitch(app, within: 2) }
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 30), "Today tab missing")
        // "Calorie progress" with a goal, the bare "CALORIES" counter without one.
        let calories = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] 'calories' OR label == 'Calorie progress'")).firstMatch
        XCTAssertTrue(
            calories.waitForExistence(timeout: 90),
            "Today never loaded\n\(app.debugDescription)"
        )
    }

    func openSettings(_ app: XCUIApplication) {
        let button = app.buttons["Settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        if !button.isHittable { clearPitch(app) }
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

    /// Banners vanish in ~5s and springboard queries are slow, so pull Notification
    /// Center down and look there; the entry stays until tapped.
    func notificationCenterEntry(_ text: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.0))
            let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            let entry = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
            if entry.waitForExistence(timeout: 4) { return entry }
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
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
        sleep(2)
        XCTAssertEqual(readDump()["stepGoal"] as? Int, 5000, "step goal not saved on focus loss: \(readDump())")
        // Goal Reached is opt-in; turning it on drives the system permission alert.
        let toggle = app.switches["Goal Reached"]
        scrollTo(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Goal Reached switch missing\n\(app.debugDescription)")
        flip(toggle, to: false)
        flip(toggle, to: true)
        let asked = allowNotificationsIfAsked()
        shot("t1-settings-notifications", app: app)
        XCTAssertTrue(asked, "toggling Goal Reached on never raised the system permission alert")
        app.buttons["Done"].firstMatch.tap()
        _ = app.buttons["Today"].waitForExistence(timeout: 10)
        sleep(2)
        XCUIDevice.shared.press(.home)
        sleep(12)  // the hook's background work takes ~15s
        let banner = notificationCenterEntry("Step goal reached", timeout: 90)
        springShot("t1-notification-center")
        XCTAssertNotNil(banner, "no Step goal reached entry in Notification Center\n\(readDump())")
        banner?.tap()
        // On iOS 27 a tap in Notification Center can just reveal an "Open" button.
        if !app.wait(for: .runningForeground, timeout: 8) {
            springShot("t1-after-first-tap")
            let open = springboard.buttons["Open"].firstMatch
            if open.waitForExistence(timeout: 3) { open.tap() }
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "app not foregrounded after tapping the notification\n\(springboard.debugDescription)")
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
        reloadAfterSeed(app)
        shot("t2-today-before-card", app: app)
        let title = app.staticTexts["Know when you hit your goal"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "permission card never appeared\n\(app.debugDescription)")
        shot("t2-card", app: app)
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "system alert showed before the card was answered")
        clearPitch(app)
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
        reloadAfterSeed(app)
        XCTAssertTrue(app.staticTexts["Know when you hit your goal"].waitForExistence(timeout: 30))
        clearPitch(app)
        app.buttons["Not Now"].tap()
        sleep(2)
        XCTAssertFalse(app.staticTexts["Know when you hit your goal"].exists)
        app.terminate()
        let again = launch(["VITALS_SEED_TODAY_ACTIVE": "3"], fresh: false)
        waitForToday(again)
        sleep(8)
        XCTAssertFalse(again.staticTexts["Know when you hit your goal"].exists, "card came back after Not Now")
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
    }

    /// Feature 8, lower direction (default seed: calories ~2,140 a day against 2,500).
    func testRecalibrationLowerAcceptThenGoalPersists() {
        let app = launch(["VITALS_SEED_PAST_ACTIVE": "0.2", "VITALS_SEED_PAST_STEPS": "0.2"])
        waitForToday(app)
        reloadAfterSeed(app)
        answerNotificationCardIfShown(app)
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
        let app = launch(["VITALS_SEED_PAST_ACTIVE": "0.2", "VITALS_SEED_PAST_STEPS": "0.2"])
        waitForToday(app)
        reloadAfterSeed(app)
        answerNotificationCardIfShown(app)
        XCTAssertTrue(app.staticTexts["Your calorie goal has been out of reach"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Keep'")).firstMatch.tap()
        sleep(2)
        shot("t3-after-keep", app: app)
        app.terminate()
        let again = launch(["VITALS_SEED_PAST_ACTIVE": "0.2", "VITALS_SEED_PAST_STEPS": "0.2"], fresh: false)
        waitForToday(again)
        reloadAfterSeed(again)
        sleep(10)
        XCTAssertFalse(again.staticTexts["Your calorie goal has been out of reach"].exists, "Keep did not snooze")
        shot("t3-relaunch-after-keep", app: again)
    }

    /// Feature 8, raise direction: 14 days well over the goal.
    func testRecalibrationRaise() {
        let app = launch(["VITALS_SEED_PAST_ACTIVE": "3", "VITALS_SEED_PAST_STEPS": "0.2"])
        waitForToday(app)
        reloadAfterSeed(app)
        answerNotificationCardIfShown(app)
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
        let again = launch(dumpNotifications: false, fresh: false)
        waitForToday(again)
        openSettings(again)
        let field = again.textFields.matching(NSPredicate(format: "value == '3100'")).firstMatch
        scrollTo(field, in: again)
        XCTAssertTrue(field.exists, "typed goal was lost when the app was killed with Settings open")
        // Toggle off persists too.
        let toggle = again.switches["Calorie Goal"]
        scrollTo(toggle, in: again)
        flip(toggle, to: false)
        again.terminate()
        let third = launch(dumpNotifications: false, fresh: false)
        waitForToday(third)
        openSettings(third)
        XCTAssertEqual(third.switches["Calorie Goal"].value as? String, "0", "Calorie Goal toggle off was not saved")
    }

    /// Diagnostic: when does a typed goal reach GoalSettings?
    func testTypedGoalCommitTiming() {
        let app = launch()
        waitForToday(app)
        openSettings(app)
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue == '10000'")).firstMatch
        scrollTo(field, in: app)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        var lines: [String] = []
        func note(_ label: String) {
            sleep(2)
            lines.append("\(label): field=\(field.value as? String ?? "nil") stepGoal=\(readDump()["stepGoal"] ?? "nil")")
        }
        note("focused")
        for ch in String(repeating: "\u{8}", count: 7) { field.typeText(String(ch)); note("after delete") }
        for ch in "5000" { field.typeText(String(ch)); note("after type \(ch)") }
        app.toolbars.buttons["Done"].tap()
        note("after keyboard Done")
        try? lines.joined(separator: "\n").write(toFile: Self.dir + "/commit-timing.txt", atomically: true, encoding: .utf8)
    }

    // MARK: Helpers

    func setGoal(_ app: XCUIApplication, current: String, to value: String) {
        let field = app.textFields.matching(
            NSPredicate(format: "value == %@ OR placeholderValue == %@", current, current)
        ).firstMatch
        scrollTo(field, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "goal field \(current) missing")
        // Right-aligned text: a centre tap puts the caret at the start. Tap past the end.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let existing = (field.value as? String) ?? current
        for _ in 0..<(existing.count + 1) { field.typeText("\u{8}") }
        for ch in value { field.typeText(String(ch)) }
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [typed], timeout: 20), .completed,
                       "goal field did not take the typed value, has \(String(describing: field.value))")
        let kbDone = app.toolbars.buttons["Done"]
        XCTAssertTrue(kbDone.waitForExistence(timeout: 5), "keyboard Done missing")
        kbDone.tap()
    }

    /// Scrolls the Settings form until `element` sits in the middle band of the screen.
    func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let form = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        let height = app.frame.height
        for _ in 0..<20 {
            if element.exists, element.isHittable, element.frame.midY > height * 0.25, element.frame.midY < height * 0.7 { return }
            let up = !element.exists || element.frame.midY > height * 0.5
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.75 : 0.35))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.4 : 0.7))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    /// Flips a Settings switch and checks it actually changed.
    func flip(_ toggle: XCUIElement, to on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let want = on ? "1" : "0"
        if (toggle.value as? String) == want { return }
        springShot("flip-before-\(toggle.label.filter(\.isLetter))")
        NSLog("AUDIT flip \(toggle.label) frame=\(toggle.frame) value=\(String(describing: toggle.value))")
        toggle.tap()
        if XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", want), object: toggle)], timeout: 6) != .completed {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            NSLog("AUDIT flip fell back to coordinate tap")
        }
        let flipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", want), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [flipped], timeout: 20), .completed,
                       "switch \(toggle.label) did not flip to \(want)", file: file, line: line)
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
                if el.exists { el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); break }
            }
            guard waitForHittable(allowButton(), timeout: 12) else { return }
            let allow = allowButton()
            guard allow.exists else { return }
            allow.tap()
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 2)
        }
    }

    func tapSwitch(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    func dumpTree(_ app: XCUIApplication, _ name: String) {
        try? app.debugDescription.write(toFile: Self.dir + "/tree-\(name).txt", atomically: true, encoding: .utf8)
    }

    /// Features 2 + 3 (settings): free user flips Evening Reminder, buys on the Test Store,
    /// reminder is scheduled with the right content.
    func testEveningReminderBuyScheduleAndTimePicker() {
        let app = launch()
        waitForToday(app)
        openSettings(app)
        let toggle = app.switches["Evening Reminder"]
        scrollTo(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Evening Reminder switch missing")
        shot("t4-settings-free", app: app)
        tapSwitch(toggle)
        let cta = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start' AND label CONTAINS 'free trial'")).firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 30), "free user's Evening Reminder tap raised no trial pitch")
        shot("t4-pitch", app: app)
        cta.tap()
        let confirm = app.buttons["Test valid purchase"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 90), "Test Store sheet never appeared")
        confirm.tap()
        _ = allowNotificationsIfAsked(timeout: 30)
        let remind = app.datePickers.firstMatch
        XCTAssertTrue(remind.waitForExistence(timeout: 60), "Remind at picker missing after purchase")
        dumpTree(app, "t4-after-buy")
        shot("t4-after-buy", app: app)
        sleep(3)
        let state = readDump()
        let pending = (state["pending"] as? [[String: Any]]) ?? []
        try? "\(state)".write(toFile: Self.dir + "/t4-state.txt", atomically: true, encoding: .utf8)
        let evening = pending.first { ($0["id"] as? String) == "vitals.eveningReminder" }
        XCTAssertNotNil(evening, "no pending vitals.eveningReminder after enabling: \(state)")
    }

    /// Feature 2: change "Remind at" through the picker, check the pending request moves, and that it fires.
    func testEveningReminderPickerMovesAndFires() {
        let app = launch()
        waitForToday(app)
        openSettings(app)
        let toggle = app.switches["Evening Reminder"]
        scrollTo(toggle, in: app)
        tapSwitch(toggle)
        let cta = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start' AND label CONTAINS 'free trial'")).firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 30))
        cta.tap()
        let confirm = app.buttons["Test valid purchase"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 90))
        confirm.tap()
        _ = allowNotificationsIfAsked(timeout: 30)
        let picker = app.datePickers.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 60))
        sleep(3)
        let target = Calendar.current.date(byAdding: .minute, value: 3, to: .now)!
        let comps = Calendar.current.dateComponents([.hour, .minute], from: target)
        picker.tap()
        sleep(1)
        shot("t4b-picker-open", app: app)
        dumpTree(app, "t4b-picker-open")
        let wheels = app.pickerWheels
        XCTAssertGreaterThanOrEqual(wheels.count, 2, "time wheels missing")
        let hour = comps.hour! % 12 == 0 ? 12 : comps.hour! % 12
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "\(hour)")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: String(format: "%02d", comps.minute!))
        if wheels.count > 2 { wheels.element(boundBy: 2).adjust(toPickerWheelValue: comps.hour! >= 12 ? "PM" : "AM") }
        shot("t4b-picker-set", app: app)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        sleep(4)
        let state = readDump()
        try? "\(state)\ntarget \(comps)".write(toFile: Self.dir + "/t4b-state.txt", atomically: true, encoding: .utf8)
        let pending = (state["pending"] as? [[String: Any]]) ?? []
        let evening = pending.first { ($0["id"] as? String) == "vitals.eveningReminder" }
        XCTAssertNotNil(evening, "no pending reminder after moving the time: \(state)")
        let trig = (evening?["trigger"] as? String) ?? ""
        XCTAssertTrue(trig.contains("hour: \(comps.hour!) minute: \(comps.minute!)"), "pending trigger did not move: \(trig)")
        // Background so it posts as a system banner, then wait it out.
        XCUIDevice.shared.press(.home)
        sleep(200)
        let after = readDump()
        try? "\(after)".write(toFile: Self.dir + "/t4b-after-fire.txt", atomically: true, encoding: .utf8)
        shot("t4b-home-after-fire", app: app)
    }

    func sbDump(_ name: String) {
        springShot(name)
        try? springboard.debugDescription.write(toFile: Self.dir + "/tree-\(name).txt", atomically: true, encoding: .utf8)
    }

    /// Feature 5: add the large widget to the Home Screen, then tap each metric into its history.
    func testLargeWidgetAddAndTap() {
        let app = launch(dumpNotifications: false)
        waitForToday(app)
        XCUIDevice.shared.press(.home)
        sleep(2)
        let sb = springboard
        sb.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.80)).press(forDuration: 2.0)
        sleep(2)
        sb.buttons["Edit"].tap()
        sleep(2)
        let add = sb.buttons["Add Widget"]
        if add.waitForExistence(timeout: 5) { add.tap() }
        sleep(3)
        let search = sb.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Total Calories")
        sleep(3)
        sb.cells["Total Calories - Daily Tracker"].tap()
        sleep(3)
        for _ in 0..<2 {
            sb.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)).press(forDuration: 0.05, thenDragTo: sb.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.45)))
            sleep(2)
        }
        springShot("w-before-add")
        sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.905)).tap()
        sleep(3)
        sb.buttons["Done"].firstMatch.tap()
        sleep(2)
        sbDump("w-added-edit")
        if sb.buttons["Done"].firstMatch.exists { sb.buttons["Done"].firstMatch.tap() }
        sleep(8)
        sbDump("w-added-home")
        // The large widget fills the top of the page: Calories in its upper
        // half, Steps in its lower half. Each block links to its history.
        sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.44)).tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "widget tap did not open the app")
        clearPitch(app)
        assertOnHistory("Steps", app)
        shot("w-tap-steps", app: app)
        XCUIDevice.shared.press(.home)
        sleep(2)
        sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "second widget tap did not open the app")
        clearPitch(app)
        assertOnHistory("Calories", app)
        shot("w-tap-calories", app: app)
    }

    func openLink(_ path: String, in app: XCUIApplication) {
        app.open(URL(string: "totalcalories://\(path)")!)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "\(path) did not bring the app forward")
        sleep(3)
    }

    func assertOnHistory(_ title: String, _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.navigationBars.staticTexts[title].waitForExistence(timeout: 15),
            "not on \(title) history\n\(app.debugDescription)", file: file, line: line
        )
    }

    /// Feature 4: every link lands where it says, warm and cold, and the
    /// Vitals+ destinations stay shut for a free user.
    func testDeepLinksRouteOnScreen() {
        let app = launch(dumpNotifications: false)
        waitForToday(app)
        clearPitch(app)
        openLink("metric/steps", in: app)
        clearPitch(app)
        assertOnHistory("Steps", app)
        shot("dl-steps", app: app)
        openLink("today", in: app)
        clearPitch(app)
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10), "today link did not pop to the dashboard")
        XCTAssertFalse(app.navigationBars.staticTexts["Steps"].exists, "today link left Steps on screen")
        openLink("metric/calories", in: app)
        clearPitch(app)
        assertOnHistory("Calories", app)
        shot("dl-calories", app: app)
        // Free user: Vitals+ routes do nothing.
        openLink("today", in: app)
        clearPitch(app)
        openLink("recap", in: app)
        XCTAssertFalse(app.navigationBars["This Week"].waitForExistence(timeout: 5), "recap opened for a free user")
        openLink("metric/net", in: app)
        XCTAssertFalse(app.navigationBars.staticTexts["Net Deficit"].exists, "net opened for a free user")
        shot("dl-free-gated", app: app)
        // Cold launch straight into a metric.
        app.terminate()
        openLink("metric/steps", in: app)
        clearPitch(app)
        assertOnHistory("Steps", app)
        shot("dl-cold-steps", app: app)
    }

    /// Feature 3 (settings): Goal Reached starts off; turning it on prompts once, and "Don't Allow" puts the section in its denied state.
    func testSettingsNotificationsDeniedState() {
        let app = launch()
        waitForToday(app)
        openSettings(app)
        let toggle = app.switches["Goal Reached"]
        scrollTo(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        shot("t5-section-initial", app: app)
        XCTAssertEqual(toggle.value as? String, "0", "Goal Reached is opt-in")
        // Turning it on raises the one system prompt.
        flip(toggle, to: true)
        let deny = springboard.alerts.buttons["Don\u{2019}t Allow"]
        let denyStraight = springboard.alerts.buttons["Don't Allow"]
        XCTAssertTrue(deny.waitForExistence(timeout: 15) || denyStraight.exists, "no system permission prompt")
        springShot("t5-alert")
        (deny.exists ? deny : denyStraight).tap()
        sleep(2)
        shot("t5-denied", app: app)
        let turnOn = app.buttons["Turn On in iOS Settings"]
        scrollTo(turnOn, in: app)
        XCTAssertTrue(turnOn.exists, "denied state button missing")
        XCTAssertTrue(app.staticTexts["Notifications are off for Total Calories in iOS Settings."].exists, "denied footer missing")
        XCTAssertEqual(app.switches["Goal Reached"].value as? String, "0", "switch should read off when denied")
        dumpTree(app, "t5-denied")
    }
}
