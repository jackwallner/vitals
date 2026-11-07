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

    private func pausedKeys(day: String, now: Date, in calendar: Calendar) -> Set<String> {
        ExcludedDays.pausedKeys(
            since: ExcludedDays.date(fromKey: day, timeZone: calendar.timeZone),
            now: now,
            calendar: calendar
        )
    }

    func testPauseOnADayAheadOfTodayStillCoversToday() {
        let la = calendar("America/Los_Angeles")
        let now = la.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!
        XCTAssertEqual(pausedKeys(day: "2026-11-07", now: now, in: la), ["2026-11-06"])
    }

    func testPauseCoversStartDayThroughToday() {
        let ny = calendar("America/New_York")
        let now = ny.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        XCTAssertEqual(
            pausedKeys(day: "2026-11-07", now: now, in: ny),
            ["2026-11-07", "2026-11-08", "2026-11-09"]
        )
    }

    func testPauseStartSurvivesMovingEitherWay() {
        for zone in ["America/Los_Angeles", "Asia/Tokyo", "Pacific/Auckland"] {
            let there = calendar(zone)
            let now = there.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
            XCTAssertEqual(
                pausedKeys(day: "2026-11-07", now: now, in: there),
                ["2026-11-07", "2026-11-08", "2026-11-09"],
                zone
            )
        }
    }

    /// Older builds stored the instant of local midnight. Whichever way the phone
    /// has since moved, the migration names the day the pause actually began.
    func testOldPauseInstantKeepsItsDayAfterTheZoneMoved() throws {
        for (startZone, instantUTC) in [
            ("America/New_York", "2026-11-07T05:00:00Z"),
            ("Asia/Tokyo", "2026-11-06T15:00:00Z"),
            ("Europe/London", "2026-11-07T00:00:00Z"),
            ("America/Los_Angeles", "2026-11-07T08:00:00Z"),
            ("Asia/Kolkata", "2026-11-06T18:30:00Z"),
            ("Pacific/Auckland", "2026-11-06T11:00:00Z"),
            ("Pacific/Honolulu", "2026-11-07T10:00:00Z")
        ] {
            let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: instantUTC))
            let original = NSTimeZone.default
            defer { NSTimeZone.default = original }
            // Every move, up to the widest the world allows.
            let offset = try XCTUnwrap(TimeZone(identifier: startZone)).secondsFromGMT(for: instant)
            for destination in stride(from: -12, through: 14, by: 1) {
                // Only an instant two real offsets share can be misread, and only from far away.
                if ["Pacific/Auckland", "Pacific/Honolulu"].contains(startZone), abs(destination * 3_600 - offset) >= 12 * 3_600 { continue }
                NSTimeZone.default = try XCTUnwrap(TimeZone(secondsFromGMT: destination * 3_600))
                let defaults = try XCTUnwrap(UserDefaults(suiteName: "pause.tests.\(UUID().uuidString)"))
                defaults.set(instant, forKey: ExcludedDays.pausedSinceKey)
                XCTAssertEqual(ExcludedDays.loadPausedDay(from: defaults), "2026-11-07", "\(startZone) to UTC\(destination)")
                XCTAssertEqual(
                    ExcludedDays.syncedPausedDay(day: nil, legacyInstant: instant.timeIntervalSince1970),
                    "2026-11-07"
                )
            }
        }
    }

    func testRunStartIsTheLatestUnbrokenPaidRun() throws {
        func day(_ n: Double) -> Date { Date(timeIntervalSince1970: n * 86_400) }
        XCTAssertNil(ReviewPromptTracker.proRunStart(periods: []))
        // Renewals back to back, out of order, are one run.
        XCTAssertEqual(
            ReviewPromptTracker.proRunStart(periods: [(day(30), day(60)), (day(0), day(30)), (day(60), day(90))]),
            day(0)
        )
        // A billing retry that recovers is still the same run.
        XCTAssertEqual(ReviewPromptTracker.proRunStart(periods: [(day(0), day(30)), (day(40), day(70))]), day(0))
        // A real lapse starts a new run.
        XCTAssertEqual(ReviewPromptTracker.proRunStart(periods: [(day(0), day(30)), (day(90), day(120))]), day(90))
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

    func testALaterStreakDoesNotCelebrateBelowTheBest() {
        XCTAssertNil(MilestoneCalculator.unfiredStreakMilestone(currentStreak: 7, firedIds: ["streak_14"]))
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
