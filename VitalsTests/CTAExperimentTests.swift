import XCTest

final class CTAExperimentTests: XCTestCase {
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: "CTAExperimentTests")
        suite.removePersistentDomain(forName: "CTAExperimentTests")
        CTAExperiment.defaults = suite
    }

    override func tearDown() {
        CTAExperiment.defaults = .standard
        suite.removePersistentDomain(forName: "CTAExperimentTests")
        super.tearDown()
    }

    func testArmIsStableOnceAssigned() {
        let first = CTAExperiment.arm
        for _ in 0..<20 { XCTAssertEqual(CTAExperiment.arm, first) }
    }

    func testAssignmentSplitsBothWays() {
        var seen = Set<CTAExperiment.Arm>()
        for _ in 0..<200 {
            CTAExperiment.reset()
            seen.insert(CTAExperiment.arm)
        }
        XCTAssertEqual(seen, Set(CTAExperiment.Arm.allCases))
    }

    func testWordingDiffersOnlyInThePossessive() {
        XCTAssertEqual(CTAExperiment.trialCTA(.my), "Start my free trial")
        XCTAssertEqual(CTAExperiment.trialCTA(.your), "Start your free trial")
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
