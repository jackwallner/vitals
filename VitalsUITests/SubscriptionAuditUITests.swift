import XCTest

/// Subscription persona audit: a skeptical free user deciding what is paid,
/// comparing the value, and testing the ways out (Restore, cancel, close).
///
/// Every walk runs on the screenshot fixtures, so HealthKit permission and real
/// data never matter, and nothing buys: no purchase button is ever tapped.
/// Restore is only tapped on a Test Store customer made for the run. Each step
/// attaches a full-screen screenshot and a text inventory (every label, every
/// control with its size, every control under 44pt) so copy and targets can be
/// judged without OCR. Nothing here asserts product behaviour: a surprise goes
/// into the notes and the walk carries on, so one stuck screen cannot hide the
/// ones after it.
@MainActor
final class SubscriptionAuditUITests: XCTestCase {

    /// One Test Store customer for the whole run.
    private static let customer = "uitest-subscription-\(UUID().uuidString.prefix(8))"

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

    // MARK: - 1 The Upgrade tab as a free user

    /// What the free user is shown for money: plans, the terms under the button
    /// for each plan, and what Restore does to that text.
    func test1_UpgradeTabPlansAndRestore() {
        let app = launch(scene: "dashboard")
        guard app.buttons["tab-upgrade"].waitForExistence(timeout: 40) else { return shot(app, "u1-no-tabs") }
        clearSheets(app, name: "u1")
        app.buttons["tab-upgrade"].tap()
        let buy = app.buttons["paywall-purchase"]
        guard buy.waitForExistence(timeout: 30) else { return shot(app, "u1-no-paywall") }
        sleep(2)
        shot(app, "u1-upgrade-top")
        note("u1: CTA '\(Self.text(buy))' \(Self.size(buy))")
        note("u1: terms on first view: [\(terms(app))]")
        audit(app, name: "u1-upgrade")
        scrollThrough(app, in: app, name: "u1-upgrade", pages: 3)
        for _ in 0..<3 { app.swipeDown() }

        for plan in ["Monthly", "Lifetime", "Yearly"] {
            let card = planCard(app, plan)
            guard card.waitForExistence(timeout: 3) else { note("u1: no \(plan) plan card"); continue }
            for _ in 0..<3 where !card.isHittable { app.swipeUp() }
            note("u1: \(plan) card '\(Self.text(card))' \(Self.size(card))")
            card.tap()
            sleep(1)
            shot(app, "u1-plan-\(plan.lowercased())")
            note("u1: \(plan) selected, CTA '\(Self.text(buy))', terms: [\(terms(app))]")
        }

        // Restore as a skeptic who has nothing to restore, then back to comparing plans.
        let restore = app.buttons["Restore"]
        guard restore.waitForExistence(timeout: 3) else { return note("u1: no Restore control") }
        note("u1: Restore is \(Self.size(restore))")
        restore.tap()
        sleep(1)
        shot(app, "u1-restore-1s", inventory: false)
        _ = app.buttons["Restoring…"].waitForNonExistence(timeout: 20)
        sleep(1)
        shot(app, "u1-restore-done")
        note("u1: after Restore: terms [\(terms(app))], restore text [\(restoreText(app))]")
        let monthly = planCard(app, "Monthly")
        if monthly.exists {
            monthly.tap()
            sleep(1)
            shot(app, "u1-restore-then-monthly")
            note("u1: after Restore then Monthly: CTA '\(Self.text(buy))', terms [\(terms(app))], restore text [\(restoreText(app))]")
        }
    }

    // MARK: - 2 The pitch, its Restore, the exit offer and the welcome price

