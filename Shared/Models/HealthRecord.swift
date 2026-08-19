import Foundation
import SwiftData

@Model
final class DailyHealthRecord {
    @Attribute(.unique) var dateString: String  // "yyyy-MM-dd" for reliable uniqueness
    var date: Date
    var activeCalories: Double
    var restingCalories: Double
    var steps: Int
    var foodCalories: Double
    /// Macronutrient grams logged in Apple Health for this day (Vitals+ Macros).
    /// Defaulted so SwiftData migrates existing stores additively, exactly like
    /// `foodCalories` did. Widgets and the watch read the same cached row.
    var proteinGrams: Double = 0
    var carbGrams: Double = 0
    var fatGrams: Double = 0
    var lastUpdated: Date

    var totalCalories: Double { activeCalories + restingCalories }

    var macros: MacroTotals {
        MacroTotals(protein: proteinGrams, carbs: carbGrams, fat: fatGrams)
    }

    private static let gregorian = Calendar(identifier: .gregorian)

    init(date: Date, activeCalories: Double = 0, restingCalories: Double = 0, steps: Int = 0) {
        let normalized = Self.gregorian.startOfDay(for: date)
        self.dateString = Self.key(for: normalized)
        self.date = normalized
        self.activeCalories = activeCalories
        self.restingCalories = restingCalories
        self.steps = steps
        self.foodCalories = 0
        self.proteinGrams = 0
        self.carbGrams = 0
        self.fatGrams = 0
        self.lastUpdated = Date()
    }

    static func key(for date: Date) -> String {
        let cal = gregorian
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
