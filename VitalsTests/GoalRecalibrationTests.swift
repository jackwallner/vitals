import XCTest

final class GoalRecalibrationTests: XCTestCase {
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }

    /// `values[0]` is yesterday, `values[1]` the day before, and so on.
    private func days(_ values: [Double]) -> [(date: Date, value: Double)] {
        values.enumerated().map { offset, value in
            (calendar.date(byAdding: .day, value: -(offset + 1), to: today)!, value)
        }
    }

    private func suggest(
        _ metric: GoalRecalibration.Metric = .steps,
        goal: Double = 10_000,
        values: [Double],
        excluded: Set<String> = [],
        goalSetAt: Date? = nil,
        snoozedUntil: Date? = nil
    ) -> GoalRecalibration.Suggestion? {
        GoalRecalibration.suggestion(
            metric: metric,
            goal: goal,
            days: days(values),
            excludedKeys: excluded,
            goalSetAt: goalSetAt,
            snoozedUntil: snoozedUntil,
            today: .now,
            calendar: calendar
        )
    }

    func testEasyGoalSuggestsTheTypicalDay() throws {
        let suggestion = try XCTUnwrap(suggest(values: Array(repeating: 12_400, count: 14)))
        XCTAssertEqual(suggestion.direction, .raise)
        XCTAssertEqual(suggestion.suggestedGoal, 12_500)
        XCTAssertEqual(suggestion.hits, 14)
    }

    func testBarelyClearedGoalStepsUpTenPercent() throws {
        let suggestion = try XCTUnwrap(suggest(values: Array(repeating: 10_200, count: 14)))
        XCTAssertEqual(suggestion.suggestedGoal, 11_000)
    }

    func testOutOfReachGoalSuggestsLowering() throws {
        let suggestion = try XCTUnwrap(suggest(values: Array(repeating: 6_400, count: 14)))
        XCTAssertEqual(suggestion.direction, .lower)
        XCTAssertEqual(suggestion.suggestedGoal, 6_500)
        XCTAssertEqual(suggestion.hits, 0)
    }

    func testMixedResultsLeaveTheGoalAlone() {
        let values = Array(repeating: 11_000.0, count: 7) + Array(repeating: 8_000.0, count: 7)
        XCTAssertNil(suggest(values: values))
    }

    func testTooFewDaysWithDataIsNoise() {
        // Zero days are missing data, not misses.
        let values = Array(repeating: 12_400.0, count: 9) + Array(repeating: 0.0, count: 5)
        XCTAssertNil(suggest(values: values))
    }

    func testRecentlyChangedGoalGetsAFairRun() {
        let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: .now)
        XCTAssertNil(suggest(values: Array(repeating: 12_400, count: 14), goalSetAt: fiveDaysAgo))
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: .now)
        XCTAssertNotNil(suggest(values: Array(repeating: 12_400, count: 14), goalSetAt: monthAgo))
    }

    func testSnoozeHidesTheSuggestion() {
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: .now)
        XCTAssertNil(suggest(values: Array(repeating: 12_400, count: 14), snoozedUntil: nextWeek))
    }

    func testExcludedDaysDoNotCount() {
        // Ten misses, four of them excluded, leaves six real days: too few.
        let values = Array(repeating: 6_400.0, count: 10)
        let excluded = Set((1...4).map { ExcludedDays.key(for: calendar.date(byAdding: .day, value: -$0, to: today)!) })
        XCTAssertNil(suggest(values: values, excluded: excluded))
    }

    func testCaloriesRoundToFifty() throws {
        let suggestion = try XCTUnwrap(suggest(.calories, goal: 2_000, values: Array(repeating: 2_630, count: 14)))
        XCTAssertEqual(suggestion.suggestedGoal, 2_650)
    }
}
