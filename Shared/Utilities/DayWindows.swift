import Foundation

/// Pure day-boundary math pulled out of `HealthKitService` so it can be driven
/// with a fixed clock and an explicit calendar. Every default reproduces what
/// the service did inline before.

/// Which past days feed the "usual by this time of day" pacing figures, and how
/// much of a day has gone by.
enum PacingCalculator {
    /// Before this local hour the day is too young for a meaningful comparison.
    static let earliestHour = 6

    struct Window: Equatable {
        let today: Date
        let windowStart: Date
    }

    /// The HealthKit window to read, or `nil` while it is too early in the day.
    static func window(now: Date, lookbackDays: Int, calendar: Calendar = .current) -> Window? {
        guard calendar.component(.hour, from: now) >= earliestHour else { return nil }
        guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else { return nil }
        return Window(today: calendar.startOfDay(for: now), windowStart: calendar.startOfDay(for: start))
    }

    /// Share of today's calendar day that has elapsed. Divides by the real length
    /// of the day (23 or 25 hours across a DST change), never by 86,400.
    static func dayFraction(now: Date, calendar: Calendar = .current) -> Double {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        return min(now.timeIntervalSince(today) / end.timeIntervalSince(today), 1.0)
    }

    static func compute(
        calories: (Date) -> Double,
        steps: (Date) -> Double,
        comparison: PacingComparison,
        lookbackDays: Int,
        excluded: Set<String>,
        now: Date,
        calendar: Calendar = .current
    ) -> PacingResult {
        let today = calendar.startOfDay(for: now)
        let targetWeekday = calendar.component(.weekday, from: now)
        let fraction = dayFraction(now: now, calendar: calendar)

        var calorieWeighted = 0.0
        var stepWeighted = 0.0
        var calorieFullDay = 0.0
        var stepFullDay = 0.0
        var calorieSampleDays = 0
        var stepSampleDays = 0

        for dayOffset in 1...lookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            if comparison == .dayOfWeek, calendar.component(.weekday, from: dayStart) != targetWeekday {
                continue
            }
            // A day the user excluded is not a sample of their usual day.
            if ExcludedDays.contains(dayStart, in: excluded, timeZone: calendar.timeZone) { continue }

            let dayCal = calories(dayStart)
            let daySteps = steps(dayStart)
            if dayCal > 0 {
                calorieSampleDays += 1
                calorieWeighted += dayCal * fraction
                calorieFullDay += dayCal
            }
            if daySteps > 0 {
                stepSampleDays += 1
                stepWeighted += daySteps * fraction
                stepFullDay += daySteps
            }
        }

        return PacingResult(
            avgCalories: calorieSampleDays > 0 ? calorieWeighted / Double(calorieSampleDays) : nil,
            avgSteps: stepSampleDays > 0 ? Int(stepWeighted / Double(stepSampleDays)) : nil,
            calorieSampleDays: calorieSampleDays,
            stepSampleDays: stepSampleDays,
            avgCaloriesFullDay: calorieSampleDays > 0 ? calorieFullDay / Double(calorieSampleDays) : nil,
            avgStepsFullDay: stepSampleDays > 0 ? Int(stepFullDay / Double(stepSampleDays)) : nil
        )
    }
}

/// What a launch or background wake does about the local day having changed.
enum DayRollover {
    enum Action: Equatable {
        case none
        /// First run ever: nothing stale to finalize, just record where we are.
        case recordOnly
        /// The cached day is behind: finalize the completed days, then record.
        case finalize
    }

    static func action(previousKey: String?, todayKey: String) -> Action {
        guard previousKey != todayKey else { return .none }
        return previousKey == nil ? .recordOnly : .finalize
    }
}

/// Contiguous per-day rows for a cached window, with zeroes for days the cache
/// has no row for.
enum CachedHistoryWindow {
    typealias Row = (date: Date, active: Double, resting: Double, steps: Int)

