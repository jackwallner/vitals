import Foundation

/// The days a per-day average divides by: finished days that have a reading.
/// Today is still partial and a day the watch sat on the charger reads 0, so
/// either would pull the average below what the user really burns or walks.
/// When no such day exists yet (a fresh install), the days with data are used,
/// today included, so the card is not blank.
enum DailyAverage {
    static func days<Day>(
        _ days: [Day],
        date: (Day) -> Date,
        hasData: (Day) -> Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Day] {
        let withData = days.filter(hasData)
        let finished = withData.filter { !calendar.isDate(date($0), inSameDayAs: now) }
        return finished.isEmpty ? withData : finished
    }

    static func mean<Day>(
        _ days: [Day],
        value: (Day) -> Double,
        date: (Day) -> Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double {
        let counted = Self.days(days, date: date, hasData: { value($0) > 0 }, now: now, calendar: calendar)
        guard !counted.isEmpty else { return 0 }
        return counted.map(value).reduce(0, +) / Double(counted.count)
    }
}
