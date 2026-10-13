import XCTest
import Foundation

// The app defines these in DataService.swift and ScreenshotConfig.swift, which
// pull in most of the app. The test bundle compiles the tracker on its own.
let vitalsAppGroupID = "group.com.jackwallner.vitals"
enum ScreenshotConfig { static let isEnabled = false }

/// The rating-ask rules from the fleet policy: ask from the second launch, wait
/// out a 30-day cooldown, stop only when the user opened the review page, and
/// never let feedback stop or restart the asks.
@MainActor
final class ReviewPromptTrackerTests: XCTestCase {
    private var saved: (Int, Date?, Date?, ReviewPromptOutcome?, Bool)!

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
    }

    override func tearDown() async throws {
        ReviewPromptTracker.appLaunchCount = saved.0
        ReviewPromptTracker.firstAppOpenDate = saved.1
        ReviewPromptTracker.lastShownDate = saved.2
        ReviewPromptTracker.outcome = saved.3
        ReviewPromptTracker.hasPendingPositiveMoment = saved.4
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
}
