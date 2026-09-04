import XCTest

/// Walks the five onboarding pitch arms and screenshots each one.
///
/// This is the pre-launch look at what the routing table can serve, taken
/// without touching the RevenueCat dashboard: `VITALS_ONBOARDING_PITCH` forces
/// the arm, so all five are reachable on a build whose live table may only be
/// serving two of them.
///
/// The food answer per arm is not a free choice. `b` and `e` read food data and
/// `canDraw` keeps them away from anyone without it, so they are walked as a
/// logger; `d` is the non-logger arm; `a` and `c` draw in either segment and are
/// walked as non-loggers, which is the larger half of the audience.
final class OnboardingPitchScreenshotUITests: XCTestCase {

    /// Arm `c` is walked twice. It has two honest states, one for the customer
    /// whose Health history already yields a maintenance figure and one for the
    /// customer who has too little, and both ship.
    private static let arms: [(arm: String, logsFood: Bool, label: String, maintenance: String?)] = [
        ("a", false, "current-control", nil),
        ("b", true,  "macro-food", nil),
        ("c", false, "locked-numbers", "2340/1610/21"),
        ("c", false, "locked-numbers-no-history", "none"),
        ("d", false, "two-weeks", nil),
        ("e", true,  "two-weeks-food", nil),
    ]

    func testCaptureEveryPitchArm() {
        for (arm, logsFood, label, maintenance) in Self.arms {
            let app = launchOnboarding(forcing: arm, maintenance: maintenance)
            advance(app, from: "welcome (\(arm))")
            sleep(2)

            selectFoodAnswer(app, logsFood: logsFood)
            advance(app, from: "food (\(arm))")
            sleep(3)
            dismissSystemSheetIfPresent()

            advance(app, from: "goals (\(arm))")
            sleep(3)

            // The pitch is the step whose CTA is no longer "Continue".
            XCTAssertTrue(app.buttons["Continue"].waitForNonExistence(timeout: 15),
                          "arm \(arm) never left goals")
            attach(app.screenshot(), name: "pitch-\(arm)-\(label)")
            app.terminate()
        }
    }

    private func launchOnboarding(forcing arm: String, maintenance: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "onboarding"
        app.launchEnvironment["VITALS_ONBOARDING_PITCH"] = arm
        if let maintenance { app.launchEnvironment["VITALS_PITCH_MAINTENANCE"] = maintenance }
        app.launch()
        return app
    }

    private func advance(_ app: XCUIApplication, from page: String) {
        let button = app.buttons["Continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "no Continue on \(page)")
        button.tap()
    }

    private func selectFoodAnswer(_ app: XCUIApplication, logsFood: Bool) {
        let wanted = logsFood ? "Yes, I log" : "No, just track"
        let card = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", wanted)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "food card '\(wanted)' missing")
        card.tap()
    }

    private func dismissSystemSheetIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Turn On All", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                sleep(2)
                return
            }
        }
    }

    private func attach(_ shot: XCUIScreenshot, name: String) {
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
