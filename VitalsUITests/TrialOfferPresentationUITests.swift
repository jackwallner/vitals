import XCTest

/// Covers the two conversion-surface defects reported against build 162:
///
/// 1. Tapping a Vitals+ row in Settings dismissed the whole Settings sheet,
///    showed the Today dashboard for a beat, and only then slid the trial pitch
///    up from the bottom. Two context switches for one tap.
/// 2. The trial pitch overflows the sheet's 68% detent, so the hero — badge,
///    headline, subhead — rubber-bands off the top on the first drag.
final class TrialOfferPresentationUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    /// The pitch opens *over* Settings: the user never leaves the pane they
    /// tapped in, and closing the pitch puts them back on the same row. It also
    /// has to be the pitch for the row they tapped — the old hand-off dropped
    /// the focus whenever a passive offer had already claimed the slot.
    func testTrialPitchOpensOverSettingsWithTheTappedFeature() {
        let app = launchSettings()

        tapMacrosSwitch(app)

        let trialCTA = app.buttons["Not now"]
        XCTAssertTrue(
            trialCTA.waitForExistence(timeout: 20),
            "Trial pitch never appeared after tapping a Vitals+ settings row"
        )
        attach(app.screenshot(), name: "pitch-over-settings")

        XCTAssertTrue(
            app.navigationBars["Settings"].exists,
            "Settings was torn down to show the pitch — the Today dashboard flashes in between"
        )
        XCTAssertTrue(
            app.staticTexts["See your macros here too"].exists,
            "Pitch didn't lead with Macros, the feature the tapped row is gated behind"
        )

        // Closing the pitch returns to the row, not to Today.
        trialCTA.tap()
        XCTAssertTrue(
            app.switches["Show Macros"].waitForExistence(timeout: 10),
            "Dismissing the pitch left Settings"
        )
        attach(app.screenshot(), name: "pitch-dismissed-back-in-settings")
    }

    /// The hero must survive an aggressive drag: it may give a little, but the
    /// badge and headline stay on screen rather than being flung out of view.
    func testTrialPitchHeroStaysOnScreenUnderDrag() {
        let app = launchSettings()

        tapMacrosSwitch(app)

        let trialCTA = app.buttons["Not now"]
        XCTAssertTrue(trialCTA.waitForExistence(timeout: 20), "Trial pitch never appeared")
        attach(app.screenshot(), name: "hero-00-resting")

        let badge = app.staticTexts["7 Days Free"]
        let headline = app.staticTexts["See your macros here too"]
        XCTAssertTrue(badge.exists || headline.exists, "Trial hero never rendered")

        let restingBadgeY = badge.exists ? badge.frame.minY : headline.frame.minY

        // Flick the pitch upward the way a thumb does when the sheet first
        // appears, then read where the hero ended up.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        attach(app.screenshot(), name: "hero-01-after-flick")

        let heroAfter = badge.exists ? badge : headline
        XCTAssertTrue(heroAfter.exists, "Trial hero left the tree entirely after one flick")

        let travelled = restingBadgeY - heroAfter.frame.minY
        attach(app.screenshot(), name: "hero-02-settled")
        XCTAssertLessThan(
            travelled, 60,
            "Trial hero travelled \(travelled)pt up on one flick — it should barely give"
        )
        XCTAssertGreaterThan(
            heroAfter.frame.minY, 0,
            "Trial hero scrolled off the top of the sheet"
        )
    }


    /// The used-trial pitch: no "free" anywhere, an honest price ladder to pick
    /// from, and a CTA that names the plan actually selected.
    func testUsedTrialPitchSellsOnPriceNotOnFree() {
        let app = launchSettings(forceIntroIneligible: true)

        tapMacrosSwitch(app)

        let yearly = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Yearly'")).firstMatch
        XCTAssertTrue(yearly.waitForExistence(timeout: 20), "Used-trial pitch never offered a plan to pick")
        attach(app.screenshot(), name: "used-trial-pitch")

        let monthly = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Monthly'")).firstMatch
        XCTAssertTrue(monthly.exists, "Used-trial pitch offered no lower-commitment plan")

        XCTAssertFalse(
            app.staticTexts["7 Days Free"].exists,
            "Used-trial pitch still advertises a free trial this account cannot get"
        )
        for label in ["Start 7-day free trial", "Start Free Trial"] {
            XCTAssertFalse(app.buttons[label].exists, "CTA still promises a trial: \(label)")
        }

        // Picking the cheaper plan has to move the CTA and the disclosure with it.
        monthly.tap()
        let monthlyCTA = app.buttons.containing(NSPredicate(format: "label CONTAINS '/ month'")).firstMatch
        XCTAssertTrue(
            monthlyCTA.waitForExistence(timeout: 5),
            "Selecting Monthly left the button quoting the yearly price"
        )
        attach(app.screenshot(), name: "used-trial-monthly-selected")
    }

    // MARK: - Helpers

    /// The ⓘ lives inside the toggle's own label and outranks it for taps, so a
    /// plain `.tap()` on the switch element opens the explanation instead of
    /// flipping the switch. Hit the control itself, on the trailing edge.
    private func tapMacrosSwitch(_ app: XCUIApplication) {
        let macros = app.switches["Show Macros"]
        XCTAssertTrue(macros.waitForExistence(timeout: 20), "Show Macros row missing")
        macros.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
    }

    private func launchSettings(forceIntroIneligible: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "settings"
        if forceIntroIneligible {
            app.launchEnvironment["VITALS_FORCE_INTRO_INELIGIBLE"] = "1"
        }
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 180),
            "Settings sheet never appeared"
        )
        _ = app.switches["Show Macros"].waitForExistence(timeout: 10)
        return app
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
