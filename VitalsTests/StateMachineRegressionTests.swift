import Foundation
import XCTest

/// Regressions from the 2026-11-06 state machine audit
/// (`project-docs/audits/state-machines-2026-11-06.md`).
@MainActor
final class StateMachineRegressionTests: XCTestCase {

    // MARK: SM-1  The pause start is a calendar day, wherever the phone goes

    private func calendar(_ id: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: id)!
        return calendar
    }

    func testPauseCoversStartDayThroughToday() {
        let ny = calendar("America/New_York")
        let now = ny.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        XCTAssertEqual(
            ExcludedDays.pausedKeys(sinceDay: "2026-11-07", now: now, calendar: ny),
            ["2026-11-07", "2026-11-08", "2026-11-09"]
        )
    }

    func testPauseStartSurvivesMovingEitherWay() {
        for zone in ["America/Los_Angeles", "Asia/Tokyo", "Pacific/Auckland"] {
            let there = calendar(zone)
            let now = there.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
            XCTAssertEqual(
                ExcludedDays.pausedKeys(sinceDay: "2026-11-07", now: now, calendar: there),
                ["2026-11-07", "2026-11-08", "2026-11-09"],
                zone
            )
        }
    }

    func testPausedDayIsStoredAndTheOldInstantIsMigratedOnce() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pause.tests.\(UUID().uuidString)"))
        let instant = try XCTUnwrap(ExcludedDays.date(fromKey: "2026-11-07"))
        defaults.set(instant, forKey: ExcludedDays.pausedSinceKey)

        XCTAssertEqual(ExcludedDays.loadPausedDay(from: defaults), "2026-11-07")
        XCTAssertNil(defaults.object(forKey: ExcludedDays.pausedSinceKey))
        XCTAssertEqual(defaults.string(forKey: ExcludedDays.pausedDayDefaultsKey), "2026-11-07")
        XCTAssertEqual(ExcludedDays.loadPausedSince(from: defaults), instant)

        ExcludedDays.savePausedDay(nil, to: defaults)
        XCTAssertNil(ExcludedDays.loadPausedDay(from: defaults))
    }

    func testWatchReadsThePausedDayTheNewPhoneSendsAndTheInstantAnOldOneSends() throws {
        XCTAssertEqual(ExcludedDays.syncedPausedDay(day: "2026-11-07", legacyInstant: 1), "2026-11-07")
        XCTAssertNil(ExcludedDays.syncedPausedDay(day: "", legacyInstant: 1), "empty means no pause")
        XCTAssertNil(ExcludedDays.syncedPausedDay(day: nil, legacyInstant: 0))
        XCTAssertNil(ExcludedDays.syncedPausedDay(day: nil, legacyInstant: nil))
        let instant = try XCTUnwrap(ExcludedDays.date(fromKey: "2026-11-07")).timeIntervalSince1970
        XCTAssertEqual(ExcludedDays.syncedPausedDay(day: nil, legacyInstant: instant), "2026-11-07")
    }

    // MARK: SM-2  A higher streak tier retires the lower ones

    func testLargestReachedTierIsTheOneCelebrated() {
        XCTAssertEqual(
            MilestoneCalculator.unfiredStreakMilestone(currentStreak: 15, firedIds: []),
            .goalStreak(n: 14)
        )
    }

    func testCelebratingAHigherTierRetiresTheLowerOnes() {
        XCTAssertNil(MilestoneCalculator.unfiredStreakMilestone(currentStreak: 16, firedIds: ["streak_14"]))
    }

    func testTheNextTierStillFiresAfterASkippedOne() {
        XCTAssertEqual(
            MilestoneCalculator.unfiredStreakMilestone(currentStreak: 30, firedIds: ["streak_14"]),
            .goalStreak(n: 30)
        )
    }

    // MARK: SM-3  A lapse restarts subscriber tenure

    private let tenureKeys = [
        "reviewPrompt.proSince",
        "reviewPrompt.subscriberMomentFired",
        "reviewPrompt.positiveMomentCount",
        "reviewPrompt.pendingPositiveMoment",
    ]
    private var savedTenure: [String: Any] = [:]

    override func setUp() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: vitalsAppGroupID))
        savedTenure = [:]
        for key in tenureKeys {
            if let value = defaults.object(forKey: key) { savedTenure[key] = value }
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: vitalsAppGroupID))
        for key in tenureKeys {
            if let value = savedTenure[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    func testContinuousSubscriberIsAskedAtThirtyDays() {
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: start))
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: day(29)))
        XCTAssertTrue(ReviewPromptTracker.recordProStatus(isPro: true, now: day(31)))
    }

    func testLapsedSubscriberIsNotAsked() {
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: start))
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: false, now: day(40)))
    }

    func testResubscribingAfterALapseStartsTenureAgain() {
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: start))
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: false, now: day(8)))
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: day(40)))
        XCTAssertFalse(ReviewPromptTracker.recordProStatus(isPro: true, now: day(69)))
        XCTAssertTrue(ReviewPromptTracker.recordProStatus(isPro: true, now: day(71)))
    }
}
