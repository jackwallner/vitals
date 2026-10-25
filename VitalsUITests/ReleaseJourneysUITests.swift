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
        app.buttons["History"].tap()
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

    // MARK: - Helpers

    private func launchDashboard() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.journeyCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "dashboard"])
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 20), "Today tab never rendered")
        return app
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
