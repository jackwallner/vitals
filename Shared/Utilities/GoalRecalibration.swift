import Foundation

/// Suggests a new daily goal when the current one has stopped meaning anything:
/// hit almost every day (too easy to notice) or almost never (too hard to try
/// for). Pure, so the thresholds are unit-tested; the dashboard shows the card.
enum GoalRecalibration {
    enum Metric: String, Sendable, CaseIterable {
        case calories
        case steps

        /// Suggestions round to numbers a person would pick themselves.
        var step: Double { self == .calories ? 50 : 500 }
        var validRange: ClosedRange<Double> { self == .calories ? 500...50_000 : 100...500_000 }
    }

    enum Direction: Equatable, Sendable { case raise, lower }

    struct Suggestion: Equatable, Sendable {
        let metric: Metric
        let direction: Direction
        let currentGoal: Double
        let suggestedGoal: Double
        let hits: Int
        let daysWithData: Int
    }

    /// Completed days looked at.
    static let windowDays = 14
    /// Fewer real days than this and a hit rate is noise.
    static let minDaysWithData = 10
    static let raiseHitRate = 0.85
    static let lowerHitRate = 0.2
    /// A goal changed this recently gets a fair run before we second-guess it.
    static let settleDays = 14
    /// "Keep" hides the card for this long.
    static let snoozeDays = 30

    /// - Parameters:
    ///   - days: daily totals for this metric, any order, any span. Today and
    ///     excluded days are ignored, as are zero days (no data, not a miss).
    ///   - goalSetAt: when the goal last changed; nil means long enough ago.
    static func suggestion(
        metric: Metric,
        goal: Double?,
        days: [(date: Date, value: Double)],
        excludedKeys: Set<String> = [],
        goalSetAt: Date?,
        snoozedUntil: Date?,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Suggestion? {
        guard let goal, goal > 0 else { return nil }
        if let snoozedUntil, snoozedUntil > today { return nil }
        if let goalSetAt,
           let settled = calendar.date(byAdding: .day, value: settleDays, to: goalSetAt),
           settled > today {
            return nil
        }

        let todayStart = calendar.startOfDay(for: today)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: todayStart) else { return nil }
        let values = days
            .filter { $0.date >= windowStart && $0.date < todayStart }
            .filter { !ExcludedDays.contains($0.date, in: excludedKeys, timeZone: calendar.timeZone) }
            .map(\.value)
            .filter { $0 > 0 }
        guard values.count >= minDaysWithData else { return nil }

        let hits = values.filter { $0 >= goal }.count
        let rate = Double(hits) / Double(values.count)
        let typical = median(values)

        if rate >= raiseHitRate {
            // The typical day, unless that's barely above the goal; then a 10% step.
            let target = typical > goal * 1.05 ? typical : goal * 1.1
            let suggested = rounded(target, metric: metric)
            guard suggested > goal else { return nil }
            return Suggestion(metric: metric, direction: .raise, currentGoal: goal, suggestedGoal: suggested, hits: hits, daysWithData: values.count)
        }
        if rate <= lowerHitRate {
            let suggested = rounded(typical, metric: metric)
            guard suggested < goal * 0.95 else { return nil }
            return Suggestion(metric: metric, direction: .lower, currentGoal: goal, suggestedGoal: suggested, hits: hits, daysWithData: values.count)
        }
        return nil
    }

    static func rounded(_ value: Double, metric: Metric) -> Double {
        let snapped = (value / metric.step).rounded() * metric.step
        return min(max(snapped, metric.validRange.lowerBound), metric.validRange.upperBound)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
