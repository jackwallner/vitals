import Foundation

/// Pure copy helpers for Vitals+ conversion CTAs. StoreKit always purchases the
/// same yearly package — trial vs paid is eligibility, not a different product.
/// These helpers keep every pitch surface (onboarding, trial sheet, milestone,
/// paywall, What's New) honest when the user already used their free trial.
enum VitalsConversionCopy {
    /// Primary button: trial language only when eligible, worded by the
    /// offering's CTA arm (`CTAExperiment`).
    static func ctaLabel(
        trialLabel: String?,
        priceLabel: String,
        eligibleForTrial: Bool,
        arm: CTAExperiment.Arm = CTAExperiment.arm
    ) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return CTAExperiment.trialCTA(arm, trialLabel: trialLabel)
        }
        if priceLabel.isEmpty { return String(localized: "Continue with Vitals+") }
        return String(localized: "Continue with Vitals+ for \(priceLabel)")
    }

    /// Short capsule CTA used on milestone / What's New (less price noise).
    static func shortCTALabel(eligibleForTrial: Bool, arm: CTAExperiment.Arm = CTAExperiment.arm) -> String {
        eligibleForTrial ? CTAExperiment.trialCTATitleCase(arm) : String(localized: "Continue with Vitals+")
    }

    /// Apple 3.1.2 disclosure adjacent to the purchase button.
    static func disclosure(
        trialLabel: String?,
        priceLabel: String,
        eligibleForTrial: Bool,
        renewClause: String = String(localized: "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions.")
    ) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return String(localized: "\(trialLabel.leadingCapitalized), then \(priceLabel). \(renewClause)")
        }
        return "\(priceLabel). \(renewClause)"
    }

    /// Compact disclosure for the trial offer sheet footer.
    static func sheetDisclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Bool) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return String(localized: "Free during trial, then \(priceLabel). Auto-renews unless cancelled 24h before trial ends.")
        }
        return String(localized: "\(priceLabel). Auto-renews unless cancelled 24h before the period ends.")
    }

    /// Headline for the pitch. A used-trial account gets its own line: they have
    /// already seen the product, so the pitch is "keep it", not "try it".
    static func headline(focusHeadline: String?, trialLabel: String?, eligibleForTrial: Bool) -> String {
        if let focusHeadline { return focusHeadline }
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return String(localized: "\(trialLabel.leadingCapitalized), on us.")
        }
        return String(localized: "Pick up where your trial left off.")
    }

    /// Sub-headline. The used-trial variant leads with the smallest honest unit
    /// of the price, because price is the only lever left once "free" is gone.
    static func subheadline(
        focusSubheadline: String?,
        eligibleForTrial: Bool,
        perWeekLabel: String?
    ) -> String {
        if let focusSubheadline {
            if eligibleForTrial { return String(localized: "\(focusSubheadline) Free for 7 days. Cancel anytime.") }
            if let perWeekLabel { return String(localized: "\(focusSubheadline) About \(perWeekLabel) a week on the yearly plan.") }
            return focusSubheadline
        }
        if eligibleForTrial {
            return String(localized: "Calories, steps, and trends in one place. No charge until your trial ends.")
        }
        if let perWeekLabel {
            return String(localized: "You've already seen what Vitals+ adds. Keep it for about \(perWeekLabel) a week, billed yearly.")
        }
        return String(localized: "You've already seen what Vitals+ adds. Keep it on.")
    }

    /// The badge above the headline. With no trial left to advertise, the annual
    /// saving is the honest deal — and only when both plans are loaded to
    /// compute it. Never invents a number.
    static func badgeText(trialLabel: String?, eligibleForTrial: Bool, annualSavingsPercent: Int?) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return trialLabel
        }
        if !eligibleForTrial, let annualSavingsPercent, annualSavingsPercent > 0 {
            return String(localized: "SAVE \(annualSavingsPercent)%")
        }
        return "VITALS+"
    }

    /// Cancel / failure copy — never blames a "trial" the user wasn't eligible for.
    static func purchaseCancelledMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? String(localized: "Trial wasn't started. Tap again to continue.")
            : String(localized: "Purchase wasn't completed. Tap again to continue.")
    }

    static func purchaseFailedMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? String(localized: "Couldn't start your trial. Please try again.")
            : String(localized: "Couldn't complete the purchase. Please try again.")
    }

    /// A transaction StoreKit accepted but has not settled: Ask to Buy waiting on
    /// a parent, an SCA challenge, or a queue that has not drained. It is neither
    /// a success nor a failure, and the surface has to stay up and say which.
    static func purchasePendingMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? String(localized: "Waiting on Apple to approve this. Your trial starts as soon as it clears.")
            : String(localized: "Waiting on Apple to approve this. Vitals+ unlocks as soon as it clears.")
    }

    /// Purchases cannot run at all in this process. Route the user somewhere
    /// that can recover rather than telling them nothing happened.
    static let purchaseUnavailableMessage =
        String(localized: "Couldn't reach the App Store. Check your connection and try again.")

    /// Hold the purchase button quiet until StoreKit has named the action.
    /// Returning nil means show a spinner, never "Continue" flipping into
    /// "Start Free Trial".
    static func paywallCTATitle(
        packageSelected: Bool,
        isLifetime: Bool,
        hasIntroOffer: Bool,
        eligibilityResolved: Bool,
        eligibleForTrial: Bool,
        arm: CTAExperiment.Arm = CTAExperiment.arm
    ) -> String? {
        guard packageSelected else { return nil }
        if isLifetime { return String(localized: "Unlock Lifetime") }
        if hasIntroOffer && !eligibilityResolved { return nil }
        if eligibleForTrial { return CTAExperiment.trialCTATitleCase(arm) }
        return String(localized: "Subscribe")
    }
}
