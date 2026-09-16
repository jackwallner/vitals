import XCTest

/// Walks the real app against HealthKit samples the DEBUG seeder writes.
/// Screenshot fixtures are not used: Today, History, Deep Trends, Settings, and
/// both Upgrade-tab layouts have to render from that seeded store.
final class SeededHealthFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSeededTodayHistorySettingsAndFeatureLedPaywall() {
        let app = launchSeeded(upgradeTab: "feature_led")
        grantHealthKitAccess(in: app)
        dismissBlockingSheets(in: app)

        XCTAssertTrue(
            app.buttons["Today"].waitForExistence(timeout: 20),
            "Today tab missing after seed"
        )
        XCTAssertTrue(
            app.staticTexts["Calories"].waitForExistence(timeout: 30)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'kcal'")).firstMatch.waitForExistence(timeout: 5),
            "Today never showed calorie data. hierarchy:\n\(app.debugDescription)"
        )
        attach(app.screenshot(), name: "seeded-today")

        dismissTrialPitch(in: app)
        app.buttons["History"].tap()
        XCTAssertTrue(
            app.staticTexts["Deep Trends"].waitForExistence(timeout: 20),
            "Deep Trends card missing on History"
        )
        XCTAssertTrue(
            app.staticTexts["Also in Vitals+: custom date ranges and PDF reports from this History tab."].waitForExistence(timeout: 5)
        )
        attach(app.screenshot(), name: "seeded-history-deep-trends")

