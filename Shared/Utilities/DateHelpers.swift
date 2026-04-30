import Foundation

enum DateHelpers {
    static func startOfDay(_ date: Date = .now) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func daysAgo(_ days: Int, from date: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: startOfDay(date))
            ?? startOfDay(date)
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
