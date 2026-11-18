import XCTest

final class JanuaryChallengeTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return cal
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func records(_ days: ClosedRange<Int>, missed: Set<Int> = []) -> [MilestoneDay] {
        days.map {
            MilestoneDay(date: day(2027, 1, $0, hour: 0), calories: missed.contains($0) ? 1500 : 2400, steps: 4000)
        }
    }

    private func snapshot(now: Date, _ records: [MilestoneDay], calories: Double? = 2200, steps: Int? = 10_000) -> JanuaryChallenge.Snapshot {
        JanuaryChallenge.snapshot(now: now, records: records, calorieGoal: calories, stepGoal: steps, calendar: calendar)
    }

    func testMonthIsThirtyOneLocalMidnights() {
        let days = JanuaryChallenge.days(calendar: calendar)
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(days.first, day(2027, 1, 1, hour: 0))
        XCTAssertEqual(days.last, day(2027, 1, 31, hour: 0))
    }

    func testBeforeJanuaryNothingCounts() {
        let result = snapshot(now: day(2026, 12, 20), [])
        XCTAssertFalse(result.hasStarted)
        XCTAssertEqual(result.goalDays, 0)
        XCTAssertTrue(result.days.allSatisfy { $0.mark == .ahead })
    }

    func testCountsDaysWhereEitherGoalWasReached() {
        let result = snapshot(now: day(2027, 1, 12), records(1...12, missed: [4, 12]))
        XCTAssertTrue(result.hasStarted)
        XCTAssertEqual(result.goalDays, 10)
        XCTAssertEqual(result.days[3].mark, .open)
        XCTAssertEqual(result.days[11].mark, .open)
        XCTAssertTrue(result.days[11].isToday)
        XCTAssertEqual(result.days[12].mark, .ahead)
    }

    func testAStepGoalAloneCounts() {
        let walked = [MilestoneDay(date: day(2027, 1, 1, hour: 0), calories: 1500, steps: 12_000)]
        XCTAssertEqual(snapshot(now: day(2027, 1, 2), walked).goalDays, 1)
    }

    func testNoGoalsMeansNoGoalDays() {
        XCTAssertEqual(snapshot(now: day(2027, 1, 12), records(1...11), calories: nil, steps: nil).goalDays, 0)
    }

    func testCompleteOnlyWithAllThirtyOne() {
        XCTAssertTrue(snapshot(now: day(2027, 2, 1), records(1...31)).isComplete)
        XCTAssertFalse(snapshot(now: day(2027, 2, 1), records(1...31, missed: [20])).isComplete)
    }

    func testRowShowsFromTwoWeeksBeforeToAWeekAfter() {
        XCTAssertFalse(JanuaryChallenge.showsRow(now: day(2026, 12, 17), calendar: calendar))
        XCTAssertTrue(JanuaryChallenge.showsRow(now: day(2026, 12, 18), calendar: calendar))
        XCTAssertTrue(JanuaryChallenge.showsRow(now: day(2027, 2, 7), calendar: calendar))
        XCTAssertFalse(JanuaryChallenge.showsRow(now: day(2027, 2, 8), calendar: calendar))
        XCTAssertTrue(JanuaryChallenge.acceptsLink(now: day(2026, 11, 20), calendar: calendar))
        XCTAssertFalse(JanuaryChallenge.acceptsLink(now: day(2027, 2, 8), calendar: calendar))
    }
}
