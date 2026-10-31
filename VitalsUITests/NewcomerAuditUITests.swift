import XCTest

/// Newcomer persona audit: a first-time user who knows none of the app's
/// vocabulary and wants one useful number straight away.
///
/// The walk covers the real first run, the first Today, a first look around
/// Settings, History and the Upgrade tab, and a return visit. Each step attaches
/// a screenshot of the whole screen (system sheets included) and a text
/// inventory (every label, every control, every control under 44pt) so copy and
/// targets can be judged without OCR. Nothing here asserts product behaviour: a
/// surprise goes into the notes and the walk carries on, so one stuck screen
/// cannot hide the ones after it. Nothing buys; Restore is only tapped on a
/// Test Store customer created for the run.
///
/// The tests are numbered because the order matters: HealthKit permission sticks
/// to the simulator for the run, so the empty-Health first run goes first.
@MainActor
final class NewcomerAuditUITests: XCTestCase {

    /// One Test Store customer for the whole run.
    private static let customer = "uitest-newcomer-\(UUID().uuidString.prefix(8))"
    private static let ringLabel = "Calorie progress"

    private var step = 0
    private var notes: [String] = []

    override func setUp() {
        continueAfterFailure = true
        step = 0
        notes = []
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
        attachment.name = "notes"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 1 First run, nothing in Health

    /// A phone with no energy samples yet: welcome, the real HealthKit sheet,
    /// goals, the pitch, Get Started, and whatever Today says with no data.
    func test1_FirstRunWithNothingInHealth() {
        let app = launch(reset: true)
        let began = Date()
        guard let left = walkOnboarding(app, name: "t1") else { return }
        note("t1: launch to Get Started \(Int(left.timeIntervalSince(began)))s")

        let seconds = secondsToFirstNumber(app, since: left, limit: 25)
        note("t1: Get Started to a calorie number: \(seconds.map { "\(Int($0))s" } ?? "never within 25s")")
        shot(app, "t1-today-after-onboarding")
        sleep(8)
        shot(app, "t1-today-8s-later")
        clearSheets(app, name: "t1")
        scrollThrough(app, in: app, name: "t1-today", pages: 3)
    }

    // MARK: - 2 Goals page mistakes

    /// The two things a newcomer does on the goals page: tap a field and type a
    /// number they believe in, and type something the app refuses.
    func test2_GoalsPageTypingAndRefusal() {
        let app = launch(reset: true)
        let cont = app.buttons["onboarding-continue"]
        guard cont.waitForExistence(timeout: 30) else { return shot(app, "t2-no-welcome") }
        cont.tap()
        _ = answerHealthSheet(app, name: "t2", wait: 8)
        guard app.staticTexts["Set your daily goals"].waitForExistence(timeout: 20) else { return shot(app, "t2-no-goals") }
        sleep(1)
        shot(app, "t2-goals-idle")

        let field = app.textFields.firstMatch
        guard field.waitForExistence(timeout: 5) else { return note("t2: no goal text field") }
        field.tap()
        sleep(2)
        shot(app, "t2-goals-keyboard-up")

        // Blank: the field a newcomer empties before typing.
        clear(field)
        shot(app, "t2-goals-calorie-blank")
        // 100 is under the 500 floor.
        field.typeText("100")
        sleep(1)
        shot(app, "t2-goals-calorie-100")
        note("t2: Continue enabled with 100 calories typed: \(app.buttons["onboarding-continue"].isEnabled)")

        clear(field)
        field.typeText("2200")
        let done = app.buttons["goal-keyboard-done"]
        if done.waitForExistence(timeout: 3), done.isHittable { done.tap() }
        sleep(1)
        shot(app, "t2-goals-2200-after-done")

        // Steps field: the second one.
        let steps = app.textFields.element(boundBy: 1)
        if steps.exists {
            steps.tap()
            clear(steps)
            steps.typeText("0")
            sleep(1)
            shot(app, "t2-goals-steps-zero")
            note("t2: Continue enabled with 0 steps typed: \(app.buttons["onboarding-continue"].isEnabled)")
            if done.exists, done.isHittable { done.tap() }
        }
    }

    // MARK: - 3 First run with a week of Health data

    /// The same first run on a phone that has data: the permission sheet comes
    /// from the seeder at launch, then onboarding runs, then Today has numbers.
    func test3_FirstRunWithHealthData() {
        let app = launch(reset: true, seed: true)
        let began = Date()
        _ = answerHealthSheet(app, name: "t3-launch")
        guard let left = walkOnboarding(app, name: "t3", sheetWait: 8) else { return }
        note("t3: launch to Get Started \(Int(left.timeIntervalSince(began)))s")

        let seconds = secondsToFirstNumber(app, since: left, limit: 40)
        note("t3: Get Started to a calorie number: \(seconds.map { "\(Int($0))s" } ?? "never within 40s")")
        shot(app, "t3-today-first-number")
        sleep(6)
        clearSheets(app, name: "t3")
        shot(app, "t3-today-6s-later")
        scrollThrough(app, in: app, name: "t3-today", pages: 6)
    }

    // MARK: - 4 First look around

    func test4_LookAroundTodaySettingsHistoryUpgrade() {
        let app = launch(seed: true, skipOnboarding: true)
        _ = answerHealthSheet(app, name: "t4", wait: 25)
        _ = secondsToFirstNumber(app, since: Date(), limit: 40)
        clearSheets(app, name: "t4")
        shot(app, "t4-today")

        // What a newcomer taps to learn what a number means.
        tapFirst(app, label: Self.ringLabel, name: "t4-ring")
        backToRoot(app)
        tapFirst(app, label: "Steps", name: "t4-steps")
        backToRoot(app)
        clearSheets(app, name: "t4")

        // Settings, top to bottom, with a few of the "About" dots opened.
        openSettings(app, name: "t4")
        let list = app.descendants(matching: .any)["settings-list"]
        if list.waitForExistence(timeout: 15) {
            shot(app, "t4-settings-top")
            let dots = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'About '"))
            note("t4: Settings has \(dots.count) About dots on the first screen")
            for index in 0..<min(2, dots.count) {
                let dot = dots.element(boundBy: index)
                guard dot.exists, dot.isHittable else { continue }
                note("t4: About dot \(index) is \(dot.frame.size.debugDescription)")
                dot.tap()
                sleep(1)
                shot(app, "t4-settings-dot-\(index)")
                dot.tap()
                sleep(1)
            }
            scrollThrough(app, in: list, name: "t4-settings", pages: 14)
            closeSettings(app)
        }
        clearSheets(app, name: "t4")

        // History.
        let history = app.buttons["tab-history"]
        if history.waitForExistence(timeout: 10) {
            history.tap()
            sleep(4)
            clearSheets(app, name: "t4")
            shot(app, "t4-history")
            scrollThrough(app, in: app, name: "t4-history", pages: 5)
        }

        // Upgrade tab: what the free user is offered, Restore, and a way out.
        let upgrade = app.buttons["tab-upgrade"]
        if upgrade.waitForExistence(timeout: 10) {
            upgrade.tap()
            sleep(4)
            shot(app, "t4-upgrade")
            scrollThrough(app, in: app, name: "t4-upgrade", pages: 4)
            let restore = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'restore'")).firstMatch
            if restore.waitForExistence(timeout: 3) {
                note("t4: Restore control is \(restore.frame.size.debugDescription) at \(restore.frame.origin.debugDescription)")
                restore.tap()
                sleep(1)
                shot(app, "t4-restore-1s")
                sleep(4)
                shot(app, "t4-restore-5s")
                dismissAlert(app)
            } else {
                note("t4: no Restore control reachable on the Upgrade tab")
            }
        }
    }

    // MARK: - 5 The focused trial sheet and the way out

    /// The passive trial sheet a newcomer meets after a few seconds of Today,
    /// and what each of the ways out does.
    func test5_TrialSheetAndTheWayOut() {
        let app = launch(seed: true, skipOnboarding: true)
        _ = answerHealthSheet(app, name: "t5", wait: 6)
        _ = secondsToFirstNumber(app, since: Date(), limit: 40)
        let dismiss = app.buttons.matching(NSPredicate(format: "identifier == 'trial-pitch-dismiss' OR label IN {'Not now','No thanks','Maybe later'}")).firstMatch
        let started = Date()
        guard dismiss.waitForExistence(timeout: 50) else {
            note("t5: no trial sheet within 50s of a loaded Today")
            return shot(app, "t5-no-trial-sheet")
        }
        note("t5: trial sheet appeared \(Int(Date().timeIntervalSince(started)))s after the first number")
        sleep(1)
        shot(app, "t5-trial-sheet")
        let cta = app.buttons["trial-pitch-cta"]
        if cta.exists { note("t5: trial CTA is \(cta.frame.size.debugDescription), label \(cta.label)") }
        note("t5: way out is '\(dismiss.label)' \(dismiss.frame.size.debugDescription)")
        dismiss.tap()
        sleep(3)
        shot(app, "t5-after-way-out")
        // A second sheet (exit offer) may follow the first.
        let again = app.buttons.matching(NSPredicate(format: "identifier IN {'trial-pitch-dismiss','paywall-close'} OR label IN {'Not now','No thanks','Maybe later','Close'}")).firstMatch
        if again.waitForExistence(timeout: 4) {
            note("t5: another sheet followed the way out")
            shot(app, "t5-second-sheet")
            again.tap()
            sleep(2)
            shot(app, "t5-after-second-way-out")
        }
    }

    // MARK: - 6 Return visit

    func test6_ReturnVisit() {
        let app = launch(seed: true, skipOnboarding: true)
        _ = answerHealthSheet(app, name: "t6", wait: 6)
        _ = secondsToFirstNumber(app, since: Date(), limit: 40)
        clearSheets(app, name: "t6")
        shot(app, "t6-first-visit")

        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 15)
        let resumed = Date()
        shot(app, "t6-resumed-immediately", inventory: false)
        let resumeSeconds = secondsToFirstNumber(app, since: resumed, limit: 10)
        note("t6: after backgrounding, calorie number back in \(resumeSeconds.map { "\(String(format: "%.1f", $0))s" } ?? "more than 10s")")
        clearSheets(app, name: "t6")

        // A cold return: no seeding, so the data is whatever Health holds.
        app.terminate()
        let again = XCUIApplication()
        again.launchEnvironment["VITALS_RC_APP_USER_ID"] = Self.customer
        again.launchEnvironment["VITALS_FORCE_SETUP_COMPLETE"] = "1"
        let relaunched = Date()
        again.launch()
        for second in [1, 2, 4] {
            let wait = Double(second) - Date().timeIntervalSince(relaunched)
            if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
            shot(again, "t6-cold-return-\(second)s", inventory: second == 4)
        }
        let cold = secondsToFirstNumber(again, since: relaunched, limit: 30)
        note("t6: cold return, calorie number after \(cold.map { "\(String(format: "%.1f", $0))s" } ?? "more than 30s")")
        sleep(4)
        clearSheets(again, name: "t6-cold")
        shot(again, "t6-cold-return-settled")
    }

