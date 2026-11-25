import XCTest
import Foundation

// The app defines this in DataService.swift, which pulls in most of the app.
// The test bundle compiles the tracker on its own.
let vitalsAppGroupID = "group.com.jackwallner.vitals"

/// The rating-ask rules from the fleet policy: ask from the second launch, wait
/// out a 30-day cooldown, stop only when the user opened the review page, and
/// never let feedback stop or restart the asks.
@MainActor
final class ReviewPromptTrackerTests: XCTestCase {
    private var saved: (Int, Date?, Date?, ReviewPromptOutcome?, Bool)!
    private let paceDayKey = "reviewPrompt.paceMomentDay"
    private var savedPaceDay: String?

    override func setUp() async throws {
        saved = (
            ReviewPromptTracker.appLaunchCount,
            ReviewPromptTracker.firstAppOpenDate,
            ReviewPromptTracker.lastShownDate,
            ReviewPromptTracker.outcome,
            ReviewPromptTracker.hasPendingPositiveMoment
        )
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.lastShownDate = nil
        ReviewPromptTracker.outcome = nil
        ReviewPromptTracker.hasPendingPositiveMoment = false
        let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
        savedPaceDay = defaults.string(forKey: paceDayKey)
        defaults.removeObject(forKey: paceDayKey)
    }

    override func tearDown() async throws {
        ReviewPromptTracker.appLaunchCount = saved.0
        ReviewPromptTracker.firstAppOpenDate = saved.1
        ReviewPromptTracker.lastShownDate = saved.2
        ReviewPromptTracker.outcome = saved.3
        ReviewPromptTracker.hasPendingPositiveMoment = saved.4
        let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
        if let savedPaceDay { defaults.set(savedPaceDay, forKey: paceDayKey) } else { defaults.removeObject(forKey: paceDayKey) }
    }

    private func days(_ n: Double) -> Date { Date.now.addingTimeInterval(n * 86_400) }

    func testAsksFromTheSecondLaunch() {
        ReviewPromptTracker.appLaunchCount = 2
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
    }

    func testNeverAsksInTheFirstSession() {
        ReviewPromptTracker.appLaunchCount = 1
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
    }

