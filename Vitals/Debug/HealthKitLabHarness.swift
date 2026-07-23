#if DEBUG
import HealthKit
import SwiftUI

/// DEBUG-only harness that reproduces the "implausible totals" bug against a
/// real `HKHealthStore` in the simulator.
///
/// The bug: `HKStatisticsCollectionQuery` with the default (loose) predicate
/// counts the *entire* quantity of a sample that overlaps the query range, even
/// when most of that sample lies past the query's end date. Basal energy is
/// written as long-running samples, so a sample covering the whole day made the
/// Today screen report a full day of resting calories before lunch.
///
/// Activated with `VITALS_HK_LAB=1` in the environment. Never reachable in a
/// Release build.
enum HealthKitLabConfig {
    static let isEnabled = ProcessInfo.processInfo.environment["VITALS_HK_LAB"] == "1"

    enum Scenario {
        /// Bug 1: future-spanning basal sample inflates today's resting total.
        case overcount
        /// Bug 2: Maintenance/TDEE widget cache drifts from the in-app figure.
        case maintenanceCacheParity
    }

    static var scenario: Scenario {
        ProcessInfo.processInfo.environment["VITALS_HK_LAB_SCENARIO"] == "maintenance"
            ? .maintenanceCacheParity
            : .overcount
    }
}

/// Marks every sample this harness writes so a rerun can clean up after itself
/// without touching anything else in the store.
private let labMarkerKey = "VitalsHealthKitLabSample"

struct HealthKitLabResult: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

@MainActor
final class HealthKitLabModel: ObservableObject {
    @Published var status = "idle"
    @Published var authInfo = "?"
    @Published var results: [HealthKitLabResult] = []
    @Published var finished = false

    private let healthKit = HealthKitService.shared
    private var store: HKHealthStore { healthKit.debugStore }

    private let basalType = HKQuantityType(.basalEnergyBurned)
    private let activeType = HKQuantityType(.activeEnergyBurned)
    // fetchTodayStats() also reads step count, so authorization must cover it or
    // the collection query throws errorAuthorizationNotDetermined (Code 5) for a
    // type that was never requested.
    private let stepType = HKQuantityType(.stepCount)

    /// The scenario, fixed so assertions can be exact:
    /// - `elapsedBasal` kcal genuinely burned between midnight and now, written
    ///   as short samples the way HealthKit actually records basal energy.
    /// - one long sample starting an hour ago and ending well after now, holding
    ///   `spanningBasal` kcal. Only the first hour of it has actually happened.
    static let elapsedBasal: Double = 700
    static let spanningBasal: Double = 3_600
    static let spanningHours: Double = 12
    static let activeToday: Double = 54

    /// The hour of `spanningBasal` that has actually elapsed.
    static var spanningElapsedShare: Double { spanningBasal / spanningHours }

    func run() async {
        var phase = "start"
        do {
            phase = "requesting authorization"
            status = phase
            try await store.requestAuthorization(
                toShare: [basalType, activeType],
                read: [basalType, activeType, stepType]
            )

            // Surface the resulting *write* authorization so the UI test can see
            // whether the permission sheet actually granted sharing (0 = not
            // determined, 1 = denied, 2 = authorized) before save() is attempted.
            let basalAuth = store.authorizationStatus(for: basalType).rawValue
            let activeAuth = store.authorizationStatus(for: activeType).rawValue
            authInfo = "basal=\(basalAuth) active=\(activeAuth)"

            phase = "clearing previous lab samples"
            status = phase
            try await deleteLabSamples()

            switch HealthKitLabConfig.scenario {
            case .maintenanceCacheParity:
                try await runMaintenanceCacheParity(phase: &phase)
            case .overcount:
                try await runOvercount(phase: &phase)
            }

            status = "done"
            finished = true
        } catch {
            status = "error in [\(phase)]: \(String(describing: error))"
            finished = true
        }
    }

    /// Bug 1 (Ozzie): a basal sample that ends in the future inflates today's
    /// resting total under the default predicate. Verifies the strictEndDate fix.
    private func runOvercount(phase: inout String) async throws {
        phase = "writing samples"
        status = phase
        let now = Date.now
        let dayStart = DateHelpers.startOfDay(now)
        try await writeSamples(now: now, dayStart: dayStart)

        phase = "querying loose"
        status = phase
        let loose = try await healthKit.debugDailyTotals(
            .basalEnergyBurned, unit: .kilocalorie(),
            start: dayStart, end: now, strictEnd: false
        )
        phase = "querying strict"
        status = phase
        let strict = try await healthKit.debugDailyTotals(
            .basalEnergyBurned, unit: .kilocalorie(),
            start: dayStart, end: now, strictEnd: true
        )
        phase = "querying today"
        status = phase
        let today = try await healthKit.fetchTodayStats()

        results = [
            .init(label: "loose", value: Self.format(loose[dayStart] ?? 0)),
            .init(label: "strict", value: Self.format(strict[dayStart] ?? 0)),
            .init(label: "todayResting", value: Self.format(today.resting)),
            .init(label: "todayActive", value: Self.format(today.active)),
        ]
    }

