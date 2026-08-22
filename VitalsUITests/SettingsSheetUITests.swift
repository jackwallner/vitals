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
            // Macro Goals on means a switch plus a gram field per visible
            // macro, each macro deciding for itself whether it has a target.
            "Protein Goal", "Carbs Goal", "Fat Goal",
            "Daily protein", "Daily carbs", "Daily fat"
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
        let children = ["Fasting Mode", "Calorie Split", "Macro Goals", "Protein Goal"]
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

    /// The ⓘ beside a setting expands its explanation under the row, and tapping
    /// it again collapses it. Covers both halves of the pattern that replaced the
    /// footer prose: the dot's hit target actually fires (a high-priority tap
    /// gesture, not a Button, precisely because the Button form did not),
    /// and the explanation is real text in the tree rather than a presentation
    /// that silently failed to appear. The dot now sits inside the Toggle's own
    /// label (so its row measures the same as every plain toggle row), which
    /// means its tap has to outrank the label's "flip the switch" tap.
    func testInfoDotRevealsExplanation() {
        let app = launchSettings(scene: "settingsPro")

        let dot = app.buttons["About Net Deficit"]
        XCTAssertTrue(dot.waitForExistence(timeout: 20), "Net Deficit ⓘ missing")

        let explanation = app.staticTexts[
            "Calories burned minus the food energy in Apple Health. A positive number means a deficit."
        ]
        XCTAssertFalse(explanation.exists, "Explanation should start collapsed")

        dot.tap()
        XCTAssertTrue(
            explanation.waitForExistence(timeout: 5),
            "Tapping the ⓘ did not reveal the Net Deficit explanation"
        )
        attach(app.screenshot(), name: "info-dot-expanded")

        dot.tap()
        XCTAssertTrue(
            waitForDisappearance(of: explanation),
            "Tapping the ⓘ again did not collapse the explanation"
        )
    }

    /// Only one explanation is open at a time, so opening a second closes the
    /// first instead of stacking two walls of prose inside one section.
    func testOpeningASecondInfoDotClosesTheFirst() {
        let app = launchSettings(scene: "settingsPro")

        let netDeficitDot = app.buttons["About Net Deficit"]
        XCTAssertTrue(netDeficitDot.waitForExistence(timeout: 20))

        let netDeficitText = app.staticTexts[
            "Calories burned minus the food energy in Apple Health. A positive number means a deficit."
        ]
        netDeficitDot.tap()
        XCTAssertTrue(netDeficitText.waitForExistence(timeout: 5))

        // A Form realizes rows lazily, so the Macros ⓘ is not in the tree until
        // it scrolls into view. Expanding Net Deficit above it pushes it further
        // down, which is exactly the case worth covering.
        let macrosDot = app.buttons["About Macros"]
        let form = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch
        for _ in 0..<6 where !macrosDot.isHittable {
            form.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(macrosDot.isHittable, "Macros ⓘ never scrolled into view")

        macrosDot.tap()
        XCTAssertTrue(
            waitForDisappearance(of: netDeficitText),
            "Opening the Macros explanation left the Net Deficit one open"
        )
    }

    /// Rate App, Get Help, and Feature Request sit on one row under the Vitals+
    /// status card in both the free and Pro sheets. They used to live in the
    /// section header (Pro only), which left free users without an equivalent.
    func testSettingsSupportRowShowsRateHelpAndFeatureRequest() {
        for scene in ["settings", "settingsPro"] {
            let app = launchSettings(scene: scene)
            let form = app.collectionViews.firstMatch.exists
                ? app.collectionViews.firstMatch
                : app.tables.firstMatch
            let rate = app.buttons["Rate App"]
            for _ in 0..<12 where !rate.exists {
                scrollStep(form)
            }
            XCTAssertTrue(
                rate.waitForExistence(timeout: 2),
                "Rate App missing in \(scene)"
            )
            XCTAssertTrue(
                app.buttons["Get Help"].exists,
                "Get Help missing in \(scene)"
            )
            XCTAssertTrue(
                app.buttons["Feature Request"].exists,
                "Feature Request missing in \(scene)"
            )
            attach(app.screenshot(), name: "support-row-\(scene)")
        }
    }

    /// Body Profile lives behind a NavigationLink, so its ⓘ shares a row with a
    /// link that wants the whole row's tap. Covers both halves: the dot opens the
    /// explanation, and the row still navigates rather than the dot swallowing it.
    func testBodyProfileRowHasContextAndStillNavigates() {
        let app = launchSettings(scene: "settingsPro")

        let form = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch
        let dot = app.buttons["About Body Profile"]
        for _ in 0..<10 where !dot.isHittable {
            form.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(dot.isHittable, "Body Profile ⓘ never scrolled into view")

        let explanation = app.staticTexts[
            "Your BMI, free, calculated from the height and weight already in Apple Health. No Health data? Enter them by hand instead."
        ]
        dot.tap()
        XCTAssertTrue(
            explanation.waitForExistence(timeout: 5),
            "Body Profile ⓘ did not reveal its explanation"
        )
        attach(app.screenshot(), name: "body-profile-context")

        // The link must still work: the dot sits inside the same row. Target
        // the row's unique accessible button label because the navigation link
        // also exposes a child StaticText with the same title.
        let bodyProfileRow = app.buttons["Body Profile, BMI, height, and weight"]
        XCTAssertTrue(bodyProfileRow.isHittable, "Body Profile row is not hittable")
        bodyProfileRow.tap()
        XCTAssertTrue(
            app.navigationBars["Body Profile"].waitForExistence(timeout: 10),
            "Body Profile row no longer navigates"
        )
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
        frames: Int = 10
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
            if index < frames { scrollStep(form) }
        }
        return found
    }

    /// A fixed drag rather than `swipeUp`, which carries momentum: a flick can
    /// travel more than a screen and skip a block of rows entirely between two
    /// captured frames, so the walk's result depended on how tall the rows
    /// happened to be. Two thirds of the form per step always overlaps.
    private func scrollStep(_ form: XCUIElement) {
        let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// Polls rather than `expectation(for:evaluatedWith:)`, which Swift 6 rejects
    /// here: XCTestCase is not Sendable, so handing self to the predicate form is
    /// a data-race error.
    private func waitForDisappearance(
        of element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(100_000)
        }
        return !element.exists
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
