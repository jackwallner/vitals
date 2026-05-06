import XCTest

final class CalorieTrendSummaryTests: XCTestCase {
    func testWeeklyAndMonthlyAveragesExcludeToday() throws {
        let calendar = Calendar(identifier: .gregorian)
        let end = calendar.startOfDay(for: Date.now)
        // 60 days ending today; today (index 59) is excluded from averages.
        let history = makeHistory(days: 60, ending: end, calendar: calendar) { index in
            if index >= 53 { return (active: 700.0, resting: 1_700.0) }
            if index >= 30 { return (active: 600.0, resting: 1_600.0) }
            return (active: 500.0, resting: 1_500.0)
        }

        let summary = try XCTUnwrap(CalorieTrendSummary.make(history: history, calendar: calendar))

        XCTAssertEqual(summary.points.count, 30)

        // Weekly: Apr 19-25 (7 days, today Apr 26 excluded)
        //   Apr 19 (index 52) = 2200; Apr 20-25 (indices 53-58) = 2400
        //   Average = (2200 + 6 * 2400) / 7 = 2371.4286
        XCTAssertEqual(try XCTUnwrap(summary.weekly.average), 2_371.4286, accuracy: 0.001)
        XCTAssertEqual(summary.weekly.sampleDays, 7)
        XCTAssertEqual(summary.weekly.expectedDays, 7)
        // Previous week: Apr 12-18 (indices 45-51) = all 2200
        //   Change = (2371.4286 - 2200) / 2200 * 100 = 7.7922%
        XCTAssertEqual(try XCTUnwrap(summary.weekly.percentChange), 7.7922, accuracy: 0.001)

        // Monthly: Mar 27-Apr 25 (30 days, today excluded)
        //   Mar 27 (index 29) = 2000; Mar 28-Apr 19 (indices 30-52) = 23 days of 2200; Apr 20-25 (indices 53-58) = 6 days of 2400
        //   Average = (2000 + 23 * 2200 + 6 * 2400) / 30 = 2233.3333
        XCTAssertEqual(try XCTUnwrap(summary.monthly.average), 2_233.3333, accuracy: 0.001)
        XCTAssertEqual(summary.monthly.sampleDays, 30)
        XCTAssertEqual(summary.monthly.expectedDays, 30)
        // Previous month: Feb 26-Mar 26 (29 available days, all 2000)
        //   Change = (2233.3333 - 2000) / 2000 * 100 = 11.6667%
        XCTAssertEqual(try XCTUnwrap(summary.monthly.percentChange), 11.6667, accuracy: 0.001)
    }

    func testZeroAndNegativeDaysAreExcludedFromAverages() throws {
        let calendar = Calendar(identifier: .gregorian)
        let end = calendar.startOfDay(for: Date.now)
        // 14 days ending today; today (index 13) excluded from averages.
        let history = makeHistory(days: 14, ending: end, calendar: calendar) { index in
            switch index {
            case 7, 8, 9:
                return (active: 500.0, resting: 1_500.0)
            case 10, 11:
                return (active: 0, resting: 0)
            case 12:
                return (active: -100, resting: 0)
            case 13:
                return (active: 1_000.0, resting: 1_500.0)
            default:
                return (active: 0, resting: 0)
            }
        }

        let summary = try XCTUnwrap(CalorieTrendSummary.make(history: history, calendar: calendar))

        // referenceDate = Apr 22 (index 9), the last completed day with data.
        // Weekly: Apr 16-22; zero days excluded, only Apr 20-22 have data (3 days, 2000 each).
        XCTAssertEqual(try XCTUnwrap(summary.weekly.average), 2_000, accuracy: 0.001)
        XCTAssertEqual(summary.weekly.sampleDays, 3)
        XCTAssertEqual(summary.weekly.expectedDays, 7)
        // Previous week (Apr 9-15) has no data in the 14-day window.
        XCTAssertNil(summary.weekly.percentChange)
    }

    func testEmptyHistoryReturnsNil() {
        XCTAssertNil(CalorieTrendSummary.make(history: [], calendar: Calendar(identifier: .gregorian)))
    }

    private func makeHistory(
        days: Int,
        ending end: Date,
        calendar: Calendar,
        values: (Int) -> (active: Double, resting: Double)
    ) -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        (0..<days).compactMap { index in
            let reverseIndex = days - index - 1
            guard let date = calendar.date(byAdding: .day, value: -reverseIndex, to: end) else { return nil }
            let value = values(index)
            return (date: date, active: value.active, resting: value.resting, steps: 0)
        }
    }
}
