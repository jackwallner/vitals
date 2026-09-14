import XCTest

final class ExcludedDaysPitchTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))!
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 15))!
    }

    /// Ten days at 2,000 with one watch-on-the-charger day at 1,500.
    private func history(lowOffset: Int = 4) -> [(date: Date, calories: Double)] {
        (1...10).map { offset in (day(offset, from: now), offset == lowOffset ? 1_500 : 2_000) }
    }

    func testNamesTheLowestCompletedDayAndItsLift() throws {
        let pitch = try XCTUnwrap(ExcludedDaysPitch.make(history: history(), now: now, calendar: calendar))
        XCTAssertEqual(pitch.day, day(4, from: now))
        XCTAssertEqual(pitch.headline, "Leave Sep 9 out of your averages")
        // Average 1,950 with it, 2,000 without.
        XCTAssertEqual(pitch.subheadline, "Your lowest day in the last 30 burned 1,500 cal. Leaving it out lifts your 30-day average by 50 cal.")
    }

    /// Today is always partial, so it would win "lowest" every morning.
    func testTodayNeverCountsAsTheLowestDay() throws {
        let withToday = history() + [(now, 300)]
        let pitch = try XCTUnwrap(ExcludedDaysPitch.make(history: withToday, now: now, calendar: calendar))
        XCTAssertEqual(pitch.day, day(4, from: now))
    }

    /// The day under the user's finger, not a different one.
    func testATappedDayIsTheDayPitched() throws {
        let tapped = day(2, from: now)
        let pitch = try XCTUnwrap(ExcludedDaysPitch.make(history: history(), tapped: tapped, now: now, calendar: calendar))
        XCTAssertEqual(pitch.day, tapped)
        XCTAssertEqual(pitch.headline, "Leave Sep 11 out of your averages")
        XCTAssertEqual(pitch.subheadline, "That day burned 2,000 cal. Leave it out of every average, total, and streak.")
    }

    func testATappedDayWithNoDataFallsBackToGenericCopy() {
        XCTAssertNil(ExcludedDaysPitch.make(history: history(), tapped: day(20, from: now), now: now, calendar: calendar))
    }

    func testTooLittleHistoryFallsBackToGenericCopy() {
        let thin = Array(history().prefix(ExcludedDaysPitch.minimumLoggedDays - 1))
        XCTAssertNil(ExcludedDaysPitch.make(history: thin, now: now, calendar: calendar))
    }

    func testZeroDaysAreNotLoggedDays() throws {
        let withBlank = history() + [(day(12, from: now), 0)]
        let pitch = try XCTUnwrap(ExcludedDaysPitch.make(history: withBlank, now: now, calendar: calendar))
        XCTAssertEqual(pitch.day, day(4, from: now))
    }
}
