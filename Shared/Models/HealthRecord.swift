import Foundation
import SwiftData

@Model
final class DailyHealthRecord {
    @Attribute(.unique) var date: Date
    var activeCalories: Double
    var restingCalories: Double
    var steps: Int
    var lastUpdated: Date

    var totalCalories: Double { activeCalories + restingCalories }

    init(date: Date, activeCalories: Double = 0, restingCalories: Double = 0, steps: Int = 0) {
        self.date = date
        self.activeCalories = activeCalories
        self.restingCalories = restingCalories
        self.steps = steps
        self.lastUpdated = Date()
    }
}
