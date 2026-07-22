import XCTest

final class VitalsConversionCopyTests: XCTestCase {
    func testEligibleCTAUsesTrialLabel() {
        let cta = VitalsConversionCopy.ctaLabel(
            trialLabel: "7-day free trial",
            priceLabel: "$14.99 / year",
            eligibleForTrial: true
        )
        XCTAssertEqual(cta, "Start 7-day free trial")
    }

    func testIneligibleCTAUsesPaidYearly() {
        let cta = VitalsConversionCopy.ctaLabel(
            trialLabel: "7-day free trial",
            priceLabel: "$14.99 / year",
            eligibleForTrial: false
        )
        XCTAssertEqual(cta, "Continue with Vitals+ for $14.99 / year")
        XCTAssertFalse(cta.lowercased().contains("trial"))
    }

    func testIneligibleDisclosureOmitsTrialPromise() {
        let text = VitalsConversionCopy.disclosure(
            trialLabel: "7-day free trial",
            priceLabel: "$14.99 / year",
            eligibleForTrial: false
        )
        XCTAssertTrue(text.hasPrefix("$14.99 / year."))
        XCTAssertFalse(text.lowercased().contains("free trial"))
    }

    func testEligibleDisclosureLeadsWithTrial() {
        let text = VitalsConversionCopy.disclosure(
            trialLabel: "7-day free trial",
            priceLabel: "$14.99 / year",
            eligibleForTrial: true
        )
        XCTAssertTrue(text.lowercased().contains("7-day free trial"))
        XCTAssertTrue(text.contains("$14.99 / year"))
    }

    func testSheetDisclosureSwitchesForUsedTrial() {
        let trial = VitalsConversionCopy.sheetDisclosure(
            trialLabel: "7-day free trial",
            priceLabel: "$14.99 / year",
            eligibleForTrial: true
        )
        let paid = VitalsConversionCopy.sheetDisclosure(
            trialLabel: "7-day free trial",
            priceLabel: "$14.99 / year",
            eligibleForTrial: false
        )
        XCTAssertTrue(trial.lowercased().contains("free during trial"))
        XCTAssertFalse(paid.lowercased().contains("free during trial"))
        XCTAssertTrue(paid.hasPrefix("$14.99 / year."))
    }

    func testFailureCopyDoesNotBlameTrialWhenIneligible() {
        XCTAssertTrue(
            VitalsConversionCopy.purchaseFailedMessage(eligibleForTrial: false)
                .lowercased()
                .contains("purchase")
        )
        XCTAssertFalse(
            VitalsConversionCopy.purchaseFailedMessage(eligibleForTrial: false)
                .lowercased()
                .contains("trial")
        )
        XCTAssertTrue(
            VitalsConversionCopy.purchaseCancelledMessage(eligibleForTrial: true)
                .lowercased()
                .contains("trial")
        )
    }

    func testShortCTA() {
        XCTAssertEqual(VitalsConversionCopy.shortCTALabel(eligibleForTrial: true), "Start Free Trial")
        XCTAssertEqual(VitalsConversionCopy.shortCTALabel(eligibleForTrial: false), "Continue with Vitals+")
    }
}
