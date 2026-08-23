import XCTest

/// The onboarding trial CTA is the highest-intent control in the app, and until
/// now it had one failure mode with no way out: when RevenueCat returned no
/// packages, `conversionCTAReady` stayed false, the button hid its label, showed
/// a spinner and disabled itself. The fallback that opens the full paywall lives
/// *inside* the button's action, so an unpressable button meant an unreachable
/// fallback, and a temporary network failure became a permanent dead end on the
/// screen where the user had already decided to buy.
///
/// `VITALS_FAIL_PRODUCT_LOAD=1` reproduces exactly that state. These assert the
/// recovery, not the happy path: the happy path is covered by
/// `OnboardingFlowUITests`, which runs against the loaded test-store packages.
final class OnboardingCTARecoveryUITests: XCTestCase {

    /// The app gives up on RevenueCat after 6 seconds. The rest of this budget
    /// is for the simulator: a loaded machine spends most of a minute just
    /// walking three onboarding pages, and a short wait here fails as
    /// "never recovered" when nothing is actually wrong.
    private let recoveryTimeout: TimeInterval = 60

    /// Existence is not enough to tap. While the CTA is still waiting on
    /// products its label is drawn at zero opacity, so the element is in the
    /// tree and matches `waitForExistence` a beat before it can be pressed.
    private func waitUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable { return true }
            usleep(250_000)
        }
        return false
    }

    private func launchAtPitchWithNoProducts() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "onboarding"
        app.launchEnvironment["VITALS_FAIL_PRODUCT_LOAD"] = "1"
        app.launch()

        advance(app, from: "welcome")
        sleep(3)
        dismissSystemSheetIfPresent()
        advance(app, from: "goals")
        sleep(2)

        let card = app.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "No, just track"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "food card missing")
        card.tap()
        advance(app, from: "food")
        sleep(2)
        return app
    }

    private func advance(_ app: XCUIApplication, from page: String) {
        let button = app.buttons["Continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "no Continue on \(page)")
        button.tap()
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

    /// The button has to come back with a label the app can honour. It must not
    /// name a trial or a price, because with no packages loaded it knows
    /// neither, and it must not stay a spinner forever.
    func testPitchCTARecoversWhenProductsNeverLoad() {
        let app = launchAtPitchWithNoProducts()

        let cta = app.buttons["See Vitals+ Plans"]
        XCTAssertTrue(waitUntilHittable(cta, timeout: recoveryTimeout),
                      "trial CTA never recovered from a failed product load")
        XCTAssertTrue(cta.isEnabled, "recovered CTA is still disabled")
    }

    /// Pressing it must reach the full paywall, which owns the retry and the
    /// error message. Reaching *something* is the whole point of the fix.
    func testRecoveredCTAOpensTheFullPaywall() {
        let app = launchAtPitchWithNoProducts()

        let cta = app.buttons["See Vitals+ Plans"]
        XCTAssertTrue(waitUntilHittable(cta, timeout: recoveryTimeout), "CTA never recovered")
        cta.tap()

        // With no packages the paywall draws its own empty state, which is the
        // point: it names the failure and offers a retry, neither of which
        // existed on the onboarding step.
        XCTAssertTrue(app.staticTexts["Couldn't Load Plans"].waitForExistence(timeout: 15),
                      "recovered CTA did not open the full paywall")
        XCTAssertTrue(app.buttons["Try Again"].exists,
                      "fallback paywall offered no way to retry the product load")
    }

    /// The free exit is the other half of not trapping anyone. It is a plain
    /// button with no dependency on the store, and a failed product load must
    /// not take it away.
    func testFreeExitStillWorksWhenProductsNeverLoad() {
        let app = launchAtPitchWithNoProducts()

        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(waitUntilHittable(getStarted, timeout: recoveryTimeout),
                      "free exit missing from a degraded pitch")
        getStarted.tap()

        // Onboarding dismisses to the tab bar.
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 15),
                      "free exit did not finish onboarding")
    }
}