    func testRequiresFinishedSetup() {
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: false))
    }

    func testWaitsOutTheCooldown() {
        ReviewPromptTracker.markShown()
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true, now: days(29)))
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true, now: days(31)))
    }

    func testOpeningTheReviewPageEndsTheAsks() {
        ReviewPromptTracker.markOpenedWriteReview()
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true, now: days(400)))
    }

    func testFeedbackDoesNotStopTheAsks() {
        ReviewPromptTracker.markFeedbackSubmitted()
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true, now: days(31)))
    }

    func testFeedbackAfterTheReviewPageKeepsTheAsksEnded() {
        ReviewPromptTracker.markOpenedWriteReview()
        ReviewPromptTracker.markFeedbackSubmitted()
        XCTAssertEqual(ReviewPromptTracker.outcome, .openedWriteReview)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true, now: days(400)))
    }

    func testBlockedAskKeepsTheMomentPending() {
        ReviewPromptTracker.recordPositiveMoment()
        XCTAssertTrue(ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: true))
        XCTAssertTrue(ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: true))
        ReviewPromptTracker.markShown()
        XCTAssertFalse(ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: true))
    }

    // MARK: Good moments

    func testCrossingEitherGoalIsAGoodMoment() {
        XCTAssertTrue(ReviewMoment.dailyGoalHit(crossedCalories: true, crossedSteps: false))
        XCTAssertTrue(ReviewMoment.dailyGoalHit(crossedCalories: false, crossedSteps: true))
        XCTAssertTrue(ReviewMoment.dailyGoalHit(crossedCalories: true, crossedSteps: true))
    }

    func testNoGoalCrossedIsNotAMoment() {
        XCTAssertFalse(ReviewMoment.dailyGoalHit(crossedCalories: false, crossedSteps: false))
    }

    func testOnlyAStreakMilestoneIsGood() {
        XCTAssertTrue(ReviewMoment.isGood(.goalStreak(n: 7)))
        XCTAssertFalse(ReviewMoment.isGood(.monthReview(month: "2026-10", daysWithData: 28)))
    }

    func testNothingAsksWithoutAMoment() {
        ReviewPromptTracker.appLaunchCount = 5
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
        XCTAssertFalse(ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: true))
    }

    func testASkippedMomentIsDroppedNotReplayed() {
        ReviewPromptTracker.recordPositiveMoment()
        ReviewPromptTracker.consumePendingPositiveMoment()
        XCTAssertFalse(ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: true))
    }

    func testTheSecondLaunchGateHoldsForAGoodMoment() {
        ReviewPromptTracker.recordPositiveMoment()
        ReviewPromptTracker.appLaunchCount = 1
        XCTAssertFalse(ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: true))
        ReviewPromptTracker.appLaunchCount = 2
        XCTAssertTrue(ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: true))
    }

    // MARK: Ahead of usual pace

    func testClearlyAheadOnStepsIsAGoodMoment() {
        XCTAssertTrue(ReviewMoment.aheadOfUsualPace(steps: 4_000, usualSteps: 3_000, calories: 900, usualCalories: nil))
    }

    func testClearlyAheadOnCaloriesIsAGoodMoment() {
        XCTAssertTrue(ReviewMoment.aheadOfUsualPace(steps: 0, usualSteps: nil, calories: 1_400, usualCalories: 1_200))
    }

    func testBehindOrLevelIsNotAMoment() {
        XCTAssertFalse(ReviewMoment.aheadOfUsualPace(steps: 2_000, usualSteps: 3_000, calories: 1_000, usualCalories: 1_200))
        XCTAssertFalse(ReviewMoment.aheadOfUsualPace(steps: 3_000, usualSteps: 3_000, calories: 1_200, usualCalories: 1_200))
    }

    func testATinyLeadIsNotAMoment() {
        // 300 steps over a usual 100 is triple, but under the 500 step floor.
        XCTAssertFalse(ReviewMoment.aheadOfUsualPace(steps: 400, usualSteps: 100, calories: 0, usualCalories: nil))
        // 60 kcal over, under the 100 kcal floor.
        XCTAssertFalse(ReviewMoment.aheadOfUsualPace(steps: 0, usualSteps: nil, calories: 1_260, usualCalories: 1_200))
        // 400 steps over a usual 5,000 is under the 10 percent share.
        XCTAssertFalse(ReviewMoment.aheadOfUsualPace(steps: 5_400, usualSteps: 5_000, calories: 0, usualCalories: nil))
    }

    func testNoPaceDataIsNotAMoment() {
        XCTAssertFalse(ReviewMoment.aheadOfUsualPace(steps: 9_000, usualSteps: nil, calories: 2_000, usualCalories: nil))
        XCTAssertFalse(ReviewMoment.aheadOfUsualPace(steps: 9_000, usualSteps: 0, calories: 2_000, usualCalories: 0))
    }

    func testPaceMomentFiresOncePerDay() {
        XCTAssertTrue(ReviewPromptTracker.recordAheadOfPaceMoment(dayKey: "2026-11-25", hasCompletedSetup: true))
        XCTAssertTrue(ReviewPromptTracker.hasPendingPositiveMoment)
        XCTAssertFalse(ReviewPromptTracker.recordAheadOfPaceMoment(dayKey: "2026-11-25", hasCompletedSetup: true))
        XCTAssertTrue(ReviewPromptTracker.recordAheadOfPaceMoment(dayKey: "2026-11-26", hasCompletedSetup: true))
    }

    func testPaceMomentKeepsEveryGate() {
        ReviewPromptTracker.appLaunchCount = 1
        XCTAssertFalse(ReviewPromptTracker.recordAheadOfPaceMoment(dayKey: "2026-11-25", hasCompletedSetup: true))
        XCTAssertFalse(ReviewPromptTracker.hasPendingPositiveMoment)
        ReviewPromptTracker.appLaunchCount = 2
        XCTAssertFalse(ReviewPromptTracker.recordAheadOfPaceMoment(dayKey: "2026-11-25", hasCompletedSetup: false))
        // A blocked first session leaves the day's moment for the second launch.
        XCTAssertTrue(ReviewPromptTracker.recordAheadOfPaceMoment(dayKey: "2026-11-25", hasCompletedSetup: true))
        ReviewPromptTracker.markShown()
        XCTAssertFalse(ReviewPromptTracker.recordAheadOfPaceMoment(dayKey: "2026-11-26", hasCompletedSetup: true))
    }

    func testPaceMomentStopsAfterTheWriteReviewPage() {
        ReviewPromptTracker.markOpenedWriteReview()
        XCTAssertFalse(ReviewPromptTracker.recordAheadOfPaceMoment(dayKey: "2026-12-30", hasCompletedSetup: true))
    }
}
