package com.jackwallner.vitals.model

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** Ports `EnergyAveragesCalculatorTests` plus the excluded-day cases from `ExcludedDaysTests`. */
class EnergyAveragesTest {
    private val today = TestDays.today

    @Test fun averagesTdeeAndBmrOverCompletedDays() {
        val result = EnergyAveragesCalculator.compute(TestDays.before(today, 30, 500.0, 1_600.0), today)
        assertEquals(30, result.sampleDays)
        assertEquals(2_100.0, result.tdee!!, 0.001)
        assertEquals(1_600.0, result.bmr!!, 0.001)
    }

    @Test fun excludesTodaysPartialDay() {
        val history = TestDays.before(today, 10, 500.0, 1_600.0) + DayStats(today, 150.0, 50.0, 100.0, 0)
        val result = EnergyAveragesCalculator.compute(history, today)
        assertEquals(10, result.sampleDays)
        assertEquals(2_100.0, result.tdee!!, 0.001)
    }

    @Test fun dropsZeroRestingNonWearDays() {
        val history = TestDays.before(today, 8, 500.0, 1_600.0) + TestDays.before(today, 2, 0.0, 0.0, from = 9)
        val result = EnergyAveragesCalculator.compute(history, today)
        assertEquals(8, result.sampleDays)
        assertEquals(1_600.0, result.bmr!!, 0.001)
    }

    @Test fun belowMinimumSamplesReturnsNothing() {
        val result = EnergyAveragesCalculator.compute(TestDays.before(today, 5, 500.0, 1_600.0), today)
        assertEquals(5, result.sampleDays)
        assertNull(result.tdee)
        assertNull(result.bmr)
    }

    @Test fun ignoresRecordsOlderThanThirtyCompletedDays() {
        val history = TestDays.before(today, 30, 500.0, 1_600.0) + TestDays.before(today, 4, 5_000.0, 5_000.0, from = 31)
        val result = EnergyAveragesCalculator.compute(history, today)
        assertEquals(30, result.sampleDays)
        assertEquals(2_100.0, result.tdee!!, 0.001)
        assertEquals(1_600.0, result.bmr!!, 0.001)
    }

    @Test fun extraFetchedRowsMatchTheExactWindow() {
        val exact = EnergyAveragesCalculator.compute(TestDays.before(today, 30, 500.0, 1_600.0), today)
        val extra = EnergyAveragesCalculator.compute(TestDays.before(today, 34, 500.0, 1_600.0), today)
        assertEquals(exact, extra)
    }

    @Test fun estimatedRestingDaysAreNotMeasuredSoTheyAreSkipped() {
        val estimated = (1..10).map {
            DayStats(today.minusDays(it.toLong()), 1_900.0, 400.0, 1_500.0, 0, RestingSource.ESTIMATED)
        }
        val result = EnergyAveragesCalculator.compute(estimated, today)
        assertEquals(0, result.sampleDays)
        assertNull(result.tdee)
    }

    @Test fun excludedDaysAreDropped() {
        val history = TestDays.before(today, 20, 500.0, 1_600.0).mapIndexed { i, d ->
            if (i < 5) d.copy(total = 9_000.0, active = 7_400.0) else d
        }
        val excluded = history.take(5).map { ExcludedDays.key(it.date) }.toSet()
        val withAll = EnergyAveragesCalculator.compute(history, today)
        val without = EnergyAveragesCalculator.compute(history, today, excludedKeys = excluded)
        assertNotNull(without.tdee)
        assertEquals(15, without.sampleDays)
        assertEquals(2_100.0, without.tdee!!, 0.001)
        assertEquals(true, withAll.tdee!! > 2_100.0)
    }

    @Test fun excludingEnoughDaysDropsBelowTheSampleFloor() {
        val history = TestDays.before(today, 9, 500.0, 1_600.0)
        val excluded = history.take(3).map { ExcludedDays.key(it.date) }.toSet()
        val result = EnergyAveragesCalculator.compute(history, today, excludedKeys = excluded)
        assertEquals(6, result.sampleDays)
        assertNull(result.tdee)
        assertEquals(LocalDate.of(2026, 7, 16), today)
    }
}