    // MARK: - 7 First run, Don't Allow

    /// The newcomer who declines the Health sheet. HealthKit never says whether a
    /// read was refused, so Today sees an empty read; this records what it tells
    /// them and where its recovery button leads. Run alone: the refusal sticks
    /// to the simulator and would empty every other walk.
    func test7_FirstRunDecliningHealthAccess() {
        let app = launch(reset: true)
        let cont = app.buttons["onboarding-continue"]
        guard cont.waitForExistence(timeout: 30) else { return shot(app, "t7-no-welcome") }
        sleep(1)
        shot(app, "t7-welcome")
        cont.tap()

        let decline = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Don't Allow", "UIA.Health.DontAllow.Button")).firstMatch
        if decline.waitForExistence(timeout: 20) {
            sleep(2)
            shot(app, "t7-health-sheet", inventory: false)
            decline.tap()
            sleep(2)
        } else {
            note("t7: no Health sheet to decline within 20s")
        }
        guard app.staticTexts["Set your daily goals"].waitForExistence(timeout: 20) else { return shot(app, "t7-no-goals") }
        shot(app, "t7-goals-after-declining")
        app.buttons["onboarding-continue"].tap()

        let soft = app.buttons["onboarding-get-started"]
        guard soft.waitForExistence(timeout: 30) else { return shot(app, "t7-no-pitch") }
        sleep(2)
        // A newcomer who reads "Restore" and has nothing to restore.
        let restore = app.buttons["Restore"]
        if restore.exists, restore.isHittable {
            note("t7: pitch Restore is \(restore.frame.size.debugDescription)")
            restore.tap()
            sleep(2)
            shot(app, "t7-pitch-restore-2s", inventory: false)
            sleep(5)
            shot(app, "t7-pitch-restore-7s")
        } else {
            note("t7: no reachable Restore on the pitch")
        }
        soft.tap()
        let left = Date()

        let seconds = secondsToFirstNumber(app, since: left, limit: 12)
        note("t7: calorie number after declining: \(seconds.map { "\(Int($0))s" } ?? "none within 12s")")
        sleep(4)
        shot(app, "t7-today-after-declining")
        clearSheets(app, name: "t7")

        // The recovery button in the banner, whichever one this build shows.
        let recovery = app.buttons.matching(NSPredicate(format: "label IN {'Check Health Access','Enable Health','Open Health','Retry'}"))
        note("t7: banner buttons: \((0..<recovery.count).map { recovery.element(boundBy: $0).label }.joined(separator: ", "))")
        for label in ["Retry", "Check Health Access", "Enable Health"] {
            let button = app.buttons[label]
            guard button.exists, button.isHittable else { continue }
            note("t7: '\(label)' is \(button.frame.size.debugDescription)")
            button.tap()
            sleep(4)
            shot(app, "t7-after-\(label.replacingOccurrences(of: " ", with: "-").lowercased())", inventory: false)
            if app.state != .runningForeground {
                note("t7: '\(label)' left the app")
                app.activate()
                _ = app.wait(for: .runningForeground, timeout: 15)
                sleep(2)
            }
        }
        shot(app, "t7-today-after-recovery-taps")
    }

