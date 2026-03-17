import Foundation
import SwiftData

@Model
final class DailyHealthRecord {
    @Attribute(.unique) var dateString: String  // "yyyy-MM-dd" for reliable uniqueness
    var date: Date
    var activeCalories: Double
    var restingCalories: Double
    var steps: Int
    var lastUpdated: Date

    var totalCalories: Double { activeCalories + restingCalories }

    init(date: Date, activeCalories: Double = 0, restingCalories: Double = 0, steps: Int = 0) {
        let normalized = Calendar.current.startOfDay(for: date)
        self.dateString = Self.key(for: normalized)
        self.date = normalized
        self.activeCalories = activeCalories
        self.restingCalories = restingCalories
        self.steps = steps
        self.lastUpdated = Date()
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func key(for date: Date) -> String {
        keyFormatter.string(from: date)
    }
}