    /// Onboarding's last page as a skeptic reads it, what Restore says there,
    /// the free way out, the half-price sheet that follows, its way out, and the
    /// price the Upgrade tab then holds.
    func test2_PitchRestoreExitOfferAndWelcomePrice() {
        let app = launch(scene: "onboarding", arguments: ["-exitOffer.force"], keepAppearance: true)
        for page in ["welcome", "goals"] {
            let next = app.buttons["onboarding-continue"]
            guard next.waitForExistence(timeout: 30) else { return shot(app, "p2-no-\(page)") }
            sleep(1)
            next.tap()
            dismissSystemSheet()
        }
        let soft = app.buttons["onboarding-get-started"]
        guard soft.waitForExistence(timeout: 30) else { return shot(app, "p2-no-pitch") }
        sleep(2)
        shot(app, "p2-pitch")
        audit(app, name: "p2-pitch")
        let trial = app.buttons.matching(NSPredicate(format: "identifier == 'trial-pitch-cta' OR label CONTAINS[c] 'free trial'")).firstMatch
        note("p2: pitch CTA '\(Self.text(trial))' \(Self.size(trial)); Get Started \(Self.size(soft)); terms [\(terms(app))]")

        let restore = app.buttons["Restore"]
        if restore.exists, restore.isHittable {
            note("p2: pitch Restore is \(Self.size(restore))")
            restore.tap()
            sleep(1)
            shot(app, "p2-pitch-restore-1s", inventory: false)
            _ = app.buttons["Restoring…"].waitForNonExistence(timeout: 20)
            sleep(1)
            shot(app, "p2-pitch-restore-done")
            note("p2: after pitch Restore: terms [\(terms(app))], restore text [\(restoreText(app))]")
        } else {
            note("p2: no reachable Restore on the pitch")
        }

        soft.tap()
        let left = Date()
        let tiles = app.descendants(matching: .any)["exit-offer-tiles"]
        let appeared = tiles.waitForExistence(timeout: 40)
        note("p2: exit offer \(appeared ? "appeared \(Int(Date().timeIntervalSince(left)))s after Get Started" : "did not appear within 40s")")
        guard appeared else { return shot(app, "p2-no-exit-offer") }
        sleep(2)
        shot(app, "p2-exit-offer")
        audit(app, name: "p2-exit-offer")
        note("p2: offer tiles '\(tiles.label)'; terms [\(terms(app))]")
        let noThanks = app.buttons["No thanks"]
        note("p2: No thanks is \(Self.size(noThanks))")

        let offerRestore = app.buttons["Restore"]
        if offerRestore.exists, offerRestore.isHittable {
            note("p2: offer Restore is \(Self.size(offerRestore))")
            offerRestore.tap()
            _ = app.buttons["Restoring…"].waitForNonExistence(timeout: 20)
            sleep(1)
            shot(app, "p2-offer-restore-done")
            note("p2: after offer Restore: terms [\(terms(app))], restore text [\(restoreText(app))]")
        }

        if noThanks.exists { noThanks.tap() } else { note("p2: no 'No thanks' button to tap") }
        sleep(3)
        shot(app, "p2-after-no-thanks")
        let upgrade = app.buttons["tab-upgrade"]
        if upgrade.waitForExistence(timeout: 5) {
            upgrade.tap()
            sleep(3)
            shot(app, "p2-upgrade-welcome-price")
            note("p2: Upgrade tab after the offer: terms [\(terms(app))]")
            scrollThrough(app, in: app, name: "p2-upgrade", pages: 2)
        }
    }

    // MARK: - 3 Settings as a free user

    /// The first Settings screen as a free user meets it, the upsell row, and
    /// what a locked switch does when it is flipped.
    func test3_SettingsUpsellAndLockedSwitches() {
        let app = launch(scene: "settings", keepAppearance: true)
        let list = app.descendants(matching: .any)["settings-list"]
        guard list.waitForExistence(timeout: 40) else { return shot(app, "s3-no-settings") }
        sleep(2)
        shot(app, "s3-settings-top")
        audit(app, name: "s3-settings-top")

        let unlock = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Unlock Vitals+'")).firstMatch
        if unlock.waitForExistence(timeout: 5) {
            note("s3: upsell row '\(Self.text(unlock))' \(Self.size(unlock))")
            unlock.tap()
            readPitch(app, name: "s3-upsell-row")
        } else {
            note("s3: no 'Unlock Vitals+' row on the first screen")
        }

        for title in ["Net Deficit", "Weekly Recap"] {
            let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { list.swipeUp() }
            guard toggle.exists, toggle.isHittable else {
                note("s3: '\(title)' switch not reachable")
                continue
            }
            let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
            note("s3: '\(title)' switch label '\(Self.text(toggle))' value '\(toggle.value as? String ?? "?")' \(Self.size(toggle))")
            shot(app, "s3-\(slug)-before", inventory: false)
            toggle.tap()
            usleep(400_000)
            shot(app, "s3-\(slug)-just-tapped", inventory: false)
            readPitch(app, name: "s3-\(slug)")
            note("s3: '\(title)' after the way out: value '\(toggle.value as? String ?? "?")', still hittable \(toggle.isHittable)")
            shot(app, "s3-\(slug)-back-in-settings", inventory: false)
        }

        for _ in 0..<10 { list.swipeDown() }
        scrollThrough(app, in: list, name: "s3-settings", pages: 9)
    }

