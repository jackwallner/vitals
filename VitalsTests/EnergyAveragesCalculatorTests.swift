import XCTest

final class EnergyAveragesCalculatorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    /// Builds `(date, active, resting)` records counting back from the day before
    /// `reference`, one per prior day.
    private func makeRecords(
        endingBefore reference: Date,
        count: Int,
        active: Double,
        resting: Double
    ) -> [(date: Date, active: Double, resting: Double)] {
        (1...count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: reference) else { return nil }
            return (date: day, active: active, resting: resting)
        }
    }

    func testAveragesTDEEAndBMROverCompletedDays() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9)))
        let records = makeRecords(endingBefore: reference, count: 30, active: 500, resting: 1_600)

        let result = EnergyAveragesCalculator.compute(records: records, referenceDate: reference)

        XCTAssertEqual(result.sampleDays, 30)
        XCTAssertEqual(try XCTUnwrap(result.tdee), 2_100, accuracy: 0.001) // 500 + 1600
        XCTAssertEqual(try XCTUnwrap(result.bmr), 1_600, accuracy: 0.001)
    }

    func testExcludesTodayPartialDay() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9)))
        var records = makeRecords(endingBefore: reference, count: 10, active: 500, resting: 1_600)
        // A huge "today" partial reading must not pull the average up.
        records.append((date: reference, active: 50, resting: 100))

        let result = EnergyAveragesCalculator.compute(records: records, referenceDate: reference)

        XCTAssertEqual(result.sampleDays, 10)
        XCTAssertEqual(try XCTUnwrap(result.tdee), 2_100, accuracy: 0.001)
    }

    func testDropsZeroRestingNonWearDays() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9)))
        var records = makeRecords(endingBefore: reference, count: 8, active: 500, resting: 1_600)
        // Two watch-off days (resting 0) are dropped, not averaged as zeros.
        records.append(contentsOf: makeRecords(endingBefore: reference, count: 2, active: 0, resting: 0))

        let result = EnergyAveragesCalculator.compute(records: records, referenceDate: reference)

        XCTAssertEqual(result.sampleDays, 8)
        XCTAssertEqual(try XCTUnwrap(result.bmr), 1_600, accuracy: 0.001)
    }

    func testReturnsNilBelowMinimumSamples() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9)))
        let records = makeRecords(endingBefore: reference, count: 5, active: 500, resting: 1_600)

        let result = EnergyAveragesCalculator.compute(records: records, referenceDate: reference)

        XCTAssertEqual(result.sampleDays, 5)
        XCTAssertNil(result.tdee)
        XCTAssertNil(result.bmr)
    }
}
