import Foundation

/// Pure copy helpers for Vitals+ conversion CTAs. StoreKit always purchases the
/// same yearly package — trial vs paid is eligibility, not a different product.
/// These helpers keep every pitch surface (onboarding, trial sheet, milestone,
/// paywall, What's New) honest when the user already used their free trial.
enum VitalsConversionCopy {
    /// Primary button: trial language only when eligible.
    static func ctaLabel(trialLabel: String?, priceLabel: String, eligibleForTrial: Bool) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "Start \(trialLabel)"
        }
        if priceLabel.isEmpty { return "Continue with Vitals+" }
        return "Continue with Vitals+ for \(priceLabel)"
    }

    /// Short capsule CTA used on milestone / What's New (less price noise).
    static func shortCTALabel(eligibleForTrial: Bool) -> String {
        eligibleForTrial ? "Start Free Trial" : "Continue with Vitals+"
    }

    /// Apple 3.1.2 disclosure adjacent to the purchase button.
    static func disclosure(
        trialLabel: String?,
        priceLabel: String,
        eligibleForTrial: Bool,
        renewClause: String = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions."
    ) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "\(trialLabel.capitalized), then \(priceLabel). \(renewClause)"
        }
        return "\(priceLabel). \(renewClause)"
    }

    /// Compact disclosure for the trial offer sheet footer.
    static func sheetDisclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Bool) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "Free during trial, then \(priceLabel). Auto-renews unless cancelled 24h before trial ends."
        }
        return "\(priceLabel). Auto-renews unless cancelled 24h before the period ends."
    }

    /// Cancel / failure copy — never blames a "trial" the user wasn't eligible for.
    static func purchaseCancelledMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? "Trial wasn't started. Tap again to continue."
            : "Purchase wasn't completed. Tap again to continue."
    }

    static func purchaseFailedMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? "Couldn't start your trial. Please try again."
            : "Couldn't complete the purchase. Please try again."
    }
}