    // MARK: - 4 History as a free user

    /// The two History controls the listing's free column and the paywall both
    /// talk about: the Custom period and the summary report.
    func test4_HistoryLockedCustomRangeAndReport() {
        let app = launch(scene: "dashboard", keepAppearance: true)
        guard app.buttons["tab-history"].waitForExistence(timeout: 40) else { return shot(app, "h4-no-tabs") }
        clearSheets(app, name: "h4")
        app.buttons["tab-history"].tap()
        sleep(5)
        clearSheets(app, name: "h4")
        shot(app, "h4-history")
        audit(app, name: "h4-history")

        let custom = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Custom'")).firstMatch
        if custom.waitForExistence(timeout: 5) {
            note("h4: Custom period '\(Self.text(custom))' hint '\(custom.value as? String ?? "")' \(Self.size(custom))")
            custom.tap()
            readPitch(app, name: "h4-custom")
        } else {
            note("h4: no Custom period control")
        }

        let report = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'summary report'")).firstMatch
        if report.waitForExistence(timeout: 5) {
            note("h4: report control '\(Self.text(report))' \(Self.size(report))")
            report.tap()
            readPitch(app, name: "h4-report")
        } else {
            note("h4: no summary report control")
        }

        // The CSV export the listing calls free.
        let share = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'share' OR label CONTAINS[c] 'export'")).firstMatch
        if share.waitForExistence(timeout: 3), share.isHittable {
            note("h4: export control '\(Self.text(share))' \(Self.size(share))")
            share.tap()
            sleep(2)
            shot(app, "h4-export-tap")
            let ok = app.alerts.buttons.firstMatch
            if ok.waitForExistence(timeout: 2) {
                note("h4: export alert '\(app.alerts.firstMatch.label)', first button '\(ok.label)'")
                let cancel = app.alerts.buttons["Cancel"]
                if cancel.exists { cancel.tap() } else { note("h4: export alert has no Cancel button, left as is") }
            }
        } else {
            note("h4: no export control reachable by label")
        }
    }

    // MARK: - 5 The subscriber's view

    /// What a paying customer sees on the Vitals+ tab and in Settings: whether
    /// anything names the plan, the renewal date, or a way to manage or cancel.
    func test5_SubscriberViewHasManageAndCancel() {
        let app = launch(scene: "premiumActive", keepAppearance: true)
        guard app.buttons["tab-upgrade"].waitForExistence(timeout: 40) else { return shot(app, "v5-no-tabs") }
        sleep(4)
        clearSheets(app, name: "v5")
        shot(app, "v5-vitals-plus-tab")
        audit(app, name: "v5-vitals-plus-tab")
        scrollThrough(app, in: app, name: "v5-vitals-plus-tab", pages: 8)
        note("v5: manage or cancel words anywhere on the tab's screens: \(manageWords(app))")

        for _ in 0..<12 { app.swipeDown() }
        let restoreRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Restore'")).firstMatch
        for _ in 0..<10 where !(restoreRow.exists && restoreRow.isHittable) { app.swipeUp() }
        if restoreRow.exists, restoreRow.isHittable {
            note("v5: Restore row '\(Self.text(restoreRow))' \(Self.size(restoreRow))")
            restoreRow.tap()
            sleep(3)
            shot(app, "v5-restore-alert", inventory: false)
            let alert = app.alerts.firstMatch
            if alert.exists { note("v5: alert '\(alert.label)': \(alert.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))") }
            let ok = app.alerts.buttons.firstMatch
            if ok.exists { ok.tap() }
        } else {
            note("v5: no Restore row reachable")
        }
        app.terminate()

        // Settings as a subscriber.
        let again = launch(scene: "settingsPro", keepAppearance: true)
        let list = again.descendants(matching: .any)["settings-list"]
        guard list.waitForExistence(timeout: 40) else { return shot(again, "v5-no-settings") }
        sleep(2)
        shot(again, "v5-settings-top")
        scrollThrough(again, in: list, name: "v5-settings", pages: 10)
        note("v5: manage or cancel words in Settings: \(manageWords(again))")
    }