    // MARK: - 8 Empty Health tour

    /// Everything a newcomer with no Health data opens next: Today, History,
    /// Settings, the Upgrade tab. Named to run after test 7, so Health is still
    /// refused and empty, and no seeding runs.
    func test8_EmptyHealthTourOfTodayHistorySettingsUpgrade() {
        let app = launch(skipOnboarding: true)
        sleep(5)
        clearSheets(app, name: "t8")
        shot(app, "t8-today-empty")
        audit(app, name: "t8-today-empty")

        let history = app.buttons["tab-history"]
        if history.waitForExistence(timeout: 10) {
            history.tap()
            sleep(4)
            clearSheets(app, name: "t8")
            shot(app, "t8-history-empty")
            audit(app, name: "t8-history-empty")
        }

        let today = app.buttons["tab-today"]
        if today.waitForExistence(timeout: 5) { today.tap(); sleep(2) }
        openSettings(app, name: "t8")
        let list = app.descendants(matching: .any)["settings-list"]
        if list.waitForExistence(timeout: 15) {
            sleep(1)
            shot(app, "t8-settings-top")
            audit(app, name: "t8-settings-top")
            closeSettings(app)
        }

        let upgrade = app.buttons["tab-upgrade"]
        if upgrade.waitForExistence(timeout: 10) {
            upgrade.tap()
            sleep(4)
            shot(app, "t8-upgrade")
            audit(app, name: "t8-upgrade")
        }
    }

