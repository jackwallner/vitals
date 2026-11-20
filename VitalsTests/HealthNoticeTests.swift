import HealthKit
import XCTest

final class HealthNoticeTests: XCTestCase {
    func testHandledPermissionSheetWithEmptyDataDoesNotClaimAccessIsOff() {
        XCTAssertEqual(HealthNotice.emptyFetch(requestStatus: .unnecessary), .noData)
        XCTAssertEqual(HealthNotice.noData.buttonTitle, "Check Health Access")
    }

    func testNoDataNoticeSaysWhereToTurnAccessBackOn() {
        let message = HealthNotice.noData.message
        XCTAssertTrue(message.contains("Settings → Privacy & Security → Health → Total Calories"), message)
        XCTAssertFalse(message.contains("syncing"), message)
    }

    func testUnansweredPermissionSheetStillOffersAuthorization() {
        XCTAssertEqual(HealthNotice.emptyFetch(requestStatus: .shouldRequest), .accessNeeded)
    }

    func testUnknownRequestStatusDoesNotClaimDenial() {
        XCTAssertEqual(HealthNotice.emptyFetch(requestStatus: .unknown), .noData)
        XCTAssertEqual(HealthNotice.emptyFetch(requestStatus: nil), .noData)
    }
}
