import XCTest

/// The release gate's journeys: what a user sees on the way to deciding the
/// app is worth keeping. Each step ends in a `QA.checkpoint`, which runs the
/// fleet oracles (late layout shifts, clipped or overlapping text, off-screen
/// controls, copy that leaks a value or a dash, Apple's accessibility audit, a
/// screen that never stops drawing). `qa-gate run ~/vitals` runs this class
/// once per persona and turns the findings into a verdict.
///
/// Journeys here assert reachability, except the core loop, which asserts its
/// numbers. Whether a screen is right is the oracles' job, so a new screen gets
/// checked without new assertions.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {

    /// The journeys' own RevenueCat customer, which never buys. The Debug
    /// default (`qa-ios`) is shared by every run on every simulator, so one Test
    /// Store purchase anywhere turned the newcomer into a subscriber with no
    /// Upgrade tab. Fixed rather than random so a gate run adds one customer to
    /// the live project's charts, not one per launch.
    static let journeyCustomer = "qa-ios-journeys"

    func testFirstRunOnboardingToPitch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.journeyCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "onboarding"])
        let cta = app.buttons["Continue"]
        XCTAssertTrue(cta.waitForExistence(timeout: 20), "welcome never rendered")
        QA.checkpoint(app, "welcome")

        cta.tap()
        dismissSystemSheet()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20), "goals never rendered")
        QA.checkpoint(app, "goals")

        app.buttons["Continue"].tap()
        dismissSystemSheet()
        QA.checkpoint(app, "pitch")
    }

    /// The exit offer's own sheet, raised on Today a few seconds after "Get
    /// Started" in the offer arm. Checked by the oracles like any other screen,
    /// since it is one a new customer can land on.
    func testOnboardingExitOffer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.journeyCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "onboarding"], arguments: ["-exitOffer.force"])
        for _ in 0..<2 {
            XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20), "onboarding stalled")
            app.buttons["Continue"].tap()
            dismissSystemSheet()
        }
        let softExit = app.buttons["Get Started"]
        XCTAssertTrue(softExit.waitForExistence(timeout: 25), "pitch never rendered")
        softExit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["exit-offer-tiles"].waitForExistence(timeout: 25), "offer never followed on Today")
        QA.checkpoint(app, "exit-offer-sheet")
    }

    func testTodayHistoryUpgradeAndBack() {
        let app = launchDashboard()
        QA.checkpoint(app, "today-launch")

        clearTrialPitch(app)
        // Unfolded on an iPhone Duo, History is the trailing pane and has no tab.
        let history = app.buttons["History"]
        if history.exists { history.tap() }
        QA.checkpoint(app, "history")

        clearTrialPitch(app)
        app.buttons["Upgrade"].tap()
        QA.checkpoint(app, "upgrade")

        clearTrialPitch(app)
        app.buttons["Today"].tap()
        QA.checkpoint(app, "today-return")
    }

    func testTrialSheetPresents() {
        let app = launchDashboard()
        let pitch = app.buttons.matching(NSPredicate(format: "label IN {'Not now', 'No thanks', 'Maybe later', 'Close'}")).firstMatch
        guard pitch.waitForExistence(timeout: 40) else { return }
        QA.checkpoint(app, "trial-sheet")
        pitch.tap()
        QA.checkpoint(app, "trial-sheet-dismissed")
    }

    func testSettingsSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.journeyCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30), "Settings never presented")
        QA.checkpoint(app, "settings")
    }

    func testInterruptedAndRelaunched() {
        let app = launchDashboard()
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 20))
        QA.interrupt(app)
        QA.checkpoint(app, "after-background")
        QA.relaunch(app)
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 20), "Today missing after relaunch")
        QA.checkpoint(app, "after-relaunch")
    }

    /// The loop a customer opens Vitals for: today's burn and steps from Apple
    /// Health, read against a calorie goal they set, still there tomorrow. Runs
    /// on real HealthKit samples rather than screenshot fixtures, so a broken
    /// read, a goal that does not save, or one lost on relaunch is a wrong
    /// number here. The DEBUG seeder writes today as 1,620 resting plus 420
    /// active kcal and 4,800 steps.
    func testCoreLoopTodayTotalsReadAgainstANewGoalAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.journeyCustomer, "VITALS_SEED_HEALTH": "1", "VITALS_FORCE_SETUP_COMPLETE": "1"])
        grantHealthAccess(app)

        let calories = app.descendants(matching: .any)["today-calories"].firstMatch
        let steps = app.descendants(matching: .any)["today-steps"].firstMatch
        XCTAssertTrue(waitForNumbers(app, steps, prefix: [Self.seededSteps]), "Today never showed the seeded steps: \(numbers(steps))")
        XCTAssertTrue(waitForNumbers(app, calories, prefix: [Self.seededCalories]), "Today never showed the seeded burn: \(numbers(calories))")
        QA.checkpoint(app, "core-today")

        // Whatever an earlier run left, the goal entered here is a new one.
        let goal = numbers(calories).dropFirst().first == 3_100 ? 3_200 : 3_100
        clearTrialPitch(app)
        app.buttons["today-settings"].tap()
        let field = app.textFields["settings-calorie-goal"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "Settings has no calorie goal field")
        for _ in 0..<8 where !field.isHittable { app.swipeUp() }
        QA.checkpoint(app, "core-settings")

        field.tap()
        let typed = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count + 2) + "\(goal)")
        XCTAssertEqual(field.value as? String, "\(goal)", "goal field did not take the typed value")
        app.buttons["settings-done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 15), "Settings did not close on Done")

        let expected = [Self.seededCalories, goal]
        XCTAssertTrue(waitForNumbers(app, calories, prefix: expected), "Today does not read against the new goal: \(numbers(calories))")
        QA.checkpoint(app, "core-today-new-goal")

        QA.relaunch(app)
        XCTAssertTrue(waitForNumbers(app, calories, prefix: expected), "goal or burn lost on relaunch: \(numbers(calories))")
        XCTAssertTrue(waitForNumbers(app, steps, prefix: [Self.seededSteps]), "steps lost on relaunch: \(numbers(steps))")
        QA.checkpoint(app, "core-after-relaunch")
    }

    // MARK: - Helpers

    private func launchDashboard() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.journeyCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "dashboard"])
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 20), "Today tab never rendered")
        return app
    }

    /// Today as `HealthKitSeeder` writes it: 1,620 resting + 420 active kcal.
    static let seededCalories = 2_040
    static let seededSteps = 4_800

    /// The integers in an element's accessibility value, grouping stripped, so
    /// "2040 of 3100 calories" and its German reading compare the same.
    private func numbers(_ element: XCUIElement) -> [Int] {
        guard element.exists, let value = element.value as? String else { return [] }
        let pattern = try! NSRegularExpression(pattern: "\\d(?:[\\d.,\\u00A0\\u202F]*\\d)?")
        return pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            Range(match.range, in: value).flatMap { Int(value[$0].filter(\.isNumber)) }
        }
    }

    /// Waits for the value to lead with `prefix`. The seeder rewrites today on
    /// every launch, so the figure passes through zero first; the trial pitch
    /// can land over Today meanwhile and is cleared so the value stays readable.
    private func waitForNumbers(_ app: XCUIApplication, _ element: XCUIElement, prefix: [Int],
                                timeout: TimeInterval = 60) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if Array(numbers(element).prefix(prefix.count)) == prefix { return true }
            clearTrialPitch(app)
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.5)
        }
        return false
    }

    /// The Health sheet the seeder raises on a fresh install. Absent once an
    /// earlier run on this simulator answered it.
    private func grantHealthAccess(_ app: XCUIApplication) {
        let allow = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "UIA.Health.Allow.Button", "Allow"
        )).firstMatch
        guard allow.waitForExistence(timeout: 20) else { return }
        let all = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        if all.waitForExistence(timeout: 3) {
            all.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        for _ in 0..<3 where allow.exists {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: allow)
            guard XCTWaiter().wait(for: [ready], timeout: 10) == .completed else { return }
            allow.tap()
            _ = allow.waitForNonExistence(timeout: 3)
        }
    }

    /// The trial pitch lands on a timer; it is checked in its own journey.
    private func clearTrialPitch(_ app: XCUIApplication) {
        let dismiss = app.buttons.matching(NSPredicate(format: "label IN {'Not now', 'No thanks', 'Maybe later', 'Close'}")).firstMatch
        // Twice: a first "Not now" can turn the sheet into the exit offer.
        for _ in 0..<2 where dismiss.exists {
            if dismiss.isHittable { dismiss.tap() }
            _ = dismiss.waitForNonExistence(timeout: 3)
        }
    }

    private func dismissSystemSheet() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Turn On All", "Don't Allow"] where springboard.buttons[label].exists {
            springboard.buttons[label].tap()
            sleep(2)
            return
        }
    }
}
