import XCTest

/// Drives `HealthKitLabHarness` against a real HealthKit store in the simulator.
/// The only thing this test can't do headlessly is grant HealthKit permission,
/// so it taps the system authorization sheet itself.
final class HealthKitLabUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testBasalSampleSpanningNowIsNotCountedInFull() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_HK_LAB"] = "1"
        app.launch()

        grantHealthKitAccess(in: app)

        let state = app.staticTexts["hklab.state"]
        XCTAssertTrue(
            state.waitForExistence(timeout: 60),
            "lab never rendered; status=\(statusText(app))"
        )
        let deadline = Date.now.addingTimeInterval(120)
        while state.label != "FINISHED", Date.now < deadline {
            _ = app.staticTexts["hklab.nonexistent"].waitForExistence(timeout: 1)
        }
        XCTAssertEqual(state.label, "FINISHED", "lab did not finish; status=\(statusText(app))")

        let authInfoEl = app.staticTexts["hklab.authInfo"]
        let authInfo = "writeAuth[\(authInfoEl.exists ? authInfoEl.label : "?")]"
        XCTAssertEqual(statusText(app), "done", "lab reported an error. \(authInfo)")

        let loose = value(app, "hklab.loose")
        let strict = value(app, "hklab.strict")
        let todayResting = value(app, "hklab.todayResting")

        XCTContext.runActivity(named: "measured") { _ in
            print("loose=\(loose) strict=\(strict) todayResting=\(todayResting)")
        }

        // 700 kcal of basal genuinely elapsed today (short samples that all end
        // before now). The pathological sample holds 3,600 kcal but ends ~11h in
        // the future, so only a fraction has actually happened.
        let elapsed = 700.0

        // Bug (Ozzie's report): the default/loose predicate lets a basal sample
        // that ends in the future leak its not-yet-burned energy into today's
        // bucket, pushing the total well above what actually elapsed. The exact
        // figure is time-of-day dependent (HealthKit proportionally splits the
        // sample into the day bucket), but it always clears `elapsed` by the full
        // hour of the sample that precedes now (~300 kcal) plus its in-day future.
        XCTAssertGreaterThan(
            loose, elapsed + 200,
            "loose predicate no longer overcounts the future-spanning sample — bug premise changed"
        )

        // Fix: `.strictEndDate` drops the sample that ends after now entirely,
        // leaving only basal that genuinely elapsed today.
        XCTAssertEqual(
            strict, elapsed, accuracy: 60,
            "strictEndDate should drop the sample that ends after now"
        )

        // The shipping read path must use the fixed predicate, so the number the
        // user actually sees matches `strict`, not the inflated `loose` total.
        XCTAssertEqual(
            todayResting, strict, accuracy: 60,
            "fetchTodayStats must use strictEndDate so today's resting isn't inflated"
        )
        XCTAssertLessThan(
            todayResting, loose,
            "fetchTodayStats must not report the inflated loose total the user reported"
        )
    }

    /// Bug 2 (Tim White): the Maintenance/TDEE widget reads only the SwiftData
    /// cache. The today/observer path leaves recent completed days as stale
    /// partial snapshots, so the widget figure drifted below the in-app live one
    /// until the app was reopened. Verifies the drift and that
    /// `refreshHistoryCache` (now run from the background task) restores parity.
    func testMaintenanceWidgetCacheMatchesLiveAfterHistoryRefresh() {
        let app = XCUIApplication()
        app.launchEnvironment["VITALS_HK_LAB"] = "1"
        app.launchEnvironment["VITALS_HK_LAB_SCENARIO"] = "maintenance"
        app.launch()

        grantHealthKitAccess(in: app)

        let state = app.staticTexts["hklab.state"]
        XCTAssertTrue(
            state.waitForExistence(timeout: 60),
            "lab never rendered; status=\(statusText(app))"
        )
        let deadline = Date.now.addingTimeInterval(120)
        while state.label != "FINISHED", Date.now < deadline {
            _ = app.staticTexts["hklab.nonexistent"].waitForExistence(timeout: 1)
        }
        XCTAssertEqual(state.label, "FINISHED", "lab did not finish; status=\(statusText(app))")

        let authInfoEl = app.staticTexts["hklab.authInfo"]
        let authInfo = "writeAuth[\(authInfoEl.exists ? authInfoEl.label : "?")]"
        XCTAssertEqual(statusText(app), "done", "lab reported an error. \(authInfo)")

        let liveTDEE = value(app, "hklab.liveTDEE")
        let staleTDEE = value(app, "hklab.staleTDEE")
        let fixedTDEE = value(app, "hklab.fixedTDEE")

        XCTContext.runActivity(named: "measured") { _ in
            print("liveTDEE=\(liveTDEE) staleTDEE=\(staleTDEE) fixedTDEE=\(fixedTDEE)")
        }

        // Scenario writes 8 full days of 1,600 resting + 500 active → TDEE 2,100.
        XCTAssertEqual(liveTDEE, 2_100, accuracy: 30, "live in-app TDEE should reflect the written full days")

        // Bug: reading the stale/partial cache through the widget's own code path
        // yields a materially different (lower) figure than the app shows live.
        XCTAssertLessThan(
            staleTDEE, liveTDEE - 100,
            "stale partial cache should drift below the live figure (the reported mismatch)"
        )

        // Fix: after refreshHistoryCache finalizes the completed days, the
        // widget's cache read matches the in-app live figure.
        XCTAssertEqual(
            fixedTDEE, liveTDEE, accuracy: 30,
            "refreshHistoryCache must bring the widget cache back in line with the live figure"
        )
    }

    private func value(_ app: XCUIApplication, _ identifier: String) -> Double {
        let element = app.staticTexts[identifier]
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("missing \(identifier)")
            return .nan
        }
        return Double(element.label) ?? .nan
    }

    private func statusText(_ app: XCUIApplication) -> String {
        let status = app.staticTexts["hklab.status"]
        return status.exists ? status.label : "<no status>"
    }

    /// The HealthKit sheet is a remote view, so its elements show up in the
    /// app's hierarchy rather than SpringBoard's. "Allow" is disabled until at
    /// least one category is switched on, so enable everything first.
    ///
    /// A missing sheet is not a failure: if this device already granted access
    /// the request returns without prompting.
    private func grantHealthKitAccess(in app: XCUIApplication) {
        guard anyAllowButton(in: app).waitForExistence(timeout: 30) else { return }

        // iOS 27 splits this into two pages: pick the data categories, then pick
        // how far back to share. Each page has its own Allow, disabled until
        // that page has a selection, so drive them until the request completes.
        for page in 0..<5 {
            if authorizationFinished(in: app) { return }

            let button = anyAllowButton(in: app)
            guard button.waitForExistence(timeout: 15) else {
                XCTFail(
                    "no Allow button on page \(page) and auth never completed. hierarchy:\n"
                    + app.debugDescription
                )
                return
            }

            // The individual *switch* elements are named differently across OS
            // versions (iOS 26 drops the Read/Write infix and reuses one
            // identifier for both sections), but the enclosing *cells* are named
            // consistently and each exposes a 0/1 `value`. Gate on the cells so
            // the same code works on iOS 26 and 27.
            let cellIDs = [
                "UIA.Health.Read.ActiveEnergy.SwitchCell",
                "UIA.Health.Read.RestingEnergy.SwitchCell",
                "UIA.Health.Write.ActiveEnergy.SwitchCell",
                "UIA.Health.Write.RestingEnergy.SwitchCell",
            ]
            // Steps is requested for read (fetchTodayStats queries it). Identifier
            // differs slightly across OS versions; include whichever is present.
            let stepCellIDs = [
                "UIA.Health.Read.Steps.SwitchCell",
                "UIA.Health.Read.StepCount.SwitchCell",
            ]
            let onPageWithSwitches = app.cells[cellIDs[0]].waitForExistence(timeout: 3)

            if onPageWithSwitches {
                // The lab both writes and reads basal/active energy, so every
                // read AND write toggle must be on before advancing. The
                // on-screen master "Turn On All" cell flips them all in one
                // tap with no scrolling, sidestepping the swipe-toggles-a-switch
                // flakiness. Tap it, then enable any straggler by tapping its
                // row (never the switch element, and never a blind swipe).
                let deadline = Date.now.addingTimeInterval(30)
                while Date.now < deadline {
                    let required = cellIDs + stepCellIDs.filter { app.cells[$0].exists }
                    if allCellsOn(in: app, required) { break }
                    tapTurnOnAll(in: app)
                    for identifier in required where app.cells[identifier].value as? String != "1" {
                        enableCell(in: app, identifier: identifier)
                    }
                    _ = app.staticTexts["hklab.nonexistent"].waitForExistence(timeout: 1)
                }
                let required = cellIDs + stepCellIDs.filter { app.cells[$0].exists }
                guard allCellsOn(in: app, required) else {
                    XCTFail("could not enable every category. hierarchy:\n\(app.debugDescription)")
                    return
                }
            } else {
                // iOS 27 page 2: grant the whole history, not just the past 30 days.
                tapFirstMatch(in: app, label: "Full History")
            }

            // Re-resolve the confirm button each poll: the page animates and the
            // query can briefly lose its match.
            let deadline = Date.now.addingTimeInterval(15)
            var ready = false
            while Date.now < deadline {
                let current = anyAllowButton(in: app)
                if current.exists, current.isEnabled, current.isHittable {
                    ready = true
                    break
                }
                _ = app.buttons["hklab.nonexistent"].waitForExistence(timeout: 1)
            }
            guard ready else {
                XCTFail("Allow stayed disabled on page \(page). hierarchy:\n\(app.debugDescription)")
                return
            }
            anyAllowButton(in: app).tap()
            _ = app.buttons["hklab.nonexistent"].waitForExistence(timeout: 3)
        }
    }

    /// The sheet's confirm button keeps its identifier but relabels itself
    /// "Allow" → "Continue" once categories are switched on, so match on either.
    private func anyAllowButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@ OR label == %@",
                "UIA.Health.Allow.Button", "Allow", "Continue"
            )
        ).firstMatch
    }

    /// Taps the master "Turn On All" cell when it's present and still in the
    /// "on" direction. Exists on both iOS 26 ("Turn On All") and iOS 27
    /// ("Turn on all (N) categories"); one tap flips every read + write toggle
    /// with no scrolling. No-op once everything is already on (the label flips
    /// to "Turn Off All").
    private func tapTurnOnAll(in app: XCUIApplication) {
        let master = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        guard master.exists, master.isHittable else { return }
        let stillOff = master.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Turn On All")
        ).firstMatch.exists
        guard stillOff else { return }
        master.tap()
    }

    /// Scrolls a category row into view and taps it (which flips its switch).
    /// Taps the row body rather than the switch element: a swipe that lands on a
    /// switch can drag it half-on, whereas the row is safe to scroll and tap.
    private func enableCell(in app: XCUIApplication, identifier: String) {
        let cell = app.cells[identifier]
        guard cell.exists else { return }
        var scrolls = 0
        while !cell.isHittable, scrolls < 4 {
            app.swipeUp()
            scrolls += 1
        }
        guard cell.isHittable, cell.value as? String != "1" else { return }
        cell.tap()
    }

    /// True only when every listed category cell reads "on". Cells stay in the
    /// hierarchy with their value even when scrolled off, so this reads reliably
    /// regardless of scroll position.
    private func allCellsOn(in app: XCUIApplication, _ identifiers: [String]) -> Bool {
        for identifier in identifiers {
            let cell = app.cells[identifier]
            guard cell.exists, cell.value as? String == "1" else { return false }
        }
        return true
    }

    /// The harness moves off "requesting authorization" as soon as the request
    /// returns, which is the only reliable signal that the sheet is done.
    private func authorizationFinished(in app: XCUIApplication) -> Bool {
        let status = app.staticTexts["hklab.status"]
        return status.exists && status.label != "requesting authorization"
    }

    /// The sheet's controls aren't consistently buttons, so try each element
    /// type that can carry the label.
    private func tapFirstMatch(in app: XCUIApplication, label: String) {
        for query in [app.buttons, app.cells, app.staticTexts] {
            let element = query[label]
            if element.exists, element.isHittable {
                element.tap()
                return
            }
        }
    }
}
