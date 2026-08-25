import XCTest

/// Onboarding is welcome → food → goals → pitch, and the primary button is the
/// same control moving through it. Food comes before goals so the one HealthKit
/// prompt, fired on the way to goals, already knows whether to carry the dietary
/// and macro types. Two things are asserted here because both were regressions
/// rather than theories:
///
/// 1. The button must not move between pages. Each page puts something
///    different above it (a trust line, nothing, a billing disclosure), and
///    letting that slot size to its content walked the CTA up and down the
///    screen, which made the last press feel like a different kind of act than
///    the two before it.
/// 2. The pitch must follow the food answer. Net Deficit and Macros read food
///    data, so selling them to someone who logs none promises an empty screen.
/// 3. The button must not move for the keyboard either, and the keyboard must
///    have an obvious way out. The goals page had neither.
final class OnboardingFlowUITests: XCTestCase {

    private func launchOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "onboarding"
        app.launch()
        return app
    }

    /// The system HealthKit sheet is a separate process; the runner may or may
    /// not surface one depending on prior state.
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

    private func advance(_ app: XCUIApplication, from page: String) {
        let button = app.buttons["Continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "no Continue on \(page)")
        XCTAssertTrue(button.isHittable, "Continue not hittable on \(page)")
        button.tap()
    }

    func testPrimaryButtonDoesNotMoveBetweenPages() {
        let app = launchOnboarding()

        let welcomeCTA = app.buttons["Continue"]
        XCTAssertTrue(welcomeCTA.waitForExistence(timeout: 20), "welcome never rendered")
        let welcomeFrame = welcomeCTA.frame

        advance(app, from: "welcome")
        sleep(2)

        let foodCTA = app.buttons["Continue"]
        XCTAssertTrue(foodCTA.waitForExistence(timeout: 20), "food step never rendered")
        let foodFrame = foodCTA.frame

        selectFoodAnswer(app, logsFood: false)
        advance(app, from: "food")
        sleep(3)
        dismissSystemSheetIfPresent()

        let goalsCTA = app.buttons["Continue"]
        XCTAssertTrue(goalsCTA.waitForExistence(timeout: 20), "goals never rendered")
        let goalsFrame = goalsCTA.frame

        // One point of tolerance for rounding, not for layout drift.
        XCTAssertEqual(welcomeFrame.minY, foodFrame.minY, accuracy: 1,
                       "CTA moved between welcome (\(welcomeFrame.minY)) and food (\(foodFrame.minY))")
        XCTAssertEqual(foodFrame.minY, goalsFrame.minY, accuracy: 1,
                       "CTA moved between food (\(foodFrame.minY)) and goals (\(goalsFrame.minY))")
        XCTAssertEqual(welcomeFrame.height, goalsFrame.height, accuracy: 1, "CTA changed height")
    }

    /// The goals page is the one onboarding step with a keyboard, and it used to
    /// break the invariant above the moment anyone touched a goal field:
    /// SwiftUI's keyboard avoidance lifted the CTA 274pt to mid-screen, hid the
    /// Step Goal card entirely, and, because a number pad has no return key and
    /// the page had no way out, left it there. The last press before the trial
    /// commit landed nowhere near the trial commit.
    ///
    /// Nothing yields to the keyboard now, so this asserts the button holds its
    /// y with the number pad up, that the number pad can actually be dismissed
    /// (both ways out), and that the button ends up where the trial CTA is.
    func testCTAHoldsItsPlaceUnderTheKeyboard() {
        let app = launchOnboarding()
        advance(app, from: "welcome")
        sleep(2)
        selectFoodAnswer(app, logsFood: true)
        advance(app, from: "food")
        sleep(3)
        dismissSystemSheetIfPresent()

        let cta = app.buttons["Continue"]
        XCTAssertTrue(cta.waitForExistence(timeout: 20), "goals never rendered")
        let idle = cta.frame

        app.textFields.firstMatch.tap()
        sleep(2)
        XCTAssertEqual(app.keyboards.count, 1, "goal field did not take focus")
        XCTAssertEqual(idle.minY, app.buttons["Continue"].frame.minY, accuracy: 1,
                       "CTA moved when the keyboard came up")

        // Way out 1: the Done button over the number pad.
        let done = app.buttons["goal-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no Done above the keyboard")
        XCTAssertTrue(done.isHittable, "Done is not reachable")
        done.tap()
        sleep(2)
        XCTAssertEqual(app.keyboards.count, 0, "Done left the keyboard up")

        // Way out 2: tapping the page header. Also proves the field still takes
        // focus after a dismissal, which an earlier version of this broke: the
        // dismiss gesture sat on an ancestor of the fields and raced them for
        // the same tap.
        for attempt in 1...2 {
            app.textFields.firstMatch.tap()
            sleep(2)
            XCTAssertEqual(app.keyboards.count, 1, "field would not refocus (attempt \(attempt))")
            app.staticTexts["Set your daily goals"].tap()
            sleep(2)
            XCTAssertEqual(app.keyboards.count, 0, "tapping the page left the keyboard up (attempt \(attempt))")
        }

        advance(app, from: "goals")
        sleep(5)
        let trialCTA = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "trial"))
            .firstMatch
        XCTAssertTrue(trialCTA.waitForExistence(timeout: 25), "trial CTA never rendered")
        XCTAssertEqual(idle.minY, trialCTA.frame.minY, accuracy: 1,
                       "goals CTA (\(idle.minY)) and trial CTA (\(trialCTA.frame.minY)) are not the same slot")
    }

    func testFoodAnswerYesLeadsThePitchWithFoodFeatures() {
        let app = onboardingAtPitch(logsFood: true)
        XCTAssertTrue(app.staticTexts["Macros"].waitForExistence(timeout: 20),
                      "a food logger was not offered Macros")
        XCTAssertTrue(app.staticTexts["Net deficit"].exists,
                      "a food logger was not offered Net deficit")
    }

    /// The important half: someone who logs nothing must not be sold the two
    /// features that would render blank for them.
    func testFoodAnswerNoRemovesFoodFeaturesFromThePitch() {
        let app = onboardingAtPitch(logsFood: false)
        XCTAssertTrue(app.staticTexts["Deeper trends"].waitForExistence(timeout: 20),
                      "non-logger pitch never rendered")
        XCTAssertFalse(app.staticTexts["Macros"].exists,
                       "pitched Macros to someone who logs no food")
        XCTAssertFalse(app.staticTexts["Net deficit"].exists,
                       "pitched Net deficit to someone who logs no food")
    }

    private func selectFoodAnswer(_ app: XCUIApplication, logsFood: Bool) {
        let wanted = logsFood ? "Yes, I log" : "No, just track"
        let card = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", wanted)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "food card '\(wanted)' missing")
        card.tap()
    }

    private func onboardingAtPitch(logsFood: Bool) -> XCUIApplication {
        let app = launchOnboarding()
        advance(app, from: "welcome")
        sleep(2)

        selectFoodAnswer(app, logsFood: logsFood)
        advance(app, from: "food")
        sleep(3)
        dismissSystemSheetIfPresent()

        advance(app, from: "goals")
        sleep(2)
        return app
    }
}
