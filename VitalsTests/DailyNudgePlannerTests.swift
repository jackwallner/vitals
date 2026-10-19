import XCTest

final class DailyNudgePlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 7:00 PM on an arbitrary day.
    private var evening: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 19))!
    }

    // MARK: Goal reached

    func testNewlyReachedSkipsAnnouncedAndUnmetGoals() {
        let reached = DailyNudgePlanner.newlyReached(
            calories: 2_600, steps: 9_000, calorieGoal: 2_500, stepGoal: 10_000, announced: []
        )
        XCTAssertEqual(reached, [.calories])
        let again = DailyNudgePlanner.newlyReached(
            calories: 2_600, steps: 10_500, calorieGoal: 2_500, stepGoal: 10_000, announced: [.calories]
        )
        XCTAssertEqual(again, [.steps])
    }

    func testNoGoalMeansNothingToReach() {
        XCTAssertEqual(
            DailyNudgePlanner.newlyReached(calories: 9_000, steps: 90_000, calorieGoal: nil, stepGoal: nil, announced: []),
            []
        )
    }

    func testGoalReachedCopyLinksToTheMetric() throws {
        let content = try XCTUnwrap(DailyNudgePlanner.goalReached(
            [.steps], calories: 1_800, steps: 10_240, calorieGoal: 2_500, stepGoal: 10_000
        ))
        XCTAssertEqual(content.title, "Step goal reached")
        XCTAssertEqual(content.body, "10,240 of 10,000 steps today.")
        XCTAssertEqual(content.link, .metric(.steps))
    }

    func testBothGoalsReachedLinksToToday() throws {
        let content = try XCTUnwrap(DailyNudgePlanner.goalReached(
            [.calories, .steps], calories: 2_600, steps: 10_240, calorieGoal: 2_500, stepGoal: 10_000
        ))
        XCTAssertEqual(content.title, "Both goals reached")
        XCTAssertEqual(content.link, .today)
    }

    // MARK: Evening reminder

    func testCalorieShortfallNetsOutRestingStillToCome() throws {
        // 1,140 resting over 19 hours is 60 an hour, so 300 more by midnight:
        // 400 + 1,140 + 300 = 1,840 against 2,500 leaves 660 active.
        let gap = try XCTUnwrap(DailyNudgePlanner.calorieShortfall(
            active: 400, resting: 1_140, goal: 2_500, now: evening, calendar: calendar
        ))
        XCTAssertEqual(gap, 660, accuracy: 0.001)
    }

    func testRestingAloneReachingTheGoalIsNoShortfall() {
        XCTAssertNil(DailyNudgePlanner.calorieShortfall(
            active: 800, resting: 1_140, goal: 2_200, now: evening, calendar: calendar
        ))
    }

    func testStepsOnlyReminderSuggestsAWalk() throws {
        let content = try XCTUnwrap(DailyNudgePlanner.evening(
            active: 900, resting: 1_140, steps: 7_900, calorieGoal: 2_000, stepGoal: 10_000,
            calorieStreak: 0, stepStreak: 0, now: evening, calendar: calendar
        ))
        XCTAssertEqual(content.title, "2,100 steps to go")
        XCTAssertEqual(content.body, "About a 25 min walk closes out your step goal.")
        XCTAssertEqual(content.link, .today)
    }

    func testLiveStreakLeadsTheReminder() throws {
        let content = try XCTUnwrap(DailyNudgePlanner.evening(
            active: 900, resting: 1_140, steps: 7_900, calorieGoal: 2_000, stepGoal: 10_000,
            calorieStreak: 0, stepStreak: 12, now: evening, calendar: calendar
        ))
        XCTAssertEqual(content.title, "Keep your 12-day step streak")
        XCTAssertEqual(content.body, "2,100 steps to go today, about a 25 min walk.")
    }

    func testStreakOnAMetGoalIsNotMentioned() throws {
        // The step streak is safe today; only calories are open.
        let content = try XCTUnwrap(DailyNudgePlanner.evening(
            active: 400, resting: 1_140, steps: 11_000, calorieGoal: 2_500, stepGoal: 10_000,
            calorieStreak: 0, stepStreak: 30, now: evening, calendar: calendar
        ))
        XCTAssertEqual(content.title, "About 660 active cal to go")
    }

    func testCalorieStreakReminder() throws {
        let content = try XCTUnwrap(DailyNudgePlanner.evening(
            active: 400, resting: 1_140, steps: 11_000, calorieGoal: 2_500, stepGoal: 10_000,
            calorieStreak: 5, stepStreak: 0, now: evening, calendar: calendar
        ))
        XCTAssertEqual(content.title, "Keep your 5-day calorie streak")
        XCTAssertEqual(content.body, "About 660 active cal to go today.")
    }

    func testBothOpenWithoutStreak() throws {
        let content = try XCTUnwrap(DailyNudgePlanner.evening(
            active: 400, resting: 1_140, steps: 7_900, calorieGoal: 2_500, stepGoal: 10_000,
            calorieStreak: 1, stepStreak: 1, now: evening, calendar: calendar
        ))
        XCTAssertEqual(content.title, "Today's goals are still open")
        XCTAssertEqual(content.body, "2,100 steps and about 660 active cal to go.")
    }

    func testNothingToSayWhenEveryGoalIsMet() {
        XCTAssertNil(DailyNudgePlanner.evening(
            active: 1_200, resting: 1_140, steps: 12_000, calorieGoal: 2_000, stepGoal: 10_000,
            calorieStreak: 9, stepStreak: 9, now: evening, calendar: calendar
        ))
    }

    func testLongWalksAreNotSuggested() {
        XCTAssertNil(DailyNudgePlanner.walkMinutes(forSteps: 15_000))
        XCTAssertEqual(DailyNudgePlanner.walkMinutes(forSteps: 300), 5)
    }
}
