import XCTest

/// Persona audit: a busy user interrupted mid-task who returns later. Each test
/// starts interacting immediately so it fits the recording window. Observations
/// are written to `notes.txt` and screenshots attached; nothing here fails on a
/// finding, only on the harness not reaching the screen it needs.
final class InterruptedUserUITests: XCTestCase {
    var notes: [String] = []

    override func setUp() { continueAfterFailure = true }

    override func tearDown() {
        let text = notes.joined(separator: "\n")
        let attachment = XCTAttachment(string: text)
        attachment.name = "notes-\(name.filter(\.isLetter))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func note(_ s: String) { notes.append(s); NSLog("INTERRUPT \(s)") }

    func shot(_ name: String, _ app: XCUIApplication) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func background(_ seconds: UInt32) {
        XCUIDevice.shared.press(.home)
        sleep(seconds)
    }

    func grantHealth(_ app: XCUIApplication) {
        func allow() -> XCUIElement {
            app.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label == %@ OR label == %@",
                "UIA.Health.Allow.Button", "Allow", "Continue")).firstMatch
        }
        guard app.buttons["UIA.Health.Allow.Button"].waitForExistence(timeout: 15) else { return }
        for _ in 0..<5 {
            let master = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
            if master.waitForExistence(timeout: 1) { master.tap() }
            let b = allow()
            guard b.exists else { return }
            b.tap()
            sleep(2)
            if !app.buttons["UIA.Health.Allow.Button"].exists { return }
        }
    }

    func clearPitch(_ app: XCUIApplication) {
        for label in ["Not now", "Maybe later", "Close", "Not Now"] where app.buttons[label].exists {
            app.buttons[label].tap(); sleep(1)
        }
    }

    // MARK: Onboarding interrupted

    func testOnboardingInterruptedThenReturn() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_RESET_STATE"] = "1"
        app.launchEnvironment["VITALS_RC_APP_USER_ID"] = "uitest-vitals-\(UUID().uuidString)"
        app.launch()
        let cont = app.buttons["Continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 30), "welcome never rendered")
        shot("o1-welcome", app)
        cont.tap()
        grantHealth(app)
        sleep(2)
        shot("o2-goals", app)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "goals fields missing")
        field.tap()
        sleep(1)
        for _ in 0..<6 { field.typeText("\u{8}") }
        field.typeText("2900")
        sleep(1)
        shot("o3-typed-keyboard-up", app)
        note("typed calorie goal 2900, keyboard up: \(app.keyboards.count)")
        // Interruption 1: phone call / app switch while keyboard is up.
        background(4)
        app.activate()
        sleep(2)
        shot("o4-after-bg-return", app)
        note("after bg: keyboards=\(app.keyboards.count) fieldValue=\(app.textFields.firstMatch.value as? String ?? "nil")")
        // Interruption 2: app killed (swiped away / memory pressure), user comes back tomorrow.
        app.terminate()
        let again = XCUIApplication()
        again.launchEnvironment["VITALS_RC_APP_USER_ID"] = "uitest-vitals-resume"
        again.launch()
        sleep(5)
        shot("o5-relaunch", again)
        note("relaunch: Continue exists=\(again.buttons["Continue"].exists) todayTab=\(again.buttons["Today"].exists) welcome=\(again.staticTexts["Welcome to Total Calories"].exists)")
        if again.buttons["Continue"].exists {
            again.buttons["Continue"].tap()
            grantHealth(again)
            sleep(2)
            shot("o6-goals-after-relaunch", again)
            note("goals after relaunch value=\(again.textFields.firstMatch.value as? String ?? "nil") (typed 2900)")
        }
    }

    // MARK: Settings / history interrupted

    func testSettingsDraftAndTabSurviveInterruption() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_RESET_STATE"] = "1"
        app.launchEnvironment["VITALS_RC_APP_USER_ID"] = "uitest-vitals-\(UUID().uuidString)"
        app.launchEnvironment["VITALS_SEED_HEALTH"] = "1"
        app.launchEnvironment["VITALS_FORCE_SETUP_COMPLETE"] = "1"
        app.launch()
        grantHealth(app)
        let deadline = Date.now.addingTimeInterval(60)
        while Date.now < deadline, !(app.buttons["Today"].exists && app.buttons["History"].exists) {
            clearPitch(app); sleep(1)
        }
        clearPitch(app)
        shot("s1-today", app)
        // History tab, then interruption.
        app.buttons["History"].tap()
        sleep(3)
        clearPitch(app)
        shot("s2-history", app)
        let seg = app.segmentedControls.firstMatch
        if seg.exists, seg.buttons.count > 1 { seg.buttons.element(boundBy: 1).tap(); sleep(2) }
        shot("s3-history-segment", app)
        background(6)
        app.activate()
        sleep(3)
        shot("s4-history-after-bg", app)
        note("after bg history selected=\(app.buttons["History"].isSelected) segmentSelected=\(seg.buttons.allElementsBoundByIndex.map { $0.isSelected })")
        // Cold relaunch: where do they land?
        app.terminate()
        let again = XCUIApplication()
        again.launchEnvironment["VITALS_SEED_HEALTH"] = "1"
        again.launchEnvironment["VITALS_RC_APP_USER_ID"] = "uitest-vitals-resume"
        again.launch()
        sleep(6)
        clearPitch(again)
        shot("s5-cold-relaunch", again)
        note("cold relaunch: Today selected=\(again.buttons["Today"].isSelected) History selected=\(again.buttons["History"].isSelected)")
        // Settings with half-typed goal, interrupted.
        let settings = again.buttons["Settings"]
        if settings.waitForExistence(timeout: 15) {
            settings.tap()
            sleep(2)
            shot("s6-settings", again)
            let field = again.textFields.firstMatch
            if field.waitForExistence(timeout: 10) {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
                for _ in 0..<8 { field.typeText("\u{8}") }
                field.typeText("31")
                shot("s7-half-typed", again)
                background(5)
                again.activate()
                sleep(2)
                shot("s8-settings-after-bg", again)
                note("half-typed after bg: value=\(again.textFields.firstMatch.value as? String ?? "nil") keyboards=\(again.keyboards.count) settingsNav=\(again.navigationBars["Settings"].exists)")
            } else { note("no text field in Settings") }
        } else { note("Settings button missing on relaunch") }
    }
}
