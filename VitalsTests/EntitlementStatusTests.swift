import XCTest

final class EntitlementStatusTests: XCTestCase {
    func testCachedSubscriberHasAccessBeforeFirstResponseAndAfterFailure() {
        var status = EntitlementStatus(cachedPro: true)
        XCTAssertEqual(status.resolution, .unresolved)
        XCTAssertTrue(status.isPro)
        status.refreshFailed()
        XCTAssertEqual(status.resolution, .unresolved)
        XCTAssertTrue(status.isPro)
    }

    func testUnresolvedWithoutCachedAccessDoesNotGrantPro() {
        var status = EntitlementStatus(cachedPro: false)
        status.refreshFailed()
        XCTAssertEqual(status.resolution, .unresolved)
        XCTAssertFalse(status.isPro)
    }

    func testConfirmedLapseReplacesCachedAccessAndSurvivesLaterFailure() {
        var status = EntitlementStatus(cachedPro: true)
        status.resolve(isPro: false)
        XCTAssertEqual(status.resolution, .inactive)
        XCTAssertFalse(status.isPro)
        status.refreshFailed()
        XCTAssertFalse(status.isPro)
    }

    func testSuccessfulRetryUnlocksAndSubsequentFailureKeepsAccess() {
        var status = EntitlementStatus(cachedPro: false)
        status.refreshFailed()
        status.resolve(isPro: true)
        XCTAssertEqual(status.resolution, .active)
        XCTAssertTrue(status.isPro)
        status.refreshFailed()
        XCTAssertEqual(status.resolution, .unresolved)
        XCTAssertTrue(status.isPro)
    }
}
