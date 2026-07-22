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

    func testIgnoresRecordsOlderThanThirtyCompletedDays() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9)))
        var records = makeRecords(endingBefore: reference, count: 30, active: 500, resting: 1_600)
        let oldRecords = (31...34).compactMap { offset -> (date: Date, active: Double, resting: Double)? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: reference) else { return nil }
            return (date: day, active: 5_000, resting: 5_000)
        }
        records.append(contentsOf: oldRecords)

        let result = EnergyAveragesCalculator.compute(records: records, referenceDate: reference)

        XCTAssertEqual(result.sampleDays, 30)
        XCTAssertEqual(try XCTUnwrap(result.tdee), 2_100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.bmr), 1_600, accuracy: 0.001)
    }

    func testExtraFetchedRowsMatchExactThirtyDayInput() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9)))
        let exactWindow = makeRecords(endingBefore: reference, count: 30, active: 500, resting: 1_600)
        let extraRows = makeRecords(endingBefore: reference, count: 34, active: 500, resting: 1_600)

        let exactResult = EnergyAveragesCalculator.compute(records: exactWindow, referenceDate: reference)
        let extraResult = EnergyAveragesCalculator.compute(records: extraRows, referenceDate: reference)

        XCTAssertEqual(extraResult, exactResult)
    }
}

final class DateHelpersTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testHealthQueryEndCapsTodayAtNow() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10, minute: 11)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22)))

        XCTAssertEqual(DateHelpers.healthQueryEnd(including: today, now: now), now)
    }

    func testHealthQueryEndCapsFutureDateAtNow() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10, minute: 11)))
        let future = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24)))

        XCTAssertEqual(DateHelpers.healthQueryEnd(including: future, now: now), now)
    }

    func testHealthQueryEndExtendsCompletedDayToNextMidnight() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10, minute: 11)))
        let completedDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 18)))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 21)))

        XCTAssertEqual(DateHelpers.healthQueryEnd(including: completedDay, now: now), expected)
    }
}
