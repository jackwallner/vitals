import Foundation

/// Stepping the Today screen through past days. A viewed day of nil is today.
enum DayBrowser {
    /// The same reach as History's longest fixed period.
    static let maxDaysBack = 365

    /// The day before `viewed`, or nil once `maxDaysBack` is reached.
    static func previous(of viewed: Date?, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let current = calendar.startOfDay(for: viewed ?? now)
        guard let day = calendar.date(byAdding: .day, value: -1, to: current),
              let earliest = calendar.date(byAdding: .day, value: -maxDaysBack, to: today),
              day >= earliest
        else { return nil }
        return day
    }

    /// The day after `viewed`, or nil when that day is today.
    static func next(of viewed: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: viewed)),
              day < today
        else { return nil }
        return day
    }
}
