import Foundation

enum DateHelpers {
    static func startOfDay(_ date: Date = .now) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func daysAgo(_ days: Int, from date: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: startOfDay(date))
            ?? startOfDay(date)
    }

    /// Exclusive end for a daily HealthKit query whose requested end date is inclusive.
    /// Completed days extend to the next midnight; ranges containing today stop at `now`
    /// so duration-based samples cannot contribute future quantities.
    static func healthQueryEnd(including end: Date, now: Date = .now) -> Date {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: end)
        let today = calendar.startOfDay(for: now)
        guard endDay < today else { return now }
        return calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md")
        return f
    }()

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return f
    }()

    private static let shortMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private static let dayOfWeekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func mediumDate(_ date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        monthYearFormatter.string(from: date)
    }

    static func shortMonth(_ date: Date) -> String {
        shortMonthFormatter.string(from: date)
    }

    static func dayOfWeek(_ date: Date) -> String {
        dayOfWeekFormatter.string(from: date)
    }

    /// Returns start of week for the given date (Sunday by default, or use Calendar's firstWeekday)
    static func startOfWeek(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Returns start of month for the given date
    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}
