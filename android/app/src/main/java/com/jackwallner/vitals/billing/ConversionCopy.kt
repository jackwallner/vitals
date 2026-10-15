package com.jackwallner.vitals.billing

/**
 * Port of `VitalsConversionCopy.swift`, worded for Google Play. The CTA wording
 * test runs on iOS only; Android ships the "my" arm without the test attribute.
 */
object ConversionCopy {
    const val TRIAL_CTA = "Start my free trial"
    const val TRIAL_CTA_TITLE = "Start My Free Trial"
    const val RENEW_CLAUSE =
        "Auto-renews unless cancelled at least 24 hours before the end of the current period. " +
            "Manage or cancel in Google Play under Payments & subscriptions."
    const val ONBOARDING_RENEW_CLAUSE = "Auto-renews unless cancelled 24h before it ends. Cancel in Google Play."
    const val UNAVAILABLE = "Couldn't reach Google Play. Check your connection and try again."

    fun ctaLabel(trialLabel: String?, priceLabel: String, eligibleForTrial: Boolean): String = when {
        eligibleForTrial && !trialLabel.isNullOrEmpty() -> TRIAL_CTA
        priceLabel.isEmpty() -> "Continue with Vitals+"
        else -> "Continue with Vitals+ for $priceLabel"
    }

    fun shortCtaLabel(eligibleForTrial: Boolean): String = if (eligibleForTrial) TRIAL_CTA_TITLE else "Continue with Vitals+"

    fun disclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Boolean, renewClause: String = RENEW_CLAUSE): String =
        if (eligibleForTrial && !trialLabel.isNullOrEmpty()) "${trialLabel.capitalizeWords()}, then $priceLabel. $renewClause"
        else "$priceLabel. $renewClause"

    fun sheetDisclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Boolean): String =
        if (eligibleForTrial && !trialLabel.isNullOrEmpty()) {
            "Free during trial, then $priceLabel. Auto-renews unless cancelled 24h before trial ends."
        } else "$priceLabel. Auto-renews unless cancelled 24h before the period ends."

    fun purchaseCancelledMessage(eligibleForTrial: Boolean): String =
        if (eligibleForTrial) "Trial wasn't started. Tap again to continue." else "Purchase wasn't completed. Tap again to continue."

    fun purchaseFailedMessage(eligibleForTrial: Boolean): String =
        if (eligibleForTrial) "Couldn't start your trial. Please try again." else "Couldn't complete the purchase. Please try again."

    fun purchasePendingMessage(eligibleForTrial: Boolean): String =
        if (eligibleForTrial) "Waiting on Google Play to approve this. Your trial starts as soon as it clears."
        else "Waiting on Google Play to approve this. Vitals+ unlocks as soon as it clears."

    /** nil while eligibility is still resolving, so the button never flashes between labels. */
    fun paywallCtaTitle(
        isLifetime: Boolean,
        hasIntroOffer: Boolean,
        eligibilityResolved: Boolean,
        eligibleForTrial: Boolean,
    ): String? = when {
        isLifetime -> "Unlock Lifetime"
        hasIntroOffer && !eligibilityResolved -> null
        eligibleForTrial -> TRIAL_CTA_TITLE
        else -> "Subscribe"
    }

    fun badgeText(trialLabel: String?, eligibleForTrial: Boolean, annualSavingsPercent: Int?): String {
        if (eligibleForTrial && trialLabel != null) {
            val days = trialLabel.takeWhile { it.isDigit() }
            if (days.isNotEmpty()) return "$days DAYS FREE"
        }
        if (!eligibleForTrial && annualSavingsPercent != null && annualSavingsPercent > 0) return "SAVE $annualSavingsPercent%"
        return "VITALS+"
    }
}

internal fun String.capitalizeWords(): String =
    split(" ").joinToString(" ") { word -> word.split("-").joinToString("-") { it.replaceFirstChar(Char::uppercaseChar) } }
