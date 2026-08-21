import XCTest

/// Opens the Settings sheet in a screenshot scene and walks it top to bottom,
/// attaching a frame per scroll position. `settingsPro` unlocks Vitals+ with
/// Net Deficit and Show Macros on, which is the only state where the nested
/// intake sub-options (Fasting Mode, per-macro rows, Calorie Split, Macro
/// Goals, gram fields) render at all.
final class SettingsSheetUITests: XCTestCase {

    override func setUp() {
        // Report every row that is wrong in one run, not just the first.
        continueAfterFailure = true
    }

    func testSettingsSheetProState() {
        let app = launchSettings(scene: "settingsPro")
        let expected = [
            "Net Deficit", "Fasting Mode", "Show Macros",
            "Protein", "Carbs", "Fat",
            "Calorie Split", "Macro Goals",
            // Macro Goals on means a gram field per visible macro.
            "Protein goal", "Carbs goal", "Fat goal"
        ]
        let found = walk(app, prefix: "settings-pro", labels: expected)

        for label in expected {
            XCTAssertTrue(
                found.contains(label),
                "\(label) missing from the Pro settings sheet"
            )
        }
    }

    func testSettingsSheetFreeStateHidesSubOptions() {
        let app = launchSettings(scene: "settings")
        let parents = ["Net Deficit", "Show Macros"]
        // The regression this build fixes: these used to render greyed out for
        // every user with the parents off, which is most of them.
        let children = ["Fasting Mode", "Calorie Split", "Macro Goals", "Protein goal"]
        let found = walk(app, prefix: "settings-free", labels: parents + children)

        for label in parents {
            XCTAssertTrue(found.contains(label), "\(label) missing")
        }
        for label in children {
            XCTAssertFalse(
                found.contains(label),
                "\(label) should stay hidden until its parent toggle is on"
            )
        }
    }

    // MARK: - Helpers

    private func launchSettings(scene: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = scene
        app.launch()

        let title = app.navigationBars["Settings"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 180),
            "Settings sheet never appeared for scene \(scene)"
        )
        // The sheet can render before StoreService and GoalSettings have
        // settled, so give the rows a beat before reading the tree.
        _ = app.switches["Show Macros"].waitForExistence(timeout: 10)
        return app
    }

    /// Walks the sheet top to bottom, attaching a frame per position and
    /// recording which of `labels` were seen anywhere along the way.
    ///
    /// The union across positions matters because a Form realizes rows lazily:
    /// a row below the fold is absent from the tree until it scrolls into view,
    /// so a single snapshot can't answer "does this row exist at all". Exact
    /// subscript lookups rather than a tree-text search, because the section
    /// footer prose mentions "Calorie Split" and would match a substring test
    /// even when the toggle is correctly hidden.
    private func walk(
        _ app: XCUIApplication,
        prefix: String,
        labels: [String],
        frames: Int = 7
    ) -> Set<String> {
        let form = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch

        var found: Set<String> = []
        for index in 0...frames {
            attach(app.screenshot(), name: "\(prefix)-\(String(format: "%02d", index))")
            for label in labels where !found.contains(label) {
                if app.switches[label].exists || app.staticTexts[label].exists {
                    found.insert(label)
                }
            }
            if index < frames { form.swipeUp(velocity: .slow) }
        }
        return found
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
