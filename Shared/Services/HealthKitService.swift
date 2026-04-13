import Foundation
import HealthKit
import os
import SwiftData
import WidgetKit
#if os(watchOS)
import WatchKit
#endif

private let healthKitLogger = Logger(subsystem: "com.jackwallner.vitals", category: "HealthKit")

@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    @Published var isAuthorized: Bool

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.stepCount),
    ]

    private init() {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
        } else {
            isAuthorized = false
            // authorizationStatus(for:) only reports write/sharing auth — useless for
            // read-only apps.  Use the async request-status API instead: .unnecessary
            // means the user was already prompted (we can't know their answer for reads,
            // but we should attempt to fetch data regardless).
            Task {
                let status = await self.authorizationRequestStatus()
                if status == .unnecessary {
                    self.isAuthorized = true
                }
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthKitLogger.info("Requesting HealthKit authorization for \(self.readTypes.count, privacy: .public) read types")
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            enableBackgroundDelivery()
            healthKitLogger.info("HealthKit authorization request completed")
        } catch {
            healthKitLogger.error("HealthKit authorization request failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func authorizationRequestStatus() async -> HKAuthorizationRequestStatus? {
        if ScreenshotConfig.isEnabled {
            return .unnecessary
        }
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error {
                    healthKitLogger.error("Failed to fetch HealthKit authorization request status: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }

                healthKitLogger.info("HealthKit authorization request status: \(status.rawValue, privacy: .public)")
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Today's Stats

    /// Apple does not expose whether the user allowed *reads*; `getRequestStatus` only reflects whether
    /// the permission sheet still needs to be shown. After that, always query — empty vs denied is indistinguishable.
    func synchronizeAuthorizationStateForFetching() async {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let status = await authorizationRequestStatus() else { return }
        switch status {
        case .shouldRequest:
            do {
                try await requestAuthorization()
            } catch {
                healthKitLogger.error("synchronizeAuthorizationStateForFetching: requestAuthorization failed: \(String(describing: error), privacy: .public)")
            }
        case .unnecessary:
            isAuthorized = true
        @unknown default:
            isAuthorized = true
        }
    }

    func fetchTodayStats() async throws -> (active: Double, resting: Double, steps: Int) {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            return ScreenshotFixtures.todayStats()
        }
        #endif
        // Use the same HealthKit path as `fetchHistory` / the History tab: `HKStatisticsCollectionQuery`
        // with a daily interval and *no* per-sample predicate. Apple documents collection queries for
        // partitioning quantities into fixed intervals (e.g. days):
        // https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries
        //
        // For a single calendar day, match the interval used across the rest of this file: `[dayStart, dayEnd)`
        // where `dayEnd` is the start of the next day (same as `fetchHistory(from:to:)` after it extends `end`).
        // Apple's statistical-queries sample also uses midnight → next midnight for the predicate window:
        // https://developer.apple.com/documentation/healthkit/executing-statistical-queries
        let calendar = Calendar.current
        let dayStart = DateHelpers.startOfDay()
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            healthKitLogger.error("fetchTodayStats: could not compute start of tomorrow after dayStart")
            throw NSError(
                domain: "com.jackwallner.vitals.healthkit",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Calendar could not compute end of day."]
            )
        }
        let interval = DateComponents(day: 1)

        async let activeMap = queryStatisticsCollection(.activeEnergyBurned, unit: .kilocalorie(), start: dayStart, end: dayEnd, interval: interval)
        async let restingMap = queryStatisticsCollection(.basalEnergyBurned, unit: .kilocalorie(), start: dayStart, end: dayEnd, interval: interval)
        async let stepsMap = queryStatisticsCollection(.stepCount, unit: .count(), start: dayStart, end: dayEnd, interval: interval)

        let (active, resting, steps) = try await (activeMap, restingMap, stepsMap)

        return (
            active: active[dayStart] ?? 0,
            resting: resting[dayStart] ?? 0,
            steps: Int(steps[dayStart] ?? 0)
        )
    }

    func fetchTodayStatsWithRetry(
        maxAttempts: Int = 3,
        retryDelay: Duration = .seconds(1)
    ) async throws -> (active: Double, resting: Double, steps: Int) {
        var lastStats = (active: 0.0, resting: 0.0, steps: 0)

        for attempt in 1...maxAttempts {
            let stats = try await fetchTodayStats()
            lastStats = stats

            if !areAllStatsZero(stats) || attempt == maxAttempts {
                if areAllStatsZero(stats) {
                    healthKitLogger.notice("HealthKit returned all-zero stats after \(attempt, privacy: .public) attempts")
                }
                return stats
            }

            healthKitLogger.notice("HealthKit returned all-zero stats on attempt \(attempt, privacy: .public); retrying")
            try? await Task.sleep(for: retryDelay)
            if Task.isCancelled { return stats }
        }

        return lastStats
    }

    // MARK: - History

    func fetchHistory(days: Int) async throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            return ScreenshotFixtures.history(days: days)
        }
        #endif
        let start = DateHelpers.daysAgo(max(days - 1, 0))
        return try await fetchHistory(from: start, to: .now)
    }

    func fetchHistory(from start: Date, to end: Date) async throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            let dayCount = max(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0, 30)
            return ScreenshotFixtures.history(days: dayCount, end: end)
        }
        #endif
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
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            return ScreenshotFixtures.pacing()
        }
        #endif
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
    private var observerQueriesInstalled = false

    func enableBackgroundDelivery() {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let types: [HKQuantityType] = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
        ]

        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, error in
                if let error {
                    healthKitLogger.error("Background delivery error for \(String(describing: type), privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }

        guard !observerQueriesInstalled else { return }
        observerQueriesInstalled = true

        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                // Call completion handler immediately — watchOS kills the app
                // if this isn't called within 15 seconds.
                completionHandler()
                if let error {
                    healthKitLogger.error("HKObserverQuery error for \(String(describing: type), privacy: .public): \(String(describing: error), privacy: .public)")
                    return
                }
                #if os(watchOS)
                // On watchOS, don't do heavy work in the observer callback —
                // the CAROUSEL watchdog has a tight CPU budget and will kill us.
                // Just schedule a background refresh and let the protected handler do it.
                Task { @MainActor in
                    WKApplication.shared().scheduleBackgroundRefresh(
                        withPreferredDate: Date(timeIntervalSinceNow: 5),
                        userInfo: nil
                    ) { _ in }
                }
                #else
                Task { @MainActor in
                    // Debounce: multiple HK types often deliver simultaneously.
                    // Coalesce into a single refreshCache call.
                    self?.pendingRefreshTask?.cancel()
                    self?.pendingRefreshTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        do {
                            try await self?.refreshCache()
                        } catch {
                            healthKitLogger.error("Observer-triggered cache refresh failed: \(String(describing: error), privacy: .public)")
                        }
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
            resolvedStats = try await fetchTodayStatsWithRetry()
        }

        healthKitLogger.info(
            "Refreshing today cache with stats active=\(resolvedStats.active, privacy: .public) resting=\(resolvedStats.resting, privacy: .public) steps=\(resolvedStats.steps, privacy: .public)"
        )

        let context = ModelContext(DataService.sharedModelContainer)
        let today = DateHelpers.startOfDay()
        let todayKey = DailyHealthRecord.key(for: today)

        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString == todayKey }
        )
        let existing = try context.fetch(descriptor).first

        if areAllStatsZero(resolvedStats) {
            let requestStatus = await authorizationRequestStatus()
            let existingHasData = existing.map {
                hasRecordedData((active: $0.activeCalories, resting: $0.restingCalories, steps: $0.steps))
            } ?? false

            healthKitLogger.notice(
                "Resolved all-zero today stats requestStatus=\(String(describing: requestStatus), privacy: .public) existingHasData=\(existingHasData, privacy: .public)"
            )

            if requestStatus == .shouldRequest {
                healthKitLogger.notice("Skipping cache write for all-zero stats because authorization is not settled")
                return
            }

            if existingHasData {
                healthKitLogger.notice("Skipping cache overwrite because existing today cache already has non-zero values")
                return
            }

            healthKitLogger.notice("Persisting all-zero today stats because there is no better same-day cache to preserve")
        }

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
        healthKitLogger.info("Saved today cache and reloaded widget timelines")
    }

    func clearTodayCache() throws {
        let context = ModelContext(DataService.sharedModelContainer)
        let todayKey = DailyHealthRecord.key(for: DateHelpers.startOfDay())
        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString == todayKey }
        )

        let records = try context.fetch(descriptor)
        guard !records.isEmpty else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        for record in records {
            context.delete(record)
        }

        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
        healthKitLogger.info("Cleared today cache and reloaded widget timelines")
    }

    func fetchCachedTodayStats() throws -> (active: Double, resting: Double, steps: Int)? {
        let context = ModelContext(DataService.sharedModelContainer)
        let todayKey = DailyHealthRecord.key(for: DateHelpers.startOfDay())
        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString == todayKey }
        )

        guard let record = try context.fetch(descriptor).first else {
            healthKitLogger.info("No cached today stats found")
            return nil
        }
        healthKitLogger.info(
            "Loaded cached today stats active=\(record.activeCalories, privacy: .public) resting=\(record.restingCalories, privacy: .public) steps=\(record.steps, privacy: .public) lastUpdated=\(String(describing: record.lastUpdated), privacy: .public)"
        )
        return (active: record.activeCalories, resting: record.restingCalories, steps: record.steps)
    }

    func hasRecordedData(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        stats.active > 0 || stats.resting > 0 || stats.steps > 0
    }

    // MARK: - Private Helpers

    private func areAllStatsZero(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        stats.active == 0 && stats.resting == 0 && stats.steps == 0
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
