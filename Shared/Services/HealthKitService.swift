import Foundation
import HealthKit
import SwiftData
import WidgetKit

@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    @Published var isAuthorized = false

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.stepCount),
    ]

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        isAuthorized = true
    }

    // MARK: - Today's Stats

    func fetchTodayStats() async throws -> (active: Double, resting: Double, steps: Int) {
        let start = DateHelpers.startOfDay()
        nonisolated(unsafe) let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)

        async let active = queryCumulativeSum(.activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        async let resting = queryCumulativeSum(.basalEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        async let steps = queryCumulativeSum(.stepCount, unit: .count(), predicate: predicate)

        return try await (active: active, resting: resting, steps: Int(steps))
    }

    // MARK: - History

    func fetchHistory(days: Int) async throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let start = DateHelpers.daysAgo(days)
        let end = DateHelpers.startOfDay(.now)
        return try await fetchHistory(from: start, to: end)
    }

    func fetchHistory(from start: Date, to end: Date) async throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let start = DateHelpers.startOfDay(start)
        let end = DateHelpers.startOfDay(end)
        let interval = DateComponents(day: 1)

        let activeMap = try await queryStatisticsCollection(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end, interval: interval)
        let restingMap = try await queryStatisticsCollection(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end, interval: interval)
        let stepsMap = try await queryStatisticsCollection(.stepCount, unit: .count(), start: start, end: end, interval: interval)

        var results: [(date: Date, active: Double, resting: Double, steps: Int)] = []
        var current = start
        while current < end {
            results.append((
                date: current,
                active: activeMap[current] ?? 0,
                resting: restingMap[current] ?? 0,
                steps: Int(stepsMap[current] ?? 0)
            ))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return results
    }

    // MARK: - Pacing (average at this time of day over last 14 days)

    func fetchPacing() async throws -> (avgCalories: Double, avgSteps: Int) {
        let calendar = Calendar.current
        let now = Date.now
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let fourteenDaysAgo = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -14, to: now)!)

        // 3 bulk queries instead of 42 individual ones
        let interval = DateComponents(day: 1)
        let today = calendar.startOfDay(for: now)

        async let activeMap = queryStatisticsCollection(.activeEnergyBurned, unit: .kilocalorie(), start: fourteenDaysAgo, end: today, interval: interval)
        async let restingMap = queryStatisticsCollection(.basalEnergyBurned, unit: .kilocalorie(), start: fourteenDaysAgo, end: today, interval: interval)
        async let stepsMap = queryStatisticsCollection(.stepCount, unit: .count(), start: fourteenDaysAgo, end: today, interval: interval)

        let (active, resting, steps) = try await (activeMap, restingMap, stepsMap)

        // For each past day, calculate what was burned by this time of day
        // Use the ratio: (currentHour*60 + currentMinute) / (24*60) as an approximation
        let minutesSoFar = Double(currentHour * 60 + currentMinute)
        let dayMinutes = 24.0 * 60.0
        let dayFraction = minutesSoFar / dayMinutes

        var totalCalories = 0.0
        var totalSteps = 0.0
        var daysCounted = 0

        var current = fourteenDaysAgo
        while current < today {
            let dayCal = (active[current] ?? 0) + (resting[current] ?? 0)
            let daySteps = steps[current] ?? 0
            totalCalories += dayCal * dayFraction
            totalSteps += daySteps * dayFraction
            daysCounted += 1
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        guard daysCounted > 0 else { return (0, 0) }
        return (
            avgCalories: totalCalories / Double(daysCounted),
            avgSteps: Int(totalSteps / Double(daysCounted))
        )
    }

    // MARK: - Background Delivery

    func enableBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let types: [HKQuantityType] = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
        ]

        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, error in
                if let error { print("Background delivery error for \(type): \(error)") }
            }

            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                guard error == nil else {
                    completionHandler()
                    return
                }
                nonisolated(unsafe) let handler = completionHandler
                Task { @MainActor in
                    try? await self?.refreshCache()
                    handler()
                }
            }
            store.execute(query)
        }
    }

    func refreshCache() async throws {
        let stats = try await fetchTodayStats()
        let context = DataService.sharedModelContainer.mainContext
        let today = DateHelpers.startOfDay()
        let todayKey = DailyHealthRecord.key(for: today)

        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString == todayKey }
        )
        let existing = try context.fetch(descriptor).first

        if let record = existing {
            record.activeCalories = stats.active
            record.restingCalories = stats.resting
            record.steps = stats.steps
            record.lastUpdated = .now
        } else {
            let record = DailyHealthRecord(
                date: today,
                activeCalories: stats.active,
                restingCalories: stats.resting,
                steps: stats.steps
            )
            context.insert(record)
        }

        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Private Helpers

    private nonisolated func queryCumulativeSum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async throws -> Double {
        let store = self.store
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(identifier),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private nonisolated func queryStatisticsCollection(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        interval: DateComponents
    ) async throws -> [Date: Double] {
        let store = self.store
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(identifier),
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var results: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let value = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                    results[statistics.startDate] = value
                }
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }
}
