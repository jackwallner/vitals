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
