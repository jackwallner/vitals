import XCTest

final class WeeklyRecapBuilderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    /// Builds a record `offset` days before `today` (offset 1 = yesterday).
    private func day(offset: Int, calories: Double, steps: Int, today: Date) -> MilestoneDay {
        let start = calendar.startOfDay(for: today)
        let date = calendar.date(byAdding: .day, value: -offset, to: start)!
        return MilestoneDay(date: date, calories: calories, steps: steps)
    }

    private func fixedToday() throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 15)))
    }

    func testTotalsAveragesAndGoalDays() throws {
        let today = try fixedToday()
        // This week (offsets 1...7): 2000 cal / 10k steps. Prior (8...14): 1800 cal / 9k steps.
        var records: [MilestoneDay] = []
        for offset in 1...7 { records.append(day(offset: offset, calories: 2_000, steps: 10_000, today: today)) }
        for offset in 8...14 { records.append(day(offset: offset, calories: 1_800, steps: 9_000, today: today)) }

        let recap = try XCTUnwrap(WeeklyRecapBuilder.build(
            records: records, calorieGoal: 1_900, stepGoal: nil, today: today, calendar: calendar
        ))

        XCTAssertEqual(recap.daysWithData, 7)
        XCTAssertEqual(recap.totalCalories, 14_000, accuracy: 0.0001)
        XCTAssertEqual(recap.avgCalories, 2_000, accuracy: 0.0001)
        XCTAssertEqual(recap.avgSteps, 10_000)
        XCTAssertEqual(recap.goalDaysHit, 7)
        XCTAssertEqual(recap.goalDaysPossible, 7)
        // (2000 − 1800) / 1800 * 100 = 11.111%
        XCTAssertEqual(try XCTUnwrap(recap.calorieChangePct), 11.1111, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(recap.stepChangePct), 11.1111, accuracy: 0.001)
    }

    func testTodayIsExcluded() throws {
        let today = try fixedToday()
        // A huge "today" (offset 0) must not leak into the window.
        var records = [day(offset: 0, calories: 99_999, steps: 99_999, today: today)]
        for offset in 1...7 { records.append(day(offset: offset, calories: 2_000, steps: 10_000, today: today)) }

        let recap = try XCTUnwrap(WeeklyRecapBuilder.build(
            records: records, calorieGoal: nil, stepGoal: nil, today: today, calendar: calendar
        ))
        XCTAssertEqual(recap.daysWithData, 7)
        XCTAssertEqual(recap.avgCalories, 2_000, accuracy: 0.0001)
        XCTAssertNil(recap.goalDaysHit)
    }

    func testNilWhenNoDataThisWeek() throws {
        let today = try fixedToday()
        // Only prior-week data — current 7-day window is empty.
        let records = (8...14).map { day(offset: $0, calories: 1_800, steps: 9_000, today: today) }
        XCTAssertNil(WeeklyRecapBuilder.build(
            records: records, calorieGoal: nil, stepGoal: nil, today: today, calendar: calendar
        ))
    }

    func testChangePctNilWithoutPriorWeek() throws {
        let today = try fixedToday()
        let records = (1...7).map { day(offset: $0, calories: 2_000, steps: 10_000, today: today) }
        let recap = try XCTUnwrap(WeeklyRecapBuilder.build(
            records: records, calorieGoal: nil, stepGoal: nil, today: today, calendar: calendar
        ))
        XCTAssertNil(recap.calorieChangePct)
        XCTAssertNil(recap.stepChangePct)
    }

    func testBestDayPicksHighestCalories() throws {
        let today = try fixedToday()
        var records = (1...7).map { day(offset: $0, calories: 1_500, steps: 8_000, today: today) }
        // Offset 3 is the standout day.
        records[2] = day(offset: 3, calories: 3_200, steps: 12_000, today: today)

        let recap = try XCTUnwrap(WeeklyRecapBuilder.build(
            records: records, calorieGoal: nil, stepGoal: nil, today: today, calendar: calendar
        ))
        XCTAssertEqual(try XCTUnwrap(recap.bestCalorieValue), 3_200, accuracy: 0.0001)
        let expectedBest = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: today))!
        XCTAssertEqual(recap.bestCalorieDay, expectedBest)
    }
}
