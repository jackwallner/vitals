import XCTest

/// Covers the one rule the whole feature rests on: an excluded day counts
/// toward nothing, and a paused stretch excludes every day it covers without
/// anything having to run at midnight.
final class ExcludedDaysTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)))
    }

    // MARK: - Keys and the pause range

    func testKeyMatchesTheCacheSpelling() throws {
        let date = try day(2026, 9, 3)
        XCTAssertEqual(ExcludedDays.key(for: date), "2026-09-03")
        XCTAssertEqual(ExcludedDays.key(for: date), DailyHealthRecord.key(for: date))
    }

    func testPausedKeysCoverPauseDayThroughTodayInclusive() throws {
        let keys = ExcludedDays.pausedKeys(
            since: try day(2026, 9, 8),
            now: try day(2026, 9, 11),
            calendar: calendar
        )
        XCTAssertEqual(keys, ["2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11"])
    }

    func testNotPausedCoversNothing() {
        XCTAssertTrue(ExcludedDays.pausedKeys(since: nil, now: .now, calendar: calendar).isEmpty)
    }

    func testPauseDatedInTheFutureCoversNothing() throws {
        let keys = ExcludedDays.pausedKeys(
            since: try day(2026, 9, 20),
            now: try day(2026, 9, 11),
            calendar: calendar
        )
        XCTAssertTrue(keys.isEmpty)
    }

    func testEffectiveKeysUnionPickedDaysWithTheRunningPause() throws {
        let suite = "ExcludedDaysTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        ExcludedDays.save(["2026-08-01"], to: defaults)
        ExcludedDays.savePausedSince(try day(2026, 9, 10), to: defaults)

        let keys = ExcludedDays.effectiveKeys(from: defaults, now: try day(2026, 9, 11))
        XCTAssertEqual(keys, ["2026-08-01", "2026-09-10", "2026-09-11"])
    }

    // MARK: - Parsing keys back into dates

    func testKeyParsesToTheSameGregorianDayOnANonGregorianDevice() throws {
        let date = try XCTUnwrap(ExcludedDays.date(fromKey: "2026-09-03"))
        XCTAssertEqual(ExcludedDays.key(for: date), "2026-09-03")

        // What a Thai device's Calendar.current reads that instant as: the same
        // day, in Buddhist-era numbering. The old parse landed in 1483.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = .current
        let parts = buddhist.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(parts.year, 2569)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 3)
        XCTAssertEqual(buddhist.startOfDay(for: date), date)
    }

    func testEveryDayOfAYearRoundTripsThroughItsKey() throws {
        var cursor = try day(2027, 1, 1)
        let end = try day(2028, 1, 1)
        while cursor < end {
            let key = ExcludedDays.key(for: cursor)
            XCTAssertEqual(ExcludedDays.date(fromKey: key), cursor, key)
            cursor = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: cursor))
        }
    }

    func testMalformedKeyParsesToNil() {
        XCTAssertNil(ExcludedDays.date(fromKey: "2026-09"))
        XCTAssertNil(ExcludedDays.date(fromKey: "not-a-day"))
    }

    // MARK: - Key cache

    func testCacheHoldsTheSetUntilMidnightThenAddsTheNewPausedDay() throws {
        var cache = ExcludedDays.KeyCache()
        let pause = try day(2026, 9, 10)
        let morning = try XCTUnwrap(calendar.date(byAdding: .hour, value: 9, to: try day(2026, 9, 11)))
        let lateEvening = try XCTUnwrap(calendar.date(byAdding: .hour, value: 23, to: try day(2026, 9, 11)))
        let nextMorning = try XCTUnwrap(calendar.date(byAdding: .hour, value: 1, to: try day(2026, 9, 12)))

        XCTAssertEqual(cache.keys(picked: [], pausedSince: pause, now: morning, calendar: calendar), ["2026-09-10", "2026-09-11"])
        // Still the same day: the cached set comes back even for different inputs,
        // which is why the owner has to invalidate on every change.
        XCTAssertEqual(cache.keys(picked: ["2026-01-01"], pausedSince: pause, now: lateEvening, calendar: calendar), ["2026-09-10", "2026-09-11"])
        XCTAssertEqual(
            cache.keys(picked: [], pausedSince: pause, now: nextMorning, calendar: calendar),
            ["2026-09-10", "2026-09-11", "2026-09-12"]
        )
    }

    func testInvalidatedCachePicksUpAChangedSet() throws {
        var cache = ExcludedDays.KeyCache()
        let now = try day(2026, 9, 11)
        XCTAssertEqual(cache.keys(picked: ["2026-08-01"], pausedSince: nil, now: now, calendar: calendar), ["2026-08-01"])
        cache.invalidate()
        XCTAssertEqual(cache.keys(picked: ["2026-08-02"], pausedSince: nil, now: now, calendar: calendar), ["2026-08-02"])
    }

    func testCacheRecomputesWhenTheClockGoesBackADay() throws {
        var cache = ExcludedDays.KeyCache()
        let pause = try day(2026, 9, 1)
        _ = cache.keys(picked: [], pausedSince: pause, now: try day(2026, 9, 11), calendar: calendar)
        XCTAssertEqual(cache.keys(picked: [], pausedSince: pause, now: try day(2026, 9, 2), calendar: calendar), ["2026-09-01", "2026-09-02"])
    }

    /// History reads the set once per record per chart bar. Rebuilding a long
    /// pause on each read hung the screen in 1.8.6; a cached read must be cheap
    /// enough that a year of History costs nothing noticeable.
    func testRepeatedReadsDuringALongPauseStayCheap() throws {
        var cache = ExcludedDays.KeyCache()
        let now = try day(2026, 9, 11)
        let pause = try XCTUnwrap(calendar.date(byAdding: .day, value: -400, to: now))
        let start = Date()
        var total = 0
        for _ in 0..<100_000 {
            total += cache.keys(picked: [], pausedSince: pause, now: now, calendar: calendar).count
        }
        XCTAssertEqual(total, 401 * 100_000)
        // Uncached this is 40 million key builds (minutes). Cached it is well
        // under a second; the bound is loose for a loaded simulator host.
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testSavingAnEmptySetClearsTheKey() throws {
        let suite = "ExcludedDaysTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        ExcludedDays.save(["2026-08-01"], to: defaults)
        ExcludedDays.save([], to: defaults)
        XCTAssertTrue(ExcludedDays.load(from: defaults).isEmpty)
        XCTAssertNil(defaults.object(forKey: ExcludedDays.defaultsKey))
    }

    // MARK: - TDEE / BMR

    func testEnergyAveragesDropExcludedDays() throws {
        let reference = try day(2026, 9, 11)
        // 10 completed days: nine ordinary, one huge.
        let records: [(date: Date, active: Double, resting: Double)] = (1...10).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: reference) else { return nil }
            let active: Double = offset == 1 ? 4_000 : 500
            return (date: date, active: active, resting: 1_500)
        }

        let all = EnergyAveragesCalculator.compute(records: records, referenceDate: reference)
        XCTAssertEqual(all.sampleDays, 10)
        XCTAssertEqual(try XCTUnwrap(all.tdee), 2_350, accuracy: 0.001)

        let outlierDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: reference))
        let filtered = EnergyAveragesCalculator.compute(
            records: records,
            referenceDate: reference,
            excludedKeys: [ExcludedDays.key(for: outlierDay)]
        )
        XCTAssertEqual(filtered.sampleDays, 9)
        XCTAssertEqual(try XCTUnwrap(filtered.tdee), 2_000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(filtered.bmr), 1_500, accuracy: 0.001)
    }

    func testExcludingEnoughDaysDropsBelowTheSampleFloor() throws {
        let reference = try day(2026, 9, 11)
        let records: [(date: Date, active: Double, resting: Double)] = (1...8).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: reference) else { return nil }
            return (date: date, active: 500, resting: 1_500)
        }
        let excluded = Set((1...2).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: reference).map(ExcludedDays.key(for:))
        })

        let result = EnergyAveragesCalculator.compute(
            records: records,
            referenceDate: reference,
            excludedKeys: excluded
        )
        XCTAssertEqual(result.sampleDays, 6)
        XCTAssertNil(result.tdee)
        XCTAssertNil(result.bmr)
    }

    // MARK: - Trend averages

    func testCalorieTrendKeepsExcludedDaysAsPointsButOutOfTheAverage() throws {
        let end = try day(2026, 4, 26)
        let history = makeHistory(days: 14, ending: end) { index in
            // index 12 is yesterday: a 6,000 calorie day that would drag the week.
            index == 12 ? (active: 4_500, resting: 1_500) : (active: 500, resting: 1_500)
        }
        let excludedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: end))

        let summary = try XCTUnwrap(
            CalorieTrendSummary.make(
                history: history,
                excludedKeys: [ExcludedDays.key(for: excludedDay)],
                calendar: calendar
            )
        )

        // Still drawn.
        let point = try XCTUnwrap(summary.points.first { calendar.isDate($0.date, inSameDayAs: excludedDay) })
        XCTAssertTrue(point.isExcluded)
        XCTAssertEqual(point.totalCalories, 6_000, accuracy: 0.001)

        // Counted by nothing: the window walks back to the last day that still
        // counts, so the average is seven ordinary days with no trace of the 6,000.
        XCTAssertEqual(summary.weekly.sampleDays, 7)
        XCTAssertEqual(try XCTUnwrap(summary.weekly.average), 2_000, accuracy: 0.001)

        // Without the exclusion the same week carries the outlier.
        let unfiltered = try XCTUnwrap(CalorieTrendSummary.make(history: history, calendar: calendar))
        XCTAssertEqual(try XCTUnwrap(unfiltered.weekly.average), (6_000 + 6 * 2_000) / 7, accuracy: 0.001)
    }

    func testStepTrendAverageSkipsExcludedDays() throws {
        let end = try day(2026, 4, 26)
        let history = makeHistory(days: 14, ending: end, steps: { index in index == 12 ? 40_000 : 8_000 }) { _ in
            (active: 500, resting: 1_500)
        }
        let excludedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: end))

        let summary = try XCTUnwrap(
            StepTrendSummary.make(
                history: history,
                excludedKeys: [ExcludedDays.key(for: excludedDay)],
                calendar: calendar
            )
        )
        // Six: the step window keys off the wall clock rather than the dataset's
        // last day, so it keeps its reference and simply drops the excluded day.
        XCTAssertEqual(summary.weekly.sampleDays, 6)
        XCTAssertEqual(try XCTUnwrap(summary.weekly.average), 8_000, accuracy: 0.001)
        let unfiltered = try XCTUnwrap(StepTrendSummary.make(history: history, calendar: calendar))
        XCTAssertEqual(try XCTUnwrap(unfiltered.weekly.average), (40_000 + 6 * 8_000) / 7, accuracy: 0.001)
        let point = try XCTUnwrap(summary.points.first { calendar.isDate($0.date, inSameDayAs: excludedDay) })
        XCTAssertTrue(point.isExcluded)
    }

    // MARK: - Streaks

    func testExcludedDayNeitherBreaksNorExtendsAStreak() throws {
        let today = try day(2026, 9, 11)
        // Yesterday and the two days before it hit; the day before that missed,
        // and is the day the user excluded.
        let days: [MilestoneDay] = try (1...5).map { offset in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: today))
            let hit = offset != 4
            return MilestoneDay(date: date, calories: hit ? 3_000 : 400, steps: hit ? 12_000 : 900)
        }
        let missedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -4, to: today))

        let broken = MilestoneCalculator.currentGoalStreak(
            records: days,
            calorieGoal: 2_500,
            stepGoal: 10_000,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(broken, 3)

        let bridged = MilestoneCalculator.currentGoalStreak(
            records: days,
            calorieGoal: 2_500,
            stepGoal: 10_000,
            today: today,
            calendar: calendar,
            excludedKeys: [ExcludedDays.key(for: missedDay)]
        )
        // The excluded day is stepped over: three before it, one after.
        XCTAssertEqual(bridged, 4)
    }

    func testAnExcludedDayWithNoRecordAlsoBridgesTheStreak() throws {
        let today = try day(2026, 9, 11)
        // No row at all for the gap day (offset 3): a HealthKit hole the user
        // excluded because the watch was off.
        let days: [MilestoneDay] = try [1, 2, 4, 5].map { offset in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: today))
            return MilestoneDay(date: date, calories: 3_000, steps: 12_000)
        }
        let gapDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: today))

        XCTAssertEqual(
            MilestoneCalculator.currentGoalStreak(
                records: days,
                calorieGoal: 2_500,
                stepGoal: 10_000,
                today: today,
                calendar: calendar
            ),
            2
        )
        XCTAssertEqual(
            MilestoneCalculator.currentGoalStreak(
                records: days,
                calorieGoal: 2_500,
                stepGoal: 10_000,
                today: today,
                calendar: calendar,
                excludedKeys: [ExcludedDays.key(for: gapDay)]
            ),
            4
        )
    }

    func testAllDaysExcludedTerminatesWithNoStreak() throws {
        let today = try day(2026, 9, 11)
        let days: [MilestoneDay] = try (1...5).map { offset in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: today))
            return MilestoneDay(date: date, calories: 3_000, steps: 12_000)
        }
        let excluded = Set(days.map { ExcludedDays.key(for: $0.date) })

        XCTAssertEqual(
            MilestoneCalculator.currentGoalStreak(
                records: days,
                calorieGoal: 2_500,
                stepGoal: 10_000,
                today: today,
                calendar: calendar,
                excludedKeys: excluded
            ),
            0
        )
    }

    // MARK: - Weekly recap

    func testWeeklyRecapDropsExcludedDaysFromBothWeeks() throws {
        let today = try day(2026, 9, 11)
        let records: [MilestoneDay] = try (1...14).map { offset in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: today))
            // Offset 1 is a 6,000 outlier; every other day is 2,000.
            return MilestoneDay(date: date, calories: offset == 1 ? 6_000 : 2_000, steps: 10_000)
        }
        let outlier = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))

        let plain = try XCTUnwrap(
            WeeklyRecapBuilder.build(records: records, calorieGoal: nil, stepGoal: nil, today: today, calendar: calendar)
        )
        XCTAssertEqual(plain.daysWithData, 7)
        XCTAssertEqual(plain.avgCalories, (6_000 + 6 * 2_000) / 7, accuracy: 0.001)

        let filtered = try XCTUnwrap(
            WeeklyRecapBuilder.build(
                records: records,
                calorieGoal: nil,
                stepGoal: nil,
                today: today,
                calendar: calendar,
                excludedKeys: [ExcludedDays.key(for: outlier)]
            )
        )
        XCTAssertEqual(filtered.daysWithData, 6)
        XCTAssertEqual(filtered.avgCalories, 2_000, accuracy: 0.001)
        XCTAssertEqual(filtered.bestCalorieValue, 2_000)
    }

    // MARK: - Net deficit

    func testNetDeficitTrendCountsNeitherExcludedDaysNorUnloggedOnes() throws {
        let end = try day(2026, 4, 26)
        let history = makeHistory(days: 10, ending: end) { _ in (active: 900, resting: 1_500) }
        var foodByDate: [Date: Double] = [:]
        for row in history { foodByDate[row.date] = 1_800 }
        let excludedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: end))

        let summary = try XCTUnwrap(
            NetDeficitTrendSummary.make(
                history: history,
                foodByDate: foodByDate,
                excludedKeys: [ExcludedDays.key(for: excludedDay)],
                calendar: calendar
            )
        )

        let point = try XCTUnwrap(summary.points.first { calendar.isDate($0.date, inSameDayAs: excludedDay) })
        XCTAssertTrue(point.isExcluded, "the chart needs to know why this day doesn't count")
        XCTAssertFalse(point.counts, "an excluded day must not feed the net-deficit average")
        XCTAssertFalse(summary.points.filter(\.counts).contains { calendar.isDate($0.date, inSameDayAs: excludedDay) })
        XCTAssertEqual(try XCTUnwrap(summary.weekly.average), 600, accuracy: 0.001)
    }

    /// The watch draws `isLogged`, not `counts`: an excluded day with food logged
    /// keeps its (dimmed) bar, and only a day with no food is a placeholder.
    func testNetDeficitPointSeparatesExcludedFromUnlogged() throws {
        let end = try day(2026, 4, 26)
        let history = makeHistory(days: 10, ending: end) { _ in (active: 900, resting: 1_500) }
        let excludedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: end))
        let unloggedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: end))
        var foodByDate: [Date: Double] = [:]
        for row in history where !calendar.isDate(row.date, inSameDayAs: unloggedDay) {
            foodByDate[row.date] = 1_800
        }

        let summary = try XCTUnwrap(
            NetDeficitTrendSummary.make(
                history: history,
                foodByDate: foodByDate,
                excludedKeys: [ExcludedDays.key(for: excludedDay)],
                calendar: calendar
            )
        )

        let excluded = try XCTUnwrap(summary.points.first { calendar.isDate($0.date, inSameDayAs: excludedDay) })
        XCTAssertTrue(excluded.isLogged, "an excluded logged day must still draw its bar")
        XCTAssertFalse(excluded.counts)

        let unlogged = try XCTUnwrap(summary.points.first { calendar.isDate($0.date, inSameDayAs: unloggedDay) })
        XCTAssertFalse(unlogged.isLogged, "an unlogged day is the placeholder")
        XCTAssertFalse(unlogged.isExcluded)
    }

    // MARK: - Month review

    func testMonthReviewIgnoresExcludedDays() throws {
        // Day 2 of the month, so the prior month is in the review window.
        let today = try day(2026, 5, 2)
        let records: [MilestoneDay] = try (1...22).map { dayOfMonth in
            MilestoneDay(date: try day(2026, 4, dayOfMonth), calories: 2_000, steps: 9_000)
        }

        XCTAssertEqual(
            MilestoneCalculator.reviewableLastMonth(records: records, today: today, calendar: calendar),
            .monthReview(month: "2026-04", daysWithData: 22)
        )

        // Excluding three of them drops the month under the 20-day bar.
        let excluded = Set(try (20...22).map { ExcludedDays.key(for: try day(2026, 4, $0)) })
        XCTAssertNil(
            MilestoneCalculator.reviewableLastMonth(
                records: records,
                today: today,
                calendar: calendar,
                excludedKeys: excluded
            )
        )
    }

    // MARK: - Macros

    func testMacroSummaryDropsExcludedDays() throws {
        let start = try day(2026, 9, 1)
        var macrosByDay: [Date: MacroTotals] = [:]
        for offset in 0..<4 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
            macrosByDay[date] = MacroTotals(protein: offset == 3 ? 400 : 100, carbs: 200, fat: 60)
        }
        let feast = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: start))

        let all = try XCTUnwrap(MacroSummary.make(macrosByDay: macrosByDay, calendar: calendar))
        XCTAssertEqual(all.loggedDays, 4)
        XCTAssertEqual(all.average.protein, 175, accuracy: 0.001)

        let filtered = try XCTUnwrap(
            MacroSummary.make(
                macrosByDay: macrosByDay,
                excludedKeys: [ExcludedDays.key(for: feast)],
                calendar: calendar
            )
        )
        XCTAssertEqual(filtered.loggedDays, 3)
        XCTAssertEqual(filtered.average.protein, 100, accuracy: 0.001)
        XCTAssertNil(filtered.days.first { calendar.isDate($0.date, inSameDayAs: feast) })
    }

    // MARK: - Goal days in the recap

    func testRecapGoalDaysOnlyCountDaysThatStillCount() throws {
        let today = try day(2026, 9, 11)
        // Yesterday hit the goal; the six days before it didn't.
        let records: [MilestoneDay] = try (1...7).map { offset in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: today))
            return MilestoneDay(date: date, calories: offset == 1 ? 3_000 : 1_500, steps: 4_000)
        }

        let plain = try XCTUnwrap(
            WeeklyRecapBuilder.build(
                records: records, calorieGoal: 2_500, stepGoal: nil, today: today, calendar: calendar
            )
        )
        XCTAssertEqual(plain.goalDaysHit, 1)
        XCTAssertEqual(plain.goalDaysPossible, 7)

        let hitDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let filtered = try XCTUnwrap(
            WeeklyRecapBuilder.build(
                records: records,
                calorieGoal: 2_500,
                stepGoal: nil,
                today: today,
                calendar: calendar,
                excludedKeys: [ExcludedDays.key(for: hitDay)]
            )
        )
        // Excluding a day takes it out of both halves of "3 of 7", never one.
        XCTAssertEqual(filtered.goalDaysHit, 0)
        XCTAssertEqual(filtered.goalDaysPossible, 6)
    }

    // MARK: - Helpers

    private func makeHistory(
        days: Int,
        ending end: Date,
        steps: (Int) -> Int = { _ in 8_000 },
        values: (Int) -> (active: Double, resting: Double)
    ) -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        (0..<days).compactMap { index in
            let reverseIndex = days - index - 1
            guard let date = calendar.date(byAdding: .day, value: -reverseIndex, to: end) else { return nil }
            let value = values(index)
            return (date: date, active: value.active, resting: value.resting, steps: steps(index))
        }
    }
}
