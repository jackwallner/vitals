import XCTest

final class CalorieTrendSummaryTests: XCTestCase {
    func testWeeklyAndMonthlyAveragesUseRecentNonZeroDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 26)))
        let history = makeHistory(days: 60, ending: end, calendar: calendar) { index in
            if index >= 53 { return (active: 700.0, resting: 1_700.0) }
            if index >= 30 { return (active: 600.0, resting: 1_600.0) }
            return (active: 500.0, resting: 1_500.0)
        }

        let summary = try XCTUnwrap(CalorieTrendSummary.make(history: history, calendar: calendar))

        XCTAssertEqual(summary.points.count, 30)
        XCTAssertEqual(try XCTUnwrap(summary.weekly.average), 2_400, accuracy: 0.001)
        XCTAssertEqual(summary.weekly.sampleDays, 7)
        XCTAssertEqual(try XCTUnwrap(summary.weekly.percentChange), 9.0909, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.monthly.average), 2_246.6667, accuracy: 0.001)
        XCTAssertEqual(summary.monthly.sampleDays, 30)
        XCTAssertEqual(try XCTUnwrap(summary.monthly.percentChange), 12.3333, accuracy: 0.001)
    }

    func testZeroAndNegativeDaysAreExcludedFromAverages() throws {
        let calendar = Calendar(identifier: .gregorian)
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 26)))
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

        XCTAssertEqual(try XCTUnwrap(summary.weekly.average), 2_125, accuracy: 0.001)
        XCTAssertEqual(summary.weekly.sampleDays, 4)
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
