import XCTest

final class UnfoldedSplitTests: XCTestCase {
    func testCompactWidthNeverSplits() {
        XCTAssertNil(UnfoldedSplit.make(width: 867, isRegularWidth: false, fold: 455.5...495.5))
    }

    func testTooNarrowForTwoPanesStaysOneColumn() {
        // The unfolded Duo held in portrait.
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
    }

    func testPanesMeetTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 867, isRegularWidth: true, fold: 455.5...495.5)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 455.5, secondaryX: 495.5, secondaryWidth: 371.5))
    }

    func testNoFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 900, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 450, secondaryX: 450, secondaryWidth: 450))
    }

    func testFoldLeavingANarrowPaneFallsBackToEven() {
        let split = UnfoldedSplit.make(width: 900, isRegularWidth: true, fold: 100...140)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 450, secondaryX: 450, secondaryWidth: 450))
    }
}
