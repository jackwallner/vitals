import XCTest
@testable import Vitals

final class MilestoneCalculatorTests: XCTestCase {
    func testUnfiredPicksLargestReachedTier() {
        let fired: Set<String> = []
        let event = MilestoneCalculator.unfiredStreakMilestone(currentStreak: 20, firedIds: fired)
        XCTAssertEqual(event, .goalStreak(n: 14))
    }

    func testUnfiredSkipsAlreadyFiredTiers() {
        let fired: Set<String> = ["streak_7", "streak_14"]
        let event = MilestoneCalculator.unfiredStreakMilestone(currentStreak: 20, firedIds: fired)
        XCTAssertNil(event)
    }

    func testSeedMarksAllReachedTiersWithoutCelebratingHigher() {
        var fired: Set<String> = []
        MilestoneCalculator.seedFiredStreakIds(currentStreak: 30, into: &fired)
        XCTAssertEqual(fired, ["streak_7", "streak_14", "streak_30"])
        XCTAssertNil(MilestoneCalculator.unfiredStreakMilestone(currentStreak: 30, firedIds: fired))
        // Later crossing still celebrates.
        let next = MilestoneCalculator.unfiredStreakMilestone(currentStreak: 60, firedIds: fired)
        XCTAssertEqual(next, .goalStreak(n: 60))
    }

    func testSeedWithShortStreakLeavesFutureTiersOpen() {
        var fired: Set<String> = []
        MilestoneCalculator.seedFiredStreakIds(currentStreak: 3, into: &fired)
        XCTAssertTrue(fired.isEmpty)
        let event = MilestoneCalculator.unfiredStreakMilestone(currentStreak: 7, firedIds: fired)
        XCTAssertEqual(event, .goalStreak(n: 7))
    }
}
