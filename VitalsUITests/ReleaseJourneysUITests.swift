import XCTest

/// The release gate's journeys: what a user sees on the way to deciding the
/// app is worth keeping. Each step ends in a `QA.checkpoint`, which runs the
/// fleet oracles (late layout shifts, clipped or overlapping text, off-screen
/// controls, copy that leaks a value or a dash, Apple's accessibility audit, a
/// screen that never stops drawing). `qa-gate run ~/vitals` runs this class
/// once per persona and turns the findings into a verdict.
///
/// Journeys here assert reachability only. Whether a screen is right is the
/// oracles' job, so a new screen gets checked without new assertions.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {

    /// The journeys' own RevenueCat customer, which never buys. The Debug
    /// default (`qa-ios`) is shared by every run on every simulator, so one Test
    /// Store purchase anywhere turned the newcomer into a subscriber with no
    /// Upgrade tab. Fixed rather than random so a gate run adds one customer to
    /// the live project's charts, not one per launch.
    static let journeyCustomer = "qa-ios-journeys"

    /// Found by identifier, not label: the german persona runs these with the
    /// app in German.
    static let pitchDismiss = NSPredicate(format: "identifier IN {'trial-pitch-dismiss', 'paywall-close'}")

    /// The app's own translations of the controls without an identifier, from
    /// `Localizable.xcstrings`; the english and german personas need two of each.
    static let calorieRing = NSPredicate(format: "label IN {'Calorie progress', 'Kalorienfortschritt', 'Progreso de calorías', 'Progression des calories', 'Progresso calorie', 'カロリーの進捗', '卡路里进度'}")
    static let settingsButton = NSPredicate(format: "label IN {'Settings', 'Einstellungen', 'Ajustes', 'Réglages', 'Impostazioni', '設定', '设置'}")
    static let doneButton = NSPredicate(format: "label IN {'Done', 'Fertig', 'Listo', 'OK', 'Fine', '完了', '完成'}")

    func testFirstRunOnboardingToPitch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.journeyCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "onboarding"])
        let cta = app.buttons["onboarding-continue"]
        XCTAssertTrue(cta.waitForExistence(timeout: 20), "welcome never rendered")
        QA.checkpoint(app, "welcome")

        cta.tap()
        dismissSystemSheet()
        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 20), "goals never rendered")
        QA.checkpoint(app, "goals")

        app.buttons["onboarding-continue"].tap()
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
            XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 20), "onboarding stalled")
            app.buttons["onboarding-continue"].tap()
            dismissSystemSheet()
        }
        let softExit = app.buttons["onboarding-get-started"]
        XCTAssertTrue(softExit.waitForExistence(timeout: 25), "pitch never rendered")
        softExit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["exit-offer-tiles"].waitForExistence(timeout: 25), "offer never followed on Today")
        QA.checkpoint(app, "exit-offer-sheet")
    }

    func testTodayHistoryUpgradeAndBack() {
        let app = launchDashboard()
        QA.checkpoint(app, "today-launch")

        clearTrialPitch(app)
        // Unfolded on the Duo, History is the trailing pane and has no tab button.
        let historyTab = app.buttons["tab-history"]
        if historyTab.exists { historyTab.tap() }
        QA.checkpoint(app, "history")

        clearTrialPitch(app)
        app.buttons["tab-upgrade"].tap()
        QA.checkpoint(app, "upgrade")

        clearTrialPitch(app)
        app.buttons["tab-today"].tap()
        QA.checkpoint(app, "today-return")
    }

    func testTrialSheetPresents() {
        let app = launchDashboard()
        let pitch = app.buttons.matching(Self.pitchDismiss).firstMatch
        guard pitch.waitForExistence(timeout: 40) else { return }
        QA.checkpoint(app, "trial-sheet")
        pitch.tap()
        QA.checkpoint(app, "trial-sheet-dismissed")
    }

    func testSettingsSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.journeyCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "settings"])
        XCTAssertTrue(app.descendants(matching: .any)["settings-list"].waitForExistence(timeout: 30), "Settings never presented")
        QA.checkpoint(app, "settings")
    }

    func testInterruptedAndRelaunched() {
        let app = launchDashboard()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 20))
        QA.interrupt(app)
        QA.checkpoint(app, "after-background")
        QA.relaunch(app)
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 20), "Today missing after relaunch")
        QA.checkpoint(app, "after-relaunch")
    }

    /// The core loop: set a daily calorie target in Settings and see Today's
    /// ring measure against it. Values are read from the ring's accessibility
    /// value as bare digits (grouping separators stripped, so 2,500 and 2.500
    /// compare equal). The controls without an identifier are found by the
    /// field's placeholder or the app's own translations, so the german and Duo
    /// personas run it unchanged.
    ///
    /// The goal is not asserted after the relaunch: screenshot mode re-seeds
    /// the 2,500 and 10,000 fixture goals every launch (`GoalSettings`), so a
    /// kept goal cannot be observed here. The relaunch asserts Today draws the
    /// day's calories again.
    func testCoreLoopCalorieGoalShowsOnTodayRing() {
        let app = launchDashboard()
        clearTrialPitch(app)
        let ring = app.descendants(matching: .any).matching(Self.calorieRing).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 20), "calorie ring never rendered")
        XCTAssertTrue(Self.ringReads(ring, calories: "2400", goal: "2500"), "fixture ring reads \(ringValue(ring))")
        QA.checkpoint(app, "today-before")

        let gear = app.buttons.matching(Self.settingsButton).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "Settings button missing")
        gear.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-list"].waitForExistence(timeout: 20), "Settings never presented")
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue == '2500'")).firstMatch
        scrollToHittable(field, in: app.descendants(matching: .any)["settings-list"])
        XCTAssertTrue(field.isHittable, "calorie target field never reachable")
        QA.checkpoint(app, "settings-goal")

        replaceText(in: field, with: "3000")
        XCTAssertEqual(field.value as? String, "3000", "typed target not in the field")
        let done = app.navigationBars.buttons.matching(Self.doneButton).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Settings Done button missing")
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-list"].waitForNonExistence(timeout: 20), "Settings never closed")
        clearTrialPitch(app)
        XCTAssertTrue(ring.waitForExistence(timeout: 20), "calorie ring missing after Settings")
        XCTAssertTrue(Self.ringReads(ring, calories: "2400", goal: "3000"), "ring did not take the new target: \(ringValue(ring))")
        QA.checkpoint(app, "today-new-goal")

        QA.relaunch(app)
        clearTrialPitch(app)
        let reloaded = app.descendants(matching: .any).matching(Self.calorieRing).firstMatch
        XCTAssertTrue(reloaded.waitForExistence(timeout: 20), "calorie ring missing after relaunch")
        XCTAssertTrue(ringValue(reloaded).contains("2400"), "ring lost the day's calories after relaunch: \(ringValue(reloaded))")
        QA.checkpoint(app, "today-after-relaunch")
    }

    // MARK: - Helpers

    private func launchDashboard() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.journeyCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "dashboard"])
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 20), "Today tab never rendered")
        return app
    }

    /// The trial pitch lands on a timer; it is checked in its own journey.
    private func clearTrialPitch(_ app: XCUIApplication) {
        let dismiss = app.buttons.matching(Self.pitchDismiss).firstMatch
        // Twice: a first "Not now" can turn the sheet into the exit offer.
        for _ in 0..<2 where dismiss.exists {
            if dismiss.isHittable { dismiss.tap() }
            _ = dismiss.waitForNonExistence(timeout: 3)
        }
    }

    /// The ring's value with grouping separators removed (2,400, 2.400, 2 400),
    /// so the numbers compare as bare digits in every language.
    private func ringValue(_ ring: XCUIElement) -> String {
        Self.ungrouped(ring.value as? String ?? "")
    }

    private static func ungrouped(_ text: String) -> String {
        text.filter { !",.\u{00A0}\u{202F}\u{2009}'’".contains($0) }
    }

    /// The ring reads "<calories> of <goal> calories" in the app's language, so
    /// only the digits are compared: the calories first, the goal after them.
    private static func ringReads(_ ring: XCUIElement, calories: String, goal: String) -> Bool {
        let value = ungrouped(ring.value as? String ?? "")
        guard let first = value.range(of: calories) else { return false }
        return value[first.upperBound...].contains(goal)
    }

    private func scrollToHittable(_ element: XCUIElement, in list: XCUIElement) {
        for _ in 0..<4 where !element.isHittable {
            QA.swipe(list, .up)
        }
    }

    /// Number pads have no select-all: put the caret at the end, then delete
    /// whatever is there and type the replacement.
    private func replaceText(in field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        field.typeText(text)
    }

    private func dismissSystemSheet() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Turn On All", "Don't Allow", "Erlauben", "Alle aktivieren", "Nicht erlauben"] where springboard.buttons[label].exists {
            springboard.buttons[label].tap()
            sleep(2)
            return
        }
    }
}
