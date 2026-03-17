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
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)

        let active = try await queryCumulativeSum(.activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        let resting = try await queryCumulativeSum(.basalEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        let steps = try await queryCumulativeSum(.stepCount, unit: .count(), predicate: predicate)

        return (active: active, resting: resting, steps: Int(steps))
    }

    // MARK: - History

    func fetchHistory(days: Int) async throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let start = DateHelpers.daysAgo(days)
        let end = DateHelpers.startOfDay(.now)
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
