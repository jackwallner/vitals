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

    /// Every surface that asks for money has to offer a way back in. This one
    /// carried Terms and Privacy but no Restore, so a returning subscriber who
    /// reinstalled and met a feature pitch could pay again or leave.
    func testFocusedPitchOffersRestoreBesideTheLegalLinks() {
        let app = launchSettings()

        tapMacrosSwitch(app)

        XCTAssertTrue(
            app.buttons["Not now"].waitForExistence(timeout: 20),
            "Trial pitch never appeared"
        )
        XCTAssertTrue(
            app.buttons["Restore"].exists,
            "focused pitch asks for a purchase with no way to restore one"
        )
        XCTAssertTrue(app.links["Terms"].exists || app.buttons["Terms"].exists,
                      "Terms missing from the pitch footer")
        attach(app.screenshot(), name: "pitch-footer-has-restore")
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


    /// The dashboard-owned pitch, which is a different presentation path from the
    /// Settings one and is the path that shipped broken in build 163: the sheet
    /// flag and the payload were set in the same tick, so SwiftUI built the sheet
    /// body against a payload it had not seen and rendered an empty card.
    ///
    /// Asserts on the sheet's *contents*, not on the sheet existing — a blank
    /// white sheet is still a presented sheet, which is exactly why nothing
    /// caught this.
    func testHistoryUpgradeTapRendersARealPitchNotABlankSheet() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "history"
        app.launch()

        let custom = app.buttons["Custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 180), "History never rendered its period selector")
        custom.tap()

        let cta = app.buttons["Not now"]
        XCTAssertTrue(cta.waitForExistence(timeout: 20), "Locked Custom range raised no pitch at all")
        attach(app.screenshot(), name: "history-pitch")

        // A blank sheet has a purchase button and a headline missing, so check
        // for both halves of the pitch rather than any one element.
        let purchase = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Vitals+' OR label CONTAINS 'free trial'")
        ).firstMatch
        XCTAssertTrue(purchase.exists, "Pitch rendered with no purchase button — blank sheet")
        XCTAssertTrue(
            app.staticTexts["Export any date range"].exists,
            "Pitch rendered without the headline for the feature that was tapped — blank sheet"
        )
    }


    /// The Upgrade tab's buy button must not move when the plan changes. The
    /// disclosure under it is shorter for Lifetime (no auto-renew clause), which
    /// used to shrink the footer and slide the button down mid-decision.
    func testUpgradeTabCTAStaysPutWhenSwitchingPlans() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "premium"
        app.launch()

        let purchase = purchaseButton(app)
        XCTAssertTrue(purchase.waitForExistence(timeout: 180), "Upgrade tab never rendered a buy button")
        attach(app.screenshot(), name: "upgrade-tab-yearly")
        let restingY = purchase.frame.minY

        let lifetime = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Lifetime'")).firstMatch
        guard lifetime.waitForExistence(timeout: 10) else {
            XCTFail("No Lifetime plan card to select")
            return
        }
        lifetime.tap()

        let after = purchaseButton(app)
        XCTAssertTrue(after.waitForExistence(timeout: 5))
        attach(app.screenshot(), name: "upgrade-tab-lifetime")
        XCTAssertEqual(
            after.frame.minY, restingY, accuracy: 1,
            "Buy button moved \(abs(after.frame.minY - restingY))pt when Lifetime was selected"
        )

        // Restore now shares the legal line rather than owning one.
        XCTAssertTrue(app.buttons["Restore"].exists, "Restore is missing from the legal line")
        XCTAssertFalse(app.buttons["Restore Purchases"].exists, "Restore still has a line of its own")
    }

    // MARK: - Helpers

    /// The Upgrade tab's buy button, whose label changes with the plan.
    private func purchaseButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["paywall-purchase"]
    }

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
