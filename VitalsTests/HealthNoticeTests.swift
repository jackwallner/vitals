import HealthKit
import XCTest

final class HealthNoticeTests: XCTestCase {
    func testHandledPermissionSheetWithEmptyDataDoesNotClaimAccessIsOff() {
        XCTAssertEqual(HealthNotice.emptyFetch(requestStatus: .unnecessary), .noData)
        XCTAssertEqual(HealthNotice.noData.buttonTitle, "Check Health Access")
    }

    func testUnansweredPermissionSheetStillOffersAuthorization() {
        XCTAssertEqual(HealthNotice.emptyFetch(requestStatus: .shouldRequest), .accessNeeded)
    }

    func testUnknownRequestStatusDoesNotClaimDenial() {
        XCTAssertEqual(HealthNotice.emptyFetch(requestStatus: .unknown), .noData)
        XCTAssertEqual(HealthNotice.emptyFetch(requestStatus: nil), .noData)
    }
}
