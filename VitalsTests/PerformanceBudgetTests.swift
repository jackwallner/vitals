import SwiftData
import XCTest

/// Worst-case open and scroll paths against three years of dense, every-day
/// data with a long excluded-day pause. Each budget is the best of three runs
/// on the simulator, measured at 1 to 13 ms, rounded up to a 0.1 s floor (the
/// measurement is beside each one), so a loaded machine passes with wide margin
/// and a quadratic regression over 1,095 days does not.
@MainActor
final class PerformanceBudgetTests: XCTestCase {
    private let la: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let dayCount = 3 * 365
    /// Today is 2027-08-20 at 12:00 in Los Angeles; the 1,095 days before it are filled.
    private var now: Date {
        la.date(from: DateComponents(year: 2027, month: 8, day: 20, hour: 12))!
    }

    private typealias Row = (date: Date, active: Double, resting: Double, steps: Int)

    private func fixtureHistory() -> [Row] {
        let today = la.startOfDay(for: now)
        return (0...dayCount).map { index in
            let offset = dayCount - index
            let day = la.date(byAdding: .day, value: -offset, to: today)!
            return (
                date: day,
                active: 300 + Double((index * 37) % 400),
                resting: 1_500 + Double((index * 11) % 200),
                steps: 4_000 + (index * 97) % 9_000
            )
        }
    }

    /// A 400 day pause plus every 9th day picked by hand.
    private func fixtureExcluded() -> (picked: Set<String>, pausedSince: Date) {
        let today = la.startOfDay(for: now)
        let picked = Set((0..<dayCount).filter { $0 % 9 == 0 }.map { offset -> String in
            let day = la.date(byAdding: .day, value: -(offset + 401), to: today)!
            return DailyHealthRecord.key(for: day, timeZone: la.timeZone)
        })
        return (picked, la.date(byAdding: .day, value: -400, to: today)!)
    }

