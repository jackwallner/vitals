import Foundation

/// The Excluded Days trial pitch, written about the user's own data instead of
/// in the abstract. "Leave Sep 3 out" with that day's number beside it is a
/// reason to tap; "keep odd days out of your averages" is a description.
///
/// The day is the one the user tapped when there is one, since pitching a
/// different day than the one under their finger reads as a bug. Otherwise it
/// is their lowest recent day: total burn bottoms out on the days the watch sat
/// on the charger or they were sick in bed, which is exactly what the feature is
/// for, and it is the day whose removal moves the average the most.
struct ExcludedDaysPitch: Equatable {
    let day: Date
    let headline: String
    let subheadline: String

    /// Completed days only, so today's partial burn never wins "lowest".
    static let windowDays = 30
    /// Fewer logged days than this and "your average" is too thin to quote.
    static let minimumLoggedDays = 7

    /// - Parameters:
    ///   - history: daily total calories, any order, any span.
    ///   - tapped: the calendar day the user reached for, if any.
    static func make(
        history: [(date: Date, calories: Double)],
        tapped: Date? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ExcludedDaysPitch? {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: today) else { return nil }
        var byDay: [Date: Double] = [:]
        for entry in history {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= windowStart, day < today, entry.calories > 0 else { continue }
            byDay[day, default: 0] = max(byDay[day, default: 0], entry.calories)
        }
        guard byDay.count >= minimumLoggedDays else { return nil }

        let chosen: (day: Date, calories: Double)
        if let tapped, let calories = byDay[calendar.startOfDay(for: tapped)] {
            chosen = (calendar.startOfDay(for: tapped), calories)
        } else if tapped == nil, let lowest = byDay.min(by: { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }) {
            chosen = (lowest.key, lowest.value)
        } else {
            return nil
        }

        let total = byDay.values.reduce(0, +)
        let average = total / Double(byDay.count)
        let averageWithout = (total - chosen.calories) / Double(byDay.count - 1)
        let lift = Int((averageWithout - average).rounded())

        let dayLabel = dayFormatter(calendar).string(from: chosen.day)
        let calories = Int(chosen.calories.rounded()).formatted(.number)
        // Only a lift is worth quoting. "Lowers your average" is true of any
        // above-average day the user taps and sells nothing.
        let effect = lift > 0
            ? "Leaving it out lifts your 30-day average by \(lift.formatted(.number)) cal."
            : "Leave it out of every average, total, and streak."
        let isLowest = tapped == nil
        let lead = isLowest
            ? "Your lowest day in the last 30 burned \(calories) cal."
            : "That day burned \(calories) cal."
        return ExcludedDaysPitch(
            day: chosen.day,
            headline: "Leave \(dayLabel) out of your averages",
            subheadline: "\(lead) \(effect)"
        )
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }
}
