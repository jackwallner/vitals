#if DEBUG
import Foundation
import HealthKit
import os

/// Writes a plausible 40-day HealthKit history so simulator walks hit the real
/// Today / History / Deep Trends / Net Deficit paths instead of screenshot
/// fixtures. Activated with `VITALS_SEED_HEALTH=1`.
enum HealthKitSeeder {
    private static let logger = Logger(subsystem: "com.jackwallner.vitals", category: "HealthKitSeeder")
    private static let markerKey = "VitalsSeededHealthSample"

    @MainActor
    static func run() async {
        guard DebugLaunchConfig.seedHealth else { return }
        let store = HealthKitService.shared.debugStore
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let basal = HKQuantityType(.basalEnergyBurned)
        let active = HKQuantityType(.activeEnergyBurned)
        let steps = HKQuantityType(.stepCount)
        let dietary = HKQuantityType(.dietaryEnergyConsumed)
        let protein = HKQuantityType(.dietaryProtein)
        let carbs = HKQuantityType(.dietaryCarbohydrates)
        let fat = HKQuantityType(.dietaryFatTotal)
        let height = HKQuantityType(.height)
        let mass = HKQuantityType(.bodyMass)

        let share: Set<HKSampleType> = [basal, active, steps, dietary, protein, carbs, fat, height, mass]
        let read: Set<HKObjectType> = share

        do {
            try await store.requestAuthorization(toShare: share, read: read)
            try await deleteMarked(in: store, types: Array(share))
            try await writeHistory(in: store, types: (
                basal: basal, active: active, steps: steps,
                dietary: dietary, protein: protein, carbs: carbs, fat: fat,
                height: height, mass: mass
            ))
            try await HealthKitService.shared.refreshCache()
            logger.info("Seeded HealthKit history and refreshed the cache")
        } catch {
            logger.error("HealthKit seed failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func writeHistory(
        in store: HKHealthStore,
        types: (
            basal: HKQuantityType, active: HKQuantityType, steps: HKQuantityType,
            dietary: HKQuantityType, protein: HKQuantityType, carbs: HKQuantityType,
            fat: HKQuantityType, height: HKQuantityType, mass: HKQuantityType
        )
    ) async throws {
        var samples: [HKQuantitySample] = []
        let now = Date.now
        let today = DateHelpers.startOfDay(now)

        samples.append(quantity(types.height, unit: .meter(), value: 1.78, start: today, end: today.addingTimeInterval(60)))
        samples.append(quantity(types.mass, unit: .gramUnit(with: .kilo), value: 82.4, start: today, end: today.addingTimeInterval(60)))

        for offset in 0...40 {
            let day = DateHelpers.daysAgo(offset)
            let isToday = offset == 0
            let wobble = sin(Double(offset) / 3.2)
            let resting = 1_620 + wobble * 40
            let activeKcal = isToday ? 420 + wobble * 30 : 520 + wobble * 160
            let stepCount = isToday ? 4_800 : 8_400 + wobble * 2_200
            let food = isToday ? 1_150 : 1_980 + wobble * 180
            let proteinG = isToday ? 72.0 : 138 + wobble * 18
            let carbsG = isToday ? 110.0 : 195 + wobble * 28
            let fatG = isToday ? 38.0 : 64 + wobble * 10

            let restStart = day.addingTimeInterval(3_600)
            let restEnd = isToday ? min(now, restStart.addingTimeInterval(3_600)) : day.addingTimeInterval(7_200)
            let actStart = day.addingTimeInterval(10_800)
            let actEnd = isToday ? min(now, actStart.addingTimeInterval(3_600)) : day.addingTimeInterval(14_400)
            guard restEnd > restStart, actEnd > actStart else { continue }

            let mealEnd = isToday ? now : day.addingTimeInterval(50_400)
            let mealStart = mealEnd.addingTimeInterval(-3_600)
            guard mealEnd > mealStart else { continue }

            samples.append(quantity(types.basal, unit: .kilocalorie(), value: resting, start: restStart, end: restEnd))
            samples.append(quantity(types.active, unit: .kilocalorie(), value: activeKcal, start: actStart, end: actEnd))
            samples.append(quantity(types.steps, unit: .count(), value: stepCount, start: actStart, end: actEnd))
            samples.append(quantity(types.dietary, unit: .kilocalorie(), value: food, start: mealStart, end: mealEnd))
            samples.append(quantity(types.protein, unit: .gram(), value: proteinG, start: mealStart, end: mealEnd))
            samples.append(quantity(types.carbs, unit: .gram(), value: carbsG, start: mealStart, end: mealEnd))
            samples.append(quantity(types.fat, unit: .gram(), value: fatG, start: mealStart, end: mealEnd))
        }

        try await store.save(samples)
    }

    private static func quantity(
        _ type: HKQuantityType, unit: HKUnit, value: Double, start: Date, end: Date
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: max(value, 0)),
            start: start,
            end: max(end, start.addingTimeInterval(1)),
            metadata: [markerKey: true]
        )
    }

    private static func deleteMarked(in store: HKHealthStore, types: [HKSampleType]) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: markerKey, operatorType: .equalTo, value: true
        )
        for type in types {
            _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                store.deleteObjects(of: type, predicate: predicate) { _, count, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: count)
                    }
                }
            }
        }
    }
}
#endif