    /// Best of three runs, in seconds, printed so the budget can be re-derived.
    private func best(_ label: String, budget: Double, _ body: () throws -> Void) rethrows {
        var fastest = Double.infinity
        for _ in 0..<3 {
            let start = ContinuousClock.now
            try body()
            let elapsed = start.duration(to: .now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            fastest = min(fastest, seconds)
        }
        print("PERF \(label): \(String(format: "%.1f", fastest * 1_000)) ms (budget \(Int(budget * 1_000)) ms)")
        XCTAssertLessThan(fastest, budget, "\(label) took \(fastest) s")
    }

    func testFixtureBuildsInUnderTwoSeconds() {
        let start = ContinuousClock.now
        let history = fixtureHistory()
        let excluded = fixtureExcluded()
        let elapsed = start.duration(to: .now)
        XCTAssertEqual(history.count, dayCount + 1)
        XCTAssertGreaterThan(excluded.picked.count, 100)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    // 7754d8a5 / b8bd0455 (History slow on a long range): the chart series and
    // every average for three years, with excluded days dimmed.
    func testHistoryChartSeriesForThreeYears() throws {
        let history = fixtureHistory()
        let keys = fixtureExcluded().picked.union(
            ExcludedDays.pausedKeys(since: fixtureExcluded().pausedSince, now: now, calendar: la)
        )
        best("calorie series", budget: 0.1) {  // measured 5.9 ms, floored at 0.1 s
            _ = CalorieTrendSummary.make(history: history, excludedKeys: keys, calendar: la)
        }
        best("step series", budget: 0.1) {  // measured 9.6 ms, floored at 0.1 s
            _ = StepTrendSummary.make(history: history, excludedKeys: keys, calendar: la)
        }
        let food = Dictionary(uniqueKeysWithValues: history.map { ($0.date, 1_800 + Double($0.steps % 500)) })
        best("net deficit series", budget: 0.1) {  // measured 13.1 ms, floored at 0.1 s
            _ = NetDeficitTrendSummary.make(history: history, foodByDate: food, excludedKeys: keys, calendar: la)
        }
    }

    // b8bd0455 (a 60 day pause hung History): the excluded set is asked for once
    // per record while three years of rows scroll in, and must stay cheap.
    func testExcludedSetReadsPerRecordDuringALongPause() {
        let history = fixtureHistory()
        let excluded = fixtureExcluded()
        best("excluded key reads", budget: 0.1) {  // measured 5.3 ms, floored at 0.1 s
            var cache = ExcludedDays.KeyCache()
            var hits = 0
            for row in history {
                let keys = cache.keys(picked: excluded.picked, pausedSince: excluded.pausedSince, now: now, calendar: la)
                if ExcludedDays.contains(row.date, in: keys, timeZone: la.timeZone) { hits += 1 }
            }
            XCTAssertGreaterThan(hits, 400)
        }
    }

    // 057d0dc2 (Maintenance figure): the 30 day TDEE over a cache that holds
    // three years, and the streak and recap walks that open Today.
    func testTodayComputationsOverThreeYearsOfHistory() throws {
        let history = fixtureHistory()
        let keys = fixtureExcluded().picked
        let records = history.map { (date: $0.date, active: $0.active, resting: $0.resting) }
        best("energy averages", budget: 0.1) {  // measured 5.1 ms, floored at 0.1 s
            _ = EnergyAveragesCalculator.compute(records: records, referenceDate: now, excludedKeys: keys, calendar: la)
        }
        let days = history.map { MilestoneDay(date: $0.date, calories: $0.active + $0.resting, steps: $0.steps) }
        best("streak and recap", budget: 0.1) {  // measured 8.4 ms, floored at 0.1 s
            _ = MilestoneCalculator.currentGoalStreak(
                records: days, calorieGoal: 1_000, stepGoal: nil, today: now, calendar: la, excludedKeys: keys
            )
            _ = WeeklyRecapBuilder.build(
                records: days, calorieGoal: 2_000, stepGoal: 8_000, today: now, calendar: la, excludedKeys: keys
            )
        }
        best("pacing", budget: 0.1) {  // measured 10.0 ms, floored at 0.1 s
            let byDay = Dictionary(uniqueKeysWithValues: history.map { ($0.date, $0) })
            _ = PacingCalculator.compute(
                calories: { (byDay[$0].map { $0.active + $0.resting }) ?? 0 },
                steps: { Double(byDay[$0]?.steps ?? 0) },
                comparison: .allDays, lookbackDays: 365, excluded: keys, now: now, calendar: la
            )
        }
    }

    // 7b3ea59 (cache rows): opening History reads the SwiftData cache for three
    // years and fills the window; the widget reads the same rows.
    func testCacheReadAndBackfillForThreeYears() throws {
        let history = fixtureHistory()
        let build = ContinuousClock.now
        let schema = Schema([DailyHealthRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        for row in history {
            context.insert(DailyHealthRecord(date: row.date, activeCalories: row.active, restingCalories: row.resting, steps: row.steps))
        }
        try context.save()
        XCTAssertLessThan(build.duration(to: .now), .seconds(2), "fixture build")

        best("widget cache read", budget: 0.1) {  // measured 0.6 ms, floored at 0.1 s
            let output = EnergyAveragesCacheReader.read(container: container, referenceDate: now, minSamples: 7)
            XCTAssertEqual(output.result.sampleDays, 30)
        }
        let rows: [String: CachedHistoryWindow.Row] = Dictionary(
            uniqueKeysWithValues: history.map { (DailyHealthRecord.key(for: $0.date, timeZone: la.timeZone), $0) }
        )
        best("window backfill", budget: 0.1) {  // measured 3.8 ms, floored at 0.1 s
            let window = CachedHistoryWindow.fill(rows: rows, from: history[0].date, to: history[history.count - 1].date, calendar: la)
            XCTAssertEqual(window.count, history.count)
        }
    }
}
