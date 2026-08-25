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

    /// Macronutrients, written to Health by the same food apps that write
    /// dietary energy. HealthKit grants reads per type, so authorizing
    /// `dietaryEnergyConsumed` says nothing about these; they must be asked for.
    private let macroReadTypes: Set<HKObjectType> = [
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
    ]

    /// Body Profile reads are requested separately (and only on explicit user
    /// action) so the core onboarding sheet keeps asking for just the three
    /// energy/step types. Mixing new read types into an existing request can
    /// silently suppress the HealthKit permission sheet — the same quirk the
    /// dietary energy flow already works around.
    private let bodyProfileBaseReadTypes: Set<HKObjectType> = [
        HKQuantityType(.height),
        HKQuantityType(.bodyMass),
    ]
    private let bodyFatReadType: HKObjectType = HKQuantityType(.bodyFatPercentage)
    private var bodyProfileReadTypes: Set<HKObjectType> {
        bodyProfileBaseReadTypes.union([bodyFatReadType])
    }

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

    /// The first and, for most people, only HealthKit prompt.
    ///
    /// `includeFood` folds dietary energy and the three macronutrients into the
    /// same sheet, which onboarding uses when the user has said they log food.
    /// One sheet is safe here specifically because nothing is authorized yet:
    /// the quirk that suppresses a prompt needs an already-determined type in
    /// the request, and at first launch there are none. Everywhere else in the
    /// app the food types must still be asked for on their own — see
    /// `requestDietaryAuthorization` and `requestMacroAuthorization`.
    func requestAuthorization(includeFood: Bool = false) async throws {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let readTypes = includeFood
            ? baseReadTypes.union(macroReadTypes).union([dietaryReadType])
            : baseReadTypes
        healthKitLogger.info(
            "Requesting HealthKit authorization for \(readTypes.count, privacy: .public) read types includeFood=\(includeFood, privacy: .public)"
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

    /// Request authorization for the food types only. Calling this separately avoids a
    /// HealthKit quirk where mixing already-authorized types with new ones can silently
    /// suppress the permission sheet (especially when called shortly after a prior auth).
    ///
    /// Asks for dietary energy *and* the macros in one sheet: they come from the same
    /// food app, and a user who grants food access once shouldn't be re-prompted when
    /// they later turn Macros on. Users who already granted energy on an older build
    /// get `requestMacroAuthorization` instead, which asks only for the new types.
    func requestDietaryAuthorization() async throws {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthKitLogger.info("Requesting HealthKit authorization for dietary energy + macros")
        do {
            try await store.requestAuthorization(toShare: [], read: macroReadTypes.union([dietaryReadType]))
            enableBackgroundDelivery()
            healthKitLogger.info("Dietary authorization request completed")
        } catch {
            healthKitLogger.error("Dietary authorization request failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Request authorization for the three macronutrient types only. Kept separate
    /// from `requestDietaryAuthorization` for the upgrade path: a user who granted
    /// dietary energy on an earlier build has that type already determined, and
    /// bundling a determined type with undetermined ones is exactly the case that
    /// can suppress the permission sheet.
    func requestMacroAuthorization() async throws {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthKitLogger.info("Requesting HealthKit authorization for macros only")
        do {
            try await store.requestAuthorization(toShare: [], read: macroReadTypes)
            enableBackgroundDelivery()
            healthKitLogger.info("Macro authorization request completed")
        } catch {
            healthKitLogger.error("Macro authorization request failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }


    /// Request authorization for the Body Profile types only (height, body mass,
    /// body-fat). Requested separately from the core types — see
    /// `bodyProfileReadTypes`. Does not flip `isAuthorized`, which tracks core
    /// energy/step access.
    func requestBodyProfileAuthorization(includeBodyFat: Bool = true) async throws {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let readTypes = includeBodyFat
            ? bodyProfileReadTypes
            : bodyProfileBaseReadTypes
        healthKitLogger.info(
            "Requesting HealthKit authorization for \(readTypes.count, privacy: .public) body profile read types includeBodyFat=\(includeBodyFat, privacy: .public)"
        )
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            healthKitLogger.info("Body profile authorization request completed")
        } catch {
            healthKitLogger.error("Body profile authorization request failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func authorizationRequestStatus(
        includeDietaryEnergy: Bool = false,
        includeMacros: Bool = false,
        includeBodyProfile: Bool = false
    ) async -> HKAuthorizationRequestStatus? {
        if ScreenshotConfig.isEnabled {
            return .unnecessary
        }
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        var readTypes = baseReadTypes
        if includeDietaryEnergy { readTypes.formUnion([dietaryReadType]) }
        if includeMacros { readTypes.formUnion(macroReadTypes) }
        if includeBodyProfile { readTypes.formUnion(bodyProfileReadTypes) }

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
                try await requestAuthorization(includeFood: false)
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
        let dayStart = DateHelpers.startOfDay()
        let now = Date.now

        // Energy is required; steps are best-effort. A user (or the lab harness)
        // can grant Active/Resting while leaving Steps off — that must not blank
        // the whole Today total with `Authorization not determined`.
        async let active = queryElapsedTotal(.activeEnergyBurned, unit: .kilocalorie(), dayStart: dayStart, now: now)
        async let resting = queryElapsedTotal(.basalEnergyBurned, unit: .kilocalorie(), dayStart: dayStart, now: now)
        async let steps = queryElapsedTotalIfAuthorized(.stepCount, unit: .count(), dayStart: dayStart, now: now)

        let (activeToday, restingToday, stepsToday) = try await (active, resting, steps)

        return (
            active: activeToday,
            resting: restingToday,
            steps: Int(stepsToday)
        )
    }

    /// Dietary energy (food) logged for today in Health, in kilocalories (e.g. from MyFitnessPal).
    func fetchDietaryEnergyToday() async throws -> Double {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            return ScreenshotFixtures.dietaryEnergyToday()
        }
        #endif
        let dayStart = DateHelpers.startOfDay()
        let interval = DateComponents(day: 1)
        let map = try await queryStatisticsCollection(.dietaryEnergyConsumed, unit: .kilocalorie(), start: dayStart, end: .now, interval: interval)
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
        let queryEnd = DateHelpers.healthQueryEnd(including: endNormalized)
        let interval = DateComponents(day: 1)
        // Food is logged as instants, not as ongoing samples, so there is no
        // in-progress quantity to prorate — the default predicate is correct here.
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

    /// Macronutrient grams logged for today in Health (e.g. from MyFitnessPal).
    ///
    /// All three types are queried concurrently and a failure on any one is fatal
    /// to the call: a partial read would render as "0 g fat" and look like the
    /// user ate no fat, which is worse than showing the unavailable state.
    func fetchMacrosToday() async throws -> MacroTotals {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            return ScreenshotFixtures.macrosToday()
        }
        #endif
        let dayStart = DateHelpers.startOfDay()
        let interval = DateComponents(day: 1)
        async let protein = queryStatisticsCollection(.dietaryProtein, unit: .gram(), start: dayStart, end: .now, interval: interval)
        async let carbs = queryStatisticsCollection(.dietaryCarbohydrates, unit: .gram(), start: dayStart, end: .now, interval: interval)
        async let fat = queryStatisticsCollection(.dietaryFatTotal, unit: .gram(), start: dayStart, end: .now, interval: interval)

        let (proteinMap, carbMap, fatMap) = try await (protein, carbs, fat)
        let totals = MacroTotals(
            protein: statisticValue(proteinMap, for: dayStart),
            carbs: statisticValue(carbMap, for: dayStart),
            fat: statisticValue(fatMap, for: dayStart)
        )
        healthKitLogger.debug("fetchMacrosToday: P\(totals.protein, privacy: .public) C\(totals.carbs, privacy: .public) F\(totals.fat, privacy: .public)")
        // Same positive-signal trick as dietary energy: HealthKit never reports
        // read authorization, so the first non-zero read is how we learn the
        // macro observers are worth installing on future launches.
        if totals.hasData && !macroBackgroundDeliveryEnabled {
            macroBackgroundDeliveryEnabled = true
            enableBackgroundDelivery()
        }
        return totals
    }

    /// Daily macro totals between two dates. One entry per day in the window,
    /// zero-filled where no food was logged (callers filter on `hasData`).
    func fetchMacroHistory(days: Int) async throws -> [(date: Date, macros: MacroTotals)] {
        let start = DateHelpers.daysAgo(max(days - 1, 0))
        return try await fetchMacroHistory(from: start, to: .now)
    }

    func fetchMacroHistory(from start: Date, to end: Date) async throws -> [(date: Date, macros: MacroTotals)] {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            let dayCount = max(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0, 30)
            return ScreenshotFixtures.macroHistory(days: dayCount, end: end)
        }
        #endif
        let normalizedStart = DateHelpers.startOfDay(start)
        let endNormalized = DateHelpers.startOfDay(end)
        let queryEnd = DateHelpers.healthQueryEnd(including: endNormalized)
        let interval = DateComponents(day: 1)
        // Food is logged as instants, so the default predicate is correct here,
        // same reasoning as `fetchDietaryHistory`.
        async let proteinMap = queryStatisticsCollection(.dietaryProtein, unit: .gram(), start: normalizedStart, end: queryEnd, interval: interval)
        async let carbMap = queryStatisticsCollection(.dietaryCarbohydrates, unit: .gram(), start: normalizedStart, end: queryEnd, interval: interval)
        async let fatMap = queryStatisticsCollection(.dietaryFatTotal, unit: .gram(), start: normalizedStart, end: queryEnd, interval: interval)
        let (protein, carbs, fat) = try await (proteinMap, carbMap, fatMap)

        var results: [(date: Date, macros: MacroTotals)] = []
        var current = normalizedStart
        while current < queryEnd {
            results.append((
                date: current,
                macros: MacroTotals(
                    protein: statisticValue(protein, for: current),
                    carbs: statisticValue(carbs, for: current),
                    fat: statisticValue(fat, for: current)
                )
            ))
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
        // Completed days end at the next midnight; a range containing today stops
        // at the current instant so partial duration samples cannot include the future.
        let endNormalized = DateHelpers.startOfDay(end)
        let queryEnd = DateHelpers.healthQueryEnd(including: endNormalized)
        let includesToday = endNormalized >= DateHelpers.startOfDay()
        let interval = DateComponents(day: 1)

        // Completed days are correct with the default predicate: a sample that
        // straddles midnight is split between the days it actually covers.
        async let activeMap = queryStatisticsCollection(.activeEnergyBurned, unit: .kilocalorie(), start: normalizedStart, end: queryEnd, interval: interval)
        async let restingMap = queryStatisticsCollection(.basalEnergyBurned, unit: .kilocalorie(), start: normalizedStart, end: queryEnd, interval: interval)
        async let stepsMap = queryStatisticsCollection(.stepCount, unit: .count(), start: normalizedStart, end: queryEnd, interval: interval)

        let (active, resting, steps) = try await (activeMap, restingMap, stepsMap)

        // Today's calendar-day bucket would include the not-yet-elapsed part of any
        // sample still in progress. Take today's row from the same call the Today
        // screen uses, so History, the widgets (via `saveHistoryToCache`) and Today
        // can't disagree by construction.
        let todayStats = includesToday ? try await fetchTodayStats() : nil

        let calendar = Calendar.current
        var results: [(date: Date, active: Double, resting: Double, steps: Int)] = []
        var current = normalizedStart
        while current < queryEnd {
            if let todayStats, calendar.isDateInToday(current) {
                results.append((
                    date: current,
                    active: todayStats.active,
                    resting: todayStats.resting,
                    steps: todayStats.steps
                ))
            } else {
                results.append((
                    date: current,
                    active: statisticValue(active, for: current),
                    resting: statisticValue(resting, for: current),
                    steps: Int(statisticValue(steps, for: current))
                ))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return results
    }

    typealias EnergyAverages = EnergyAveragesResult

    /// Average maintenance (TDEE) and resting (BMR) energy over the last `days`
    /// completed days. Today is excluded (partial), and days where resting energy
    /// is 0 are dropped as non-wear so a few watch-off days can't drag the figure
    /// down. Returns nil values until at least `minSamples` valid days exist.
    /// Shares its math with the widget via `EnergyAveragesCalculator`.
    ///
    /// Only queries active + resting energy — steps aren't part of TDEE/BMR, so
    /// a missing Steps grant must not block the Maintenance figure.
    func fetchEnergyAverages(days: Int = 30, minSamples: Int = 7) async throws -> EnergyAverages {
#if DEBUG
        if ScreenshotConfig.isEnabled, ScreenshotConfig.scene == .premiumDashboard {
            return ScreenshotFixtures.energyAverages()
        }
#endif
        // Pull one extra day so excluding today still leaves a full window.
        let start = DateHelpers.daysAgo(max(days, 0))
        let end = Date.now
        let normalizedStart = DateHelpers.startOfDay(start)
        let endNormalized = DateHelpers.startOfDay(end)
        let queryEnd = DateHelpers.healthQueryEnd(including: endNormalized)
        let interval = DateComponents(day: 1)

        // Only completed days feed the average (see `EnergyAveragesCalculator`),
        // so today's partial bucket is discarded downstream and the default
        // predicate is what keeps midnight-straddling samples on the right day.
        async let activeMap = queryStatisticsCollection(.activeEnergyBurned, unit: .kilocalorie(), start: normalizedStart, end: queryEnd, interval: interval)
        async let restingMap = queryStatisticsCollection(.basalEnergyBurned, unit: .kilocalorie(), start: normalizedStart, end: queryEnd, interval: interval)
        let (active, resting) = try await (activeMap, restingMap)

        var records: [(date: Date, active: Double, resting: Double)] = []
        var current = normalizedStart
        while current < queryEnd {
            records.append((
                date: current,
                active: statisticValue(active, for: current),
                resting: statisticValue(resting, for: current)
            ))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return EnergyAveragesCalculator.compute(
            records: records,
            referenceDate: .now,
            minSamples: minSamples
        )
    }

    /// WatchOS-only helper: merge HealthKit history with the shared SwiftData cache.
    /// The paired iPhone populates this cache with full historical data; the watch's
    /// local HealthKit store may only contain a subset, so cached entries take priority.
    func fetchMergedHistory(days: Int) async throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let healthKitHistory = try await fetchHistory(days: days)
        let cachedHistory = try? fetchCachedHistory(days: days)
        guard let cachedHistory, !cachedHistory.isEmpty else { return healthKitHistory }

        var merged = healthKitHistory
        let cachedDict = Dictionary(
            cachedHistory.map { (DailyHealthRecord.key(for: $0.date), $0) },
            uniquingKeysWith: { _, rhs in rhs }
        )
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

    // MARK: - Body Profile

    /// Most-recent height, body mass, and body-fat samples from Apple Health,
    /// normalized to metric storage units (meters, kilograms, percent 0–100).
    /// Any field is nil when no sample exists or the read is unauthorized — the
    /// caller can't distinguish "denied" from "absent" (HealthKit doesn't expose
    /// read auth), so the UI offers manual entry either way.
    func fetchBodyProfileFromHealth(includeBodyFat: Bool = true) async throws -> HealthBodyProfile {
        guard HKHealthStore.isHealthDataAvailable() else { return .empty }

        async let height = mostRecentQuantity(.height, unit: .meter())
        async let weight = mostRecentQuantity(.bodyMass, unit: .gramUnit(with: .kilo))

        let (h, w) = await (height, weight)
        let bf = includeBodyFat
            ? await mostRecentQuantity(.bodyFatPercentage, unit: .percent())
            : nil
        // HealthKit body fat is stored as a fraction (0.20 == 20%); convert to a
        // 0–100 percent for storage/display so callers never re-derive the scale.
        let bodyFatPercent = bf.map { $0 * 100 }

        healthKitLogger.info(
            "fetchBodyProfileFromHealth: height=\(h != nil, privacy: .public) weight=\(w != nil, privacy: .public) bodyFat=\(bodyFatPercent != nil, privacy: .public)"
        )

        return HealthBodyProfile(heightMeters: h, weightKilograms: w, bodyFatPercent: bodyFatPercent)
    }

    /// Fetches the latest single sample for a quantity type. Returns nil on error
    /// or when no sample exists (both indistinguishable from "not authorized" for
    /// reads), so the body-profile UI can fall back to manual entry.
    private func mostRecentQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let store = self.store
        let quantityType = HKQuantityType(identifier)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    healthKitLogger.error("mostRecentQuantity \(identifier.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
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

    /// Same signal as `dietaryBackgroundDeliveryEnabled`, for the macro types.
    private var macroBackgroundDeliveryEnabled: Bool {
        get { (UserDefaults(suiteName: vitalsAppGroupID) ?? .standard).bool(forKey: "macroBackgroundDeliveryEnabled") }
        set { (UserDefaults(suiteName: vitalsAppGroupID) ?? .standard).set(newValue, forKey: "macroBackgroundDeliveryEnabled") }
    }

    /// The calendar day `refreshCache` last wrote a today-row for. Comparing it to
    /// the current day is how a midnight rollover is detected without a timer.
    private var lastCachedDayKey: String? {
        get { (UserDefaults(suiteName: vitalsAppGroupID) ?? .standard).string(forKey: "lastCachedDayKey") }
        set { (UserDefaults(suiteName: vitalsAppGroupID) ?? .standard).set(newValue, forKey: "lastCachedDayKey") }
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

        // Macros ride the same "only when the user cares" rule. Protein alone is
        // enough of an observer: food apps write all three macros in the same
        // save, so one type firing means the whole day's macros just changed.
        // Registering three observers would just triple the wakeups for nothing.
        if GoalSettings.shared.showMacros || macroBackgroundDeliveryEnabled {
            types.append(HKQuantityType(.dietaryProtein))
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

    /// Finalizes the day that just ended, the first time anything refreshes after
    /// local midnight.
    ///
    /// `refreshCache` only ever writes a row for the *current* day, so at 00:00 the
    /// day that just ended is frozen at whatever partial snapshot it happened to
    /// hold — and it immediately becomes the newest completed day in the
    /// Maintenance/TDEE widget's window, dragging that average below the in-app
    /// figure. Rather than a timer, the rollover is detected by comparing the day
    /// of the last write against today: HealthKit background delivery wakes the app
    /// within minutes of midnight as fresh basal samples land, so the finalize runs
    /// without the user opening anything. Also covers travel across timezones and
    /// any gap where the device was off overnight.
    ///
    /// Best effort by design: a failure here must not stop today's cache write.
    /// Skipped on watchOS, where the observer callback runs under a tight CPU
    /// budget and a multi-day history fetch risks the CAROUSEL watchdog.
    func finalizeDayRolloverIfNeeded() async {
        #if os(watchOS)
        return
        #else
        let todayKey = DailyHealthRecord.key(for: DateHelpers.startOfDay())
        let previousKey = lastCachedDayKey
        guard previousKey != todayKey else { return }
        // First run ever: nothing stale to finalize, just record where we are.
        guard previousKey != nil else {
            lastCachedDayKey = todayKey
            return
        }
        healthKitLogger.info(
            "Day rolled over from \(previousKey ?? "-", privacy: .public) to \(todayKey, privacy: .public); finalizing completed days"
        )
        do {
            try await refreshHistoryCache()
            lastCachedDayKey = todayKey
        } catch {
            // Leave the marker alone so the next refresh retries the finalize.
            healthKitLogger.error(
                "Day-rollover finalize failed; will retry on next refresh: \(String(describing: error), privacy: .public)"
            )
        }
        #endif
    }

    func refreshCache(stats: (active: Double, resting: Double, steps: Int)? = nil) async throws {
        await finalizeDayRolloverIfNeeded()

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

        // Macros cache on the same pass, for the same reason: without it the
        // stored row only ever reflects the last foreground dashboard read.
        if GoalSettings.shared.showMacros || macroBackgroundDeliveryEnabled {
            if let macros = try? await fetchMacrosToday() {
                record.proteinGrams = macros.protein
                record.carbGrams = macros.carbs
                record.fatGrams = macros.fat
            }
        }

        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
        healthKitLogger.info("Saved today cache and reloaded widget timelines")
    }

    /// Finalizes recent *completed* days in the shared cache from live HealthKit.
    ///
    /// The today/observer path (`refreshCache`) only ever writes a partial
    /// snapshot for the *current* day. Once that day completes it stays partial
    /// in the cache until the app is next foregrounded and `saveHistoryToCache`
    /// overwrites it with the full-day total. The Maintenance/TDEE widget
    /// (`EnergyAveragesWidget`) reads *only* the cache and excludes today, so a
    /// stale partial "yesterday" made its 30-day average drift below the in-app
    /// figure (which is computed live) — the mismatch users reported. Running
    /// this from the periodic background refresh keeps the cache window in sync
    /// without requiring the user to open the app.
    ///
    /// Covers the full TDEE window (plus a small buffer) so every completed day
    /// the widget can include is finalized. `saveHistoryToCache` reloads widget
    /// timelines, so the Maintenance widget updates on the same pass.
    func refreshHistoryCache(days: Int = EnergyAveragesCalculator.windowDays + 2) async throws {
        let history = try await fetchHistory(days: days)
        try saveHistoryToCache(history: history)
        healthKitLogger.info("Refreshed \(history.count, privacy: .public)-day history cache for TDEE widget parity")
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

    func updateCachedMacros(_ macros: MacroTotals) throws {
        let context = ModelContext(DataService.sharedModelContainer)
        let todayKey = DailyHealthRecord.key(for: DateHelpers.startOfDay())
        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString == todayKey }
        )
        if let record = try context.fetch(descriptor).first {
            record.proteinGrams = macros.protein
            record.carbGrams = macros.carbs
            record.fatGrams = macros.fat
            record.lastUpdated = .now
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()
            healthKitLogger.info("Cached macros: P\(macros.protein, privacy: .public) C\(macros.carbs, privacy: .public) F\(macros.fat, privacy: .public)")
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
        // Key by the stored `dateString` (the @Attribute(.unique) key) rather than
        // recomputing `key(for: date)` at read time: a timezone/DST shift can re-bucket
        // two distinct stored rows onto the same recomputed day, and cross-process writes
        // (widget + app) can occasionally slip a true duplicate past the unique constraint.
        // Either case made `Dictionary(uniqueKeysWithValues:)` trap. Collapse collisions to
        // the freshest row instead of crashing.
        let recordDict = Dictionary(
            records.map { ($0.dateString, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.lastUpdated >= rhs.lastUpdated ? lhs : rhs }
        )

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
        WidgetCenter.shared.reloadAllTimelines()
        healthKitLogger.info("Saved history cache and reloaded widget timelines: \(inserted, privacy: .public) inserted, \(updated, privacy: .public) updated")
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

    #if DEBUG
    /// Test-only seam. `HealthKitLabHarness` needs to run the *same* bucketing
    /// code against a real `HKHealthStore` with both predicate variants so the
    /// overcount can be reproduced before it is fixed. Nothing in the shipping
    /// build references this.
    func debugDailyTotals(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        strictEnd: Bool
    ) async throws -> [Date: Double] {
        try await queryStatisticsCollection(
            identifier,
            unit: unit,
            start: start,
            end: end,
            interval: DateComponents(day: 1),
            excludeSamplesEndingAfterEnd: strictEnd
        )
    }

    /// Test-only seam for the third variant the lab compares against the other
    /// two: one bucket ending at `now`, which is what the shipping Today path
    /// uses.
    func debugElapsedTotal(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        dayStart: Date,
        now: Date
    ) async throws -> Double {
        try await queryElapsedTotal(identifier, unit: unit, dayStart: dayStart, now: now)
    }

    /// Test-only seam: the lab writes samples, so it needs the same store the
    /// queries read from.
    var debugStore: HKHealthStore { store }

    /// Test-only seam: lets the lab pretend the last cache write happened on an
    /// earlier day, so the midnight-rollover path can be exercised without
    /// waiting for (or faking) local midnight.
    func debugSetLastCachedDay(_ key: String?) {
        lastCachedDayKey = key
    }

    /// Test-only: wipe every cached day so the maintenance-cache lab scenario
    /// starts from a known-empty cache regardless of prior runs.
    func debugClearAllCachedRecords() throws {
        let context = ModelContext(DataService.sharedModelContainer)
        for record in try context.fetch(FetchDescriptor<DailyHealthRecord>()) {
            context.delete(record)
        }
        try context.save()
    }
    #endif

    /// Total for `[dayStart, now)`, using a single statistics bucket whose end is
    /// `now` rather than the next midnight.
    ///
    /// HealthKit splits a sample across bucket boundaries in proportion to how
    /// much of its duration falls inside each bucket, so a bucket that stops at
    /// `now` credits today with exactly the share that has actually elapsed.
    /// The two alternatives are both wrong for a sample still in progress:
    /// a calendar-day bucket also counts the part lying in the future (the
    /// "4,397 kcal of resting energy before lunch" report), and `.strictEndDate`
    /// throws the sample away whole, losing the part that genuinely happened.
    private func queryElapsedTotal(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        dayStart: Date,
        now: Date
    ) async throws -> Double {
        // HealthKit rejects a zero-length interval, and at the stroke of midnight
        // there is nothing elapsed to report anyway. Round up so the single
        // bucket covers the whole window with nothing left over.
        let elapsed = Int(now.timeIntervalSince(dayStart).rounded(.up))
        guard elapsed >= 1 else { return 0 }
        let map = try await queryStatisticsCollection(
            identifier,
            unit: unit,
            start: dayStart,
            end: now,
            interval: DateComponents(second: elapsed)
        )
        return statisticValue(map, for: dayStart)
    }

    /// Like `queryElapsedTotal`, but returns 0 when the type has not been
    /// authorized yet instead of failing the whole Today fetch. Energy is
    /// required; steps are best-effort, since a user (or the lab harness) can
    /// grant Active/Resting while leaving Steps off.
    private func queryElapsedTotalIfAuthorized(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        dayStart: Date,
        now: Date
    ) async -> Double {
        do {
            return try await queryElapsedTotal(identifier, unit: unit, dayStart: dayStart, now: now)
        } catch {
            healthKitLogger.error(
                "Optional \(identifier.rawValue, privacy: .public) query failed; treating as zero: \(String(describing: error), privacy: .public)"
            )
            return 0
        }
    }

    private func queryStatisticsCollection(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        interval: DateComponents,
        excludeSamplesEndingAfterEnd: Bool = false
    ) async throws -> [Date: Double] {
        let store = self.store
        // Scope the underlying sample scan to [start, end) so HK doesn't have
        // to consider every sample of the type ever recorded. Use the default
        // overlap behavior so cross-midnight samples can enter the correct day
        // bucket. Current-day queries additionally require samples to end by
        // `end`; iOS 27 beta can expose basal samples spanning beyond now, and
        // otherwise their future quantity is included in today's cumulative sum.
        let options: HKQueryOptions = excludeSamplesEndingAfterEnd ? .strictEndDate : []
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: options)
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
