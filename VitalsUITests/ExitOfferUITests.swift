import XCTest

/// The exit offer follows a deliberate close as its own sheet (see
/// `.claude/rules/exit-offer.md`). `-exitOffer.force` puts the run in the offer
/// arm. The contract:
///
/// 1. The close goes through as normal: onboarding finishes, Today shows.
/// 2. On release builds the offer waits for a return to the app an hour
///    later; `-exitOffer.force` skips that wait, as `force` does for App
///    Review, and `-exitOffer.returnDelay` keeps a short one.
/// 3. The offer sheet comes up with the price tiles, and its disclosure names
///    the offer price, so the button sells the plan on screen.
/// 4. "No thanks" closes it, and it does not come back.
/// 5. For the welcome window (`-exitOffer.welcomeWindow` shortens its 48
///    hours) every paywall sells yearly at the offer price with the regular
///    price struck through and says when it ends; then full price returns.
///
/// The trial sheet's "Not now" needs seeded Health data to present, so it lives
/// in `SeededHealthFlowUITests.testTrialSheetNotNowLeadsToTheExitOffer`.
final class ExitOfferUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testOnboardingGetStartedLeadsToTheOfferOnToday() {
        runOnboardingOffer(screenshotName: "onboarding-exit-offer")
    }

    /// At accessibility text sizes the sheet scrolls, and the tiles must still
    /// be on screen when it opens, not under the fold.
    func testOnboardingOfferIsOnScreenAtLargestText() {
        runOnboardingOffer(
            screenshotName: "onboarding-exit-offer-ax",
            arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        )
    }

    /// The release-day path: nothing in the visit that closed the paywall, then
    /// the offer once the customer comes back after the wait.
    func testOfferWaitsForAReturnToTheApp() {
        let app = closeOnboarding(arguments: ["-exitOffer.returnDelay", "20"])
        let tiles = app.descendants(matching: .any)["exit-offer-tiles"]
        XCTAssertFalse(tiles.waitForExistence(timeout: 12), "the offer came up in the visit that closed the paywall")

        XCUIDevice.shared.press(.home)
        sleep(15)
        app.activate()
        XCTAssertTrue(tiles.waitForExistence(timeout: 20), "the offer never came up on the return")
        assertOfferSheet(app, tiles: tiles)
    }

    /// After "No thanks" the Upgrade tab keeps the half price and counts it
    /// down, then goes back to the regular price when the window ends.
    func testWelcomePriceStaysOnThePaywallUntilItEnds() {
        let app = closeOnboarding(arguments: ["-exitOffer.welcomeWindow", "75"])
        let tiles = app.descendants(matching: .any)["exit-offer-tiles"]
        XCTAssertTrue(tiles.waitForExistence(timeout: 20), "the offer never followed on Today")
        let shownAt = Date()
        let price = tiles.label
            .replacingOccurrences(of: "Your price, ", with: "")
            .components(separatedBy: " a year").first ?? ""
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Welcome price, ends in")).firstMatch.exists,
                      "the offer sheet does not say when the price ends")
        assertOfferSheet(app, tiles: tiles)

        app.buttons["Upgrade"].tap()
        let welcomeLine = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Welcome price, ends in")).firstMatch
        let offerPlan = app.staticTexts.matching(NSPredicate(format: "label == %@", "\(price) / year")).firstMatch
        XCTAssertTrue(welcomeLine.waitForExistence(timeout: 15), "the paywall does not say when the welcome price ends")
        XCTAssertTrue(offerPlan.exists, "the paywall's yearly plan is not at the offer price \(price)")
        XCTAssertTrue(app.staticTexts["HALF OFF"].exists, "the yearly plan is not marked half off")
        attach(app.screenshot(), name: "paywall-welcome-price")

        let left = 75 - Date().timeIntervalSince(shownAt)
        if left > 0 { sleep(UInt32(left.rounded(.up)) + 3) }
        XCTAssertTrue(welcomeLine.waitForNonExistence(timeout: 10), "the welcome price outlived its window")
        XCTAssertFalse(offerPlan.exists, "the yearly plan stayed at the offer price after the window")
        XCTAssertFalse(app.staticTexts["HALF OFF"].exists, "the half-off badge stayed after the window")
        attach(app.screenshot(), name: "paywall-after-welcome-price")
    }

    private func runOnboardingOffer(screenshotName: String, arguments: [String] = []) {
        let app = closeOnboarding(arguments: arguments)
        let tiles = app.descendants(matching: .any)["exit-offer-tiles"]
        XCTAssertTrue(tiles.waitForExistence(timeout: 20), "the offer never followed on Today")
        sleep(1)
        attach(app.screenshot(), name: screenshotName)
        assertOfferSheet(app, tiles: tiles)
    }

    /// Walks onboarding and closes its trial page with "Get Started".
    private func closeOnboarding(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "onboarding"
        app.launchArguments += ["-exitOffer.force"] + arguments
        app.launch()

        for page in ["welcome", "goals"] {
            let next = app.buttons["Continue"]
            XCTAssertTrue(next.waitForExistence(timeout: 20), "no Continue on \(page)")
            next.tap()
            sleep(3)
            dismissSystemSheet()
        }

        let softExit = app.buttons["Get Started"]
        XCTAssertTrue(softExit.waitForExistence(timeout: 25), "pitch never rendered")
        softExit.tap()

        XCTAssertTrue(app.staticTexts["Go further with Vitals+"].waitForNonExistence(timeout: 10),
                      "\"Get Started\" did not leave onboarding")
        XCTAssertFalse(app.descendants(matching: .any)["exit-offer-tiles"].exists,
                       "the offer came up on the onboarding page itself")
        return app
    }

    // MARK: - Helpers

    /// The tiles read "Your price, $14.99 a year, usually $29.99"; the 3.1.2
    /// disclosure has to quote that same yearly price, or the button would be
    /// selling a different plan from the one on screen.
    private func assertOfferSheet(_ app: XCUIApplication, tiles: XCUIElement) {
        let cta = app.buttons["trial-pitch-cta"]
        let noThanks = app.buttons["No thanks"]
        XCTAssertTrue(cta.exists, "the offer sheet has no purchase button")
        XCTAssertTrue(noThanks.exists, "the way out is not \"No thanks\"")
        XCTAssertTrue(app.frame.contains(tiles.frame), "tiles (\(tiles.frame)) run off the screen")
        XCTAssertTrue(tiles.frame.maxY <= cta.frame.minY, "tiles (\(tiles.frame)) overlap the footer")

        let label = tiles.label
        XCTAssertTrue(label.hasPrefix("Your price, "), "unexpected tiles label: \(label)")
        let price = label
            .replacingOccurrences(of: "Your price, ", with: "")
            .components(separatedBy: " a year").first ?? ""
        XCTAssertFalse(price.isEmpty, "no price in the tiles label: \(label)")
        XCTAssertTrue(label.contains("usually"), "the usual price is missing: \(label)")
        let disclosure = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "\(price) / year")).firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5),
                      "no disclosure quotes the offer price \(price) / year")

        noThanks.tap()
        XCTAssertTrue(tiles.waitForNonExistence(timeout: 10), "\"No thanks\" did not close the offer")
        sleep(6)
        XCTAssertFalse(tiles.exists, "the offer came back after \"No thanks\"")
    }

    private func dismissSystemSheet() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Turn On All", "Don't Allow"] where springboard.buttons[label].exists {
            springboard.buttons[label].tap()
            sleep(2)
            return
        }
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
