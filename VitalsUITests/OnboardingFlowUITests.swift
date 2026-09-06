import XCTest

/// Onboarding is welcome → goals → pitch, and the primary button is the same
/// control moving through it. The food question that sat between welcome and
/// goals is gone with the 1.8.5 restore of the 1.7.4/1.7.5 onboarding, so the
/// one HealthKit prompt fires on the way out of welcome and carries the dietary
/// and macro types unconditionally.
///
/// Three things are asserted here because all three were regressions rather
/// than theories:
///
/// 1. The button must not move between pages. Each page puts something
///    different above it (a trust line, nothing, a soft exit and a billing
///    disclosure), and letting that slot size to its content walked the CTA up
///    and down the screen, which made the last press feel like a different kind
///    of act than the two before it.
/// 2. The pitch is one page for everybody: glyph, headline, four rows, no
///    example card and no arm switch. Every segmented and card-carrying version
///    of it converted at roughly half the rate of this one.
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
        sleep(3)
        dismissSystemSheetIfPresent()

        let goalsCTA = app.buttons["Continue"]
        XCTAssertTrue(goalsCTA.waitForExistence(timeout: 20), "goals never rendered")
        let goalsFrame = goalsCTA.frame

        // One point of tolerance for rounding, not for layout drift.
        XCTAssertEqual(welcomeFrame.minY, goalsFrame.minY, accuracy: 1,
                       "CTA moved between welcome (\(welcomeFrame.minY)) and goals (\(goalsFrame.minY))")
        XCTAssertEqual(welcomeFrame.height, goalsFrame.height, accuracy: 1, "CTA changed height")

        // x and width too. Comparing only minY and height is how a build
        // shipped with the welcome CTA drawn at half width and hanging off the
        // left edge: every assertion above passed on it, because the break was
        // horizontal and nothing here was looking sideways.
        for (page, frame) in [("welcome", welcomeFrame), ("goals", goalsFrame)] {
            XCTAssertEqual(frame.minX, welcomeFrame.minX, accuracy: 1,
                           "CTA x moved on \(page) (\(frame.minX) vs \(welcomeFrame.minX))")
            XCTAssertEqual(frame.width, welcomeFrame.width, accuracy: 1,
                           "CTA width changed on \(page) (\(frame.width) vs \(welcomeFrame.width))")
            XCTAssertTrue(app.frame.contains(frame),
                          "CTA on \(page) (\(frame)) is not inside the window (\(app.frame))")
            XCTAssertTrue(frame.width > app.frame.width * 0.7,
                          "CTA on \(page) is \(frame.width)pt wide, not the full-width primary")
        }
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

        // Way out 1: the Done bar parked on top of the keyboard.
        //
        // Existence and `isHittable` are not enough, and asserting only those
        // is how the first version of this shipped broken: a keyboard-toolbar
        // Done satisfied both on two simulators and then rendered nowhere at
        // all on a real phone. So this pins it to the screen: on top of the
        // keyboard, inside the window, and wide enough to be the thumb target
        // the rest of onboarding trains people to expect rather than a text
        // link tucked into the form.
        let done = app.buttons["goal-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no Done above the keyboard")
        XCTAssertTrue(done.isHittable, "Done is not reachable")
        let keyboardTop = app.keyboards.firstMatch.frame.minY
        XCTAssertTrue(done.frame.maxY <= keyboardTop,
                      "Done (\(done.frame)) is under the keyboard (top \(keyboardTop))")
        XCTAssertTrue(app.frame.contains(done.frame),
                      "Done (\(done.frame)) is outside the app window (\(app.frame))")
        XCTAssertTrue(done.frame.width > app.frame.width * 0.6,
                      "Done (\(done.frame.width)pt) is not a full-width target")
        XCTAssertTrue(done.frame.height >= 44,
                      "Done (\(done.frame.height)pt) is under the 44pt tap minimum")
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

    /// The restored pitch: one page, four rows, in the 1.7.4/1.7.5 order, with
    /// no example card and no segmentation. The card and the segment fork are
    /// asserted absent deliberately — both were added after 1.7.5 and both are
    /// what 1.8.5 is removing, so a reintroduction should fail here rather than
    /// quietly ship.
    func testPitchIsTheRestoredFourRowPage() {
        let app = onboardingAtPitch()

        XCTAssertTrue(app.staticTexts["Go further with Vitals+"].waitForExistence(timeout: 25),
                      "restored pitch headline never rendered")
        for row in ["Net deficit", "Streaks & projections", "Deeper trends", "Summary reports"] {
            XCTAssertTrue(app.staticTexts[row].exists, "pitch is missing the '\(row)' row")
        }

        XCTAssertFalse(app.staticTexts["Macros"].exists,
                       "Macros is a post-1.7.5 row and is not in the restored pitch")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@", "Example Vitals Plus numbers:"
        )).firstMatch.exists, "the example card came back")
    }

    /// The soft exit is back to its 1.7.4/1.7.5 placement: centred, directly
    /// above the CTA, with only the billing disclosure between them. This is
    /// deliberately the arrangement the fleet soft-exit benchmark argues
    /// against, so it is pinned here to stop a well-meaning tidy-up reverting
    /// the revert.
    ///
    /// Width is not asserted, and that is not an oversight. The label is a
    /// `.plain` Button wrapping a `.frame(maxWidth: .infinity)` Text, so the
    /// tap area fills the bar but the accessibility frame XCUITest reports is
    /// the glyph bounds — 81pt on an iPhone 17 Pro. Asserting on that measures
    /// the words, not the layout. Centring is the property that actually
    /// distinguishes this from the intrinsic-width pill 1.8.3 shipped.
    func testSoftExitSitsCentredDirectlyAboveTheCTA() {
        let app = onboardingAtPitch()

        let softExit = app.buttons["Get Started"]
        XCTAssertTrue(softExit.waitForExistence(timeout: 25), "soft exit never rendered")
        let trialCTA = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "trial"))
            .firstMatch
        XCTAssertTrue(trialCTA.waitForExistence(timeout: 25), "trial CTA never rendered")

        XCTAssertTrue(softExit.frame.maxY <= trialCTA.frame.minY,
                      "soft exit (\(softExit.frame)) is not above the CTA (\(trialCTA.frame))")
        XCTAssertEqual(softExit.frame.midX, app.frame.midX, accuracy: 2,
                       "soft exit is not centred (\(softExit.frame.midX) vs \(app.frame.midX))")

        // Only the disclosure separates them. 1.8.3 put the disclosure below
        // the button and bought the gap with padding instead, which pushed the
        // exit far enough up to read as part of the pitch rather than as the
        // alternative to buying.
        let gap = trialCTA.frame.minY - softExit.frame.maxY
        XCTAssertTrue(gap < 100, "soft exit is \(gap)pt above the CTA, too far for the 1.7.5 stack")
    }

    private func onboardingAtPitch() -> XCUIApplication {
        let app = launchOnboarding()
        advance(app, from: "welcome")
        sleep(3)
        dismissSystemSheetIfPresent()

        advance(app, from: "goals")
        sleep(2)
        return app
    }
}
