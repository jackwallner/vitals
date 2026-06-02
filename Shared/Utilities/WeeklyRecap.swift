import Foundation

/// A computed summary of the last 7 completed days, with a head-to-head against
/// the 7 days before that. Rendered by `WeeklyRecapView` when the user opens the
/// recap (from the weekly notification or the inline "view recap" affordance).
struct WeeklyRecap: Sendable, Equatable {
    let totalCalories: Double
    let totalSteps: Int
    let avgCalories: Double
    let avgSteps: Int
    let daysWithData: Int
    /// Days in the window that met the calorie or step goal (nil if no goals set).
    let goalDaysHit: Int?
    let goalDaysPossible: Int?
    /// Percent change vs. the prior 7 days, nil when the prior week had no data.
    let calorieChangePct: Double?
    let stepChangePct: Double?
    /// Best single day in the window by total calories.
    let bestCalorieDay: Date?
    let bestCalorieValue: Double?
}

enum WeeklyRecapBuilder {
    /// Builds a recap from history rows. `records` should cover at least the last
    /// 14 days (today excluded — it may be partial). Returns nil when the most
    /// recent 7-day window has no data at all.
    static func build(
        records: [MilestoneDay],
        calorieGoal: Double?,
        stepGoal: Int?,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyRecap? {
        let byDay: [Date: MilestoneDay] = Dictionary(
            records.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { a, _ in a }
        )
        let todayStart = calendar.startOfDay(for: today)

        // Window: yesterday back through 7 days ago (offsets 1...7).
        func windowDays(startOffset: Int) -> [MilestoneDay] {
            (startOffset..<(startOffset + 7)).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: todayStart).flatMap { byDay[$0] }
            }
        }

        let thisWeek = windowDays(startOffset: 1)
        let priorWeek = windowDays(startOffset: 8)

        let withData = thisWeek.filter { $0.calories > 0 || $0.steps > 0 }
        guard !withData.isEmpty else { return nil }

        let totalCalories = withData.reduce(0) { $0 + $1.calories }
        let totalSteps = withData.reduce(0) { $0 + $1.steps }
        let daysWithData = withData.count
        let avgCalories = totalCalories / Double(daysWithData)
        let avgSteps = totalSteps / daysWithData

        let goalDaysHit: Int?
        let goalDaysPossible: Int?
        if calorieGoal != nil || stepGoal != nil {
            goalDaysPossible = daysWithData
            goalDaysHit = withData.filter { day in
                let hitCal = calorieGoal.map { day.calories >= $0 } ?? false
                let hitStep = stepGoal.map { day.steps >= $0 } ?? false
                return hitCal || hitStep
            }.count
        } else {
            goalDaysHit = nil
            goalDaysPossible = nil
        }

        let priorWithData = priorWeek.filter { $0.calories > 0 || $0.steps > 0 }
        let priorCalAvg = priorWithData.isEmpty ? nil : priorWithData.reduce(0) { $0 + $1.calories } / Double(priorWithData.count)
        let priorStepAvg = priorWithData.isEmpty ? nil : Double(priorWithData.reduce(0) { $0 + $1.steps }) / Double(priorWithData.count)

        let calorieChangePct = priorCalAvg.flatMap { $0 > 0 ? (avgCalories - $0) / $0 * 100 : nil }
        let stepChangePct = priorStepAvg.flatMap { $0 > 0 ? (Double(avgSteps) - $0) / $0 * 100 : nil }

        let best = withData.max { $0.calories < $1.calories }

        return WeeklyRecap(
            totalCalories: totalCalories,
            totalSteps: totalSteps,
            avgCalories: avgCalories,
            avgSteps: avgSteps,
            daysWithData: daysWithData,
            goalDaysHit: goalDaysHit,
            goalDaysPossible: goalDaysPossible,
            calorieChangePct: calorieChangePct,
            stepChangePct: stepChangePct,
            bestCalorieDay: best?.date,
            bestCalorieValue: best?.calories
        )
    }
}
