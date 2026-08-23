import XCTest

/// Every plan the Upgrade tab sells has to be on screen when the tab opens.
///
/// Every layout pins the purchase button below a scrolling pitch, and a pitch
/// that grows past the viewport pushes the last plan under the fold. That is
/// how the Lifetime row came to sit 59pt below the viewport on an iPhone 17 Pro:
/// rendered, in the accessibility tree, and reachable only by guessing that the
/// pitch scrolled. A one-off plan nobody can see is a plan nobody buys, so the
/// geometry is asserted rather than eyeballed, for every arm the dashboard can
/// select and for values it might send that this build does not know.
final class UpgradeTabPlanVisibilityUITests: XCTestCase {

    private static let plans = ["Yearly", "Monthly", "Lifetime"]

    func testCatalogVariantShowsEveryPlanAboveTheButton() {
        assertEveryPlanIsClearOfTheCTA(variant: "catalog")
    }

    func testFeatureLedVariantShowsEveryPlanAboveTheButton() {
        assertEveryPlanIsClearOfTheCTA(variant: "feature_led")
    }

    /// A value the dashboard can send that this binary does not know must still
    /// produce a complete, buyable paywall rather than a broken one.
    func testUnknownVariantFallsBackToACompletePaywall() {
        assertEveryPlanIsClearOfTheCTA(variant: "some_unshipped_layout")
    }

    private func assertEveryPlanIsClearOfTheCTA(
        variant: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "premium"
        app.launchEnvironment["VITALS_UPGRADE_TAB"] = variant
        app.launch()

        // Doubles as the 3.1.2 check: every arm has to name the subscription it
        // is selling. The feature_led arm replaces the header that carried this
        // text, and shipped once without it.
        XCTAssertTrue(
            app.staticTexts["Vitals+"].waitForExistence(timeout: 30)
                || app.staticTexts["VITALS+"].waitForExistence(timeout: 5),
            "\(variant): Upgrade tab never rendered, or never named Vitals+",
            file: file, line: line
        )

        let cta = app.buttons["paywall-purchase"]
        XCTAssertTrue(
            cta.waitForExistence(timeout: 30),
            "\(variant): purchase button never rendered",
            file: file, line: line
        )

        // The prices arrive from RevenueCat, and the plan list lays out again
        // when they land. Wait for the last plan rather than racing it.
        let lifetime = app.staticTexts["Lifetime"]
        XCTAssertTrue(
            lifetime.waitForExistence(timeout: 30),
            "\(variant): Lifetime plan never rendered",
            file: file, line: line
        )

        let ctaTop = cta.frame.minY
        for plan in Self.plans {
            let row = app.staticTexts[plan]
            XCTAssertTrue(row.exists, "\(variant): \(plan) plan is missing", file: file, line: line)
            XCTAssertTrue(
                row.isHittable,
                "\(variant): \(plan) plan is not hittable without scrolling",
                file: file, line: line
            )
            XCTAssertLessThanOrEqual(
                row.frame.maxY, ctaTop,
                "\(variant): \(plan) plan runs past the top of the purchase button "
                    + "(\(row.frame.maxY) > \(ctaTop)); it is below the fold on first paint",
                file: file, line: line
            )
        }
    }
}
