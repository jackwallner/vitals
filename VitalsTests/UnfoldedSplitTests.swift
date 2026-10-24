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

    func testUnfoldedDuoLandscapeGivesBothPanesAPhoneWidth() {
        // Inner display held landscape, 951 pt wide, fold down the middle.
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 465.5...485.5)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 465.5, secondaryX: 485.5, secondaryWidth: 465.5))
        if let split {
            XCTAssertGreaterThanOrEqual(split.primaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertGreaterThanOrEqual(split.secondaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertLessThanOrEqual(split.primaryWidth, split.secondaryX, "primary pane runs under the fold")
        }
    }

    func testUnfoldedPrimaryPaneStartsBelowTheTabBar() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 465.5...485.5)
        XCTAssertEqual(UnfoldedSplit.primaryTopInset(split, tabBarHeight: 64), 64)
    }

    func testFoldedPaneFillsTheScreenUnderTheFloatingBar() {
        XCTAssertEqual(UnfoldedSplit.primaryTopInset(nil, tabBarHeight: 64), 0)
    }
}
