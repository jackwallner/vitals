import XCTest

/// The hidden rotator is the only way to see an arm on a real phone, so "where
/// exactly do I tap" has to have an answer that was checked rather than
/// guessed. The first placement failed exactly this test, which is the reason
/// the test exists: an invisible strip inside the paywall's scroll container
/// was never where a thumb would land.
/// The UI-test bundle cannot import the app target, so the arm names are
/// restated here. That is the point: if the app renames one, this list stops
/// matching and the test says so.
private enum PaywallVariantNames {
    static let cycle = ["catalog", "full_list", "feature_led", "maintenance_led"]
}

final class VariantRotatorUITests: XCTestCase {

    func testTenTapsAtTheTopRotatesTheArm() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "premium"
        app.launch()

        XCTAssertTrue(app.buttons["paywall-purchase"].waitForExistence(timeout: 30),
                      "Upgrade tab never rendered")

        // The Upgrade tab button, while already on the Upgrade tab.
        let upgradeTab = app.buttons["Upgrade"]
        XCTAssertTrue(upgradeTab.waitForExistence(timeout: 10), "Upgrade tab button missing")
        for _ in 0..<10 { upgradeTab.tap() }

        // First stop in the cycle is whatever `PaywallUIVariant.allCases`
        // starts with, so assert on the toast itself rather than pinning a
        // name that a reordered enum would silently break.
        let toast = app.staticTexts["variant-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5),
                      "ten taps on the Upgrade tab did not rotate the arm")
        attach(app.screenshot(), name: "rotator-first-arm")

        let named = PaywallVariantNames.cycle.contains(toast.label)
        XCTAssertTrue(named, "toast said \(toast.label), which is not an arm")
    }

    /// The way back matters more than the way in. A tester who cannot return to
    /// normal has to delete the app, and the cycle is the only route.
    func testCyclingAllTheWayRoundReturnsToRevenueCatControl() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "premium"
        app.launch()

        let upgradeTab = app.buttons["Upgrade"]
        XCTAssertTrue(upgradeTab.waitForExistence(timeout: 30), "Upgrade tab button missing")

        // The override is stored, on purpose, so it survives a relaunch and an
        // earlier test in this class can leave one set. Walk to the "normal"
        // stop first so the lap below starts from a known place.
        var guardRail = 0
        while rotate(upgradeTab, in: app) != Self.normalLabel {
            guardRail += 1
            XCTAssertLessThan(guardRail, 8, "never reached the normal stop")
        }

        let lap = PaywallVariantNames.cycle.map { _ in rotate(upgradeTab, in: app) }
        XCTAssertEqual(lap, PaywallVariantNames.cycle,
                       "the cycle did not visit every arm in order")
        XCTAssertEqual(rotate(upgradeTab, in: app), Self.normalLabel,
                       "the cycle never returned to RevenueCat control")
    }

    private static let normalLabel = "RevenueCat decides (normal)"

    /// The override is stored in the App Group and survives the app, so a test
    /// that leaves one set hands it to every later test in the run. Walk back
    /// to the normal stop before finishing.
    override func tearDown() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "premium"
        app.launch()
        let upgradeTab = app.buttons["Upgrade"]
        if upgradeTab.waitForExistence(timeout: 20) {
            var laps = 0
            while rotate(upgradeTab, in: app) != Self.normalLabel, laps < 8 { laps += 1 }
        }
        app.terminate()
        super.tearDown()
    }

    /// Ten taps, then read and wait out the toast so the next read cannot see
    /// the previous label.
    @discardableResult
    private func rotate(_ tab: XCUIElement, in app: XCUIApplication) -> String {
        for _ in 0..<10 { tab.tap() }
        let toast = app.staticTexts["variant-toast"]
        guard toast.waitForExistence(timeout: 5) else {
            XCTFail("rotator stopped responding")
            return ""
        }
        let label = toast.label
        _ = toast.waitForNonExistence(timeout: 5)
        return label
    }

    private func attach(_ shot: XCUIScreenshot, name: String) {
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
