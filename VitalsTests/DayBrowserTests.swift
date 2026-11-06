import XCTest

final class DayBrowserTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testPreviousFromTodayIsYesterdayAtMidnight() {
        let now = date(2026, 11, 6, hour: 22)
        XCTAssertEqual(DayBrowser.previous(of: nil, now: now, calendar: calendar), date(2026, 11, 5))
    }

    func testNextIntoTodayReturnsNil() {
        let now = date(2026, 11, 6, hour: 22)
        XCTAssertNil(DayBrowser.next(of: date(2026, 11, 5), now: now, calendar: calendar))
    }

    func testNextBetweenPastDaysStepsOneDay() {
        let now = date(2026, 11, 6, hour: 22)
        XCTAssertEqual(DayBrowser.next(of: date(2026, 11, 3), now: now, calendar: calendar), date(2026, 11, 4))
    }

    /// A day left on screen across midnight is still a past day, one further back.
    func testViewedDayStaysValidAfterMidnight() {
        let viewed = date(2026, 11, 5)
        XCTAssertEqual(DayBrowser.next(of: viewed, now: date(2026, 11, 7, hour: 0), calendar: calendar), date(2026, 11, 6))
    }

    func testPreviousStopsAtTheLimit() {
        let now = date(2026, 11, 6, hour: 9)
        let limit = calendar.date(byAdding: .day, value: -DayBrowser.maxDaysBack, to: date(2026, 11, 6))!
        let dayAfterLimit = calendar.date(byAdding: .day, value: 1, to: limit)!
        XCTAssertEqual(DayBrowser.previous(of: dayAfterLimit, now: now, calendar: calendar), limit)
        XCTAssertNil(DayBrowser.previous(of: limit, now: now, calendar: calendar))
    }

    /// Both DST days are 23 and 25 hours long, so steps must be calendar days.
    func testStepsCrossDaylightSavingChanges() {
        let now = date(2026, 12, 1, hour: 12)
        XCTAssertEqual(DayBrowser.previous(of: date(2026, 11, 2), now: now, calendar: calendar), date(2026, 11, 1))
        XCTAssertEqual(DayBrowser.next(of: date(2026, 11, 1), now: now, calendar: calendar), date(2026, 11, 2))
        XCTAssertEqual(DayBrowser.previous(of: date(2026, 3, 9), now: date(2026, 4, 1), calendar: calendar), date(2026, 3, 8))
    }
}
