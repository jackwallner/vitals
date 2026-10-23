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

    /// A RevenueCat customer of its own per launch. The Debug default (`qa-ios`)
    /// is shared by every run on every simulator, so one Test Store purchase
    /// anywhere turned the newcomer into a subscriber with no Upgrade tab.
    static var freshCustomer: String { "qa-journey-\(UUID().uuidString)" }

    func testFirstRunOnboardingToPitch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.freshCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "onboarding"])
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
        let pitch = app.buttons.matching(NSPredicate(format: "label IN {'Not now', 'Maybe later', 'Close'}")).firstMatch
        guard pitch.waitForExistence(timeout: 40) else { return }
        QA.checkpoint(app, "trial-sheet")
        pitch.tap()
        QA.checkpoint(app, "trial-sheet-dismissed")
    }

    func testSettingsSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.freshCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "settings"])
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
        QA.launch(app, environment: ["VITALS_RC_APP_USER_ID": Self.freshCustomer, "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1", "VITALS_SCREENSHOT_SCENE": "dashboard"])
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 20), "Today tab never rendered")
        return app
    }

    /// The trial pitch lands on a timer; it is checked in its own journey.
    private func clearTrialPitch(_ app: XCUIApplication) {
        let dismiss = app.buttons.matching(NSPredicate(format: "label IN {'Not now', 'Maybe later', 'Close'}")).firstMatch
        if dismiss.exists, dismiss.isHittable { dismiss.tap() }
        _ = dismiss.waitForNonExistence(timeout: 3)
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