    static func fill(
        rows: [String: Row],
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [Row] {
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        var results: [Row] = []
        var current = normalizedStart
        while current <= normalizedEnd {
            let key = DailyHealthRecord.key(for: current, timeZone: calendar.timeZone)
            results.append(rows[key] ?? (date: current, active: 0, resting: 0, steps: 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return results
    }
}

// MARK: - Pacing types

/// How to aggregate historical days when computing “usual” progress at this time of day.
enum PacingComparison: Int, CaseIterable, Sendable {
    /// Average only past days that match today’s weekday (e.g. compare Mondays to Mondays).
    case dayOfWeek = 0
    /// Average every day in the lookback window (subject to non-empty samples).
    case allDays = 1

    var label: String {
        switch self {
        case .dayOfWeek: String(localized: "Same weekday")
        case .allDays: String(localized: "All days")
        }
    }
}

/// How far back to look for pacing samples (completed days before today; empty days excluded per metric).
enum PacingLookback: Int, CaseIterable, Sendable {
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90
    case oneYear = 365

    static let `default` = PacingLookback.thirtyDays

    var label: String {
        switch self {
        case .fourteenDays: String(localized: "14 days")
        case .thirtyDays: String(localized: "30 days")
        case .ninetyDays: String(localized: "90 days")
        case .oneYear: String(localized: "1 year")
        }
    }
}

/// Effective minimum number of sample days required before pacing rendering is allowed.
/// Must match the logic in `DashboardView.refresh()` so the Settings footer reports the
/// same threshold the dashboard actually enforces.
///
/// For `.dayOfWeek`: `lookback / 7` is the maximum number of matching weekdays within
/// the window, capped at 4 so "1 Year × Same Weekday" isn't blocked by a 52-day
/// requirement. For `.allDays`: fixed at 3.
func effectiveMinPacingSamples(for comparison: PacingComparison, lookback: PacingLookback) -> Int {
    switch comparison {
    case .dayOfWeek:
        let raw = max(lookback.rawValue / 7, 1)
        return min(raw, 3)
    case .allDays:
        return 3
    }
}

/// Usual calories/steps by this time of day; sample counts exclude empty days per metric.
struct PacingResult: Sendable {
    let avgCalories: Double?
    let avgSteps: Int?
    let calorieSampleDays: Int
    let stepSampleDays: Int
    /// Usual *full-day* totals over the same sample set (no time-of-day weighting).
    /// Drives the Vitals+ end-of-day projection: expected remaining = full − now.
    /// nil when there aren't enough samples, exactly like the time-weighted averages.
    let avgCaloriesFullDay: Double?
    let avgStepsFullDay: Int?

    init(
        avgCalories: Double?,
        avgSteps: Int?,
        calorieSampleDays: Int,
        stepSampleDays: Int,
        avgCaloriesFullDay: Double? = nil,
        avgStepsFullDay: Int? = nil
    ) {
        self.avgCalories = avgCalories
        self.avgSteps = avgSteps
        self.calorieSampleDays = calorieSampleDays
        self.stepSampleDays = stepSampleDays
        self.avgCaloriesFullDay = avgCaloriesFullDay
        self.avgStepsFullDay = avgStepsFullDay
    }

    /// Resolves optional dashboard values: needs enough non-empty sample days per visible metric.
    func dashboardValues(minSamples: Int = 3, showCalories: Bool, showSteps: Bool) -> (
        calories: Double?,
        caloriesBuilding: Bool,
        steps: Int?,
        stepsBuilding: Bool
    ) {
        let calories: Double?
        let caloriesBuilding: Bool
        if showCalories {
            if let avg = avgCalories, calorieSampleDays >= minSamples, avg > 0 {
                calories = avg
                caloriesBuilding = false
            } else {
                calories = nil
                caloriesBuilding = calorieSampleDays > 0 && calorieSampleDays < minSamples
            }
        } else {
            calories = nil
            caloriesBuilding = false
        }

        let steps: Int?
        let stepsBuilding: Bool
        if showSteps {
            if let avg = avgSteps, stepSampleDays >= minSamples, avg > 0 {
                steps = avg
                stepsBuilding = false
            } else {
                steps = nil
                stepsBuilding = stepSampleDays > 0 && stepSampleDays < minSamples
            }
        } else {
            steps = nil
            stepsBuilding = false
        }

        return (calories, caloriesBuilding, steps, stepsBuilding)
    }
}
