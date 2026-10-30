import XCTest

/// Overnight report F03: the report's trend compares like with like, so
/// identical windows read as no change.
@MainActor
final class SummaryReportTrendTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func window(endingDaysAgo end: Int, count: Int, from now: Date) -> [ReportDay] {
        (0..<count).map { index in
            let date = calendar.date(byAdding: .day, value: -(end + index), to: calendar.startOfDay(for: now))!
            return ReportDay(date: date, activeCalories: 500, restingCalories: 2_000, steps: 10_000, foodCalories: nil)
        }
    }

    private func report(days: [ReportDay], previous: [ReportDay], now: Date) -> SummaryReport {
        SummaryReportGenerator.make(
            title: "Test", periodStart: now, periodEnd: now, days: days, previousDays: previous,
            calorieGoal: nil, stepGoal: nil, now: now, calendar: calendar
        )
    }

    func testFlatHistoryWithAPartialTodayReadsAsNoChange() throws {
        let now = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        var current = window(endingDaysAgo: 1, count: 29, from: now)
        current.append(ReportDay(date: calendar.startOfDay(for: now), activeCalories: 50, restingCalories: 600, steps: 1_000, foodCalories: nil))
        let result = report(days: current, previous: window(endingDaysAgo: 30, count: 30, from: now), now: now)
        XCTAssertEqual(try XCTUnwrap(result.calorieTrendPct), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.stepTrendPct), 0, accuracy: 0.001)
    }

    func testIdenticalWindowsWithAnEmptyDayEachReadAsNoChange() throws {
        let now = Date()
        func emptyFirst(_ days: [ReportDay]) -> [ReportDay] {
            var days = days
            days[0] = ReportDay(date: days[0].date, activeCalories: 0, restingCalories: 0, steps: 0, foodCalories: nil)
            return days
        }
        let result = report(
            days: emptyFirst(window(endingDaysAgo: 1, count: 30, from: now)),
            previous: emptyFirst(window(endingDaysAgo: 31, count: 30, from: now)),
            now: now
        )
        XCTAssertEqual(try XCTUnwrap(result.calorieTrendPct), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.stepTrendPct), 0, accuracy: 0.001)
    }
}
