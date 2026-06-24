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

    private let baseReadTypes: Set<HKObjectType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.stepCount),
    ]

    private let dietaryReadType: HKObjectType = HKQuantityType(.dietaryEnergyConsumed)

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
                let status = await self.authorizationRequestStatus(includeDietaryEnergy: false)
                if status == .unnecessary {
                    self.isAuthorized = true
                }
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorization(includeDietaryEnergy: Bool = false) async throws {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let readTypes = includeDietaryEnergy
            ? baseReadTypes.union([dietaryReadType])
            : baseReadTypes
        healthKitLogger.info(
            "Requesting HealthKit authorization for \(readTypes.count, privacy: .public) read types includeDietary=\(includeDietaryEnergy, privacy: .public)"
        )
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

    /// Request authorization for dietary energy only. Calling this separately avoids a
    /// HealthKit quirk where mixing already-authorized types with new ones can silently
    /// suppress the permission sheet (especially when called shortly after a prior auth).
    func requestDietaryAuthorization() async throws {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthKitLogger.info("Requesting HealthKit authorization for dietary energy only")
        do {
            try await store.requestAuthorization(toShare: [], read: [dietaryReadType])
            enableBackgroundDelivery()
            healthKitLogger.info("Dietary energy authorization request completed")
        } catch {
            healthKitLogger.error("Dietary energy authorization request failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }


    func authorizationRequestStatus(includeDietaryEnergy: Bool = false) async -> HKAuthorizationRequestStatus? {
        if ScreenshotConfig.isEnabled {
            return .unnecessary
        }
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let readTypes = includeDietaryEnergy
            ? baseReadTypes.union([dietaryReadType])
            : baseReadTypes

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
        guard let status = await authorizationRequestStatus(includeDietaryEnergy: false) else { return }
        switch status {
        case .shouldRequest:
            do {
                try await requestAuthorization(includeDietaryEnergy: false)
            } catch {
                healthKitLogger.error("synchronizeAuthorizationStateForFetching: requestAuthorization failed: \(String(describing: error), privacy: .public)")
            }
        case .unnecessary:
            isAuthorized = true
        case .unknown:
            // HealthKit hasn't resolved status yet; leave isAuthorized unchanged
            // so we try again on the next refresh.
            break
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
        // Use `HKStatisticsCollectionQuery` (single bucket) rather than the
        // singular `HKStatisticsQuery`. Collection queries proportionally split
        // sample quantities across bucket boundaries based on duration; the
        // singular query just sums matching samples whole. With a workout that
        // crosses midnight, the singular path mis-attributes those calories,
        // so Today disagreed with History (which has always bucketed). Same
        // shape and unit as `fetchHistory`'s per-day bucketing so the two
        // paths produce the same number for "today".
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
            active: statisticValue(active, for: dayStart),
            resting: statisticValue(resting, for: dayStart),
            steps: Int(statisticValue(steps, for: dayStart))
        )
    }

    /// Dietary energy (food) logged for today in Health, in kilocalories (e.g. from MyFitnessPal).
    func fetchDietaryEnergyToday() async throws -> Double {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            return ScreenshotFixtures.dietaryEnergyToday()
        }
        #endif
        let calendar = Calendar.current
        let dayStart = DateHelpers.startOfDay()
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            healthKitLogger.error("fetchDietaryEnergyToday: could not compute end of day")
            throw NSError(
                domain: "com.jackwallner.vitals.healthkit",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Calendar could not compute end of day."]
            )
        }
        let interval = DateComponents(day: 1)
        let map = try await queryStatisticsCollection(.dietaryEnergyConsumed, unit: .kilocalorie(), start: dayStart, end: dayEnd, interval: interval)
        let kcal = statisticValue(map, for: dayStart)
        healthKitLogger.debug("fetchDietaryEnergyToday: \(kcal, privacy: .public) kcal")
        // First non-zero read is our positive signal that dietary reads are authorized.
        // Persist so future launches can keep the dietary observer installed even when
        // Net Deficit happens to be toggled off at that moment.
        if kcal > 0 && !dietaryBackgroundDeliveryEnabled {
            dietaryBackgroundDeliveryEnabled = true
            enableBackgroundDelivery()
        }
        return kcal
    }

    /// Daily dietary energy (food) totals between two dates, in kilocalories.
    /// Returns one entry per day in the window (zero where no samples exist).
    func fetchDietaryHistory(days: Int) async throws -> [(date: Date, foodCalories: Double)] {
        let start = DateHelpers.daysAgo(max(days - 1, 0))
        return try await fetchDietaryHistory(from: start, to: .now)
    }

    func fetchDietaryHistory(from start: Date, to end: Date) async throws -> [(date: Date, foodCalories: Double)] {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return [] }
        #endif
        let normalizedStart = DateHelpers.startOfDay(start)
        let endNormalized = DateHelpers.startOfDay(end)
        let queryEnd = Calendar.current.date(byAdding: .day, value: 1, to: endNormalized) ?? endNormalized
        let interval = DateComponents(day: 1)
        let map = try await queryStatisticsCollection(.dietaryEnergyConsumed, unit: .kilocalorie(), start: normalizedStart, end: queryEnd, interval: interval)

        var results: [(date: Date, foodCalories: Double)] = []
        var current = normalizedStart
        while current < queryEnd {
            results.append((date: current, foodCalories: statisticValue(map, for: current)))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return results
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
        let normalizedStart = DateHelpers.startOfDay(start)
        // Include today by pushing end to tomorrow's start
        let endNormalized = DateHelpers.startOfDay(end)
        let queryEnd = Calendar.current.date(byAdding: .day, value: 1, to: endNormalized) ?? endNormalized
        let interval = DateComponents(day: 1)

        async let activeMap = queryStatisticsCollection(.activeEnergyBurned, unit: .kilocalorie(), start: normalizedStart, end: queryEnd, interval: interval)
        async let restingMap = queryStatisticsCollection(.basalEnergyBurned, unit: .kilocalorie(), start: normalizedStart, end: queryEnd, interval: interval)
        async let stepsMap = queryStatisticsCollection(.stepCount, unit: .count(), start: normalizedStart, end: queryEnd, interval: interval)

        let (active, resting, steps) = try await (activeMap, restingMap, stepsMap)

        var results: [(date: Date, active: Double, resting: Double, steps: Int)] = []
        var current = normalizedStart
        while current < queryEnd {
            results.append((
                date: current,
                active: statisticValue(active, for: current),
                resting: statisticValue(resting, for: current),
                steps: Int(statisticValue(steps, for: current))
            ))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return results
    }

    /// Stable energy reference figures averaged over recent completed days.
    /// `tdee` = average full-day total burn (active + resting) ≈ maintenance calories.
    /// `bmr`  = average full-day resting burn ≈ basal metabolic rate.
    /// Both nil until `sampleDays` clears the minimum.
    struct EnergyAverages: Sendable {
        let tdee: Double?
        let bmr: Double?
        let sampleDays: Int
    }

    /// Average maintenance (TDEE) and resting (BMR) energy over the last `days`
    /// completed days. Today is excluded (partial), and days where resting energy
    /// is 0 are dropped as non-wear so a few watch-off days can't drag the figure
    /// down. Returns nil values until at least `minSamples` valid days exist.
    func fetchEnergyAverages(days: Int = 30, minSamples: Int = 7) async throws -> EnergyAverages {
        // Pull one extra day so excluding today still leaves a full window.
        let history = try await fetchHistory(days: days + 1)
        let today = DateHelpers.startOfDay(.now)
        let valid = history.filter { DateHelpers.startOfDay($0.date) < today && $0.resting > 0 }
        guard valid.count >= minSamples else {
            return EnergyAverages(tdee: nil, bmr: nil, sampleDays: valid.count)
        }
        let count = Double(valid.count)
        let bmr = valid.reduce(0.0) { $0 + $1.resting } / count
        let tdee = valid.reduce(0.0) { $0 + $1.active + $1.resting } / count
        return EnergyAverages(tdee: tdee, bmr: bmr, sampleDays: valid.count)
    }

    /// WatchOS-only helper: merge HealthKit history with the shared SwiftData cache.
    /// The paired iPhone populates this cache with full historical data; the watch's
    /// local HealthKit store may only contain a subset, so cached entries take priority.
    func fetchMergedHistory(days: Int) async throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let healthKitHistory = try await fetchHistory(days: days)
        let cachedHistory = try? fetchCachedHistory(days: days)
        guard let cachedHistory, !cachedHistory.isEmpty else { return healthKitHistory }

        var merged = healthKitHistory
        let cachedDict = Dictionary(uniqueKeysWithValues: cachedHistory.map {
            (DailyHealthRecord.key(for: $0.date), $0)
        })
        for (index, day) in merged.enumerated() {
            let key = DailyHealthRecord.key(for: day.date)
            if let cached = cachedDict[key], cached.active > 0 || cached.resting > 0 {
                merged[index] = cached
            }
        }
        return merged
    }

    // MARK: - Pacing (usual progress at this time of day)

    func fetchPacing(comparison: PacingComparison, lookback: PacingLookback) async throws -> PacingResult {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            return ScreenshotFixtures.pacing()
        }
        #endif
        let calendar = Calendar.current
        let now = Date.now
        let currentHour = calendar.component(.hour, from: now)

        // Too early in the day for meaningful pacing
        guard currentHour >= 6 else {
            healthKitLogger.debug("fetchPacing: skipped (before 6:00)")
            return PacingResult(avgCalories: nil, avgSteps: nil, calorieSampleDays: 0, stepSampleDays: 0)
        }

        let lookbackDays = lookback.rawValue
        let today = calendar.startOfDay(for: now)
        guard let windowStartDate = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else {
            return PacingResult(avgCalories: nil, avgSteps: nil, calorieSampleDays: 0, stepSampleDays: 0)
        }
        let windowStart = calendar.startOfDay(for: windowStartDate)
        let targetWeekday = calendar.component(.weekday, from: now)

        let interval = DateComponents(day: 1)

        async let activeMap = queryStatisticsCollection(.activeEnergyBurned, unit: .kilocalorie(), start: windowStart, end: today, interval: interval)
        async let restingMap = queryStatisticsCollection(.basalEnergyBurned, unit: .kilocalorie(), start: windowStart, end: today, interval: interval)
        async let stepsMap = queryStatisticsCollection(.stepCount, unit: .count(), start: windowStart, end: today, interval: interval)

        let (active, resting, steps) = try await (activeMap, restingMap, stepsMap)

        let secondsSoFar = now.timeIntervalSince(today)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        let totalSecondsToday = endOfToday.timeIntervalSince(today)
        let dayFraction = min(secondsSoFar / totalSecondsToday, 1.0)

        var calorieWeighted = 0.0
        var stepWeighted = 0.0
        var calorieFullDay = 0.0
        var stepFullDay = 0.0
        var calorieSampleDays = 0
        var stepSampleDays = 0

        for dayOffset in 1...lookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            if comparison == .dayOfWeek, calendar.component(.weekday, from: dayStart) != targetWeekday {
                continue
            }

            let dayCal = statisticValue(active, for: dayStart) + statisticValue(resting, for: dayStart)
            let daySteps = statisticValue(steps, for: dayStart)
            if dayCal > 0 {
                calorieSampleDays += 1
                calorieWeighted += dayCal * dayFraction
                calorieFullDay += dayCal
            }
            if daySteps > 0 {
                stepSampleDays += 1
                stepWeighted += Double(daySteps) * dayFraction
                stepFullDay += Double(daySteps)
            }
        }

        let avgCalories: Double? = calorieSampleDays > 0 ? calorieWeighted / Double(calorieSampleDays) : nil
        let avgSteps: Int? = stepSampleDays > 0 ? Int(stepWeighted / Double(stepSampleDays)) : nil
        let avgCaloriesFullDay: Double? = calorieSampleDays > 0 ? calorieFullDay / Double(calorieSampleDays) : nil
        let avgStepsFullDay: Int? = stepSampleDays > 0 ? Int(stepFullDay / Double(stepSampleDays)) : nil

        healthKitLogger.debug(
            "fetchPacing: comparison=\(String(describing: comparison), privacy: .public) lookbackDays=\(lookbackDays, privacy: .public) calSamples=\(calorieSampleDays, privacy: .public) stepSamples=\(stepSampleDays, privacy: .public)"
        )

        return PacingResult(
            avgCalories: avgCalories,
            avgSteps: avgSteps,
            calorieSampleDays: calorieSampleDays,
            stepSampleDays: stepSampleDays,
            avgCaloriesFullDay: avgCaloriesFullDay,
            avgStepsFullDay: avgStepsFullDay
        )
    }

    // MARK: - Background Delivery

    private var pendingRefreshTask: Task<Void, Never>?
    private var installedObserverTypes: Set<String> = []

    /// UserDefaults flag: once we've successfully read dietary energy at least once,
    /// we know the user has granted access (or at least didn't deny read for it). Use
    /// that as a signal to keep the dietary observer installed across launches even
    /// when Net Deficit happens to be toggled off, so re-enabling Net Deficit later
    /// doesn't lose live updates.
    private var dietaryBackgroundDeliveryEnabled: Bool {
        get { (UserDefaults(suiteName: vitalsAppGroupID) ?? .standard).bool(forKey: "dietaryBackgroundDeliveryEnabled") }
        set { (UserDefaults(suiteName: vitalsAppGroupID) ?? .standard).set(newValue, forKey: "dietaryBackgroundDeliveryEnabled") }
    }

    func enableBackgroundDelivery() {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Core types that every user pays for — small, granted at onboarding.
        var types: [HKQuantityType] = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
        ]

        // Only register the dietary observer when we have positive signal that the
        // user cares about it (Net Deficit is on, or we've successfully read dietary
        // energy before). Otherwise the registration fails with "Authorization not
        // determined" and produces noisy logs on every launch for Net-off users.
        let includeDietary = GoalSettings.shared.showNetCalories || dietaryBackgroundDeliveryEnabled
        if includeDietary {
            types.append(HKQuantityType(.dietaryEnergyConsumed))
        }

        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, error in
                if let error {
                    healthKitLogger.error("Background delivery error for \(String(describing: type), privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }

        // Install observer queries once per type (idempotent across reentries so a
        // user flipping Net Deficit on later still gets a dietary observer without
        // duplicating the existing active/basal/step queries).
        for type in types {
            let identifier = type.identifier
            guard !installedObserverTypes.contains(identifier) else { continue }
            installedObserverTypes.insert(identifier)

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
            resolvedStats = try await fetchTodayStats()
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

        let record: DailyHealthRecord
        if let existing {
            existing.activeCalories = resolvedStats.active
            existing.restingCalories = resolvedStats.resting
            existing.steps = resolvedStats.steps
            existing.lastUpdated = .now
            record = existing
        } else {
            let newRecord = DailyHealthRecord(
                date: today,
                activeCalories: resolvedStats.active,
                restingCalories: resolvedStats.resting,
                steps: resolvedStats.steps
            )
            context.insert(newRecord)
            record = newRecord
        }

        // Keep today's food calories fresh on the same pass as the burn/step
        // stats, so Net Deficit caches and survives backgrounding exactly like
        // the other metrics. Without this, foodCalories was only ever written
        // from the foreground dashboard, so observer-driven refreshes (and the
        // widgets reading this record) saw a stale net deficit. Only read when
        // the user is actually using Net Deficit, to avoid auth noise otherwise.
        if GoalSettings.shared.showNetCalories || dietaryBackgroundDeliveryEnabled {
            if let food = try? await fetchDietaryEnergyToday() {
                record.foodCalories = food
            }
        }

        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
        healthKitLogger.info("Saved today cache and reloaded widget timelines")
    }

    func updateCachedFoodCalories(_ kcal: Double) throws {
        let context = ModelContext(DataService.sharedModelContainer)
        let todayKey = DailyHealthRecord.key(for: DateHelpers.startOfDay())
        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString == todayKey }
        )
        if let record = try context.fetch(descriptor).first {
            record.foodCalories = kcal
            record.lastUpdated = .now
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()
            healthKitLogger.info("Cached food calories: \(kcal, privacy: .public) kcal")
        }
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

    func fetchCachedHistory(days: Int) throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let start = DateHelpers.daysAgo(max(days - 1, 0))
        let end = DateHelpers.startOfDay()
        return try fetchCachedHistory(from: start, to: end)
    }

    /// Cached daily totals between `start` and `end` (inclusive of both day boundaries).
    /// Returned array fills in missing days with zeroes so callers can rely on a contiguous window.
    func fetchCachedHistory(from start: Date, to end: Date) throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let context = ModelContext(DataService.sharedModelContainer)
        let calendar = Calendar.current
        let normalizedStart = DateHelpers.startOfDay(start)
        let normalizedEnd = DateHelpers.startOfDay(end)
        let startKey = DailyHealthRecord.key(for: normalizedStart)
        let endKey = DailyHealthRecord.key(for: normalizedEnd)

        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString >= startKey && $0.dateString <= endKey },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let records = try context.fetch(descriptor)
        let recordDict = Dictionary(uniqueKeysWithValues: records.map { (DailyHealthRecord.key(for: $0.date), $0) })

        var results: [(date: Date, active: Double, resting: Double, steps: Int)] = []
        var current = normalizedStart
        while current <= normalizedEnd {
            let key = DailyHealthRecord.key(for: current)
            if let record = recordDict[key] {
                results.append((date: record.date, active: record.activeCalories, resting: record.restingCalories, steps: record.steps))
            } else {
                results.append((date: current, active: 0, resting: 0, steps: 0))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        healthKitLogger.info("Loaded cached history: \(results.count, privacy: .public) days from \(startKey, privacy: .public) to \(endKey, privacy: .public)")
        return results
    }

    func saveHistoryToCache(history: [(date: Date, active: Double, resting: Double, steps: Int)]) throws {
        let context = ModelContext(DataService.sharedModelContainer)
        var inserted = 0
        var updated = 0
        for day in history {
            let key = DailyHealthRecord.key(for: day.date)
            let descriptor = FetchDescriptor<DailyHealthRecord>(
                predicate: #Predicate { $0.dateString == key }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.activeCalories = day.active
                existing.restingCalories = day.resting
                existing.steps = day.steps
                existing.lastUpdated = .now
                updated += 1
            } else {
                let record = DailyHealthRecord(
                    date: day.date,
                    activeCalories: day.active,
                    restingCalories: day.resting,
                    steps: day.steps
                )
                context.insert(record)
                inserted += 1
            }
        }
        try context.save()
        healthKitLogger.info("Saved history cache: \(inserted, privacy: .public) inserted, \(updated, privacy: .public) updated")
    }

    func hasRecordedData(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        stats.active > 0 || stats.resting > 0 || stats.steps > 0
    }

    // MARK: - Private Helpers

    /// Canonical "stats row is empty" check. Views should call this instead of defining
    /// their own local `isAllZero` helpers so semantics stay in sync.
    static func isAllZero(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        stats.active == 0 && stats.resting == 0 && stats.steps == 0
    }

    private func areAllStatsZero(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        Self.isAllZero(stats)
    }

    private func statisticValue(_ map: [Date: Double], for dayStart: Date) -> Double {
        if let exact = map[dayStart] { return exact }
        let calendar = Calendar.current
        return map.first { calendar.isDate($0.key, inSameDayAs: dayStart) }?.value ?? 0
    }

    private func queryStatisticsCollection(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        interval: DateComponents
    ) async throws -> [Date: Double] {
        let store = self.store
        // Scope the underlying sample scan to [start, end) so HK doesn't have
        // to consider every sample of the type ever recorded. Use the default
        // overlap behavior (no `.strictStartDate`) so samples that cross the
        // boundary are still included — `HKStatisticsCollectionQuery` will
        // proportionally split their quantities across the day buckets based
        // on duration, which is exactly what we want for cross-midnight
        // workouts to land in the right day.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(identifier),
                quantitySamplePredicate: predicate,
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
