import Foundation
import SwiftData

/// Reads the shared SwiftData cache and computes the 30-day TDEE/BMR averages
/// the Maintenance widget shows.
///
/// Lives next to `EnergyAveragesCalculator` and is shared by the widget
/// (`EnergyAveragesWidget`) and the debug lab harness so the widget's *exact*
/// read path (the completed-day window + the calculator) is exercised, never a
/// copy. The window here must stay identical to the app's live path
/// (`fetchEnergyAverages` → HealthKit active/resting totals →
/// `EnergyAveragesCalculator`), which is what guarantees the widget and the
/// in-app figure agree given the same underlying data. When they disagreed it
/// was a cache-freshness problem, not a calculation one — see
/// `HealthKitService.refreshHistoryCache`.
enum EnergyAveragesCacheReader {
    struct Output: Sendable {
        let result: EnergyAveragesResult
        /// False when the cache holds no rows in the window at all (fresh
        /// install / no history synced yet), distinct from "building" (some
        /// rows, but fewer than `minSamples`).
        let hasCache: Bool
    }

    static func read(
        container: ModelContainer,
        referenceDate: Date = .now,
        minSamples: Int
    ) -> Output {
        let todayKey = DailyHealthRecord.key(for: DateHelpers.startOfDay(referenceDate))
        let windowStartKey = DailyHealthRecord.key(
            for: DateHelpers.daysAgo(EnergyAveragesCalculator.windowDays, from: referenceDate)
        )
        // Match the app's exact completed calendar-day window. Missing days stay
        // missing rather than being replaced with older rows outside the window.
        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate {
                $0.dateString >= windowStartKey && $0.dateString < todayKey
            },
            sortBy: [SortDescriptor(\DailyHealthRecord.dateString, order: .reverse)]
        )

        // Fresh context so this can run from a widget timeline/snapshot callback
        // (not necessarily the main actor) without touching `mainContext`.
        let context = ModelContext(container)
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else {
            return Output(
                result: EnergyAveragesResult(tdee: nil, bmr: nil, sampleDays: 0),
                hasCache: false
            )
        }

        let result = EnergyAveragesCalculator.compute(
            records: rows.map { (date: $0.date, active: $0.activeCalories, resting: $0.restingCalories) },
            referenceDate: referenceDate,
            minSamples: minSamples
        )
        return Output(result: result, hasCache: true)
    }
}