    /// Bug 2 (Tim White): the Maintenance/TDEE widget reads only the SwiftData
    /// cache, and the today/observer path leaves recent completed days as stale
    /// partial snapshots, so the widget figure drifted from the in-app live one.
    ///
    /// Reproduces the drift and proves the fix end to end against a real store:
    ///   1. Write full completed-day basal+active history to HealthKit.
    ///   2. `liveTDEE` — the in-app figure (live HealthKit).
    ///   3. Seed the cache with partial (stale) rows the way the today path
    ///      would, then read it through the *widget's* code path → `staleTDEE`.
    ///   4. Run the fix (`refreshHistoryCache`) and read the cache again →
    ///      `fixedTDEE`, which must now equal `liveTDEE`.
    private func runMaintenanceCacheParity(phase: inout String) async throws {
        phase = "clearing cache"
        status = phase
        try healthKit.debugClearAllCachedRecords()

        phase = "writing history"
        status = phase
        let validDays = 8
        let fullResting = 1_600.0
        let fullActive = 500.0
        try await writeHistory(days: validDays, resting: fullResting, active: fullActive)

        phase = "live averages"
        status = phase
        let live = try await healthKit.fetchEnergyAverages(minSamples: 7)

        phase = "seeding stale cache"
        status = phase
        // Partial snapshots: what the today/observer path leaves behind before a
        // completed day is finalized. Same days, but roughly half the burn.
        let staleHistory = (1...validDays).compactMap { offset -> (date: Date, active: Double, resting: Double, steps: Int)? in
            let day = DateHelpers.daysAgo(offset)
            return (date: day, active: fullActive / 2, resting: fullResting / 2, steps: 0)
        }
        try healthKit.saveHistoryToCache(history: staleHistory)
        let stale = EnergyAveragesCacheReader.read(
            container: DataService.sharedModelContainer, minSamples: 7
        )

        phase = "applying fix (refreshHistoryCache)"
        status = phase
        try await healthKit.refreshHistoryCache(days: validDays + 2)
        let fixed = EnergyAveragesCacheReader.read(
            container: DataService.sharedModelContainer, minSamples: 7
        )

        results = [
            .init(label: "liveTDEE", value: Self.format(live.tdee ?? -1)),
            .init(label: "staleTDEE", value: Self.format(stale.result.tdee ?? -1)),
            .init(label: "fixedTDEE", value: Self.format(fixed.result.tdee ?? -1)),
        ]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.0f", value.rounded())
    }

    /// Writes `days` full completed days of basal + active energy, one sample per
    /// day placed safely inside that day's bounds so each lands wholly in its own
    /// daily bucket. Used by the maintenance-cache-parity scenario.
    private func writeHistory(days: Int, resting: Double, active: Double) async throws {
        var samples: [HKQuantitySample] = []
        for offset in 1...days {
            let dayStart = DateHelpers.daysAgo(offset)
            let restStart = dayStart.addingTimeInterval(3_600)      // 01:00
            let restEnd = dayStart.addingTimeInterval(7_200)        // 02:00
            let actStart = dayStart.addingTimeInterval(10_800)      // 03:00
            let actEnd = dayStart.addingTimeInterval(14_400)        // 04:00
            samples.append(quantitySample(basalType, kcal: resting, start: restStart, end: restEnd))
            samples.append(quantitySample(activeType, kcal: active, start: actStart, end: actEnd))
        }
        try await store.save(samples)
    }

    private func writeSamples(now: Date, dayStart: Date) async throws {
        var samples: [HKQuantitySample] = []

        // Elapsed basal, spread over short samples between midnight and an hour ago.
        let elapsedEnd = now.addingTimeInterval(-3_600)
        let slices = 6
        let sliceSeconds = elapsedEnd.timeIntervalSince(dayStart) / Double(slices)
        if sliceSeconds > 0 {
            let perSlice = Self.elapsedBasal / Double(slices)
            for index in 0..<slices {
                let start = dayStart.addingTimeInterval(sliceSeconds * Double(index))
                let end = start.addingTimeInterval(sliceSeconds)
                samples.append(quantitySample(basalType, kcal: perSlice, start: start, end: end))
            }
        }

        // The pathological one: starts an hour ago, ends far past `now`.
        let spanningStart = now.addingTimeInterval(-3_600)
        let spanningEnd = now.addingTimeInterval(3_600 * (Self.spanningHours - 1))
        samples.append(
            quantitySample(basalType, kcal: Self.spanningBasal, start: spanningStart, end: spanningEnd)
        )

        samples.append(
            quantitySample(
                activeType, kcal: Self.activeToday,
                start: dayStart.addingTimeInterval(3_600), end: dayStart.addingTimeInterval(5_400)
            )
        )

        try await store.save(samples)
    }

    private func quantitySample(
        _ type: HKQuantityType, kcal: Double, start: Date, end: Date
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
            start: start,
            end: end,
            metadata: [labMarkerKey: true]
        )
    }

    private func deleteLabSamples() async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: labMarkerKey, operatorType: .equalTo, value: true
        )
        for type in [basalType, activeType] {
            _ = try? await deleteObjects(of: type, predicate: predicate)
        }
    }

    private func deleteObjects(of type: HKQuantityType, predicate: NSPredicate) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
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

struct HealthKitLabHarness: View {
    @StateObject private var model = HealthKitLabModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.status)
                .accessibilityIdentifier("hklab.status")
            Text(model.authInfo)
                .accessibilityIdentifier("hklab.authInfo")
            ForEach(model.results) { result in
                HStack {
                    Text(result.label)
                    Spacer()
                    Text(result.value)
                        .accessibilityIdentifier("hklab.\(result.label)")
                }
            }
            Text(model.finished ? "FINISHED" : "RUNNING")
                .accessibilityIdentifier("hklab.state")
            Spacer()
        }
        .padding()
        .task { await model.run() }
    }
}
#endif