    // MARK: - 9 Exit offer after Get Started

    /// The half-price sheet a newcomer in the offer arm meets after choosing the
    /// free way out of the pitch. `-exitOffer.force` owes it at once; released
    /// builds hold it until a return an hour later. Runs on the screenshot
    /// fixtures, as the exit offer tests do, so Health state does not matter.
    func test9_ExitOfferAfterGetStarted() {
        let app = launch(reset: true, arguments: ["-exitOffer.force"], environment: [
            "VITALS_SCREENSHOT_MODE": "1", "VITALS_SCREENSHOT_SCENE": "onboarding", "VITALS_SCREENSHOT_KEEP_APPEARANCE": "1",
        ])
        guard let left = walkOnboarding(app, name: "t9", expectHealthSheet: false) else { return }
        let tiles = app.descendants(matching: .any)["exit-offer-tiles"]
        let appeared = tiles.waitForExistence(timeout: 30)
        note("t9: exit offer \(appeared ? "appeared \(Int(Date().timeIntervalSince(left)))s after Get Started" : "did not appear within 30s")")
        sleep(1)
        shot(app, "t9-exit-offer")
        guard appeared else { return }
        let noThanks = app.buttons["No thanks"]
        note("t9: No thanks is \(noThanks.frame.size.debugDescription)")
        noThanks.tap()
        sleep(3)
        shot(app, "t9-after-no-thanks")
        let upgrade = app.buttons["tab-upgrade"]
        if upgrade.waitForExistence(timeout: 5) {
            upgrade.tap()
            sleep(4)
            shot(app, "t9-upgrade-after-offer")
        }
    }

