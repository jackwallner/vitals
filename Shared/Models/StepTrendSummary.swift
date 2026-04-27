import Foundation

struct StepTrendSummary {
    let points: [StepTrendPoint]
    let weekly: StepTrendMetric
    let monthly: StepTrendMetric

    static func make(
        history: [(date: Date, active: Double, resting: Double, steps: Int)],
        calendar: Calendar = .current
    ) -> StepTrendSummary? {
        let sorted = history
            .map {
                StepTrendPoint(
                    date: calendar.startOfDay(for: $0.date),
                    steps: max($0.steps, 0)
                )
            }
            .sorted { $0.date < $1.date }

        guard let endDate = sorted.last?.date else { return nil }
        let visiblePoints = Array(sorted.suffix(30))
        let weekly = StepTrendMetric.make(title: "7D AVG", periodDays: 7, points: sorted, endDate: endDate, calendar: calendar)
        let monthly = StepTrendMetric.make(title: "30D AVG", periodDays: 30, points: sorted, endDate: endDate, calendar: calendar)

        return StepTrendSummary(points: visiblePoints, weekly: weekly, monthly: monthly)
    }
}

struct StepTrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let steps: Int
}

struct StepTrendMetric {
    let title: String
    let average: Double?
    let sampleDays: Int
    let expectedDays: Int
    let percentChange: Double?

    var averageText: String {
        guard let average else { return "—" }
        return average.formatted(.number.precision(.fractionLength(0)))
    }

    var changeText: String {
        guard let percentChange else {
            return sampleDays > 0 ? "—" : "No data"
        }
        let direction = percentChange >= 0 ? "↑" : "↓"
        return "\(direction) \(abs(percentChange).formatted(.number.precision(.fractionLength(0))))%"
    }

    var accessibilityText: String {
        guard let average else { return "\(title) no data" }
        let trendLabel: String
        if let percentChange {
            let direction = percentChange >= 0 ? "up" : "down"
            trendLabel = "\(direction) \(abs(percentChange).formatted(.number.precision(.fractionLength(0)))) percent from prior period"
        } else if sampleDays > 0 {
            trendLabel = "\(sampleDays) of \(expectedDays) days with data"
        } else {
            trendLabel = "no prior data for comparison"
        }
        return "\(title) \(Int(average)) steps per day over \(sampleDays) completed days, \(trendLabel)"
    }

    static func make(
        title: String,
        periodDays: Int,
        points: [StepTrendPoint],
        endDate: Date,
        calendar: Calendar
    ) -> StepTrendMetric {
        let completedPoints = points.filter { !calendar.isDateInToday($0.date) && $0.steps > 0 }
        guard let referenceDate = completedPoints.last?.date else {
            return StepTrendMetric(title: title, average: nil, sampleDays: 0, expectedDays: periodDays, percentChange: nil)
        }

        guard let currentStart = calendar.date(byAdding: .day, value: -(periodDays - 1), to: referenceDate),
              let previousStart = calendar.date(byAdding: .day, value: -periodDays, to: currentStart),
              let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart)
        else {
            return StepTrendMetric(title: title, average: nil, sampleDays: 0, expectedDays: periodDays, percentChange: nil)
        }

        let currentPoints = points.filter { $0.date >= currentStart && $0.date <= referenceDate && $0.steps > 0 }
        let previousPoints = points.filter { $0.date >= previousStart && $0.date <= previousEnd && $0.steps > 0 }
        let average = averageSteps(currentPoints)
        let previousAverage = averageSteps(previousPoints)
        let percentChange = average.flatMap { current in
            previousAverage.flatMap { previous in
                previous > 0 ? ((current - previous) / previous) * 100 : nil
            }
        }

        return StepTrendMetric(
            title: title,
            average: average,
            sampleDays: currentPoints.count,
            expectedDays: periodDays,
            percentChange: percentChange
        )
    }

    private static func averageSteps(_ points: [StepTrendPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.map { Double($0.steps) }.reduce(0, +) / Double(points.count)
    }
}
