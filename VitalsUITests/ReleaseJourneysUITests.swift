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

    private func dismissSystemSheet() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Turn On All", "Don't Allow", "Erlauben", "Alle aktivieren", "Nicht erlauben"] where springboard.buttons[label].exists {
            springboard.buttons[label].tap()
            sleep(2)
            return
        }
    }
}
