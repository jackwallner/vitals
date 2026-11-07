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

    func testOnDeviceInactiveIsNotALapseUntilTheServersReply() {
        var status = EntitlementStatus(cachedPro: false)
        status.resolve(isPro: false)
        XCTAssertFalse(status.lapseConfirmed)

        status.markServerAnswered()
        status.resolve(isPro: false)
        XCTAssertTrue(status.lapseConfirmed)
    }

    func testServerSayingActiveIsNotALapse() {
        var status = EntitlementStatus(cachedPro: false)
        status.resolve(isPro: false)
        status.markServerAnswered()
        status.resolve(isPro: true)
        XCTAssertFalse(status.lapseConfirmed)
    }

    func testFailedRefreshWithdrawsAConfirmedLapse() {
        var status = EntitlementStatus(cachedPro: false)
        status.markServerAnswered()
        status.resolve(isPro: false)
        status.refreshFailed()
        status.resolve(isPro: false)
        XCTAssertFalse(status.lapseConfirmed)
    }
}
