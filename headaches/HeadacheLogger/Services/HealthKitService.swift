import Foundation
import HealthKit

actor HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private var hasRequestedAuthorization = false

    /// Identifier exists at runtime when HealthKit exposes barometric samples; not all SDKs surface a Swift enum case.
    private static let barometricPressureIdentifier = HKQuantityTypeIdentifier(
        rawValue: "HKQuantityTypeIdentifierBarometricPressure"
    )

    private static let vo2MaxUnit = HKUnit.literUnit(with: .milli)
        .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))

    private static func buildReadTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType(),
        ]

        let extraQuantityIDs: [HKQuantityTypeIdentifier] = [
            .basalEnergyBurned,
            .environmentalAudioExposure,
            .oxygenSaturation,
            .vo2Max,
            .walkingSpeed,
            .appleStandTime,
            .flightsClimbed,
        ]
        for id in extraQuantityIDs {
            if let t = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(t)
            }
        }
        if let t = HKObjectType.quantityType(forIdentifier: barometricPressureIdentifier) {
            types.insert(t)
        }
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            types.insert(mindful)
        }
        return types
    }

    private let readTypes: Set<HKObjectType>

    private init() {
        readTypes = Self.buildReadTypes()
    }

    func captureSnapshot(at date: Date) async -> HealthCaptureResult {
        if AppEnvironment.isUITesting {
            let wake = date.addingTimeInterval(-7 * 3600)
            return HealthCaptureResult(
                status: .captured,
                message: nil,
                snapshot: HealthSnapshot(
                    stepsToday: 3456,
                    activeEnergyKcalToday: 512,
                    distanceWalkingRunningKmToday: 2.4,
                    exerciseMinutesToday: 28,
                    sleepHoursLastNight: 6.8,
                    lastMainSleepWakeTime: wake,
                    hoursSinceMainSleepWake: 7,
                    restingHeartRateBpm: 61,
                    recentHeartRateAverageBpm: 74,
                    hrvSDNNMs: 34,
                    respiratoryRateBrpm: 15,
                    workoutsLast24h: 1,
                    workoutMinutesLast24h: 32,
                    environmentalAudioExposureDbA: 42,
                    oxygenSaturationPercent: 98,
                    vo2MaxMlPerKgPerMin: 42,
                    walkingSpeedMetersPerSecond: 1.1,
                    appleStandMinutesToday: 6,
                    basalEnergyKcalToday: 1400,
                    flightsClimbedToday: 4,
                    mindfulMinutesToday: 10,
                    barometricPressureDeltaHpa6h: -0.8
                )
            )
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            return HealthCaptureResult(
                status: .unavailable,
                message: "Health data is not available on this device.",
                snapshot: nil
            )
        }

        if HeadacheOnboardingStore.declinedHealthRead {
            return HealthCaptureResult(
                status: .unavailable,
                message: "Apple Health access was turned off during setup. You can enable it in Settings › Privacy › Health.",
                snapshot: nil
            )
        }

        do {
            try await requestAuthorizationIfNeeded()

            let dayStart = Calendar.current.startOfDay(for: date)

            async let steps = cumulativeSum(
                identifier: .stepCount,
                unit: .count(),
                start: dayStart,
                end: date
            )
            async let activeEnergy = cumulativeSum(
                identifier: .activeEnergyBurned,
                unit: .kilocalorie(),
                start: dayStart,
                end: date
            )
            async let basalEnergy = optionalCumulativeSum(
                identifier: .basalEnergyBurned,
                unit: .kilocalorie(),
                start: dayStart,
                end: date
            )
            async let distance = cumulativeSum(
                identifier: .distanceWalkingRunning,
                unit: .meterUnit(with: .kilo),
                start: dayStart,
                end: date
            )
            async let exercise = cumulativeSum(
                identifier: .appleExerciseTime,
                unit: .minute(),
                start: dayStart,
                end: date
            )
            async let sleepContext = sleepContextBefore(date: date)
            async let restingHeartRate = latestQuantity(
                identifier: .restingHeartRate,
                unit: .count().unitDivided(by: .minute()),
                lookbackDays: 7,
                relativeTo: date
            )
            async let recentHeartRate = averageQuantity(
                identifier: .heartRate,
                unit: .count().unitDivided(by: .minute()),
                hoursBack: 6,
                relativeTo: date
            )
            async let hrv = latestQuantity(
                identifier: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                lookbackDays: 7,
                relativeTo: date
            )
            async let respiratory = latestQuantity(
                identifier: .respiratoryRate,
                unit: .count().unitDivided(by: .minute()),
                lookbackDays: 7,
                relativeTo: date
            )
            async let workouts = workoutSummary(relativeTo: date)
            async let standMinutes = optionalCumulativeSum(
                identifier: .appleStandTime,
                unit: .minute(),
                start: dayStart,
                end: date
            )
            async let flights = optionalCumulativeSum(
                identifier: .flightsClimbed,
                unit: .count(),
                start: dayStart,
                end: date
            )
            async let vo2 = optionalLatestQuantity(
                identifier: .vo2Max,
                unit: Self.vo2MaxUnit,
                lookbackDays: 90,
                relativeTo: date
            )
            async let walkingSpeed = optionalLatestQuantity(
                identifier: .walkingSpeed,
                unit: HKUnit.meter().unitDivided(by: HKUnit.second()),
                lookbackDays: 30,
                relativeTo: date
            )
            async let oxygen = optionalLatestOxygenPercent(relativeTo: date)
            async let envAudio = optionalAverageEnvironmentalAudio(hoursBack: 6, relativeTo: date)
            async let baroDelta = optionalBarometricDeltaHpa(hoursBack: 6, relativeTo: date)
            async let mindful = optionalMindfulMinutesToday(relativeTo: date)

            let resolvedSteps = try await steps
            let resolvedActiveEnergy = try await activeEnergy
            let resolvedDistance = try await distance
            let resolvedExercise = try await exercise
            let resolvedSleepContext = try await sleepContext
            let resolvedRestingHeartRate = try await restingHeartRate
            let resolvedRecentHeartRate = try await recentHeartRate
            let resolvedHRV = try await hrv
            let resolvedRespiratory = try await respiratory
            let resolvedWorkouts = try await workouts

            let resolvedBasalEnergy = await basalEnergy
            let resolvedStandMinutes = await standMinutes
            let resolvedFlights = await flights
            let resolvedVo2 = await vo2
            let resolvedWalkingSpeed = await walkingSpeed
            let resolvedOxygen = await oxygen
            let resolvedEnvAudio = await envAudio
            let resolvedBaroDelta = await baroDelta
            let resolvedMindful = await mindful

            let (resolvedSleepHours, wakeTime) = resolvedSleepContext
            let hoursSinceWake: Double? = {
                guard let wakeTime, wakeTime < date else { return nil }
                return date.timeIntervalSince(wakeTime) / 3600
            }()

            let snapshot = HealthSnapshot(
                stepsToday: Int(resolvedSteps),
                activeEnergyKcalToday: resolvedActiveEnergy,
                distanceWalkingRunningKmToday: resolvedDistance,
                exerciseMinutesToday: resolvedExercise,
                sleepHoursLastNight: resolvedSleepHours,
                lastMainSleepWakeTime: wakeTime,
                hoursSinceMainSleepWake: hoursSinceWake,
                restingHeartRateBpm: resolvedRestingHeartRate,
                recentHeartRateAverageBpm: resolvedRecentHeartRate,
                hrvSDNNMs: resolvedHRV,
                respiratoryRateBrpm: resolvedRespiratory,
                workoutsLast24h: resolvedWorkouts.count,
                workoutMinutesLast24h: resolvedWorkouts.minutes,
                environmentalAudioExposureDbA: resolvedEnvAudio,
                oxygenSaturationPercent: resolvedOxygen,
                vo2MaxMlPerKgPerMin: resolvedVo2,
                walkingSpeedMetersPerSecond: resolvedWalkingSpeed,
                appleStandMinutesToday: resolvedStandMinutes,
                basalEnergyKcalToday: resolvedBasalEnergy,
                flightsClimbedToday: resolvedFlights,
                mindfulMinutesToday: resolvedMindful,
                barometricPressureDeltaHpa6h: resolvedBaroDelta
            )

            let status: CaptureSourceStatus = snapshot.hasMeaningfulValue ? .captured : .unavailable
            let message: String? = status == .captured ? nil : "No Health context was available for this event."
            return HealthCaptureResult(status: status, message: message, snapshot: snapshot)
        } catch {
            return HealthCaptureResult(
                status: .failed,
                message: error.localizedDescription,
                snapshot: nil
            )
        }
    }

    /// Call from onboarding so the first “Headache” tap does not show the Health permission sheet mid-capture.
    func prepareAuthorizationDuringOnboarding() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard !HeadacheOnboardingStore.declinedHealthRead else {
            hasRequestedAuthorization = true
            return
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        hasRequestedAuthorization = true
    }

    /// User chose not to connect Health during onboarding — skip future authorization prompts during capture.
    func markHealthSkippedInOnboarding() {
        hasRequestedAuthorization = true
    }

    private func requestAuthorizationIfNeeded() async throws {
        if HeadacheOnboardingStore.declinedHealthRead {
            return
        }
        guard !hasRequestedAuthorization else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        hasRequestedAuthorization = true
    }

    private func cumulativeSum(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double {
        let store = self.store
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKObjectType.quantityType(forIdentifier: identifier)!,
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

    private func optionalCumulativeSum(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard HKObjectType.quantityType(forIdentifier: identifier) != nil else { return nil }
        do {
            return try await cumulativeSum(identifier: identifier, unit: unit, start: start, end: end)
        } catch {
            return nil
        }
    }

    private func latestQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        lookbackDays: Int,
        relativeTo date: Date
    ) async throws -> Double? {
        let store = self.store
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: date) ?? date.addingTimeInterval(-86400 * Double(lookbackDays))
        let predicate = HKQuery.predicateForSamples(withStart: start, end: date, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKObjectType.quantityType(forIdentifier: identifier)!,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func optionalLatestQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        lookbackDays: Int,
        relativeTo date: Date
    ) async -> Double? {
        guard HKObjectType.quantityType(forIdentifier: identifier) != nil else { return nil }
        do {
            return try await latestQuantity(identifier: identifier, unit: unit, lookbackDays: lookbackDays, relativeTo: date)
        } catch {
            return nil
        }
    }

    private func optionalLatestOxygenPercent(relativeTo date: Date) async -> Double? {
        guard HKObjectType.quantityType(forIdentifier: .oxygenSaturation) != nil else { return nil }
        do {
            guard let raw = try await latestQuantity(
                identifier: .oxygenSaturation,
                unit: .percent(),
                lookbackDays: 7,
                relativeTo: date
            ) else { return nil }
            return raw <= 1.0 ? raw * 100.0 : raw
        } catch {
            return nil
        }
    }

    private func averageQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        hoursBack: Int,
        relativeTo date: Date
    ) async throws -> Double? {
        let store = self.store
        let start = Calendar.current.date(byAdding: .hour, value: -hoursBack, to: date) ?? date.addingTimeInterval(-3600 * Double(hoursBack))
        let predicate = HKQuery.predicateForSamples(withStart: start, end: date, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.quantityType(forIdentifier: identifier)!,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let values = (samples as? [HKQuantitySample] ?? [])
                    .map { $0.quantity.doubleValue(for: unit) }
                guard !values.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let avg = values.reduce(0, +) / Double(values.count)
                continuation.resume(returning: avg)
            }
            store.execute(query)
        }
    }

    private func optionalAverageEnvironmentalAudio(hoursBack: Int, relativeTo date: Date) async -> Double? {
        guard HKObjectType.quantityType(forIdentifier: .environmentalAudioExposure) != nil else { return nil }
        let unit = HKUnit.decibelAWeightedSoundPressureLevel()
        do {
            return try await averageQuantity(
                identifier: .environmentalAudioExposure,
                unit: unit,
                hoursBack: hoursBack,
                relativeTo: date
            )
        } catch {
            return nil
        }
    }

    private func optionalBarometricDeltaHpa(hoursBack: Int, relativeTo date: Date) async -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: Self.barometricPressureIdentifier) else { return nil }
        let store = self.store
        let start = Calendar.current.date(byAdding: .hour, value: -hoursBack, to: date) ?? date.addingTimeInterval(-3600 * Double(hoursBack))
        let predicate = HKQuery.predicateForSamples(withStart: start, end: date, options: .strictStartDate)
        let hpa = HKUnit(from: "hPa")

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                let qs = (samples as? [HKQuantitySample]) ?? []
                guard qs.count >= 2,
                      let first = qs.first?.quantity.doubleValue(for: hpa),
                      let last = qs.last?.quantity.doubleValue(for: hpa) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: last - first)
            }
            store.execute(query)
        }
    }

    private func optionalMindfulMinutesToday(relativeTo date: Date) async -> Double? {
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return nil }
        let store = self.store
        let start = Calendar.current.startOfDay(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: date, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                let cats = (samples as? [HKCategorySample]) ?? []
                let seconds = cats.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                guard seconds > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: seconds / 60.0)
            }
            store.execute(query)
        }
    }

    /// Sleep hours in the standard window plus wake time from the longest merged asleep block.
    private func sleepContextBefore(date: Date) async throws -> (hours: Double?, wakeTime: Date?) {
        let store = self.store
        let calendar = Calendar.current
        let end = date
        let previousNoon = calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86400)
        ) ?? date.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(withStart: previousNoon, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]

                let asleepSamples = (samples as? [HKCategorySample] ?? []).filter { asleepValues.contains($0.value) }
                let intervals = asleepSamples.map {
                    SleepIntervalMerge.Interval(start: $0.startDate, end: $0.endDate)
                }
                let merged = SleepIntervalMerge.merge(intervals, mergeGap: 45 * 60)
                let totalSeconds = merged.reduce(0.0) { $0 + $1.duration }
                let wake = SleepIntervalMerge.wakeTimeAfterLongestSleep(merged)

                guard totalSeconds > 0 else {
                    continuation.resume(returning: (nil, wake))
                    return
                }

                continuation.resume(returning: (totalSeconds / 3600, wake))
            }
            store.execute(query)
        }
    }

    private func workoutSummary(relativeTo date: Date) async throws -> (count: Int?, minutes: Double?) {
        let store = self.store
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: date) ?? date.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: date, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = samples as? [HKWorkout] ?? []
                guard !workouts.isEmpty else {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                let minutes = workouts.reduce(0.0) { $0 + $1.duration / 60 }
                continuation.resume(returning: (workouts.count, minutes))
            }
            store.execute(query)
        }
    }
}

private extension HealthSnapshot {
    var hasMeaningfulValue: Bool {
        stepsToday != nil ||
        activeEnergyKcalToday != nil ||
        distanceWalkingRunningKmToday != nil ||
        exerciseMinutesToday != nil ||
        sleepHoursLastNight != nil ||
        lastMainSleepWakeTime != nil ||
        hoursSinceMainSleepWake != nil ||
        restingHeartRateBpm != nil ||
        recentHeartRateAverageBpm != nil ||
        hrvSDNNMs != nil ||
        respiratoryRateBrpm != nil ||
        workoutsLast24h != nil ||
        workoutMinutesLast24h != nil ||
        environmentalAudioExposureDbA != nil ||
        oxygenSaturationPercent != nil ||
        vo2MaxMlPerKgPerMin != nil ||
        walkingSpeedMetersPerSecond != nil ||
        appleStandMinutesToday != nil ||
        basalEnergyKcalToday != nil ||
        flightsClimbedToday != nil ||
        mindfulMinutesToday != nil ||
        barometricPressureDeltaHpa6h != nil
    }
}
