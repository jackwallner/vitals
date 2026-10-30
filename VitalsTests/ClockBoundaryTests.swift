import XCTest

/// Day-boundary behaviour driven by a fixed clock and an explicit calendar
/// (America/Los_Angeles), never the machine's. DST days: 2026-11-01 is 25 hours
/// long, 2027-03-14 is 23.
final class ClockBoundaryTests: XCTestCase {
    private let la: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private func at(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) throws -> Date {
        try XCTUnwrap(la.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )))
    }

    private func key(_ date: Date) -> String {
        DailyHealthRecord.key(for: date, timeZone: la.timeZone)
    }

    // MARK: - Today's elapsed window

    // edded006 + 6e7dcf1: today's bucket must end at now, and a zero-length window
    // at the stroke of midnight must report nothing instead of asking HealthKit.
    func testElapsedWindowAtTheStrokeOfMidnightIsEmpty() throws {
        let midnight = try at(2026, 7, 22)
        XCTAssertNil(DateHelpers.elapsedSeconds(since: midnight, now: midnight))
        XCTAssertEqual(DateHelpers.elapsedSeconds(since: midnight, now: midnight.addingTimeInterval(0.4)), 1)
        XCTAssertEqual(DateHelpers.elapsedSeconds(since: midnight, now: midnight.addingTimeInterval(1)), 1)
        XCTAssertEqual(DateHelpers.elapsedSeconds(since: midnight, now: midnight.addingTimeInterval(1.2)), 2)
    }

    // edded006: the last second of the day still rounds up to a single bucket
    // that covers the whole day with nothing left over.
    func testElapsedWindowInTheLastHourCoversTheWholeDay() throws {
        let midnight = try at(2026, 7, 22)
        let lastSecond = try at(2026, 7, 22, 23, 59, 59).addingTimeInterval(0.9)
        XCTAssertEqual(DateHelpers.elapsedSeconds(since: midnight, now: lastSecond), 86_400)
    }

    // edded006: the elapsed window counts real seconds, so a 25 hour day at noon
    // is 13 hours in and a 23 hour day at noon is 11, not 12.
    func testElapsedWindowUsesRealSecondsOnDSTDays() throws {
        let fallBack = try at(2026, 11, 1)
        XCTAssertEqual(DateHelpers.elapsedSeconds(since: fallBack, now: try at(2026, 11, 1, 12)), 13 * 3_600)
        let springForward = try at(2027, 3, 14)
        XCTAssertEqual(DateHelpers.elapsedSeconds(since: springForward, now: try at(2027, 3, 14, 12)), 11 * 3_600)
    }

    /// HealthKit credits a bucket with the share of a sample's duration that
    /// falls inside it. The overcount lab (6e7dcf1 skipped it before 01:15 and
    /// after 22:00) stages a 3,600 kcal basal sample over 12 hours starting an
    /// hour ago; this replays it at any fixed clock.
    private func credit(kcal: Double, sample: (Date, Date), window: (Date, Date)) -> Double {
        let overlap = min(sample.1, window.1).timeIntervalSince(max(sample.0, window.0))
        guard overlap > 0 else { return 0 }
        return kcal * overlap / sample.1.timeIntervalSince(sample.0)
    }

    // edded006 (overcount lab): at every hour of the day the elapsed-window bucket
    // credits exactly the hour that has happened, while the calendar-day bucket
    // adds the sample's in-day future.
    func testOvercountScenarioHoldsAtEveryHourIncludingTheEdges() throws {
        let clocks = [
            try at(2026, 7, 22, 0, 0, 30), try at(2026, 7, 22, 0, 30), try at(2026, 7, 22, 1),
            try at(2026, 7, 22, 12), try at(2026, 7, 22, 23, 58), try at(2026, 11, 1, 12),
            try at(2027, 3, 14, 12),
        ]
        for now in clocks {
            let dayStart = la.startOfDay(for: now)
            let nextMidnight = try XCTUnwrap(la.date(byAdding: .day, value: 1, to: dayStart))
            let spanning = (now.addingTimeInterval(-3_600), now.addingTimeInterval(11 * 3_600))
            let seconds = try XCTUnwrap(DateHelpers.elapsedSeconds(since: dayStart, now: now))
            let elapsedWindow = (dayStart, dayStart.addingTimeInterval(TimeInterval(seconds)))

            let elapsed = credit(kcal: 3_600, sample: spanning, window: elapsedWindow)
            let calendarDay = credit(kcal: 3_600, sample: spanning, window: (dayStart, nextMidnight))
            let sinceStart = min(3_600, now.timeIntervalSince(dayStart))

            // At most one second of rounding past now is credited.
            XCTAssertEqual(elapsed, 300 * sinceStart / 3_600, accuracy: 1, "at \(now)")
            XCTAssertGreaterThanOrEqual(calendarDay, elapsed, "at \(now)")
            if now.addingTimeInterval(3_600) < nextMidnight {
                XCTAssertGreaterThan(calendarDay, elapsed + 250, "no future overcount to guard at \(now)")
            }
        }
    }

    // MARK: - Query end and day starts

    // 057d0dc2 / 6ecb8c2b: a range containing today stops at now, in the first
    // minute and the last minute of the day.
    func testQueryEndCapsTodayAtNowAtBothEdgesOfTheDay() throws {
        let today = try at(2026, 7, 22)
        let early = try at(2026, 7, 22, 0, 0, 5)
        let late = try at(2026, 7, 22, 23, 59, 59)
        XCTAssertEqual(DateHelpers.healthQueryEnd(including: today, now: early, calendar: la), early)
        XCTAssertEqual(DateHelpers.healthQueryEnd(including: today, now: late, calendar: la), late)
    }

    // 057d0dc2: the moment midnight passes, yesterday is a completed day and its
    // bucket runs to the new midnight (the day's final seconds are not dropped).
    func testQueryEndForYesterdayRunsToMidnightJustAfterRollover() throws {
        let yesterday = try at(2026, 7, 21, 23, 59, 59)
        let now = try at(2026, 7, 22, 0, 0, 10)
        XCTAssertEqual(
            DateHelpers.healthQueryEnd(including: yesterday, now: now, calendar: la),
            try at(2026, 7, 22)
        )
    }

    // 6ecb8c2b: a completed day ends at the next local midnight even when the day
    // is 25 or 23 hours long; adding 86,400 seconds would clip or overshoot.
    func testQueryEndForCompletedDSTDaysIsTheNextMidnight() throws {
        let afterFall = try at(2026, 11, 3, 9)
        XCTAssertEqual(
            DateHelpers.healthQueryEnd(including: try at(2026, 11, 1, 18), now: afterFall, calendar: la),
            try at(2026, 11, 2)
        )
        let afterSpring = try at(2027, 3, 16, 9)
        XCTAssertEqual(
            DateHelpers.healthQueryEnd(including: try at(2027, 3, 14, 18), now: afterSpring, calendar: la),
            try at(2027, 3, 15)
        )
    }

    // 057d0dc2 (window edges): daysAgo anchors on the start of day and steps whole
    // calendar days across month ends, year ends and both DST changes.
    func testDaysAgoStepsWholeCalendarDays() throws {
        XCTAssertEqual(DateHelpers.daysAgo(1, from: try at(2026, 3, 1, 0, 0, 1), calendar: la), try at(2026, 2, 28))
        XCTAssertEqual(DateHelpers.daysAgo(1, from: try at(2027, 1, 1, 23, 59), calendar: la), try at(2026, 12, 31))
        XCTAssertEqual(DateHelpers.daysAgo(1, from: try at(2026, 11, 2, 0, 30), calendar: la), try at(2026, 11, 1))
        XCTAssertEqual(DateHelpers.daysAgo(30, from: try at(2027, 4, 10, 9), calendar: la), try at(2027, 3, 11))
        XCTAssertEqual(DateHelpers.daysAgo(0, from: try at(2026, 7, 22, 23, 59, 59), calendar: la), try at(2026, 7, 22))
    }

    func testStartOfWeekAndMonthAtTheirBoundaries() throws {
        // 2026-07-19 is a Sunday.
        XCTAssertEqual(DateHelpers.startOfWeek(try at(2026, 7, 19, 0, 0, 1), calendar: la), try at(2026, 7, 19))
        XCTAssertEqual(DateHelpers.startOfWeek(try at(2026, 7, 18, 23, 59, 59), calendar: la), try at(2026, 7, 12))
        XCTAssertEqual(DateHelpers.startOfMonth(try at(2026, 12, 31, 23, 59), calendar: la), try at(2026, 12, 1))
        XCTAssertEqual(DateHelpers.startOfMonth(try at(2027, 1, 1, 0, 0, 1), calendar: la), try at(2027, 1, 1))
    }

    // MARK: - Day keys

    // b8bd0455 / 7b3ea59: a day has one Gregorian identity, read in the device's
    // zone: the last second of the day and the first of the next never share a key.
    func testDayKeysSplitExactlyAtLocalMidnightAndOnDSTDays() throws {
        XCTAssertEqual(key(try at(2026, 7, 21, 23, 59, 59)), "2026-07-21")
        XCTAssertEqual(key(try at(2026, 7, 22, 0, 0, 0)), "2026-07-22")
        XCTAssertEqual(key(try at(2026, 11, 1, 0, 30)), "2026-11-01")
        XCTAssertEqual(key(try at(2026, 11, 1, 23, 30)), "2026-11-01")
        XCTAssertEqual(key(try at(2027, 3, 14, 3, 0)), "2027-03-14")
        XCTAssertEqual(key(try at(2026, 12, 31, 23, 59, 59)), "2026-12-31")
        XCTAssertEqual(key(try at(2027, 1, 1)), "2027-01-01")
    }

    // MARK: - Energy averages

    private func rows(
        from first: Date, count: Int, active: Double = 500, resting: Double = 1_600
    ) throws -> [(date: Date, active: Double, resting: Double)] {
        try (0..<count).map { offset in
            let day = try XCTUnwrap(la.date(byAdding: .day, value: offset, to: first))
            return (date: day, active: active, resting: resting)
        }
    }

    // 057d0dc2 (Maintenance widget drift): the 30 day window is 30 calendar days,
    // so on a reference after spring forward the oldest day is still inside it.
    // A 30 x 86,400 second subtraction starts at 01:00 and drops that day.
    func testWindowKeepsThe30thDayAcrossSpringForward() throws {
        let reference = try at(2027, 4, 10, 9)
        let records = try rows(from: try at(2027, 3, 10), count: 31)
        let result = EnergyAveragesCalculator.compute(records: records, referenceDate: reference, calendar: la)
        // Mar 11 through Apr 9: 30 completed days. Mar 10 is outside the window.
        XCTAssertEqual(result.sampleDays, 30)
    }

    // 057d0dc2: same window across the fall-back change.
    func testWindowKeepsThe30thDayAcrossFallBack() throws {
        let reference = try at(2026, 11, 20, 9)
        let records = try rows(from: try at(2026, 10, 20), count: 31)
        let result = EnergyAveragesCalculator.compute(records: records, referenceDate: reference, calendar: la)
        XCTAssertEqual(result.sampleDays, 30)
    }

    // 057d0dc2: in the first minute of a new day yesterday is complete and counts;
    // in the last minute of a day that day is still today and does not.
    func testYesterdayCountsFromJustAfterMidnightAndTodayNeverDoes() throws {
        let records = try rows(from: try at(2026, 7, 10), count: 13) // Jul 10 ... Jul 22
        let justAfter = EnergyAveragesCalculator.compute(
            records: records, referenceDate: try at(2026, 7, 22, 0, 0, 1), calendar: la
        )
        XCTAssertEqual(justAfter.sampleDays, 12) // Jul 10 ... Jul 21
        let lastMinute = EnergyAveragesCalculator.compute(
            records: records, referenceDate: try at(2026, 7, 21, 23, 59), calendar: la
        )
        XCTAssertEqual(lastMinute.sampleDays, 11) // Jul 10 ... Jul 20
    }

    // 98ba58ec + b8bd0455: the 25 hour day is one sample like any other, and an
    // excluded key is read in the calendar's zone, not the machine's.
    func testDSTDayIsOneSampleAndAnExcludedKeyRemovesIt() throws {
        let reference = try at(2026, 11, 15, 9)
        let records = try rows(from: try at(2026, 10, 20), count: 26, active: 500, resting: 1_600)
        let plain = EnergyAveragesCalculator.compute(records: records, referenceDate: reference, calendar: la)
        XCTAssertEqual(plain.sampleDays, 26)
        XCTAssertEqual(try XCTUnwrap(plain.tdee), 2_100, accuracy: 0.001)

        var withBigDay = records
        withBigDay[12] = (date: withBigDay[12].date, active: 500, resting: 4_100) // Nov 1
        let big = EnergyAveragesCalculator.compute(records: withBigDay, referenceDate: reference, calendar: la)
        XCTAssertEqual(try XCTUnwrap(big.tdee), (25 * 2_100 + 4_600) / 26, accuracy: 0.001)

        let excluded = EnergyAveragesCalculator.compute(
            records: withBigDay, referenceDate: reference, excludedKeys: ["2026-11-01"], calendar: la
        )
        XCTAssertEqual(excluded.sampleDays, 25)
        XCTAssertEqual(try XCTUnwrap(excluded.tdee), 2_100, accuracy: 0.001)
    }

    // MARK: - Pause range

    // b8bd0455: a running pause grows by exactly one key per local midnight, with
    // no skipped or doubled key across either DST change.
    func testPausedKeysGrowOneDayPerMidnightAcrossDST() throws {
        let since = try at(2026, 10, 30, 14)
        let beforeMidnight = ExcludedDays.pausedKeys(since: since, now: try at(2026, 10, 31, 23, 59, 59), calendar: la)
        let afterMidnight = ExcludedDays.pausedKeys(since: since, now: try at(2026, 11, 1, 0, 0, 1), calendar: la)
        let nextDay = ExcludedDays.pausedKeys(since: since, now: try at(2026, 11, 2, 0, 0, 1), calendar: la)
        XCTAssertEqual(beforeMidnight, ["2026-10-30", "2026-10-31"])
        XCTAssertEqual(afterMidnight, ["2026-10-30", "2026-10-31", "2026-11-01"])
        XCTAssertEqual(nextDay.count, 4)

        let spring = ExcludedDays.pausedKeys(since: try at(2027, 3, 13), now: try at(2027, 3, 15, 8), calendar: la)
        XCTAssertEqual(spring, ["2027-03-13", "2027-03-14", "2027-03-15"])
    }

    // b8bd0455: the cached set is valid until the next local midnight, which on
    // the fall-back day is 25 hours away, and refreshes the moment it passes.
    func testKeyCacheExpiresAtTheNextMidnightOnADSTDay() throws {
        var cache = ExcludedDays.KeyCache()
        let since = try at(2026, 10, 30)
        let morning = try at(2026, 11, 1, 9)
        XCTAssertEqual(cache.keys(picked: [], pausedSince: since, now: morning, calendar: la).count, 3)
        // 23:30 on the 25 hour day is still inside the cached day.
        XCTAssertEqual(cache.keys(picked: ["x"], pausedSince: since, now: try at(2026, 11, 1, 23, 30), calendar: la).count, 3)
        XCTAssertEqual(cache.keys(picked: ["x"], pausedSince: since, now: try at(2026, 11, 2, 0, 0, 1), calendar: la).count, 5)
    }

    // MARK: - Trend averages across DST

    private func history(
        from first: Date, count: Int, value: (Int) -> Double
    ) throws -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        try (0..<count).map { offset in
            let day = try XCTUnwrap(la.date(byAdding: .day, value: offset, to: first))
            return (date: day, active: 0, resting: value(offset), steps: Int(value(offset)))
        }
    }

    // 98ba58ec / 8a500ea4: the 30 day average is by calendar day. The fall-back day
    // is one point, the weekly window ends on the last completed day, and the
    // excluded 25 hour day leaves the average untouched.
    func testMonthlyAverageAcrossFallBackAndItsExcludedDay() throws {
        let first = try at(2026, 10, 12) // 30 days: Oct 12 ... Nov 10, Nov 1 is index 20
        let data = try history(from: first, count: 30) { $0 == 20 ? 5_000 : 2_000 }

        let included = try XCTUnwrap(CalorieTrendSummary.make(history: data, calendar: la))
        XCTAssertEqual(included.points.count, 30)
        // The last point is the in-progress day; the 29 before it are completed.
        XCTAssertEqual(included.monthly.sampleDays, 29)
        XCTAssertEqual(try XCTUnwrap(included.monthly.average), (28 * 2_000 + 5_000) / 29, accuracy: 0.001)
        XCTAssertEqual(included.weekly.sampleDays, 7)
        XCTAssertEqual(try XCTUnwrap(included.weekly.average), 2_000, accuracy: 0.001)

        let excluded = try XCTUnwrap(CalorieTrendSummary.make(
            history: data, excludedKeys: ["2026-11-01"], calendar: la
        ))
        XCTAssertEqual(excluded.monthly.sampleDays, 28)
        XCTAssertEqual(try XCTUnwrap(excluded.monthly.average), 2_000, accuracy: 0.001)
        XCTAssertEqual(excluded.points.filter(\.isExcluded).count, 1)
    }

    func testStepTrendReadsTheExcludedKeyInTheCalendarsZone() throws {
        let first = try at(2027, 3, 1)
        let data = try history(from: first, count: 20) { $0 == 13 ? 30_000 : 8_000 } // Mar 14 is index 13
        let summary = try XCTUnwrap(StepTrendSummary.make(
            history: data, excludedKeys: ["2027-03-14"], calendar: la
        ))
        XCTAssertEqual(summary.points.filter(\.isExcluded).map { key($0.date) }, ["2027-03-14"])
        XCTAssertEqual(try XCTUnwrap(summary.weekly.average), 8_000, accuracy: 0.001)
    }

    // MARK: - Streaks and the weekly recap at midnight

    private func milestoneDays(from first: Date, count: Int, calories: Double) throws -> [MilestoneDay] {
        try (0..<count).map { offset in
            MilestoneDay(
                date: try XCTUnwrap(la.date(byAdding: .day, value: offset, to: first)),
                calories: calories, steps: 0
            )
        }
    }

    // 98ba58ec: a streak counts completed days only: at 00:00:01 the day that just
    // ended is in, at 23:59:59 the day still running is out. Holds over fall-back.
    func testStreakAdvancesAtMidnightAndWalksOverTheDSTDay() throws {
        let days = try milestoneDays(from: try at(2026, 10, 28), count: 6, calories: 2_500) // Oct 28 ... Nov 2
        let justBefore = MilestoneCalculator.currentStreak(
            records: days, today: try at(2026, 11, 2, 23, 59, 59), calendar: la
        ) { $0.calories >= 2_000 }
        XCTAssertEqual(justBefore, 5) // Oct 28 ... Nov 1
        let justAfter = MilestoneCalculator.currentStreak(
            records: days, today: try at(2026, 11, 3, 0, 0, 1), calendar: la
        ) { $0.calories >= 2_000 }
        XCTAssertEqual(justAfter, 6)
    }

    // f7809518: an excluded 25 hour day is neutral to a streak.
    func testStreakStepsOverAnExcludedFallBackDay() throws {
        var days = try milestoneDays(from: try at(2026, 10, 28), count: 6, calories: 2_500)
        days[4] = MilestoneDay(date: days[4].date, calories: 0, steps: 0) // Nov 1, no data
        let streak = MilestoneCalculator.currentStreak(
            records: days, today: try at(2026, 11, 3, 8), calendar: la, excludedKeys: ["2026-11-01"]
        ) { $0.calories >= 2_000 }
        XCTAssertEqual(streak, 5)
        let broken = MilestoneCalculator.currentStreak(
            records: days, today: try at(2026, 11, 3, 8), calendar: la
        ) { $0.calories >= 2_000 }
        XCTAssertEqual(broken, 1)
    }

    // 8a500ea4: the recap windows are the 7 completed days before today. At
    // 00:00:01 the day that just ended is its newest day; the week straddling
    // the spring-forward change still has seven.
    func testWeeklyRecapWindowAcrossSpringForwardAndAtMidnight() throws {
        var days = try milestoneDays(from: try at(2027, 3, 1), count: 17, calories: 2_000) // Mar 1 ... Mar 17
        days[15] = MilestoneDay(date: days[15].date, calories: 3_000, steps: 0) // Mar 16
        let recap = try XCTUnwrap(WeeklyRecapBuilder.build(
            records: days, calorieGoal: nil, stepGoal: nil, today: try at(2027, 3, 17, 0, 0, 1), calendar: la
        ))
        XCTAssertEqual(recap.daysWithData, 7) // Mar 10 ... Mar 16
        XCTAssertEqual(key(try XCTUnwrap(recap.bestCalorieDay)), "2027-03-16")

        let lastMinute = try XCTUnwrap(WeeklyRecapBuilder.build(
            records: days, calorieGoal: nil, stepGoal: nil, today: try at(2027, 3, 16, 23, 59, 59), calendar: la
        ))
        XCTAssertEqual(lastMinute.daysWithData, 7) // Mar 9 ... Mar 15
        XCTAssertEqual(try XCTUnwrap(lastMinute.bestCalorieValue), 2_000, accuracy: 0.001) // Mar 16 is still today
    }

    func testMonthReviewOpensOnTheFirstOfTheMonthAndClosesAfterTheThird() throws {
        let october = try milestoneDays(from: try at(2026, 10, 1), count: 31, calories: 2_000)
        XCTAssertNotNil(MilestoneCalculator.reviewableLastMonth(
            records: october, today: try at(2026, 11, 1, 0, 0, 1), calendar: la
        ))
        XCTAssertNotNil(MilestoneCalculator.reviewableLastMonth(
            records: october, today: try at(2026, 11, 3, 23, 59, 59), calendar: la
        ))
        XCTAssertNil(MilestoneCalculator.reviewableLastMonth(
            records: october, today: try at(2026, 11, 4, 0, 0, 1), calendar: la
        ))
        XCTAssertNil(MilestoneCalculator.reviewableLastMonth(
            records: october, today: try at(2026, 10, 31, 23, 59, 59), calendar: la
        ))
    }

    // MARK: - Pacing

    // 240cad0 / 7bc785e: pacing is silent before 06:00 and live from 06:00:00.
    func testPacingWindowOpensAtSixAm() throws {
        XCTAssertNil(PacingCalculator.window(now: try at(2026, 7, 22, 5, 59, 59), lookbackDays: 30, calendar: la))
        let window = try XCTUnwrap(PacingCalculator.window(now: try at(2026, 7, 22, 6), lookbackDays: 30, calendar: la))
        XCTAssertEqual(window.today, try at(2026, 7, 22))
        XCTAssertEqual(window.windowStart, try at(2026, 6, 22))
    }

    // 240cad0: the share of the day elapsed divides by the real day length, so
    // noon on a 25 hour day is 13/25 and on a 23 hour day is 11/23.
    func testDayFractionUsesTheRealLengthOfDSTDays() throws {
        XCTAssertEqual(PacingCalculator.dayFraction(now: try at(2026, 7, 22, 12), calendar: la), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PacingCalculator.dayFraction(now: try at(2026, 11, 1, 12), calendar: la), 13.0 / 25.0, accuracy: 1e-9)
        XCTAssertEqual(PacingCalculator.dayFraction(now: try at(2027, 3, 14, 12), calendar: la), 11.0 / 23.0, accuracy: 1e-9)
        XCTAssertEqual(PacingCalculator.dayFraction(now: try at(2026, 7, 22, 0), calendar: la), 0, accuracy: 1e-9)
        XCTAssertLessThan(PacingCalculator.dayFraction(now: try at(2026, 11, 1, 23, 59, 59), calendar: la), 1)
    }

    // 0bff207: same-weekday pacing picks exactly the matching weekdays across the
    // fall-back change, skips excluded days, and samples completed days only.
    func testSameWeekdayPacingAcrossFallBackSkipsExcludedDays() throws {
        let now = try at(2026, 11, 9, 12) // a Monday; previous Mondays: Nov 2, Oct 26, Oct 19, Oct 12
        var asked: [String] = []
        let result = PacingCalculator.compute(
            calories: { day in asked.append(self.key(day)); return 2_400 },
            steps: { _ in 8_000 },
            comparison: .dayOfWeek,
            lookbackDays: 28,
            excluded: ["2026-10-19"],
            now: now,
            calendar: la
        )
        XCTAssertEqual(result.calorieSampleDays, 3)
        XCTAssertEqual(Set(asked), ["2026-11-02", "2026-10-26", "2026-10-12"])
        XCTAssertEqual(try XCTUnwrap(result.avgCalories), 1_200, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.avgCaloriesFullDay), 2_400, accuracy: 0.001)
        XCTAssertEqual(result.avgSteps, 4_000)
    }

    func testAllDaysPacingSkipsEmptyDaysPerMetric() throws {
        let now = try at(2027, 3, 15, 18) // the day after spring forward
        let result = PacingCalculator.compute(
            calories: { _ in 2_000 },
            steps: { self.key($0) == "2027-03-14" ? 0 : 6_000 },
            comparison: .allDays,
            lookbackDays: 14,
            excluded: [],
            now: now,
            calendar: la
        )
        XCTAssertEqual(result.calorieSampleDays, 14)
        XCTAssertEqual(result.stepSampleDays, 13)
    }

    /// Hourly buckets for each of the `days` days before `today`, `perHour` in
    /// every hour from `from` up to (not including) `to`.
    private func hourly(days: Int, before today: Date, perHour: Double, from: Int, to: Int) -> [Date: Double] {
        var buckets: [Date: Double] = [:]
        for offset in 1...days {
            let day = la.date(byAdding: .day, value: -offset, to: today)!
            for hour in from..<to {
                buckets[day.addingTimeInterval(Double(hour) * 3_600)] = perHour
            }
        }
        return buckets
    }

    // Overnight report F01: "usual by now" follows the user's own day. Someone
    // who walks only after 17:00 has walked nothing by 08:00 on a usual day and
    // everything by 20:00, whatever share of the clock day has gone by.
    func testUsualByNowFollowsTheUsersOwnIntradayCurve() throws {
        let today = try at(2026, 7, 22)
        let intraday = PacingCalculator.IntradayHistory(
            calories: hourly(days: 30, before: today, perHour: 100, from: 0, to: 24),
            steps: hourly(days: 30, before: today, perHour: 3_000, from: 17, to: 20)
        )
        func pace(at hour: Int, _ minute: Int = 0) throws -> PacingResult {
            PacingCalculator.compute(
                calories: { _ in 2_400 }, steps: { _ in 9_000 },
                comparison: .allDays, lookbackDays: 30, excluded: [],
                now: try at(2026, 7, 22, hour, minute), calendar: la, intraday: intraday
            )
        }
        XCTAssertEqual(try pace(at: 8).avgSteps, 0)
        XCTAssertEqual(try pace(at: 20).avgSteps, 9_000)
        // Inside an hour the current bucket counts pro rata.
        XCTAssertEqual(try pace(at: 17, 30).avgSteps, 1_500)
        XCTAssertEqual(try XCTUnwrap(try pace(at: 8).avgCalories), 800, accuracy: 0.001)
        XCTAssertEqual(try pace(at: 8).avgStepsFullDay, 9_000)
        XCTAssertEqual(ProjectionCalculator.projectedEndOfDay(
            current: 800, usualByNow: Double(try XCTUnwrap(try pace(at: 8).avgSteps)), usualFullDay: 9_000
        ), 9_800)
    }

    // With hourly history for only part of the lookback, the shape learned from
    // those days scales the whole window's full-day average.
    func testIntradayShapeScalesTheFullLookbackAverage() throws {
        let now = try at(2026, 7, 22, 18)
        let intraday = PacingCalculator.IntradayHistory(
            calories: [:],
            steps: hourly(days: 5, before: try at(2026, 7, 22), perHour: 1_000, from: 10, to: 20)
        )
        let result = PacingCalculator.compute(
            calories: { _ in 2_000 }, steps: { _ in 12_000 },
            comparison: .allDays, lookbackDays: 30, excluded: [],
            now: now, calendar: la, intraday: intraday
        )
        // 8 of 10 walking hours are done by 18:00 on a usual day.
        XCTAssertEqual(result.avgSteps, 9_600)
        // No hourly calories: clock time, as before.
        XCTAssertEqual(try XCTUnwrap(result.avgCalories), 1_500, accuracy: 0.001)
    }

    // Thin hourly history (one day) is not a usual day yet: keep clock time.
    func testThinIntradayHistoryFallsBackToClockTime() throws {
        let intraday = PacingCalculator.IntradayHistory(
            calories: [:],
            steps: hourly(days: 1, before: try at(2026, 7, 22), perHour: 3_000, from: 17, to: 20)
        )
        let result = PacingCalculator.compute(
            calories: { _ in 2_400 }, steps: { _ in 9_000 },
            comparison: .allDays, lookbackDays: 30, excluded: [],
            now: try at(2026, 7, 22, 8), calendar: la, intraday: intraday
        )
        XCTAssertEqual(result.avgSteps, 3_000)
    }

    // MARK: - Rollover and cache backfill

    // edded006: the day rollover finalizes exactly once, on the first wake after
    // midnight, and a first launch only records where it is.
    func testRolloverFinalizesOnTheFirstWakePastMidnight() throws {
        let todayKey = key(try at(2026, 11, 2, 0, 0, 5))
        XCTAssertEqual(DayRollover.action(previousKey: key(try at(2026, 11, 1, 23, 59, 59)), todayKey: todayKey), .finalize)
        XCTAssertEqual(DayRollover.action(previousKey: todayKey, todayKey: todayKey), .none)
        XCTAssertEqual(DayRollover.action(previousKey: nil, todayKey: todayKey), .recordOnly)
    }

    // 7b3ea59: the backfilled window is contiguous, one row per calendar day with
    // zeroes for missing ones, across both DST changes and a year end.
    func testCachedWindowBackfillsOneRowPerCalendarDay() throws {
        for (start, end, days) in [
            (try at(2026, 10, 30), try at(2026, 11, 3, 15), 5),
            (try at(2027, 3, 12), try at(2027, 3, 16), 5),
            (try at(2026, 12, 30), try at(2027, 1, 2), 4),
        ] {
            let present = key(start)
            let rows = CachedHistoryWindow.fill(
                rows: [present: (date: start, active: 10, resting: 20, steps: 30)],
                from: start, to: end, calendar: la
            )
            XCTAssertEqual(rows.count, days)
            XCTAssertEqual(rows.first?.active, 10)
            XCTAssertEqual(rows.dropFirst().map(\.active), Array(repeating: 0, count: days - 1))
            XCTAssertEqual(Set(rows.map { key($0.date) }).count, days, "a day repeated or skipped")
            for row in rows { XCTAssertEqual(row.date, la.startOfDay(for: row.date)) }
        }
    }
}
