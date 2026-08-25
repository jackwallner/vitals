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

        // Wait for the paywall, not just for the tab button. Taps land 1.3-2.3s
        // apart while a cold Upgrade tab is still loading products, which is
        // slow enough to keep resetting the rotator's gap counter — this test
        // failed in a suite run for exactly that reason while
        // testTenTapsAtTheTopRotatesTheArm, which waits for the paywall first,
        // passed alongside it.
        XCTAssertTrue(app.buttons["paywall-purchase"].waitForExistence(timeout: 30),
                      "Upgrade tab never rendered")
        let upgradeTab = app.buttons["Upgrade"]
        XCTAssertTrue(upgradeTab.waitForExistence(timeout: 10), "Upgrade tab button missing")

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

    /// The bug the toast could not catch: the rotator wrote the new arm to the
    /// App Group, the toast read it back and reported it, and the paywall kept
    /// drawing the old layout. `upgradeTabVariant` read UserDefaults, which is
    /// not an observation source, so SwiftUI had no reason to redraw until some
    /// unrelated `@Published` fired. Assert the arm that is *rendered*.
    func testRotatingRedrawsThePaywallNotJustTheToast() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = "premium"
        app.launch()

        // See the note in testCyclingAllTheWayRoundReturnsToRevenueCatControl:
        // the paywall has to be on screen before the first batch of taps.
        XCTAssertTrue(app.buttons["paywall-purchase"].waitForExistence(timeout: 30),
                      "Upgrade tab never rendered")
        let upgradeTab = app.buttons["Upgrade"]
        XCTAssertTrue(upgradeTab.waitForExistence(timeout: 10), "Upgrade tab button missing")

        // Start from the normal stop so the lap below is deterministic.
        var guardRail = 0
        while rotate(upgradeTab, in: app) != Self.normalLabel {
            guardRail += 1
            XCTAssertLessThan(guardRail, 8, "never reached the normal stop")
        }

        for arm in PaywallVariantNames.cycle {
            let reported = rotate(upgradeTab, in: app)
            XCTAssertEqual(reported, arm, "the cycle did not visit \(arm) in order")
            // descendants(matching: .any), not otherElements: SwiftUI decides
            // what element type an identified container becomes, and pinning
            // the query to one type makes the test fail for a reason that has
            // nothing to do with which arm is drawn.
            let rendered = app.descendants(matching: .any)["paywall-arm-\(arm)"]
            // Short on purpose. The old code did eventually land on the right
            // arm, minutes later, when something else invalidated the view; a
            // generous timeout would have passed against the bug.
            XCTAssertTrue(rendered.waitForExistence(timeout: 3),
                          "toast said \(arm) but the paywall did not redraw as \(arm)")
            attach(app.screenshot(), name: "rendered-\(arm)")
        }

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
        _ = app.buttons["paywall-purchase"].waitForExistence(timeout: 30)
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
