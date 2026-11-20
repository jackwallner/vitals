import XCTest

/// Regression tests for the 2026-11-20 bug catalog fixes.
@MainActor
final class BugCatalogFixTests: XCTestCase {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    // MARK: - B2: averages count finished days with data

    private struct Day {
        let date: Date
        let kcal: Double
    }

    func testAverageSkipsAPartialTodayAndDaysWithNoReading() throws {
        let cal = calendar("America/New_York")
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 7)))
        let today = cal.startOfDay(for: now)
        var days: [Day] = try (1...6).map { offset in
            Day(date: try XCTUnwrap(cal.date(byAdding: .day, value: -offset, to: today)), kcal: offset <= 2 ? 0 : 2_400)
        }
        days.append(Day(date: today, kcal: 500))
        let average = DailyAverage.mean(days, value: \.kcal, date: \.date, now: now, calendar: cal)
        XCTAssertEqual(average, 2_400, accuracy: 0.001)
    }

    func testAverageFallsBackToTodayOnAFreshInstall() {
        let now = Date()
        let average = DailyAverage.mean([Day(date: now, kcal: 900)], value: \.kcal, date: \.date, now: now)
        XCTAssertEqual(average, 900, accuracy: 0.001)
    }

    func testReportAveragesMatchHistory() throws {
        let cal = calendar("America/New_York")
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 7)))
        let today = cal.startOfDay(for: now)
        var days: [ReportDay] = try (1...6).map { offset in
            let date = try XCTUnwrap(cal.date(byAdding: .day, value: -offset, to: today))
            return offset == 1
                ? ReportDay(date: date, activeCalories: 0, restingCalories: 0, steps: 0, foodCalories: nil)
                : ReportDay(date: date, activeCalories: 400, restingCalories: 2_000, steps: 10_000, foodCalories: nil)
        }
        days.append(ReportDay(date: today, activeCalories: 50, restingCalories: 450, steps: 800, foodCalories: nil))
        let report = SummaryReportGenerator.make(
            title: "Test", periodStart: today, periodEnd: today, days: days,
            calorieGoal: nil, stepGoal: nil, now: now, calendar: cal
        )
        XCTAssertEqual(report.avgCalories, 2_400, accuracy: 0.001)
        XCTAssertEqual(report.avgActive, 400, accuracy: 0.001)
        XCTAssertEqual(report.avgResting, 2_000, accuracy: 0.001)
        XCTAssertEqual(report.avgSteps, 10_000)
    }

    // MARK: - B5: rows cached before a westward move keep their day

    /// Ten goal days written in New York, read in Los Angeles the way
    /// `fetchCachedHistory` reads them.
    private func cachedWindowAfterMovingWest() throws -> (window: [CachedHistoryWindow.Row], la: Calendar, now: Date) {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let newYork = calendar("America/New_York")
        NSTimeZone.default = newYork.timeZone
        let nyToday = newYork.startOfDay(for: try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))))
        let records = try (1...10).map { offset in
            DailyHealthRecord(
                date: try XCTUnwrap(newYork.date(byAdding: .day, value: -offset, to: nyToday)),
                activeCalories: 500, restingCalories: 2_000, steps: 12_000
            )
        }

        let la = calendar("America/Los_Angeles")
        NSTimeZone.default = la.timeZone
        let now = try XCTUnwrap(la.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9)))
        let rows = Dictionary(uniqueKeysWithValues: records.map {
            ($0.dateString, (date: $0.localDay, active: $0.activeCalories, resting: $0.restingCalories, steps: $0.steps))
        })
        let start = try XCTUnwrap(la.date(byAdding: .day, value: -29, to: la.startOfDay(for: now)))
        return (CachedHistoryWindow.fill(rows: rows, from: start, to: now, calendar: la), la, now)
    }

    func testStreakSurvivesAWestwardTimeZoneMove() throws {
        let (window, la, now) = try cachedWindowAfterMovingWest()
        let days = window.map { MilestoneDay(date: $0.date, calories: $0.active + $0.resting, steps: $0.steps) }
        let streak = MilestoneCalculator.currentStreak(records: days, today: now, calendar: la) { $0.calories >= 2_000 }
        XCTAssertEqual(streak, 10)
    }

    func testCachedRowKeepsItsDayAfterAWestwardMove() throws {
        let (window, la, _) = try cachedWindowAfterMovingWest()
        let yesterday = try XCTUnwrap(window.dropLast().last)
        XCTAssertEqual(DailyHealthRecord.key(for: yesterday.date, timeZone: la.timeZone), "2026-11-19")
        XCTAssertEqual(yesterday.steps, 12_000)
    }

    func testExcludedDayStaysOutOfCachedAveragesAfterAWestwardMove() throws {
        let (window, la, now) = try cachedWindowAfterMovingWest()
        let records = window.map { (date: $0.date, active: $0.active, resting: $0.resting) }
        let all = EnergyAveragesCalculator.compute(records: records, referenceDate: now, minSamples: 1, calendar: la)
        let excluded = EnergyAveragesCalculator.compute(
            records: records, referenceDate: now, minSamples: 1, excludedKeys: ["2026-11-15"], calendar: la
        )
        XCTAssertEqual(all.sampleDays, 10)
        XCTAssertEqual(excluded.sampleDays, 9)
    }

    func testFillPutsAStaleRowOnTheWindowDay() throws {
        let la = calendar("America/Los_Angeles")
        let newYork = calendar("America/New_York")
        let nyMidnight = newYork.startOfDay(for: try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))))
        let laDay = la.startOfDay(for: try XCTUnwrap(la.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))))
        let window = CachedHistoryWindow.fill(
            rows: ["2026-11-19": (date: nyMidnight, active: 1, resting: 2, steps: 3)],
            from: laDay, to: laDay, calendar: la
        )
        XCTAssertEqual(window.first?.date, laDay)
        XCTAssertEqual(window.first?.steps, 3)
    }

    // MARK: - B7: digits typed on an Arabic or Persian number pad

    func testArabicIndicAndPersianDigitsParse() {
        XCTAssertEqual(TypedNumber.double("٢٥٠٠"), 2_500)
        XCTAssertEqual(TypedNumber.int("١٠٠٠٠"), 10_000)
        XCTAssertEqual(TypedNumber.double("۲۵۰۰"), 2_500)
        XCTAssertEqual(TypedNumber.int(" 2500 "), 2_500)
        XCTAssertNil(TypedNumber.int("abc"))
        XCTAssertEqual(BodyProfileCalculator.parseDecimal("٧٠"), 70)
        XCTAssertEqual(BodyProfileCalculator.parseDecimal("٧٠٫٥"), 70.5)
        XCTAssertEqual(BodyProfileCalculator.parseDecimal("۷۰"), 70)
        XCTAssertEqual(BodyProfileCalculator.parseDecimal("70.5"), 70.5)
    }
}
