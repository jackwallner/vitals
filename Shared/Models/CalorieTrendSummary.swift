import Foundation

struct CalorieTrendSummary {
    let points: [CalorieTrendPoint]
    let weekly: CalorieTrendMetric
    let monthly: CalorieTrendMetric

    static func make(
        history: [(date: Date, active: Double, resting: Double, steps: Int)],
        calendar: Calendar = .current
    ) -> CalorieTrendSummary? {
        let sorted = history
            .map {
                CalorieTrendPoint(
                    date: calendar.startOfDay(for: $0.date),
                    totalCalories: max($0.active + $0.resting, 0)
                )
            }
            .sorted { $0.date < $1.date }

        guard let endDate = sorted.last?.date else { return nil }
        let visiblePoints = Array(sorted.suffix(30))
        let weekly = CalorieTrendMetric.make(title: "7D AVG", periodDays: 7, points: sorted, endDate: endDate, calendar: calendar)
        let monthly = CalorieTrendMetric.make(title: "30D AVG", periodDays: 30, points: sorted, endDate: endDate, calendar: calendar)

        return CalorieTrendSummary(points: visiblePoints, weekly: weekly, monthly: monthly)
    }
}

struct CalorieTrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let totalCalories: Double
}

struct CalorieTrendMetric {
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
        return "\(title) \(Int(average)) calories per day over \(sampleDays) completed days, \(trendLabel)"
    }

    static func make(
        title: String,
        periodDays: Int,
        points: [CalorieTrendPoint],
        endDate: Date,
        calendar: Calendar
    ) -> CalorieTrendMetric {
        // Use the most recent completed day (not today) as the reference for averages.
        let completedPoints = points.filter { !calendar.isDateInToday($0.date) && $0.totalCalories > 0 }
        guard let referenceDate = completedPoints.last?.date else {
            return CalorieTrendMetric(title: title, average: nil, sampleDays: 0, expectedDays: periodDays, percentChange: nil)
        }

        guard let currentStart = calendar.date(byAdding: .day, value: -(periodDays - 1), to: referenceDate),
              let previousStart = calendar.date(byAdding: .day, value: -periodDays, to: currentStart),
              let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart)
        else {
            return CalorieTrendMetric(title: title, average: nil, sampleDays: 0, expectedDays: periodDays, percentChange: nil)
        }

        let currentPoints = points.filter { $0.date >= currentStart && $0.date <= referenceDate && $0.totalCalories > 0 }
        let previousPoints = points.filter { $0.date >= previousStart && $0.date <= previousEnd && $0.totalCalories > 0 }
        let average = averageCalories(currentPoints)
        let previousAverage = averageCalories(previousPoints)
        let percentChange = average.flatMap { current in
            previousAverage.flatMap { previous in
                previous > 0 ? ((current - previous) / previous) * 100 : nil
            }
        }

        return CalorieTrendMetric(
            title: title,
            average: average,
            sampleDays: currentPoints.count,
            expectedDays: periodDays,
            percentChange: percentChange
        )
    }

    private static func averageCalories(_ points: [CalorieTrendPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.totalCalories).reduce(0, +) / Double(points.count)
    }
}