    // MARK: - Walks

    /// Welcome, Health sheet, goals, pitch, Get Started. Returns the moment Get
    /// Started was tapped, or nil when the walk could not finish.
    private func walkOnboarding(_ app: XCUIApplication, name: String, expectHealthSheet: Bool = true,
                                sheetWait: TimeInterval = 20) -> Date? {
        let cont = app.buttons["onboarding-continue"]
        guard cont.waitForExistence(timeout: 30) else {
            shot(app, "\(name)-no-welcome")
            note("\(name): welcome never rendered")
            return nil
        }
        sleep(1)
        shot(app, "\(name)-welcome")
        note("\(name): welcome Continue is \(cont.frame.size.debugDescription)")
        cont.tap()

        if expectHealthSheet { _ = answerHealthSheet(app, name: name, wait: sheetWait) }
        guard app.staticTexts["Set your daily goals"].waitForExistence(timeout: 20) else {
            shot(app, "\(name)-no-goals")
            note("\(name): goals page never rendered")
            return nil
        }
        sleep(1)
        shot(app, "\(name)-goals")
        app.buttons["onboarding-continue"].tap()

        let soft = app.buttons["onboarding-get-started"]
        guard soft.waitForExistence(timeout: 30) else {
            shot(app, "\(name)-no-pitch")
            note("\(name): pitch never rendered")
            return nil
        }
        sleep(1)
        shot(app, "\(name)-pitch")
        note("\(name): Get Started is \(soft.frame.size.debugDescription)")
        sleep(4)
        shot(app, "\(name)-pitch-4s-later", inventory: false)
        soft.tap()
        return Date()
    }

    // MARK: - Health sheet

