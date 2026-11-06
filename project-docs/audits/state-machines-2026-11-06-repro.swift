// Moved out of VitalsTests/ so it does not break the build. Copy back into VitalsTests/ to run:
//   gh-sim test --scheme Vitals --only VitalsTests/StateMachineAuditRepro
import XCTest
import Foundation

/// State machine audit repro suite (2026-11-06). Failing tests assert the
/// promised behaviour; each has a passing control beside it that shows the
/// harness itself is sound. Not part of the shipping suite.
///
/// `vitalsAppGroupID` is declared by ReviewPromptTrackerTests.swift in this bundle.
@MainActor
final class StateMachineAuditRepro: XCTestCase {

    // MARK: SM-1  Averages pause start drifts a day earlier after a westward time zone move

    private func calendar(_ id: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: id)!
        return calendar
    }

    /// What `GoalSettings.pauseAverages(from:)` stores: the instant of local midnight.
    private func storedPauseInstant(day: Int, in calendar: Calendar) -> Date {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: day))!
        return DateHelpers.startOfDay(midnight, calendar: calendar)
    }

    func testControlPauseCoversStartDayThroughTodayInTheZoneItWasStartedIn() {
        let ny = calendar("America/New_York")
        let since = storedPauseInstant(day: 7, in: ny)
        let now = ny.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        XCTAssertEqual(
            ExcludedDays.pausedKeys(since: since, now: now, calendar: ny),
            ["2026-11-07", "2026-11-08", "2026-11-09"]
        )
    }

    func testControlPauseStartSurvivesAnEastwardTimeZoneMove() {
        let la = calendar("America/Los_Angeles")
        let ny = calendar("America/New_York")
        let since = storedPauseInstant(day: 7, in: la)
        let now = ny.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        XCTAssertEqual(
            ExcludedDays.pausedKeys(since: since, now: now, calendar: ny),
            ["2026-11-07", "2026-11-08", "2026-11-09"]
        )
    }

    /// Paused on 7 Nov in New York, then the phone is in Los Angeles. The pause
    /// should still start on 7 Nov: ExcludedDays says "every day from the pause
    /// date through today is excluded".
    func testPauseStartSurvivesAWestwardTimeZoneMove() {
        let ny = calendar("America/New_York")
        let la = calendar("America/Los_Angeles")
        let since = storedPauseInstant(day: 7, in: ny)
        let now = la.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        XCTAssertEqual(
            ExcludedDays.pausedKeys(since: since, now: now, calendar: la),
            ["2026-11-07", "2026-11-08", "2026-11-09"]
        )
    }

    // MARK: SM-2  Streak celebration fires a lower tier after a higher one

    func testControlSeedingConsumesEveryTierAtOrBelowTheStreak() {
        var fired: Set<String> = []
        MilestoneCalculator.seedFiredStreakIds(currentStreak: 15, into: &fired)
        XCTAssertEqual(fired, ["streak_7", "streak_14"])
        XCTAssertNil(MilestoneCalculator.unfiredStreakMilestone(currentStreak: 16, firedIds: fired))
    }

    func testControlLargestReachedTierIsTheOneCelebrated() {
        let event = MilestoneCalculator.unfiredStreakMilestone(currentStreak: 15, firedIds: [])
        XCTAssertEqual(event, .goalStreak(n: 14))
    }

    /// The caller (DashboardView.checkGoalStreakMilestone, MainTabView.handleMilestone)
    /// stores only the celebrated tier's id. Next session the lower, passed tier
    /// is still "unfired".
    func testCelebratingAHigherTierRetiresTheLowerOnes() {
        var fired: Set<String> = []
        let first = MilestoneCalculator.unfiredStreakMilestone(currentStreak: 15, firedIds: fired)
        XCTAssertEqual(first, .goalStreak(n: 14))
        fired.insert(first!.id)
        XCTAssertNil(
            MilestoneCalculator.unfiredStreakMilestone(currentStreak: 16, firedIds: fired),
            "next session celebrates \(String(describing: MilestoneCalculator.unfiredStreakMilestone(currentStreak: 16, firedIds: fired)))"
        )
    }

    // MARK: SM-3  Subscriber tenure counts a lapsed stretch

    private let tenureKeys = [
        "reviewPrompt.proSince",
        "reviewPrompt.subscriberMomentFired",
        "reviewPrompt.positiveMomentCount",
        "reviewPrompt.pendingPositiveMoment",
    ]
    private var savedTenure: [String: Any] = [:]

    override func setUp() async throws {
        let defaults = UserDefaults(suiteName: vitalsAppGroupID)!
        savedTenure = [:]
        for key in tenureKeys {
            if let value = defaults.object(forKey: key) { savedTenure[key] = value }
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() async throws {
        let defaults = UserDefaults(suiteName: vitalsAppGroupID)!
        for key in tenureKeys {
            if let value = savedTenure[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }

    func testControlContinuousSubscriberIsAskedAtThirtyDays() {
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: t0))
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: day(29)))
        XCTAssertTrue(ReviewPromptTracker.recordProStatus(isPro: true, now: day(31)))
    }

    func testControlLapsedSubscriberIsNotAsked() {
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: t0))
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: false, now: day(40)))
    }

    /// Subscribed (a trial), lapsed after 8 days, came back on day 40. Day 40 is
    /// the first day of the new subscription, not 30 days of "kept Vitals+".
    func testResubscribingAfterALapseStartsTenureAgain() {
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: t0))
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: false, now: day(8)))
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: day(40)))
    }
}
