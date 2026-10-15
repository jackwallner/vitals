package com.jackwallner.vitals.billing

import com.jackwallner.vitals.data.PackageKind
import com.jackwallner.vitals.data.PeriodUnit
import com.jackwallner.vitals.data.Plan
import com.jackwallner.vitals.data.PlanPeriod
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PlanTest {
    init { Locale.setDefault(Locale.US) }

    private val monthly = Plan("\$rc_monthly", "com.jackwallner.vitals.monthly", PackageKind.MONTHLY, 2_990_000, "\$2.99", "USD", PlanPeriod(1, PeriodUnit.MONTH), PlanPeriod(1, PeriodUnit.WEEK))
    private val yearly = Plan("\$rc_annual", "com.jackwallner.vitals.yearly", PackageKind.YEARLY, 11_990_000, "\$11.99", "USD", PlanPeriod(1, PeriodUnit.YEAR), PlanPeriod(1, PeriodUnit.WEEK))
    private val lifetime = Plan("\$rc_lifetime", "com.jackwallner.vitals.plus.lifetime", PackageKind.LIFETIME, 39_990_000, "\$39.99", "USD", null, null)

    @Test fun packageKindsComeFromTheIdentifiers() {
        assertEquals(PackageKind.YEARLY, PackageKind.fromIdentifiers("\$rc_annual"))
        assertEquals(PackageKind.MONTHLY, PackageKind.fromIdentifiers("\$rc_monthly"))
        assertEquals(PackageKind.LIFETIME, PackageKind.fromIdentifiers("com.jackwallner.vitals.plus.lifetime"))
    }

    @Test fun priceLabelsReadLikeTheIosPaywall() {
        assertEquals("\$11.99 / year", yearly.priceLabel)
        assertEquals("\$2.99 / month", monthly.priceLabel)
        assertEquals("\$39.99", lifetime.priceLabel)
    }

    @Test fun trialLabelIsInDaysForAOneWeekOffer() {
        assertEquals("7-day free trial", yearly.introOfferLabel)
        assertNull(lifetime.introOfferLabel)
    }

    @Test fun yearlySavingsAndAnchorAreComputedAgainstTwelveMonthlies() {
        assertEquals(67, yearly.savingsPercent(monthly))
        assertEquals("\$35.88", yearly.anchorPriceLabel(monthly))
        assertEquals("\$1.00 / mo", yearly.perMonthLabel)
        assertNull(monthly.savingsPercent(monthly))
        assertNull(lifetime.savingsPercent(monthly))
    }

    @Test fun perWeekAnchorsTheYearlyOverFiftyTwoWeeks() {
        assertEquals("\$0.23", yearly.perWeekLabel)
        assertNull(lifetime.perWeekLabel)
    }
}