    /// Answers the HealthKit sheet the way a newcomer who wants numbers does:
    /// turn everything on, then Allow. False when no sheet came up.
    @discardableResult
    private func answerHealthSheet(_ app: XCUIApplication, name: String, wait: TimeInterval = 20) -> Bool {
        let allow = app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "UIA.Health.Allow.Button", "Allow")
        ).firstMatch
        guard allow.waitForExistence(timeout: wait) else {
            note("\(name): no Health sheet within \(Int(wait))s")
            return false
        }
        sleep(2)
        shot(app, "\(name)-health-sheet", inventory: false)
        for page in 0..<6 {
            guard allow.exists else { break }
            let master = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
            if master.waitForExistence(timeout: 1),
               master.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Turn On All")).firstMatch.exists {
                master.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                sleep(1)
                if page == 0 { shot(app, "\(name)-health-sheet-all-on", inventory: false) }
            }
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: allow
            )
            guard XCTWaiter().wait(for: [ready], timeout: 12) == .completed else { break }
            allow.tap()
            sleep(2)
        }
        return true
    }

    // MARK: - Moves

    private func launch(reset: Bool = false, seed: Bool = false, skipOnboarding: Bool = false,
                        arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launchEnvironment["VITALS_RC_APP_USER_ID"] = Self.customer
        if reset { app.launchEnvironment["VITALS_RESET_STATE"] = "1" }
        if seed { app.launchEnvironment["VITALS_SEED_HEALTH"] = "1" }
        if skipOnboarding { app.launchEnvironment["VITALS_FORCE_SETUP_COMPLETE"] = "1" }
        app.launch()
        return app
    }

    /// Seconds from `start` until the calorie ring reads a total above zero.
    private func secondsToFirstNumber(_ app: XCUIApplication, since start: Date, limit: TimeInterval) -> TimeInterval? {
        let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", Self.ringLabel)).firstMatch
        while Date().timeIntervalSince(start) < limit {
            if ring.exists, let first = Self.firstNumber(in: ring.value as? String), first > 0 {
                return Date().timeIntervalSince(start)
            }
            usleep(500_000)
        }
        return nil
    }

    private static func firstNumber(in text: String?) -> Int? {
        guard let text else { return nil }
        let stripped = text.filter { !",.\u{00A0}\u{202F}\u{2009}'’".contains($0) }
        let digits = stripped.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    /// Dismisses whatever the app raised on its own, recording each one.
    private func clearSheets(_ app: XCUIApplication, name: String) {
        let way = NSPredicate(format: "identifier IN {'trial-pitch-dismiss','paywall-close'} OR label IN {'Not now','No thanks','Maybe later','Close'}")
        for round in 0..<3 {
            let dismiss = app.buttons.matching(way).firstMatch
            guard dismiss.waitForExistence(timeout: 1) else { return }
            shot(app, "\(name)-unprompted-sheet-\(round)")
            note("\(name): unprompted sheet, way out '\(dismiss.label)' \(dismiss.frame.size.debugDescription)")
            if dismiss.isHittable { dismiss.tap() }
            sleep(2)
        }
    }

    private func tapFirst(_ app: XCUIApplication, label: String, name: String) {
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        guard target.waitForExistence(timeout: 5), target.isHittable else {
            return note("\(name): '\(label)' not tappable")
        }
        target.tap()
        sleep(2)
        shot(app, name)
    }

    private func backToRoot(_ app: XCUIApplication) {
        for _ in 0..<3 {
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists, back.isHittable, app.navigationBars.count > 0 else { return }
            back.tap()
            sleep(1)
        }
    }

    private func openSettings(_ app: XCUIApplication, name: String) {
        let gear = app.buttons["Settings"]
        guard gear.waitForExistence(timeout: 10), gear.isHittable else {
            return note("\(name): Settings button not reachable")
        }
        note("\(name): Settings button is \(gear.frame.size.debugDescription)")
        gear.tap()
    }

    private func closeSettings(_ app: XCUIApplication) {
        let done = app.navigationBars.buttons.matching(NSPredicate(format: "label == 'Done'")).firstMatch
        if done.waitForExistence(timeout: 5), done.isHittable { done.tap() } else { app.swipeDown(velocity: .fast) }
        sleep(2)
    }

    private func dismissAlert(_ app: XCUIApplication) {
        let ok = app.alerts.buttons.firstMatch
        if ok.waitForExistence(timeout: 2) {
            note("t4: alert '\(app.alerts.firstMatch.label)' with button '\(ok.label)'")
            shot(app, "alert")
            ok.tap()
            sleep(1)
        }
    }

    private func clear(_ field: XCUIElement) {
        let current = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
    }

    /// Screenshots every page of a scroll view until the screen stops changing.
    private func scrollThrough(_ app: XCUIApplication, in container: XCUIElement, name: String, pages: Int) {
        var previous = XCUIScreen.main.screenshot().pngRepresentation
        for page in 1...pages {
            container.swipeUp()
            sleep(1)
            let now = XCUIScreen.main.screenshot().pngRepresentation
            if now == previous {
                return note("\(name): scroll ended after \(page - 1) pages")
            }
            previous = now
            shot(app, "\(name)-p\(page)")
        }
        note("\(name): still scrolling after \(pages) pages")
    }

    // MARK: - Evidence

    /// Apple's accessibility audit for what a thumb cares about: hit regions,
    /// element descriptions and traits. Only elements on screen are kept, and a
    /// finding never fails the test.
    private func audit(_ app: XCUIApplication, name: String) {
        var found: [String] = []
        do {
            try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .trait]) { issue in
                guard let target = issue.element, target.exists, target.isHittable else { return true }
                let who = target.identifier.isEmpty ? target.label : target.identifier
                found.append("\(issue.compactDescription): '\(who)' \(Int(target.frame.width))x\(Int(target.frame.height))")
                return true
            }
        } catch {
            found.append("audit could not run: \(error.localizedDescription)")
        }
        note("\(name) accessibility audit: \(found.isEmpty ? "no visible issues" : "\(found.count) issues")")
        for line in found { note("  - \(line)") }
    }


    private func note(_ text: String) {
        notes.append(text)
        print("NEWCOMER \(text)")
    }

    private func shot(_ app: XCUIApplication, _ name: String, inventory: Bool = true) {
        step += 1
        let label = String(format: "%02d-%@", step, name)
        let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picture.name = label
        picture.lifetime = .keepAlways
        add(picture)
        guard inventory else { return }
        let text = XCTAttachment(string: Self.inventory(of: app))
        text.name = "\(label).inventory"
        text.lifetime = .keepAlways
        add(text)
    }

    private static func typeName(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: return "button"
        case .switch: return "switch"
        case .link: return "link"
        case .textField: return "textField"
        case .secureTextField: return "secureTextField"
        case .segmentedControl: return "segmentedControl"
        case .slider: return "slider"
        case .stepper: return "stepper"
        case .tab: return "tab"
        default: return "other"
        }
    }

    /// Every label on screen, every control with its size, and the controls
    /// under 44pt or with no name at all.
    private static func inventory(of app: XCUIApplication) -> String {
        guard let root = try? app.snapshot() else { return "snapshot unavailable" }
        var texts: [String] = []
        var controls: [String] = []
        var small: [String] = []
        var unnamed: [String] = []
        let window = root.frame

        func walk(_ node: XCUIElementSnapshot) {
            let frame = node.frame
            let size = "\(Int(frame.width))x\(Int(frame.height)) at (\(Int(frame.minX)),\(Int(frame.minY)))"
            switch node.elementType {
            case .staticText:
                if !node.label.isEmpty { texts.append(node.label) }
            case .button, .switch, .link, .textField, .secureTextField, .segmentedControl, .slider, .stepper, .tab:
                let kind = typeName(node.elementType)
                let name = node.label.isEmpty ? "(no label)" : node.label
                let line = "type \(kind) '\(name)' id '\(node.identifier)' \(size)"
                if window.intersects(frame), frame.width > 0, frame.height > 0 {
                    controls.append(line)
                    if frame.width < 44 || frame.height < 44 { small.append(line) }
                    if node.label.isEmpty && node.identifier.isEmpty { unnamed.append(line) }
                }
            default:
                break
            }
            for child in node.children { walk(child) }
        }
        walk(root)

        return """
        SCREEN \(Int(window.width))x\(Int(window.height))
        TEXTS (\(texts.count))
        \(texts.map { "- \($0)" }.joined(separator: "\n"))
        CONTROLS (\(controls.count))
        \(controls.map { "- \($0)" }.joined(separator: "\n"))
        UNDER 44PT (\(small.count))
        \(small.map { "- \($0)" }.joined(separator: "\n"))
        NO LABEL AND NO IDENTIFIER (\(unnamed.count))
        \(unnamed.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}
