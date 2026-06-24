import Foundation

/// Pure logic for detecting "you've earned it" moments worth celebrating. Used
/// by the iOS app to surface a milestone sheet that doubles as a Vitals+ pitch.
/// Decoupled from HealthKit / SwiftData so unit tests can drive it directly.

/// Compact per-day metric tuple used for milestone math. Mirrors the shape of
/// `DailyHealthRecord` and `HealthKitService.fetchHistory` rows.
struct MilestoneDay: Sendable {
    let date: Date
    let calories: Double
    let steps: Int

    init(date: Date, calories: Double, steps: Int) {
        self.date = date
        self.calories = calories
        self.steps = steps
    }
}

enum MilestoneEvent: Equatable, Sendable {
    /// User has a current goal streak of N consecutive completed days. `n` is
    /// the celebrated milestone value (7, 14, 30, …), not necessarily the
    /// exact current streak — the caller may pick the largest unfired tier the
    /// user has reached or passed.
    case goalStreak(n: Int)

    /// Prior calendar month had enough data to be worth reviewing. `month` is
    /// "YYYY-MM" so the milestone id is naturally one-shot per month.
    case monthReview(month: String, daysWithData: Int)

    /// Stable id used for persistence — once an id has fired we don't re-fire.
    var id: String {
        switch self {
        case .goalStreak(let n): return "streak_\(n)"
        case .monthReview(let month, _): return "month_\(month)"
        }
    }
}

enum MilestoneCalculator {
    /// Streak tiers worth celebrating. Each fires at most once per user; spacing
    /// is wide enough that consecutive celebrations don't feel piled-on.
    static let celebratedStreaks: [Int] = [7, 14, 30, 60, 100]

    /// Counts consecutive days ending at "yesterday" satisfying `hit`. Today is
    /// excluded — it may still be in progress, so awarding a streak based on
    /// partial data would be premature. Days with no record (HK gap) break the
    /// streak. The building block for both the combined goal streak (below) and
    /// the per-metric streaks the Today view shows.
    static func currentStreak(
        records: [MilestoneDay],
        today: Date = .now,
        calendar: Calendar = .current,
        hit: (MilestoneDay) -> Bool
    ) -> Int {
        // Collapse rather than trap if two records land on the same day (timezone/DST
        // re-bucketing or a cross-process duplicate cache row); last write wins.
        let byDay: [Date: MilestoneDay] = Dictionary(
            records.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { _, rhs in rhs }
        )
        guard var cursor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today)) else {
            return 0
        }
        var streak = 0
        while let day = byDay[cursor], hit(day) {
            streak += 1
            guard let next = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = next
        }
        return streak
    }

    /// Combined streak: consecutive days where the user hit *either* goal. Drives
    /// the (non-Pro) celebration upsell — deliberately the broadest "on a roll"
    /// signal. Per-metric streaks for inline display use `currentStreak` directly.
    static func currentGoalStreak(
        records: [MilestoneDay],
        calorieGoal: Double?,
        stepGoal: Int?,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard calorieGoal != nil || stepGoal != nil else { return 0 }
        return currentStreak(records: records, today: today, calendar: calendar) { day in
            let hitCal = calorieGoal.map { day.calories >= $0 } ?? false
            let hitStep = stepGoal.map { day.steps >= $0 } ?? false
            return hitCal || hitStep
        }
    }

    /// Returns the largest celebrated streak tier the user has reached or
    /// passed that hasn't already fired. nil = nothing to celebrate.
    static func unfiredStreakMilestone(
        currentStreak: Int,
        firedIds: Set<String>
    ) -> MilestoneEvent? {
        let candidate = celebratedStreaks
            .filter { $0 <= currentStreak && !firedIds.contains("streak_\($0)") }
            .max()
        return candidate.map { .goalStreak(n: $0) }
    }

    /// "Reviewable" = today is day 1-3 of a new calendar month and the prior
    /// month accumulated enough data (≥20 days with any non-zero metric) to
    /// be worth pitching a recap. The early-month window keeps the prompt
    /// relevant — a recap pitched mid-month feels stale.
    static func reviewableLastMonth(
        records: [MilestoneDay],
        today: Date = .now,
        calendar: Calendar = .current,
        minDaysWithData: Int = 20
    ) -> MilestoneEvent? {
        let dayOfMonth = calendar.component(.day, from: today)
        guard dayOfMonth <= 3 else { return nil }
        guard let priorMonthDate = calendar.date(byAdding: .month, value: -1, to: today) else {
            return nil
        }
        let comps = calendar.dateComponents([.year, .month], from: priorMonthDate)
        guard let monthStart = calendar.date(from: comps),
              let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else { return nil }
        let daysWithData = records.reduce(into: 0) { acc, rec in
            guard rec.date >= monthStart, rec.date < nextMonthStart else { return }
            if rec.calories > 0 || rec.steps > 0 { acc += 1 }
        }
        guard daysWithData >= minDaysWithData else { return nil }
        let monthKey = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        return .monthReview(month: monthKey, daysWithData: daysWithData)
    }
}
