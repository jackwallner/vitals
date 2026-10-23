import XCTest

/// The exit offer appears in place on the page that was closed (see
/// `.claude/rules/exit-offer.md`). `-exitOffer.force` puts the run in the offer
/// arm. Each surface is checked for the same contract:
///
/// 1. The close keeps the page and slides the price tiles in.
/// 2. The primary button stays put and now buys the half-price plan, so the
///    disclosure above or under it names the offer price.
/// 3. The way out reads "No thanks" and leaves on the next tap.
///
/// The trial sheet's version needs seeded Health data to present, so it lives
/// in `SeededHealthFlowUITests.testTrialSheetNotNowTurnsIntoTheExitOffer`.
final class ExitOfferUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testOnboardingGetStartedTurnsThePitchIntoTheOffer() {
        runOnboardingOffer(screenshotName: "onboarding-exit-offer")
    }

    /// At accessibility text sizes the pitch scrolls, and the tiles used to
    /// slide in under the fold: the button and disclosure switched to the half
    /// price with nothing on screen saying why. They must scroll into view.
    func testOnboardingOfferScrollsIntoViewAtLargestText() {
        runOnboardingOffer(
            screenshotName: "onboarding-exit-offer-ax",
            arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        )
    }

    private func runOnboardingOffer(screenshotName: String, arguments: [String] = []) {
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
        let cta = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "trial")).firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 25), "trial CTA never rendered")
        let ctaBefore = cta.frame
        softExit.tap()

        let tiles = app.descendants(matching: .any)["exit-offer-tiles"]
        XCTAssertTrue(tiles.waitForExistence(timeout: 5), "Get Started did not bring in the offer")
        sleep(2)
        attach(app.screenshot(), name: screenshotName)

        XCTAssertTrue(app.staticTexts["Go further with Vitals+"].exists, "the pitch was replaced, not kept")
        let noThanks = app.buttons["No thanks"]
        XCTAssertTrue(noThanks.exists, "the way out is not \"No thanks\"")
        XCTAssertFalse(app.buttons["Get Started"].exists, "\"Get Started\" is still the way out")

        let ctaAfter = cta.frame
        XCTAssertEqual(ctaBefore.minY, ctaAfter.minY, accuracy: 1, "CTA moved when the offer came in")
        XCTAssertEqual(ctaBefore.width, ctaAfter.width, accuracy: 1, "CTA changed width")
        XCTAssertTrue(app.frame.contains(tiles.frame), "tiles (\(tiles.frame)) run off the screen")
        XCTAssertTrue(tiles.frame.maxY <= noThanks.frame.minY,
                      "tiles (\(tiles.frame)) overlap the footer (No thanks at \(noThanks.frame))")

        assertDisclosureNamesOfferPrice(app, tiles: tiles)

        noThanks.tap()
        XCTAssertTrue(app.staticTexts["Go further with Vitals+"].waitForNonExistence(timeout: 10),
                      "\"No thanks\" did not leave onboarding")
    }

    func testPaywallCloseSwapsThePlansForTheOffer() {
        let app = XCUIApplication()
        app.launchArguments += ["-PaywallSnapshot", "exit", "-exitOffer.force"]
        app.launch()

        let purchase = app.buttons["paywall-purchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 30), "paywall never rendered")
        let monthly = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Monthly")).firstMatch
        XCTAssertTrue(monthly.waitForExistence(timeout: 30), "plans never loaded")
        let close = app.buttons["Close"]
        XCTAssertTrue(close.exists, "no close button")
        let purchaseBefore = purchase.frame
        close.tap()

        let tiles = app.descendants(matching: .any)["exit-offer-tiles"]
        XCTAssertTrue(tiles.waitForExistence(timeout: 5), "close did not bring in the offer")
        sleep(1)
        attach(app.screenshot(), name: "paywall-exit-offer")

        XCTAssertFalse(monthly.exists, "the plan list is still showing beside the offer")
        XCTAssertTrue(app.buttons["Close"].exists, "the paywall lost its way out")
        XCTAssertEqual(purchaseBefore.minY, purchase.frame.minY, accuracy: 1, "purchase button moved")
        XCTAssertTrue(app.frame.contains(tiles.frame), "tiles (\(tiles.frame)) run off the screen")
        XCTAssertTrue(tiles.frame.maxY <= purchase.frame.minY, "tiles overlap the purchase button")

        assertDisclosureNamesOfferPrice(app, tiles: tiles)
    }

    // MARK: - Helpers

    /// The tiles read "Your price, $14.99 a year, usually $29.99"; the 3.1.2
    /// disclosure has to quote that same yearly price, or the button would be
    /// selling a different plan from the one on screen.
    private func assertDisclosureNamesOfferPrice(_ app: XCUIApplication, tiles: XCUIElement) {
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
