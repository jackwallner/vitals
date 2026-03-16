import Foundation

enum DateHelpers {
    static func startOfDay(_ date: Date = .now) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func daysAgo(_ days: Int, from date: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: startOfDay(date))!
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    static func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
