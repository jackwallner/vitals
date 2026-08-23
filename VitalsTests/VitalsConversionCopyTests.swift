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

    // MARK: - Used-trial pitch

    func testUsedTrialHeadlineDropsTrialFraming() {
        let text = VitalsConversionCopy.headline(
            focusHeadline: nil,
            trialLabel: "7-day free trial",
            eligibleForTrial: false
        )
        XCTAssertEqual(text, "Pick up where your trial left off.")
        XCTAssertFalse(text.lowercased().contains("free"))
    }

    func testEligibleHeadlineLeadsWithTheTrial() {
        XCTAssertEqual(
            VitalsConversionCopy.headline(
                focusHeadline: nil,
                trialLabel: "7-day free trial",
                eligibleForTrial: true
            ),
            "7-Day Free Trial, on us."
        )
    }

    func testFocusHeadlineWinsOverBothStates() {
        for eligible in [true, false] {
            XCTAssertEqual(
                VitalsConversionCopy.headline(
                    focusHeadline: "See your macros here too",
                    trialLabel: "7-day free trial",
                    eligibleForTrial: eligible
                ),
                "See your macros here too"
            )
        }
    }

    func testUsedTrialSubheadlineAnchorsOnThePerWeekPrice() {
        let text = VitalsConversionCopy.subheadline(
            focusSubheadline: nil,
            eligibleForTrial: false,
            perWeekLabel: "$0.58"
        )
        XCTAssertTrue(text.contains("$0.58"))
        XCTAssertFalse(text.lowercased().contains("trial ends"))
    }

    /// Price anchoring is dropped rather than faked when StoreKit hasn't
    /// answered — the sheet must never render "about  a week".
    func testUsedTrialSubheadlineSurvivesAMissingPrice() {
        let text = VitalsConversionCopy.subheadline(
            focusSubheadline: nil,
            eligibleForTrial: false,
            perWeekLabel: nil
        )
        XCTAssertEqual(text, "You've already seen what Vitals+ adds. Keep it on.")
    }

    func testBadgeUsesTrialDaysWhenEligible() {
        XCTAssertEqual(
            VitalsConversionCopy.badgeText(
                trialLabel: "7-day free trial",
                eligibleForTrial: true,
                annualSavingsPercent: 64
            ),
            "7 DAYS FREE"
        )
    }

    func testBadgeFallsBackToAnnualSavingWhenTrialIsSpent() {
        XCTAssertEqual(
            VitalsConversionCopy.badgeText(
                trialLabel: "7-day free trial",
                eligibleForTrial: false,
                annualSavingsPercent: 64
            ),
            "SAVE 64%"
        )
    }

    /// Both numbers unknown: say nothing quantitative at all.
    func testBadgeInventsNothing() {
        XCTAssertEqual(
            VitalsConversionCopy.badgeText(trialLabel: nil, eligibleForTrial: false, annualSavingsPercent: nil),
            "VITALS+"
        )
        XCTAssertEqual(
            VitalsConversionCopy.badgeText(trialLabel: nil, eligibleForTrial: false, annualSavingsPercent: 0),
            "VITALS+"
        )
    }

    func testPaywallCTAWaitsUntilEligibilityResolves() {
        XCTAssertNil(
            VitalsConversionCopy.paywallCTATitle(
                packageSelected: false,
                isLifetime: false,
                hasIntroOffer: true,
                eligibilityResolved: false,
                eligibleForTrial: false
            )
        )
        XCTAssertNil(
            VitalsConversionCopy.paywallCTATitle(
                packageSelected: true,
                isLifetime: false,
                hasIntroOffer: true,
                eligibilityResolved: false,
                eligibleForTrial: false
            )
        )
        XCTAssertEqual(
            VitalsConversionCopy.paywallCTATitle(
                packageSelected: true,
                isLifetime: false,
                hasIntroOffer: true,
                eligibilityResolved: true,
                eligibleForTrial: true
            ),
            "Start Free Trial"
        )
        XCTAssertEqual(
            VitalsConversionCopy.paywallCTATitle(
                packageSelected: true,
                isLifetime: false,
                hasIntroOffer: true,
                eligibilityResolved: true,
                eligibleForTrial: false
            ),
            "Subscribe"
        )
        XCTAssertEqual(
            VitalsConversionCopy.paywallCTATitle(
                packageSelected: true,
                isLifetime: true,
                hasIntroOffer: false,
                eligibilityResolved: false,
                eligibleForTrial: false
            ),
            "Unlock Lifetime"
        )
    }

    /// The timeline is two beats: it starts, it bills. It must not tell the user
    /// a reminder is coming (nothing sends one) and must not turn the pitch into
    /// a cancellation deadline. The auto-renewal terms live in the 3.1.2
    /// disclosure under the button, not here.
    func testTrialTimelineIsTwoStepsAndPromisesNoReminder() {
        let copy = VitalsConversionCopy.TrialTimelineCopy.make(
            trialDays: 7,
            priceLabel: "$14.99 / year"
        )
        XCTAssertEqual(copy.todayTitle, "Today: trial starts")
        XCTAssertEqual(copy.chargeTitle, "Day 7: first charge")
        XCTAssertTrue(copy.chargeDetail.contains("$14.99 / year"))

        let everything = [copy.todayTitle, copy.todayDetail, copy.chargeTitle, copy.chargeDetail]
            .joined(separator: " ")
            .lowercased()
        for banned in ["remind", "we'll tell you", "last day to cancel", "notification"] {
            XCTAssertFalse(
                everything.contains(banned),
                "trial timeline should not say \"\(banned)\": \(everything)"
            )
        }
    }
}
