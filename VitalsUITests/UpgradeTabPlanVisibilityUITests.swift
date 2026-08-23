import XCTest

/// Every plan the Upgrade tab sells has to be on screen when the tab opens.
///
/// Both A/B layouts pin the purchase button below a scrolling pitch, and the
/// timeline variant spends ~190pt explaining the trial before it gets to the
/// plans. On an iPhone 17 Pro that pushed the Lifetime row 59pt past the
/// viewport: it rendered, it was in the accessibility tree, and it was only
/// reachable if the user guessed the pitch scrolled. A one-off plan nobody can
/// see is a plan nobody buys, so the geometry is asserted rather than eyeballed.
final class UpgradeTabPlanVisibilityUITests: XCTestCase {

    private static let plans = ["Yearly", "Monthly", "Lifetime"]

    func testTimelineVariantShowsEveryPlanAboveTheButton() {
        assertEveryPlanIsClearOfTheCTA(variant: "timeline")
    }

    func testCatalogVariantShowsEveryPlanAboveTheButton() {
        assertEveryPlanIsClearOfTheCTA(variant: "catalog")
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

        XCTAssertTrue(
            app.staticTexts["Vitals+"].waitForExistence(timeout: 30),
            "\(variant): Upgrade tab never rendered",
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