    // MARK: - Moves

    private func launch(scene: String, arguments: [String] = [], keepAppearance: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launchEnvironment["VITALS_RC_APP_USER_ID"] = Self.customer
        app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["VITALS_SCREENSHOT_SCENE"] = scene
        if keepAppearance { app.launchEnvironment["VITALS_SCREENSHOT_KEEP_APPEARANCE"] = "1" }
        app.launch()
        return app
    }

    /// A plan card on the paywall, found by its plan name. The purchase button
    /// is excluded so a CTA that mentions the plan is never tapped.
    private func planCard(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ AND identifier != 'paywall-purchase' AND identifier != 'trial-pitch-cta'", name
        )).firstMatch
    }

    /// Waits for the trial sheet, records what it says, and leaves by its way out.
    private func readPitch(_ app: XCUIApplication, name: String) {
        let dismiss = app.buttons["trial-pitch-dismiss"]
        guard dismiss.waitForExistence(timeout: 15) else {
            note("\(name): no pitch sheet within 15s")
            return shot(app, "\(name)-no-pitch")
        }
        sleep(2)
        shot(app, "\(name)-pitch")
        let cta = app.buttons["trial-pitch-cta"]
        note("\(name): CTA '\(Self.text(cta))' \(Self.size(cta)); way out '\(Self.text(dismiss))' \(Self.size(dismiss)); terms [\(terms(app))]")
        let restore = app.buttons["Restore"]
        if restore.exists { note("\(name): Restore \(Self.size(restore))") }
        dismiss.tap()
        sleep(2)
        shot(app, "\(name)-after-way-out", inventory: false)
    }

    /// The renewal and price terms currently on screen, one string.
    private func terms(_ app: XCUIApplication) -> String {
        let query = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] 'renews' OR label CONTAINS[c] 'One-time purchase'"
        ))
        return query.allElementsBoundByIndex.map { $0.label }.joined(separator: " || ")
    }

    /// The Restore outcome line currently on screen, if any.
    private func restoreText(_ app: XCUIApplication) -> String {
        let query = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] 'No active' OR label CONTAINS[c] 'restore' OR label CONTAINS[c] 'found for this Apple ID'"
        ))
        return query.allElementsBoundByIndex.map { $0.label }.joined(separator: " || ")
    }

    /// Any visible word that would name a way to manage or cancel.
    private func manageWords(_ app: XCUIApplication) -> String {
        let query = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] 'manage' OR label CONTAINS[c] 'cancel' OR label CONTAINS[c] 'renew' OR label CONTAINS[c] 'billing' OR label CONTAINS[c] 'subscription'"
        ))
        let labels = query.allElementsBoundByIndex.map { $0.label }
        return labels.isEmpty ? "none" : labels.joined(separator: " || ")
    }

    private func dismissSystemSheet() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Turn On All", "Don't Allow"] where springboard.buttons[label].exists {
            springboard.buttons[label].tap()
            sleep(2)
            return
        }
    }

    /// Dismisses whatever the app raised on its own, recording each one.
    private func clearSheets(_ app: XCUIApplication, name: String) {
        let way = NSPredicate(format: "identifier IN {'trial-pitch-dismiss','paywall-close'} OR label IN {'Not now','No thanks','Maybe later'}")
        for round in 0..<3 {
            let dismiss = app.buttons.matching(way).firstMatch
            guard dismiss.waitForExistence(timeout: 1) else { return }
            shot(app, "\(name)-unprompted-sheet-\(round)")
            note("\(name): unprompted sheet, way out '\(Self.text(dismiss))' \(Self.size(dismiss))")
            if dismiss.isHittable { dismiss.tap() }
            sleep(2)
        }
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

    private static func text(_ element: XCUIElement) -> String {
        element.exists ? element.label : "(not on screen)"
    }

    private static func size(_ element: XCUIElement) -> String {
        guard element.exists else { return "(not on screen)" }
        let frame = element.frame
        return "\(Int(frame.width))x\(Int(frame.height)) at (\(Int(frame.minX)),\(Int(frame.minY)))"
    }

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
        print("SUBSCRIPTION \(text)")
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
