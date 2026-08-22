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

    /// Headline for the pitch. A used-trial account gets its own line: they have
    /// already seen the product, so the pitch is "keep it", not "try it".
    static func headline(focusHeadline: String?, trialLabel: String?, eligibleForTrial: Bool) -> String {
        if let focusHeadline { return focusHeadline }
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "\(trialLabel.capitalized), on us."
        }
        return "Pick up where your trial left off."
    }

    /// Sub-headline. The used-trial variant leads with the smallest honest unit
    /// of the price, because price is the only lever left once "free" is gone.
    static func subheadline(
        focusSubheadline: String?,
        eligibleForTrial: Bool,
        perWeekLabel: String?
    ) -> String {
        if let focusSubheadline {
            if eligibleForTrial { return "\(focusSubheadline) Free for 7 days. Cancel anytime." }
            if let perWeekLabel { return "\(focusSubheadline) About \(perWeekLabel) a week on the yearly plan." }
            return focusSubheadline
        }
        if eligibleForTrial {
            return "Calories, steps, and trends in one place. No charge until your trial ends."
        }
        if let perWeekLabel {
            return "You've already seen what Vitals+ adds. Keep it for about \(perWeekLabel) a week, billed yearly."
        }
        return "You've already seen what Vitals+ adds. Keep it on."
    }

    /// The badge above the headline. With no trial left to advertise, the annual
    /// saving is the honest deal — and only when both plans are loaded to
    /// compute it. Never invents a number.
    static func badgeText(trialLabel: String?, eligibleForTrial: Bool, annualSavingsPercent: Int?) -> String {
        if eligibleForTrial, let trialLabel,
           let days = trialLabel.split(whereSeparator: { !$0.isNumber }).first, !days.isEmpty {
            return "\(days) DAYS FREE"
        }
        if !eligibleForTrial, let annualSavingsPercent, annualSavingsPercent > 0 {
            return "SAVE \(annualSavingsPercent)%"
        }
        return "VITALS+"
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

    /// Hold the purchase button quiet until StoreKit has named the action.
    /// Returning nil means show a spinner, never "Continue" flipping into
    /// "Start Free Trial".
    static func paywallCTATitle(
        packageSelected: Bool,
        isLifetime: Bool,
        hasIntroOffer: Bool,
        eligibilityResolved: Bool,
        eligibleForTrial: Bool
    ) -> String? {
        guard packageSelected else { return nil }
        if isLifetime { return "Unlock Lifetime" }
        if hasIntroOffer && !eligibilityResolved { return nil }
        if eligibleForTrial { return "Start Free Trial" }
        return "Subscribe"
    }

    /// Blinkist-style three-step trial, with an honest middle beat: the last
    /// day you can cancel (Apple requires 24 hours before billing). Does not
    /// claim Apple will send a reminder.
    struct TrialTimelineCopy: Equatable {
        let trialDays: Int
        let cancelByDay: Int
        let todayTitle: String
        let todayDetail: String
        let cancelTitle: String
        let cancelDetail: String
        let chargeTitle: String
        let chargeDetail: String

        static func make(trialDays: Int, priceLabel: String?) -> TrialTimelineCopy {
            let days = max(trialDays, 2)
            let cancelBy = days - 1
            let charge = priceLabel.map { "Billed \($0) unless you cancel." }
                ?? "You're only billed if you keep it."
            return TrialTimelineCopy(
                trialDays: days,
                cancelByDay: cancelBy,
                todayTitle: "Today: trial starts",
                todayDetail: "Vitals+ unlocks now. No charge today.",
                cancelTitle: "Day \(cancelBy): last day to cancel",
                cancelDetail: "Cancel in Settings → Apple ID at least 24 hours before billing.",
                chargeTitle: "Day \(days): first charge",
                chargeDetail: charge
            )
        }
    }
}
