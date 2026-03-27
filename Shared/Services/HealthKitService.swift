import Foundation
import HealthKit
import SwiftData
import WidgetKit
#if os(watchOS)
import WatchKit
#endif

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
        return try await fetchHistory(from: start, to: .now)
    }

    func fetchHistory(from start: Date, to end: Date) async throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let start = DateHelpers.startOfDay(start)
        // Include today by pushing end to tomorrow's start
        let endNormalized = DateHelpers.startOfDay(end)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: endNormalized) ?? endNormalized
        let interval = DateComponents(day: 1)

        async let activeMap = queryStatisticsCollection(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end, interval: interval)
        async let restingMap = queryStatisticsCollection(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end, interval: interval)
        async let stepsMap = queryStatisticsCollection(.stepCount, unit: .count(), start: start, end: end, interval: interval)

        let (active, resting, steps) = try await (activeMap, restingMap, stepsMap)

        var results: [(date: Date, active: Double, resting: Double, steps: Int)] = []
        var current = start
        while current < end {
            results.append((
                date: current,
                active: active[current] ?? 0,
                resting: resting[current] ?? 0,
                steps: Int(steps[current] ?? 0)
            ))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return results
    }

    // MARK: - Pacing (average at this time of day over last 14 days)

    func fetchPacing() async throws -> (avgCalories: Double, avgSteps: Int, daysWithData: Int) {
        let calendar = Calendar.current
        let now = Date.now
        let currentHour = calendar.component(.hour, from: now)

        // Too early in the day for meaningful pacing
        guard currentHour >= 6 else { return (0, 0, 0) }

        guard let fourteenDaysAgoDate = calendar.date(byAdding: .day, value: -14, to: now) else { return (0, 0, 0) }
        let fourteenDaysAgo = calendar.startOfDay(for: fourteenDaysAgoDate)

        // 3 bulk queries instead of 42 individual ones
        let interval = DateComponents(day: 1)
        let today = calendar.startOfDay(for: now)

        async let activeMap = queryStatisticsCollection(.activeEnergyBurned, unit: .kilocalorie(), start: fourteenDaysAgo, end: today, interval: interval)
        async let restingMap = queryStatisticsCollection(.basalEnergyBurned, unit: .kilocalorie(), start: fourteenDaysAgo, end: today, interval: interval)
        async let stepsMap = queryStatisticsCollection(.stepCount, unit: .count(), start: fourteenDaysAgo, end: today, interval: interval)

        let (active, resting, steps) = try await (activeMap, restingMap, stepsMap)

        // For each past day, calculate what was burned by this time of day
        // Use actual seconds elapsed since midnight / total seconds in today (handles DST 23/25h days)
        let secondsSoFar = now.timeIntervalSince(today)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        let totalSecondsToday = endOfToday.timeIntervalSince(today)
        let dayFraction = min(secondsSoFar / totalSecondsToday, 1.0)

        var totalCalories = 0.0
        var totalSteps = 0.0
        var daysWithData = 0

        var current = fourteenDaysAgo
        while current < today {
            let dayCal = (active[current] ?? 0) + (resting[current] ?? 0)
            let daySteps = steps[current] ?? 0
            if dayCal > 0 || daySteps > 0 {
                daysWithData += 1
                totalCalories += dayCal * dayFraction
                totalSteps += daySteps * dayFraction
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        guard daysWithData > 0 else { return (0, 0, 0) }
        return (
            avgCalories: totalCalories / Double(daysWithData),
            avgSteps: Int(totalSteps / Double(daysWithData)),
            daysWithData: daysWithData
        )
    }

    // MARK: - Background Delivery

    private var pendingRefreshTask: Task<Void, Never>?

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
                // Call completion handler immediately — watchOS kills the app
                // if this isn't called within 15 seconds.
                completionHandler()
                if let error {
                    print("HKObserverQuery error for \(type): \(error)")
                    return
                }
                #if os(watchOS)
                // On watchOS, don't do heavy work in the observer callback —
                // the CAROUSEL watchdog has a tight CPU budget and will kill us.
                // Just schedule a background refresh and let the protected handler do it.
                WKApplication.shared().scheduleBackgroundRefresh(
                    withPreferredDate: Date(timeIntervalSinceNow: 5),
                    userInfo: nil
                ) { _ in }
                #else
                Task { @MainActor in
                    // Debounce: multiple HK types often deliver simultaneously.
                    // Coalesce into a single refreshCache call.
                    self?.pendingRefreshTask?.cancel()
                    self?.pendingRefreshTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        try? await self?.refreshCache()
                    }
                }
                #endif
            }
            store.execute(query)
        }
    }

    func refreshCache(stats: (active: Double, resting: Double, steps: Int)? = nil) async throws {
        let resolvedStats: (active: Double, resting: Double, steps: Int)
        if let stats {
            resolvedStats = stats
        } else {
            resolvedStats = try await fetchTodayStats()
        }
        let context = DataService.sharedModelContainer.mainContext
        let today = DateHelpers.startOfDay()
        let todayKey = DailyHealthRecord.key(for: today)

        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString == todayKey }
        )
        let existing = try context.fetch(descriptor).first

        if let record = existing {
            record.activeCalories = resolvedStats.active
            record.restingCalories = resolvedStats.resting
            record.steps = resolvedStats.steps
            record.lastUpdated = .now
        } else {
            let record = DailyHealthRecord(
                date: today,
                activeCalories: resolvedStats.active,
                restingCalories: resolvedStats.resting,
                steps: resolvedStats.steps
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
