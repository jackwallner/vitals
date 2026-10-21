import XCTest

final class CTAExperimentTests: XCTestCase {
    func testMissingOrUnknownMetadataIsTheLiveControl() {
        XCTAssertEqual(CTAExperiment.from(metadata: nil), .standard)
        XCTAssertEqual(CTAExperiment.from(metadata: [:]), .standard)
        XCTAssertEqual(CTAExperiment.from(metadata: ["trial_cta": "mine"]), .standard)
        XCTAssertEqual(CTAExperiment.from(metadata: ["trial_cta": 1]), .standard)
    }

    func testMetadataPicksTheArm() {
        XCTAssertEqual(CTAExperiment.from(metadata: ["trial_cta": "my"]), .my)
        XCTAssertEqual(CTAExperiment.from(metadata: ["trial_cta": "your"]), .your)
        XCTAssertEqual(CTAExperiment.from(metadata: ["trial_cta": "standard"]), .standard)
    }

    func testDefaultArmIsTheLiveControl() {
        XCTAssertEqual(CTAExperiment.offeringArm, .standard)
    }

    func testStandardIsTheLiveCopy() {
        XCTAssertEqual(CTAExperiment.trialCTA(.standard, trialLabel: "7-day free trial"), "Start 7-day free trial")
        XCTAssertEqual(CTAExperiment.trialCTATitleCase(.standard), "Start Free Trial")
    }

    func testTestArmsDifferOnlyInThePossessive() {
        XCTAssertEqual(CTAExperiment.trialCTA(.my, trialLabel: "7-day free trial"), "Start my free trial")
        XCTAssertEqual(CTAExperiment.trialCTA(.your, trialLabel: "7-day free trial"), "Start your free trial")
        XCTAssertEqual(CTAExperiment.trialCTATitleCase(.my), "Start My Free Trial")
        XCTAssertEqual(CTAExperiment.trialCTATitleCase(.your), "Start Your Free Trial")
    }

    func testIneligibleCopyIgnoresTheArm() {
        for arm in CTAExperiment.Arm.allCases {
            XCTAssertEqual(
                VitalsConversionCopy.ctaLabel(trialLabel: "7-day free trial", priceLabel: "$14.99 / year",
                                              eligibleForTrial: false, arm: arm),
                "Continue with Vitals+ for $14.99 / year"
            )
        }
    }
}
