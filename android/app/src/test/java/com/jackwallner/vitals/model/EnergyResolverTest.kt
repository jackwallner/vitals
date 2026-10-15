package com.jackwallner.vitals.model

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EnergyResolverTest {
    private val date = LocalDate.of(2026, 7, 16)

    private fun resolve(active: Double? = null, total: Double? = null, basal: Double? = null, derived: Double? = 1_500.0) =
        EnergyResolver.resolve(date, EnergyAggregates(active, total, basal, derived), steps = 4_000)

    @Test fun totalAndActiveSplitRestingAsTheRemainder() {
        val day = resolve(active = 500.0, total = 2_100.0)
        assertEquals(2_100.0, day.total)
        assertEquals(500.0, day.active)
        assertEquals(1_600.0, day.resting!!, 0.001)
        assertEquals(RestingSource.MEASURED_TOTAL, day.restingSource)
    }

    @Test fun activeAboveTotalIsClampedSoRestingNeverGoesNegative() {
        val day = resolve(active = 3_000.0, total = 2_100.0)
        assertEquals(2_100.0, day.active!!, 0.001)
        assertEquals(0.0, day.resting!!, 0.001)
    }

    @Test fun totalAndBasalDeriveActive() {
        val day = resolve(total = 2_300.0, basal = 1_700.0)
        assertEquals(600.0, day.active!!, 0.001)
        assertEquals(1_700.0, day.resting!!, 0.001)
        assertEquals(RestingSource.MEASURED_BMR, day.restingSource)
    }

    @Test fun totalAloneStaysUnsplit() {
        val day = resolve(total = 2_000.0, derived = null)
        assertEquals(2_000.0, day.total)
        assertNull(day.active)
        assertNull(day.resting)
        assertEquals(RestingSource.UNSPLIT, day.restingSource)
    }

    @Test fun activePlusBasalSumsToTheTotal() {
        val day = resolve(active = 400.0, basal = 1_600.0)
        assertEquals(2_000.0, day.total, 0.001)
        assertEquals(RestingSource.MEASURED_BMR, day.restingSource)
    }

    @Test fun activeAloneUsesTheEstimatedRestingAndSaysSo() {
        val day = resolve(active = 400.0, derived = 1_500.0)
        assertEquals(1_900.0, day.total, 0.001)
        assertEquals(1_500.0, day.resting!!, 0.001)
        assertTrue(day.restingIsEstimated)
    }

    @Test fun activeAloneWithoutAnEstimateShowsJustActive() {
        val day = resolve(active = 400.0, derived = null)
        assertEquals(400.0, day.total, 0.001)
        assertNull(day.resting)
        assertFalse(day.restingIsEstimated)
    }

    @Test fun basalAloneIsAllResting() {
        val day = resolve(basal = 1_650.0)
        assertEquals(1_650.0, day.total, 0.001)
        assertEquals(0.0, day.active!!, 0.001)
        assertEquals(1_650.0, day.resting!!, 0.001)
    }

    @Test fun nothingIsAnEmptyDayThatStillKeepsSteps() {
        val day = resolve(derived = 1_500.0)
        assertEquals(0.0, day.total)
        assertFalse(day.hasEnergy)
        assertTrue(day.hasData)
        assertEquals(RestingSource.NONE, day.restingSource)
    }

    @Test fun zeroRecordsCountAsNoRecords() {
        val day = resolve(active = 0.0, total = 0.0, basal = 0.0)
        assertEquals(RestingSource.NONE, day.restingSource)
    }
}
