import SwiftData
import XCTest

/// Bug 2 (Tim White): the Maintenance widget reads only the SwiftData cache.
/// A partial "completed day" left behind by the today/observer path makes the
/// widget's 30-day TDEE drift below the in-app live figure until history is
/// finalized. These tests exercise the widget's exact read path.
@MainActor
final class EnergyAveragesCacheReaderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testPartialCompletedDaysDriftBelowFullDayCache() throws {
        let reference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 7, minute: 30))
        )
        let container = try makeContainer()

        // Stale partial snapshots — what refreshCache leaves for a day that has
        // since completed without a history finalize pass.
        try seed(container, endingBefore: reference, days: 8, active: 250, resting: 800)
        let stale = EnergyAveragesCacheReader.read(
            container: container, referenceDate: reference, minSamples: 7
        )

        // Finalized full-day totals — what refreshHistoryCache writes.
        try seed(container, endingBefore: reference, days: 8, active: 500, resting: 1_600)
        let fixed = EnergyAveragesCacheReader.read(
            container: container, referenceDate: reference, minSamples: 7
        )

        let staleTDEE = try XCTUnwrap(stale.result.tdee)
        let fixedTDEE = try XCTUnwrap(fixed.result.tdee)

        XCTAssertEqual(fixedTDEE, 2_100, accuracy: 0.001)
        XCTAssertLessThan(
            staleTDEE, fixedTDEE - 100,
            "partial cache must drift below the finalized figure (Tim White mismatch)"
        )
        XCTAssertEqual(staleTDEE, 1_050, accuracy: 0.001)
    }

    func testEmptyCacheReportsNoData() throws {
        let reference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 7, minute: 30))
        )
        let container = try makeContainer()
        let output = EnergyAveragesCacheReader.read(
            container: container, referenceDate: reference, minSamples: 7
        )
        XCTAssertFalse(output.hasCache)
        XCTAssertNil(output.result.tdee)
        XCTAssertEqual(output.result.sampleDays, 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([DailyHealthRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seed(
        _ container: ModelContainer,
        endingBefore reference: Date,
        days: Int,
        active: Double,
        resting: Double
    ) throws {
        let context = ModelContext(container)
        for offset in 1...days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: reference) else {
                continue
            }
            let key = DailyHealthRecord.key(for: calendar.startOfDay(for: day))
            let existing = try context.fetch(
                FetchDescriptor<DailyHealthRecord>(predicate: #Predicate { $0.dateString == key })
            ).first
            if let existing {
                existing.activeCalories = active
                existing.restingCalories = resting
                existing.lastUpdated = .now
            } else {
                context.insert(
                    DailyHealthRecord(date: day, activeCalories: active, restingCalories: resting)
                )
            }
        }
        try context.save()
    }
}
