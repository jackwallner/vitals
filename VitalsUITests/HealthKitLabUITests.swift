import XCTest

/// Drives `HealthKitLabHarness` against a real HealthKit store in the simulator.
/// The only thing this test can't do headlessly is grant HealthKit permission,
/// so it taps the system authorization sheet itself.
final class HealthKitLabUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testBasalSampleSpanningNowIsNotCountedInFull() throws {
        // The scenario needs a day that has been running a while: the harness
        // lays its closed samples between midnight and an hour ago, and the
        // spanning one starts an hour ago. Run this between 00:00 and 01:00 and
        // that window has negative width, so no closed samples get written and
        // the strict total is 0 for a reason that says nothing about the code.
        let sinceMidnight = Date.now.timeIntervalSince(
            Calendar.current.startOfDay(for: .now)
        )
        try XCTSkipIf(
            sinceMidnight < 4_500,
            "less than 75 minutes into the local day; the overcount scenario cannot be staged"
        )

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
        let elapsedBucket = value(app, "hklab.elapsed")
        let todayResting = value(app, "hklab.todayResting")
        let todayActive = value(app, "hklab.todayActive")

        XCTContext.runActivity(named: "measured") { _ in
            print("loose=\(loose) strict=\(strict) elapsed=\(elapsedBucket) todayResting=\(todayResting) todayActive=\(todayActive)")
        }

        // 700 kcal of basal genuinely elapsed today as short samples that all end
        // before now. The pathological sample holds 3,600 kcal over 12h starting
        // an hour ago, so exactly one hour of it — 300 kcal — has happened.
        let closed = 700.0
        let inProgressElapsed = 300.0
        let trueTotal = closed + inProgressElapsed

        // Bug (Ozzie's report): the default/loose predicate credits today's
        // calendar-day bucket with the whole in-day portion of the spanning
        // sample, including the hours that haven't happened yet.
        XCTAssertGreaterThan(
            loose, trueTotal + 200,
            "loose predicate no longer overcounts the future-spanning sample — bug premise changed"
        )

        // The rejected alternative, kept as a comparison: `.strictEndDate` cures
        // the overcount by discarding the spanning sample whole, which also throws
        // away the hour of it that genuinely elapsed.
        XCTAssertEqual(
            strict, closed, accuracy: 60,
            "strictEndDate should drop the whole sample that ends after now"
        )

        // The fix: a bucket ending at `now` prorates the in-progress sample to the
        // share that has actually elapsed — no future energy, nothing real lost.
        XCTAssertEqual(
            elapsedBucket, trueTotal, accuracy: 60,
            "an elapsed-window bucket should count the in-progress sample's elapsed share"
        )

        // The shipping read path must be the fixed one.
        XCTAssertEqual(
            todayResting, elapsedBucket, accuracy: 1,
            "fetchTodayStats must use the elapsed-window bucket"
        )
        XCTAssertLessThan(
            todayResting, loose,
            "fetchTodayStats must not report the inflated total the user reported"
        )
        XCTAssertGreaterThan(
            todayResting, strict + 100,
            "fetchTodayStats must not discard the part of the in-progress sample that already happened"
        )

        // Regression guard: prorating must not disturb ordinary closed samples.
        // 54 kcal of active energy was written wholly inside today, well before now.
        XCTAssertEqual(
            todayActive, 54, accuracy: 1,
            "a fully-elapsed sample must still be counted in full"
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
        let rolloverTDEE = value(app, "hklab.rolloverTDEE")

        XCTContext.runActivity(named: "measured") { _ in
            print("liveTDEE=\(liveTDEE) staleTDEE=\(staleTDEE) fixedTDEE=\(fixedTDEE) rolloverTDEE=\(rolloverTDEE)")
        }

        // Scenario writes 8 full days of 1,600 resting + 500 active → TDEE 2,100
        // on a clean store. Pool simulators keep leftover Health samples from
        // other runs, so the live figure may sit above 2,100. The bug under
        // test is cache drift, not the absolute number.
        XCTAssertGreaterThan(liveTDEE, 1_500, "live in-app TDEE should come back as a real average")
        if abs(liveTDEE - 2_100) > 30 {
            print("live TDEE \(liveTDEE) is above the seeded 2100; other Health sources are in this simulator")
        }

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

        // And the trigger: with stale rows restored and the last write dated to an
        // earlier day, the ordinary refresh entry point (what the HealthKit
        // observer calls after midnight) must finalize them on its own.
        XCTAssertEqual(
            rolloverTDEE, liveTDEE, accuracy: 30,
            "a day rollover must finalize the completed days without the app being opened"
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
