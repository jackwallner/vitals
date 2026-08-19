import XCTest

final class MacroTotalsTests: XCTestCase {
    func testCaloriesUseAtwaterFactors() {
        let totals = MacroTotals(protein: 150, carbs: 200, fat: 60)
        // 150*4 + 200*4 + 60*9 = 600 + 800 + 540
        XCTAssertEqual(totals.calories, 1_940, accuracy: 0.001)
    }

    func testSharesSumToOneAndMatchCalorieContribution() throws {
        let totals = MacroTotals(protein: 150, carbs: 200, fat: 60)
        let protein = try XCTUnwrap(totals.share(.protein))
        let carbs = try XCTUnwrap(totals.share(.carbs))
        let fat = try XCTUnwrap(totals.share(.fat))

        XCTAssertEqual(protein, 600.0 / 1_940.0, accuracy: 0.0001)
        XCTAssertEqual(carbs, 800.0 / 1_940.0, accuracy: 0.0001)
        XCTAssertEqual(fat, 540.0 / 1_940.0, accuracy: 0.0001)
        XCTAssertEqual(protein + carbs + fat, 1.0, accuracy: 0.0001)
    }

    func testEmptyDayHasNoDataAndNoShares() {
        let totals = MacroTotals.zero
        XCTAssertFalse(totals.hasData)
        XCTAssertNil(totals.share(.protein))
        XCTAssertEqual(totals.calories, 0)
    }

    /// A day where only one macro was logged is still a logged day.
    func testPartialDayCountsAsData() {
        let totals = MacroTotals(protein: 40, carbs: 0, fat: 0)
        XCTAssertTrue(totals.hasData)
        XCTAssertEqual(try XCTUnwrap(totals.share(.protein)), 1.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(totals.share(.carbs)), 0.0, accuracy: 0.0001)
    }

    /// HealthKit shouldn't hand back negatives, but a negative gram count would
    /// invert the dashboard bars if one ever arrived.
    func testNegativeInputsClampToZero() {
        let totals = MacroTotals(protein: -20, carbs: 100, fat: -5)
        XCTAssertEqual(totals.protein, 0)
        XCTAssertEqual(totals.fat, 0)
        XCTAssertEqual(totals.carbs, 100)
    }

    func testSummaryExcludesUnloggedDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = { (offset: Int) -> Date in
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)))!
        }
        let macrosByDay: [Date: MacroTotals] = [
            day(0): MacroTotals(protein: 100, carbs: 200, fat: 50),
            day(1): .zero,                                            // not logged
            day(2): MacroTotals(protein: 200, carbs: 100, fat: 70),
        ]

        let summary = try XCTUnwrap(MacroSummary.make(macrosByDay: macrosByDay, calendar: calendar))

        // Averages divide by 2 logged days, not 3 calendar days.
        XCTAssertEqual(summary.loggedDays, 2)
        XCTAssertEqual(summary.average.protein, 150, accuracy: 0.001)
        XCTAssertEqual(summary.average.carbs, 150, accuracy: 0.001)
        XCTAssertEqual(summary.average.fat, 60, accuracy: 0.001)
        XCTAssertEqual(summary.total.protein, 300, accuracy: 0.001)
        XCTAssertEqual(summary.days.map(\.date), [day(0), day(2)])
    }

    func testSummaryIsNilWhenNothingLogged() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(MacroSummary.make(macrosByDay: [:], calendar: calendar))
        XCTAssertNil(MacroSummary.make(macrosByDay: [start: .zero], calendar: calendar))
    }

    func testGoalRangesAcceptDefaults() {
        for kind in MacroKind.allCases {
            XCTAssertTrue(kind.goalRange.contains(kind.defaultGoal), "\(kind.label) default is out of range")
        }
    }
}

extension MacroTotalsTests {
    /// Independently rounding each share gives 31 + 40 + 30 = 101 for this day,
    /// which reads as a bug when the three sit on one line.
    func testSharePercentagesAlwaysSumTo100() throws {
        let cases: [MacroTotals] = [
            MacroTotals(protein: 142, carbs: 186, fat: 61),
            MacroTotals(protein: 100, carbs: 100, fat: 100),
            MacroTotals(protein: 1, carbs: 1, fat: 1),
            MacroTotals(protein: 33, carbs: 33, fat: 33),
            MacroTotals(protein: 200, carbs: 0, fat: 0),
        ]
        for totals in cases {
            let split = try XCTUnwrap(totals.sharePercentages())
            XCTAssertEqual(split.values.reduce(0, +), 100, "\(totals) split did not sum to 100")
        }
    }

    func testSharePercentagesNilWhenNothingLogged() {
        XCTAssertNil(MacroTotals.zero.sharePercentages())
    }
}

extension MacroTotalsTests {
    func testHasDataIsScopedToTrackedMacros() {
        let proteinOnlyDay = MacroTotals(protein: 40, carbs: 0, fat: 0)
        XCTAssertTrue(proteinOnlyDay.hasData(in: [.protein]))
        // A carb counter shouldn't see this day counted just because protein synced.
        XCTAssertFalse(proteinOnlyDay.hasData(in: [.carbs]))
        XCTAssertFalse(proteinOnlyDay.hasData(in: [.carbs, .fat]))
        XCTAssertTrue(proteinOnlyDay.hasData(in: [.protein, .carbs]))
    }

    func testSummaryOnlyCountsDaysWithATrackedMacro() throws {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day = { (o: Int) in calendar.date(byAdding: .day, value: o, to: base)! }
        let macrosByDay: [Date: MacroTotals] = [
            day(0): MacroTotals(protein: 100, carbs: 0, fat: 0),   // protein only
            day(1): MacroTotals(protein: 0, carbs: 200, fat: 0),   // carbs only
            day(2): MacroTotals(protein: 150, carbs: 100, fat: 40),
        ]

        let carbsOnly = try XCTUnwrap(MacroSummary.make(macrosByDay: macrosByDay, visible: [.carbs], calendar: calendar))
        XCTAssertEqual(carbsOnly.loggedDays, 2)
        XCTAssertEqual(carbsOnly.average.carbs, 150, accuracy: 0.001)

        let all = try XCTUnwrap(MacroSummary.make(macrosByDay: macrosByDay, calendar: calendar))
        XCTAssertEqual(all.loggedDays, 3)
    }

    func testBestDayIsPerMacroAndNilWhenUnlogged() throws {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day = { (o: Int) in calendar.date(byAdding: .day, value: o, to: base)! }
        let macrosByDay: [Date: MacroTotals] = [
            day(0): MacroTotals(protein: 100, carbs: 300, fat: 0),
            day(1): MacroTotals(protein: 180, carbs: 120, fat: 0),
        ]
        let summary = try XCTUnwrap(MacroSummary.make(macrosByDay: macrosByDay, calendar: calendar))

        let bestProtein = try XCTUnwrap(summary.bestDay(for: .protein))
        XCTAssertEqual(bestProtein.grams, 180, accuracy: 0.001)
        XCTAssertEqual(bestProtein.date, day(1))

        // Best carbs is a different day than best protein.
        let bestCarbs = try XCTUnwrap(summary.bestDay(for: .carbs))
        XCTAssertEqual(bestCarbs.date, day(0))

        // Nothing logged for fat, so there is no best fat day to show.
        XCTAssertNil(summary.bestDay(for: .fat))
    }

    func testMacroKindSortIsProteinCarbsFat() {
        XCTAssertEqual(Set(MacroKind.allCases).sorted(), [.protein, .carbs, .fat])
    }
}
