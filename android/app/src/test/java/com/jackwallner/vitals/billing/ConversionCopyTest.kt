package com.jackwallner.vitals.billing

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Ports `VitalsConversionCopyTests` (the "my" arm), with Google Play wording. */
class ConversionCopyTest {
    private val trial = "7-day free trial"
    private val price = "\$14.99 / year"

    @Test fun eligibleCtaUsesTheTrialLabel() {
        assertEquals("Start my free trial", ConversionCopy.ctaLabel(trial, price, true))
    }

    @Test fun ineligibleCtaUsesThePaidYearlyAndNeverMentionsATrial() {
        val cta = ConversionCopy.ctaLabel(trial, price, false)
        assertEquals("Continue with Vitals+ for \$14.99 / year", cta)
        assertFalse(cta.lowercase().contains("trial"))
    }

    @Test fun ineligibleDisclosureOmitsTheTrialPromise() {
        val text = ConversionCopy.disclosure(trial, price, false)
        assertTrue(text.startsWith("\$14.99 / year."))
        assertFalse(text.lowercase().contains("free trial"))
    }

    @Test fun eligibleDisclosureLeadsWithTheTrialAndNamesGooglePlay() {
        val text = ConversionCopy.disclosure(trial, price, true)
        assertTrue(text.lowercase().contains("7-day free trial"))
        assertTrue(text.contains("\$14.99 / year"))
        assertTrue(text.contains("Google Play"))
    }

    @Test fun sheetDisclosureSwitchesForAUsedTrial() {
        assertTrue(ConversionCopy.sheetDisclosure(trial, price, true).lowercase().contains("free during trial"))
        val paid = ConversionCopy.sheetDisclosure(trial, price, false)
        assertFalse(paid.lowercase().contains("free during trial"))
        assertTrue(paid.startsWith("\$14.99 / year."))
    }

    @Test fun failureCopyDoesNotBlameATrialWhenIneligible() {
        assertTrue(ConversionCopy.purchaseFailedMessage(false).lowercase().contains("purchase"))
        assertFalse(ConversionCopy.purchaseFailedMessage(false).lowercase().contains("trial"))
        assertTrue(ConversionCopy.purchaseCancelledMessage(true).lowercase().contains("trial"))
    }

    @Test fun shortCta() {
        assertEquals("Start My Free Trial", ConversionCopy.shortCtaLabel(true))
        assertEquals("Continue with Vitals+", ConversionCopy.shortCtaLabel(false))
    }

    @Test fun badgeUsesTrialDaysThenAnnualSavingAndInventsNothing() {
        assertEquals("7 DAYS FREE", ConversionCopy.badgeText(trial, true, 64))
        assertEquals("SAVE 64%", ConversionCopy.badgeText(trial, false, 64))
        assertEquals("VITALS+", ConversionCopy.badgeText(null, false, null))
        assertEquals("VITALS+", ConversionCopy.badgeText(null, false, 0))
    }

    @Test fun paywallCtaWaitsUntilEligibilityResolves() {
        assertNull(ConversionCopy.paywallCtaTitle(false, true, false, false))
        assertEquals("Start My Free Trial", ConversionCopy.paywallCtaTitle(false, true, true, true))
        assertEquals("Subscribe", ConversionCopy.paywallCtaTitle(false, true, true, false))
        assertEquals("Unlock Lifetime", ConversionCopy.paywallCtaTitle(true, false, false, false))
    }

    @Test fun pendingCopyPromisesNothingItCannotDeliver() {
        val eligible = ConversionCopy.purchasePendingMessage(true)
        assertTrue(eligible.contains("trial") && eligible.contains("Waiting"))
        assertFalse(ConversionCopy.purchasePendingMessage(false).lowercase().contains("trial"))
    }

    @Test fun unavailableCopyPointsAtTheConnection() {
        assertTrue(ConversionCopy.UNAVAILABLE.contains("connection"))
    }
}
