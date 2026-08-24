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

        app.buttons["History"].tap()
        XCTAssertTrue(
            app.staticTexts["Deep Trends"].waitForExistence(timeout: 20),
            "Deep Trends card missing on History"
        )
        XCTAssertTrue(
            app.staticTexts["Also in Vitals+: custom date ranges and PDF reports from this History tab."].waitForExistence(timeout: 5)
        )
        attach(app.screenshot(), name: "seeded-history-deep-trends")

        app.buttons["Today"].tap()
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

    // MARK: - Launch

    private func launchSeeded(upgradeTab: String) -> XCUIApplication {
        let app = XCUIApplication()
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
        if labeled.waitForExistence(timeout: 5) {
            let deadline = Date.now.addingTimeInterval(15)
            while Date.now < deadline, !labeled.isHittable {
                _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.3)
            }
            if labeled.isHittable {
                labeled.tap()
                return
            }
        }
        // Gear is the first toolbar button on Today when VoiceOver uses a symbol.
        let gear = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'setting' OR identifier CONTAINS[c] 'setting' OR label CONTAINS[c] 'gear'")).firstMatch
        if gear.waitForExistence(timeout: 3), gear.isHittable {
            gear.tap()
            return
        }
        XCTFail("Settings control missing. hierarchy:\n\(app.debugDescription)")
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
            let deadline = Date.now.addingTimeInterval(12)
            var ready = false
            while Date.now < deadline {
                let current = anyAllowButton(in: app)
                if current.exists, current.isEnabled, current.isHittable {
                    ready = true
                    break
                }
                _ = app.buttons["nonexistent"].waitForExistence(timeout: 0.4)
            }
            guard ready else { return }
            anyAllowButton(in: app).tap()
            _ = app.buttons["nonexistent"].waitForExistence(timeout: 2)
            _ = page
        }
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
        guard master.exists, master.isHittable else { return }
        let stillOff = master.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Turn On All")
        ).firstMatch.exists
        guard stillOff else { return }
        master.tap()
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
