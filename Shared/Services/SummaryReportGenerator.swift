import Foundation

/// Aggregated metrics for a single day in the report period.
struct ReportDay: Sendable, Identifiable {
    let id = UUID()
    let date: Date
    let activeCalories: Double
    let restingCalories: Double
    let steps: Int
    let foodCalories: Double?

    var totalCalories: Double { activeCalories + restingCalories }
    var netDeficit: Double? {
        guard let food = foodCalories else { return nil }
        return totalCalories - food
    }
}

/// Result payload rendered by `SummaryReportView`.
struct SummaryReport: Sendable {
    let title: String
    let periodStart: Date
    let periodEnd: Date
    let days: [ReportDay]

    let totalCalories: Double
    let avgCalories: Double
    let totalActive: Double
    let avgActive: Double
    let totalResting: Double
    let avgResting: Double
    let totalSteps: Int
    let avgSteps: Int
    let activeDayCount: Int

    let peakCalorieDay: ReportDay?
    let peakStepDay: ReportDay?

    /// Period-over-period: percent change vs. the immediately preceding window of equal length.
    /// `nil` if there is no prior data to compare against (e.g. first month using the app).
    let calorieTrendPct: Double?
    let stepTrendPct: Double?

    let calorieGoal: Double?
    let stepGoal: Int?
    let calorieGoalHitDays: Int
    let stepGoalHitDays: Int

    /// Net deficit aggregates — only populated when the user has Net Deficit enabled
    /// and dietary calories were available for at least one day in the window.
    let avgNetDeficit: Double?
    let totalNetDeficit: Double?
    let bestNetDay: ReportDay?
    let netDeficitDayCount: Int

    var calendarLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return "\(f.string(from: periodStart)) – \(f.string(from: periodEnd))"
    }
}

@MainActor
enum SummaryReportGenerator {
    /// Build a report from a current period's days plus an optional preceding period of
    /// equal length for trend calculations.
    static func make(
        title: String,
        periodStart: Date,
        periodEnd: Date,
        days: [ReportDay],
        previousDays: [ReportDay] = [],
        calorieGoal: Double?,
        stepGoal: Int?
    ) -> SummaryReport {
        let nonZeroCalDays = days.filter { $0.totalCalories > 0 }
        let nonZeroStepDays = days.filter { $0.steps > 0 }

        let totalCalories = days.map(\.totalCalories).reduce(0, +)
        let dayCount = max(days.count, 1)
        let avgCalories = totalCalories / Double(dayCount)
        let totalActive = days.map(\.activeCalories).reduce(0, +)
        let avgActive = totalActive / Double(dayCount)
        let totalResting = days.map(\.restingCalories).reduce(0, +)
        let avgResting = totalResting / Double(dayCount)
        let totalSteps = days.map(\.steps).reduce(0, +)
        let avgSteps = Int((Double(totalSteps) / Double(dayCount)).rounded())

        let peakCal = days.max(by: { $0.totalCalories < $1.totalCalories })
        let peakStep = days.max(by: { $0.steps < $1.steps })

        let calorieTrend = trendPct(
            current: avgCalories,
            previous: averageCalories(in: previousDays)
        )
        let stepTrend = trendPct(
            current: Double(avgSteps),
            previous: averageSteps(in: previousDays)
        )

        let calHit = calorieGoal.map { goal in days.filter { $0.totalCalories >= goal }.count } ?? 0
        let stepHit = stepGoal.map { goal in days.filter { $0.steps >= goal }.count } ?? 0

        let netDays = days.compactMap { day -> (day: ReportDay, value: Double)? in
            guard let net = day.netDeficit else { return nil }
            return (day, net)
        }
        let avgNet: Double? = netDays.isEmpty ? nil : netDays.map(\.value).reduce(0, +) / Double(netDays.count)
        let totalNet: Double? = netDays.isEmpty ? nil : netDays.map(\.value).reduce(0, +)
        let bestNet: ReportDay? = netDays.max(by: { $0.value < $1.value })?.day

        return SummaryReport(
            title: title,
            periodStart: periodStart,
            periodEnd: periodEnd,
            days: days.sorted { $0.date < $1.date },
            totalCalories: totalCalories,
            avgCalories: avgCalories,
            totalActive: totalActive,
            avgActive: avgActive,
            totalResting: totalResting,
            avgResting: avgResting,
            totalSteps: totalSteps,
            avgSteps: avgSteps,
            activeDayCount: nonZeroCalDays.count,
            peakCalorieDay: peakCal,
            peakStepDay: peakStep,
            calorieTrendPct: calorieTrend,
            stepTrendPct: stepTrend,
            calorieGoal: calorieGoal,
            stepGoal: stepGoal,
            calorieGoalHitDays: calHit,
            stepGoalHitDays: stepHit,
            avgNetDeficit: avgNet,
            totalNetDeficit: totalNet,
            bestNetDay: bestNet,
            netDeficitDayCount: netDays.count
        )
    }

    private static func averageCalories(in days: [ReportDay]) -> Double {
        let nonZero = days.filter { $0.totalCalories > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.map(\.totalCalories).reduce(0, +) / Double(nonZero.count)
    }

    private static func averageSteps(in days: [ReportDay]) -> Double {
        let nonZero = days.filter { $0.steps > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return Double(nonZero.map(\.steps).reduce(0, +)) / Double(nonZero.count)
    }

    private static func trendPct(current: Double, previous: Double) -> Double? {
        guard previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }
}