        dismissTrialPitch(in: app)
        app.buttons["Today"].tap()
        dismissTrialPitch(in: app)
        openSettings(in: app)
        // 10s was too tight for a sheet presentation at the end of a long walk:
        // this is the slowest path in the suite and a loaded simulator spends
        // most of that budget on the transition alone.
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 30),
            "Settings sheet never presented"
        )
        let form = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch
        let rate = app.buttons["Rate App"]
        for _ in 0..<12 where !rate.exists {
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(rate.waitForExistence(timeout: 2), "Rate App missing")
        XCTAssertTrue(app.buttons["Get Help"].exists, "Get Help missing")
        XCTAssertTrue(app.buttons["Feature Request"].exists, "Feature Request missing")
        attach(app.screenshot(), name: "seeded-settings-support")
        app.swipeDown(velocity: .fast)

        dismissTrialPitch(in: app)
        app.buttons["Upgrade"].tap()
        XCTAssertTrue(
            app.staticTexts["Your macros, every day"].waitForExistence(timeout: 20),
            "feature-led layout never appeared on Upgrade"
        )
        // The hero is the pitch, so the card carrying it has to be there too.
        XCTAssertTrue(
            app.staticTexts["g protein"].exists || app.otherElements
                .matching(NSPredicate(format: "label CONTAINS 'Example macros card'")).firstMatch.exists,
            "feature-led hero rendered without its macro card"
        )
        XCTAssertTrue(app.buttons["paywall-purchase"].waitForExistence(timeout: 10))
        attach(app.screenshot(), name: "seeded-upgrade-feature-led")
    }

    /// Catalog is the control arm and the fallback for anything the dashboard
    /// sends that this binary does not know. It must be the benefit list, and it
    /// must not leak the treatment's hero.
    func testSeededUpgradeTabCatalogShowsTheBenefitList() {
        let app = launchSeeded(upgradeTab: "catalog")
        grantHealthKitAccess(in: app)
        dismissBlockingSheets(in: app)

        dismissTrialPitch(in: app)
        app.buttons["Upgrade"].tap()
        XCTAssertTrue(
            app.buttons["paywall-purchase"].waitForExistence(timeout: 20),
            "catalog paywall CTA missing"
        )
        XCTAssertTrue(
            app.staticTexts["Plus projections, streaks, weekly recap, active/resting split, and body profile."].waitForExistence(timeout: 10),
            "catalog leftover line missing"
        )
        XCTAssertFalse(
            app.staticTexts["Your macros, every day"].exists,
            "catalog layout leaked the feature-led hero"
        )
        XCTAssertFalse(
            app.staticTexts["How your free trial works"].exists,
            "the trial timeline is deleted and must not render anywhere"
        )
        attach(app.screenshot(), name: "seeded-upgrade-catalog")
    }

    /// A lapsed subscriber's App Group still claims Vitals+ on launch, because
    /// `isPro` starts false and a free customer never changes it. Once
    /// RevenueCat resolves, the stored exclusions must stop filtering: a free
    /// user can no longer reach the screen that turns them off.
    func testLapsedSubscriberStopsFilteringExcludedDays() {
        let app = launchSeeded(upgradeTab: "catalog", staleProCache: true)
        grantHealthKitAccess(in: app)
        dismissBlockingSheets(in: app)
        dismissTrialPitch(in: app)

        app.buttons["History"].tap()
        XCTAssertTrue(
            app.staticTexts["Deep Trends"].waitForExistence(timeout: 20),
            "History never loaded"
        )
        let note = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", "excluded from these figures")
        ).firstMatch
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: note)
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 45), .completed,
            "a free customer's History is still filtering stored excluded days"
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Averages paused")).firstMatch.exists
        )
        attach(app.screenshot(), name: "lapsed-history-unfiltered")
    }

    /// The locked Excluded Days screen must not describe the stored pause as
    /// active. `GoalSettings.excludedDayKeys` is empty while Vitals+ is
    /// inactive, so "Today and every day until you resume is excluded" was
    /// copy the numbers disagreed with: the days it named were being counted.
    func testLockedExcludedDaysDoesNotClaimAnActivePause() {
        let app = launchSeeded(upgradeTab: "catalog", staleProCache: true)
        grantHealthKitAccess(in: app)
        dismissBlockingSheets(in: app)
        dismissTrialPitch(in: app)
        app.buttons["Today"].tap()
        dismissTrialPitch(in: app)
        openSettings(in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30), "Settings never presented")

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Excluded Days")).firstMatch
        for _ in 0..<16 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable, "Excluded Days row missing")
        row.tap()

        XCTAssertTrue(
            app.buttons["excluded-days-unlock"].waitForExistence(timeout: 15),
            "locked Excluded Days screen has no unlock card"
        )

        // The active-pause footer claims exclusion is happening right now.
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Today and every day until you resume is excluded")
            ).firstMatch.exists,
            "locked screen still claims today is excluded while nothing is filtered"
        )
        // And the subtitle must not report a running day count. It lives inside
        // the Toggle's accessibility element rather than as its own static text,
        // so it is read off the switch's label — which is also the only place
        // VoiceOver can reach it.
        let pause = app.switches.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Pause averages")
        ).firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "Pause switch missing")
        XCTAssertTrue(
            pause.label.contains("on hold without Vitals+"),
            "dormant pause is not described as dormant: \(pause.label)"
        )
        XCTAssertFalse(
            pause.label.hasSuffix(" days") || pause.label.hasSuffix(" day"),
            "locked screen still counts the dormant pause's days as if it were running: \(pause.label)"
        )
        attach(app.screenshot(), name: "lapsed-excluded-days-dormant-pause")
    }

    /// A free user opens Excluded Days, sees their own lowest day, and buying
    /// from that card excludes it. Uses RevenueCat's Test Store: simulated, no
    /// StoreKit, no charge. The customer is a throwaway one named per launch.
    func testFreeExcludedDaysPitchExcludesTheDayItNamedOnPurchase() {
        let app = launchSeeded(upgradeTab: "catalog")
        grantHealthKitAccess(in: app)
        dismissBlockingSheets(in: app)
        dismissTrialPitch(in: app)
        app.buttons["Today"].tap()
        dismissTrialPitch(in: app)
        openSettings(in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30), "Settings never presented")

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Excluded Days")).firstMatch
        for _ in 0..<16 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable, "Excluded Days row missing")
        row.tap()

        let unlock = app.buttons["excluded-days-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "locked Excluded Days screen has no unlock card")
        // The card starts generic and names a day once HealthKit answers.
        let named = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Exclude '"), object: unlock)
        XCTAssertEqual(
            XCTWaiter().wait(for: [named], timeout: 30), .completed,
            "seeded history should name a day, got \(unlock.label)"
        )
        let day = unlock.label.replacingOccurrences(of: "Exclude ", with: "")
        attach(app.screenshot(), name: "free-excluded-days-locked")
        unlock.tap()

        XCTAssertTrue(
            app.staticTexts["Leave \(day) out of your averages"].waitForExistence(timeout: 15),
            "the pitch did not repeat the day the card named"
        )
        attach(app.screenshot(), name: "free-excluded-days-pitch")
        // By identifier: the Upgrade tab behind the sheet has its own trial button.
        let cta = app.buttons["trial-pitch-cta"]
        XCTAssertTrue(cta.waitForExistence(timeout: 15), "pitch CTA missing")
        cta.tap()

        let confirm = app.buttons["Test valid purchase"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 60), "Test Store sheet never appeared")
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["1 Excluded Day"].waitForExistence(timeout: 60),
            "buying from the card did not exclude the day it named"
        )
        XCTAssertFalse(app.buttons["excluded-days-unlock"].exists, "screen still locked after purchase")
        attach(app.screenshot(), name: "free-excluded-days-after-purchase")
    }

    /// The History long-press is the other door into Excluded Days. Free, it
    /// pitches the pressed day by date, and buying excludes that day.
    func testFreeHistoryLongPressPitchesAndExcludesThePressedDay() {
        let app = launchSeeded(upgradeTab: "catalog")
        grantHealthKitAccess(in: app)
        dismissBlockingSheets(in: app)
        dismissTrialPitch(in: app)

        app.buttons["History"].tap()
        let calories = app.buttons["chart-card-link-Calories"]
        XCTAssertTrue(calories.waitForExistence(timeout: 30), "Calories chart card missing")
        dismissTrialPitch(in: app)
        let recentDays = app.staticTexts["Recent Days"]
        for _ in 0..<3 where !recentDays.waitForExistence(timeout: 5) {
            if calories.isHittable { calories.tap() }
        }
        for _ in 0..<8 where !recentDays.isHittable { app.swipeUp() }

        // Yesterday's row: today is partial, so it gets the generic pitch. The
        // identifier also lands on each row's date and value texts, so match the
        // date labels ("Sat, Sep 12") and take the second.
        let dayRows = app.descendants(matching: .any)
            .matching(identifier: "recent-day-row")
            .matching(NSPredicate(format: "label MATCHES %@", "^[A-Z][a-z]{2}, [A-Z][a-z]{2} [0-9]{1,2}.*"))
        let yesterday = dayRows.element(boundBy: 1)
        XCTAssertTrue(yesterday.waitForExistence(timeout: 10), "no completed Recent Days row")
        let dayLabel = String(yesterday.label.split(separator: ",").dropFirst().first ?? "").trimmingCharacters(in: .whitespaces)
        yesterday.press(forDuration: 1.0)
        let exclude = app.buttons["Exclude from Averages"]
        XCTAssertTrue(exclude.waitForExistence(timeout: 10), "long-press menu missing")
        exclude.tap()

        XCTAssertTrue(
            app.staticTexts["Leave \(dayLabel) out of your averages"].waitForExistence(timeout: 15),
            "History pitch did not name the pressed day (\(dayLabel))"
        )
        attach(app.screenshot(), name: "free-history-exclusion-pitch")

        let cta = app.buttons["trial-pitch-cta"]
        XCTAssertTrue(cta.waitForExistence(timeout: 15), "pitch CTA missing")
        cta.tap()
        let confirm = app.buttons["Test valid purchase"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 60), "Test Store sheet never appeared")
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["EXCLUDED"].waitForExistence(timeout: 60),
            "buying from the long-press did not exclude the pressed day"
        )
        attach(app.screenshot(), name: "free-history-exclusion-after-purchase")
    }

    // MARK: - Launch

    private func launchSeeded(upgradeTab: String, staleProCache: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if staleProCache { app.launchEnvironment["VITALS_STALE_PRO_CACHE"] = "1" }
        // A fresh Test Store customer per launch: one test here buys, and an
        // install's anonymous customer would carry that into every later test.
        app.launchEnvironment["VITALS_RC_APP_USER_ID"] = "uitest-vitals-\(UUID().uuidString)"
        app.launchEnvironment["VITALS_SEED_HEALTH"] = "1"
        app.launchEnvironment["VITALS_FORCE_SETUP_COMPLETE"] = "1"
        app.launchEnvironment["VITALS_UPGRADE_TAB"] = upgradeTab
        app.launch()
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        // Existence is not enough. The tab views stay in the hierarchy rather
        // than being torn down, so a "Settings" button can be present and not
        // yet hittable while the tab transition settles, and tapping it then
        // fails as "not hittable" rather than waiting. Ask for hittable.
        let labeled = app.buttons["Settings"]
        if labeled.waitForExistence(timeout: 5), waitForHittable(labeled, timeout: 15) {
            labeled.tap()
            return
        }
        // Gear is the first toolbar button on Today when VoiceOver uses a symbol.
        let gear = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'setting' OR identifier CONTAINS[c] 'setting' OR label CONTAINS[c] 'gear'")).firstMatch
        if gear.waitForExistence(timeout: 3), waitForHittable(gear, timeout: 5) {
            gear.tap()
            return
        }
        XCTFail("Settings control missing. hierarchy:\n\(app.debugDescription)")
    }

    /// The trial pitch is on a timer, not on a tap: `TrialOfferCoordinator`
    /// holds it back while a sheet is up and presents it as soon as the app is
    /// idle. That means it can land on any tab, at any point in a long walk,
    /// and it covers the whole screen behind a `PopoverDismissRegion` — a tab
    /// tap underneath it is swallowed rather than failed, so the next assertion
    /// fails somewhere unrelated. Clear it right before anything that has to
    /// reach the app's own chrome.
    private func dismissTrialPitch(in app: XCUIApplication) {
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline {
            let dismiss = app.buttons.matching(
                NSPredicate(format: "label IN {'Not now', 'Maybe later', 'Close'}")
            ).firstMatch
            guard dismiss.exists else { return }
            if dismiss.isHittable { dismiss.tap() }
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.5)
        }
    }

    private func dismissBlockingSheets(in app: XCUIApplication) {
        let deadline = Date.now.addingTimeInterval(20)
        while Date.now < deadline {
            for label in ["Maybe later", "Not now", "Close"] where app.buttons[label].exists {
                app.buttons[label].tap()
                _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.4)
            }
            if app.buttons["Today"].exists, app.buttons["History"].exists { return }
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.5)
        }
    }

    private func grantHealthKitAccess(in app: XCUIApplication) {
        guard anyAllowButton(in: app).waitForExistence(timeout: 25) else { return }
        for page in 0..<6 {
            if !anyAllowButton(in: app).exists { return }
            tapTurnOnAll(in: app)
            tapFirstMatch(in: app, label: "Full History")
            // Poll through an expectation rather than reading isEnabled and
            // isHittable in a loop. Those two throw "failed to get matching
            // snapshot" when the element goes away between the `exists` check
            // and the property read, which is exactly what a Health sheet
            // mid-transition does on a loaded machine. A predicate expectation
            // treats a missing element as "not matching yet" and keeps waiting.
            guard waitForHittable(anyAllowButton(in: app), timeout: 12) else { return }
            // Re-check immediately before the tap: the wait above only proves
            // the button was hittable a moment ago.
            let allow = anyAllowButton(in: app)
            guard allow.exists else { return }
            allow.tap()
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 2)
            _ = page
        }
    }

    /// True once `element` is present and hittable, false if the timeout passes.
    /// Never fails the test: a Health page that auto-advances is a reason to
    /// stop tapping, not a reason to fail.
    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isHittable == true"),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func anyAllowButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@ OR label == %@",
                "UIA.Health.Allow.Button", "Allow", "Continue"
            )
        ).firstMatch
    }

    private func tapTurnOnAll(in app: XCUIApplication) {
        let master = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        // No hittability read at all: on iOS 27 the Health sheet answers
        // "failed to determine hittability" for this cell mid-transition, and
        // the throw fails the test. A coordinate tap never asks.
        guard master.waitForExistence(timeout: 1) else { return }
        let stillOff = master.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Turn On All")
        ).firstMatch.exists
        guard stillOff else { return }
        master.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func tapFirstMatch(in app: XCUIApplication, label: String) {
        for query in [app.buttons, app.cells, app.staticTexts] {
            let element = query[label]
            if element.exists, element.isHittable {
                element.tap()
                return
            }
        }
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
