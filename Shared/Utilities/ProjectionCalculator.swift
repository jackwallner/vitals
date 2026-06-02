import Foundation

/// Pure logic for the Vitals+ "on pace for…" end-of-day projection. Decoupled
/// from HealthKit so it can be unit-tested directly.
///
/// The projection is deliberately additive rather than a naive linear
/// extrapolation: resting energy accrues steadily through the day (including
/// while you sleep), so multiplying the morning total by "hours left" would wildly
/// over-project. Instead we take the user's own typical full-day total and their
/// typical accumulation *by this time of day* (both from the same pacing sample
/// set) and assume the remaining burn looks like a normal day:
///
///     projected = current + max(0, usualFullDay − usualByNow)
///
/// This respects how far ahead or behind the user already is while assuming the
/// rest of the day fills in the usual amount.
enum ProjectionCalculator {
    /// Projected end-of-day total, or nil when there isn't enough history to
    /// project honestly. `current` is today's value so far.
    static func projectedEndOfDay(
        current: Double,
        usualByNow: Double?,
        usualFullDay: Double?
    ) -> Double? {
        guard let usualFullDay, usualFullDay > 0 else { return nil }
        // No time-of-day reference (e.g. pacing suppressed early morning): fall
        // back to whichever is larger — we never project below what's banked.
        guard let usualByNow else { return max(current, usualFullDay) }
        let remaining = max(0, usualFullDay - usualByNow)
        return current + remaining
    }

    /// Whether a goal is on track to be met by end of day, given the projection.
    /// nil when there's no goal or no projection.
    static func goalOutlook(projected: Double?, goal: Double?) -> GoalOutlook? {
        guard let projected, let goal, goal > 0 else { return nil }
        let delta = projected - goal
        // Within 2% of goal reads as "right on track" rather than over/under —
        // projections aren't precise enough to call a 30-calorie gap a miss.
        let tolerance = goal * 0.02
        if delta >= -tolerance {
            return .onTrack(margin: max(0, delta))
        }
        return .behind(shortfall: -delta)
    }
}

/// End-of-day outlook for a single goal.
enum GoalOutlook: Equatable, Sendable {
    /// Projected to meet or beat the goal. `margin` is the projected overage.
    case onTrack(margin: Double)
    /// Projected to fall short. `shortfall` is how far under.
    case behind(shortfall: Double)
}
