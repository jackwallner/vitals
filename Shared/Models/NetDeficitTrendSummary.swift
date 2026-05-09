import Foundation

struct NetDeficitTrendSummary {
    let points: [NetDeficitTrendPoint]
    let weekly: NetDeficitTrendMetric

    static func make(
        history: [(date: Date, active: Double, resting: Double, steps: Int)],
        foodByDate: [Date: Double],
        calendar: Calendar = .current
    ) -> NetDeficitTrendSummary? {
        let sorted = history
            .map { day -> NetDeficitTrendPoint in
                let key = calendar.startOfDay(for: day.date)
                let food = max(foodByDate[key] ?? 0, 0)
                let burned = max(day.active + day.resting, 0)
                return NetDeficitTrendPoint(
                    date: key,
                    netDeficit: burned - food,
                    burned: burned,
                    food: food
                )
            }
            .sorted { $0.date < $1.date }

        guard let endDate = sorted.last?.date else { return nil }
        let visible = Array(sorted.suffix(30))
        let weekly = NetDeficitTrendMetric.make(
            title: "7D AVG",
            periodDays: 7,
            points: sorted,
            endDate: endDate,
            calendar: calendar
        )
        return NetDeficitTrendSummary(points: visible, weekly: weekly)
    }
}

struct NetDeficitTrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let netDeficit: Double
    let burned: Double
    let food: Double
}

struct NetDeficitTrendMetric {
    let title: String
    let average: Double?
    let sampleDays: Int
    let expectedDays: Int

    var averageText: String {
        guard let average else { return "—" }
        let r = Int(average.rounded())
        return r > 0 ? "+\(r.formatted(.number))" : r.formatted(.number)
    }

    var accessibilityText: String {
        guard let average else { return "\(title) no data" }
        return "\(title) \(Int(average)) net calories per day over \(sampleDays) completed days"
    }

    static func make(
        title: String,
        periodDays: Int,
        points: [NetDeficitTrendPoint],
        endDate: Date,
        calendar: Calendar
    ) -> NetDeficitTrendMetric {
        // Net deficit only meaningful when the user logged food that day.
        let completedPoints = points.filter { !calendar.isDateInToday($0.date) && $0.burned > 0 }
        guard let referenceDate = completedPoints.last?.date else {
            return NetDeficitTrendMetric(title: title, average: nil, sampleDays: 0, expectedDays: periodDays)
        }
        guard let currentStart = calendar.date(byAdding: .day, value: -(periodDays - 1), to: referenceDate) else {
            return NetDeficitTrendMetric(title: title, average: nil, sampleDays: 0, expectedDays: periodDays)
        }

        let currentPoints = points.filter {
            $0.date >= currentStart && $0.date <= referenceDate && $0.burned > 0
        }
        let avg: Double? = currentPoints.isEmpty
            ? nil
            : currentPoints.map(\.netDeficit).reduce(0, +) / Double(currentPoints.count)

        return NetDeficitTrendMetric(
            title: title,
            average: avg,
            sampleDays: currentPoints.count,
            expectedDays: periodDays
        )
    }
}
