import XCTest

final class ProjectionCalculatorTests: XCTestCase {
    func testProjectionAddsTypicalRemainder() {
        // Banked 1,200 by now; typically at 1,000 by now and 2,500 full day.
        // Expected remaining = 2,500 − 1,000 = 1,500 → projected = 1,200 + 1,500 = 2,700.
        let projected = ProjectionCalculator.projectedEndOfDay(
            current: 1_200,
            usualByNow: 1_000,
            usualFullDay: 2_500
        )
        XCTAssertEqual(try XCTUnwrap(projected), 2_700, accuracy: 0.0001)
    }

    func testProjectionAddsRemainderEvenWhenAheadOfPace() {
        // Banked 2,600 — ahead of the usual 2,400 by now. The day still fills in
        // the typical remainder (2,500 − 2,400 = 100) → 2,700.
        let projected = ProjectionCalculator.projectedEndOfDay(
            current: 2_600,
            usualByNow: 2_400,
            usualFullDay: 2_500
        )
        XCTAssertEqual(try XCTUnwrap(projected), 2_700, accuracy: 0.0001)
    }

    func testProjectionClampsNegativeRemainder() {
        // Degenerate: usual-by-now exceeds usual-full-day. Remainder clamps at 0,
        // so the projection never drops below what's banked.
        let projected = ProjectionCalculator.projectedEndOfDay(
            current: 2_600,
            usualByNow: 2_600,
            usualFullDay: 2_500
        )
        XCTAssertEqual(try XCTUnwrap(projected), 2_600, accuracy: 0.0001)
    }

    func testProjectionNilWithoutFullDayBaseline() {
        XCTAssertNil(ProjectionCalculator.projectedEndOfDay(current: 1_000, usualByNow: 500, usualFullDay: nil))
        XCTAssertNil(ProjectionCalculator.projectedEndOfDay(current: 1_000, usualByNow: 500, usualFullDay: 0))
    }

    func testProjectionFallsBackToMaxWithoutNowReference() {
        // No "by now" baseline (e.g. early morning): never project below banked.
        XCTAssertEqual(
            try XCTUnwrap(ProjectionCalculator.projectedEndOfDay(current: 3_000, usualByNow: nil, usualFullDay: 2_500)),
            3_000, accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(ProjectionCalculator.projectedEndOfDay(current: 800, usualByNow: nil, usualFullDay: 2_500)),
            2_500, accuracy: 0.0001
        )
    }

    func testGoalOutlookOnTrackWithinTolerance() {
        // Projected 30 under a 2,500 goal is within the 2% tolerance → on track.
        let outlook = ProjectionCalculator.goalOutlook(projected: 2_470, goal: 2_500)
        XCTAssertEqual(outlook, .onTrack(margin: 0))
    }

    func testGoalOutlookBehindBeyondTolerance() {
        let outlook = ProjectionCalculator.goalOutlook(projected: 2_200, goal: 2_500)
        XCTAssertEqual(outlook, .behind(shortfall: 300))
    }

    func testGoalOutlookOverGoal() {
        let outlook = ProjectionCalculator.goalOutlook(projected: 2_800, goal: 2_500)
        XCTAssertEqual(outlook, .onTrack(margin: 300))
    }

    func testGoalOutlookNilWithoutGoal() {
        XCTAssertNil(ProjectionCalculator.goalOutlook(projected: 2_500, goal: nil))
        XCTAssertNil(ProjectionCalculator.goalOutlook(projected: nil, goal: 2_500))
    }
}
