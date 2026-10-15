package com.jackwallner.vitals.model

import java.time.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Ports `ProjectionCalculatorTests` and the pacing rules from `HealthKitService.fetchPacing`. */
class PacingAndProjectionTest {
    @Test fun projectionAddsTypicalRemainder() {
        assertEquals(2_700.0, ProjectionCalculator.projectedEndOfDay(1_200.0, 1_000.0, 2_500.0)!!, 0.0001)
    }

    @Test fun projectionAddsRemainderEvenWhenAheadOfPace() {
        assertEquals(2_700.0, ProjectionCalculator.projectedEndOfDay(2_600.0, 2_400.0, 2_500.0)!!, 0.0001)
    }

    @Test fun projectionClampsNegativeRemainder() {
        assertEquals(2_600.0, ProjectionCalculator.projectedEndOfDay(2_600.0, 2_600.0, 2_500.0)!!, 0.0001)
    }

    @Test fun projectionNullWithoutFullDayBaseline() {
        assertNull(ProjectionCalculator.projectedEndOfDay(1_000.0, 500.0, null))
        assertNull(ProjectionCalculator.projectedEndOfDay(1_000.0, 500.0, 0.0))
    }

    @Test fun projectionFallsBackToMaxWithoutNowReference() {
        assertEquals(3_000.0, ProjectionCalculator.projectedEndOfDay(3_000.0, null, 2_500.0)!!, 0.0001)
        assertEquals(2_500.0, ProjectionCalculator.projectedEndOfDay(800.0, null, 2_500.0)!!, 0.0001)
    }

    @Test fun goalOutlookOnTrackWithinTolerance() {
        assertEquals(GoalOutlook.OnTrack(0.0), ProjectionCalculator.goalOutlook(2_470.0, 2_500.0))
    }

    @Test fun goalOutlookBehindBeyondTolerance() {
        assertEquals(GoalOutlook.Behind(300.0), ProjectionCalculator.goalOutlook(2_200.0, 2_500.0))
    }

    @Test fun goalOutlookOverGoal() {
        assertEquals(GoalOutlook.OnTrack(300.0), ProjectionCalculator.goalOutlook(2_800.0, 2_500.0))
    }

    @Test fun goalOutlookNullWithoutGoalOrProjection() {
        assertNull(ProjectionCalculator.goalOutlook(2_500.0, null))
        assertNull(ProjectionCalculator.goalOutlook(null, 2_500.0))
    }

    // Pacing

    private val noon = LocalDateTime.of(2026, 7, 16, 12, 0) // a Thursday

    private fun week(count: Int, total: Double, steps: Int) =
        (1..count).map { DayStats(noon.toLocalDate().minusDays(it.toLong()), total, null, null, steps, RestingSource.UNSPLIT) }

    @Test fun minimumSamplesFollowTheComparisonAndLookback() {
        assertEquals(2, effectiveMinPacingSamples(PacingComparison.DAY_OF_WEEK, PacingLookback.FOURTEEN))
        assertEquals(3, effectiveMinPacingSamples(PacingComparison.DAY_OF_WEEK, PacingLookback.THIRTY))
        assertEquals(3, effectiveMinPacingSamples(PacingComparison.ALL_DAYS, PacingLookback.FOURTEEN))
    }

    @Test fun noPacingBeforeSixAm() {
        val result = PacingCalculator.compute(week(30, 2_000.0, 8_000), LocalDateTime.of(2026, 7, 16, 5, 59), PacingComparison.ALL_DAYS, PacingLookback.THIRTY)
        assertEquals(PacingResult.empty, result)
    }

    @Test fun usualByNowIsTheFullDayScaledByHowMuchOfTodayHasPassed() {
        val result = PacingCalculator.compute(week(30, 2_000.0, 8_000), noon, PacingComparison.ALL_DAYS, PacingLookback.THIRTY)
        assertEquals(1_000.0, result.avgCalories!!, 0.001)
        assertEquals(4_000, result.avgSteps)
        assertEquals(2_000.0, result.avgCaloriesFullDay!!, 0.001)
        assertEquals(30, result.calorieSampleDays)
    }

    @Test fun sameWeekdayOnlyCountsMatchingDays() {
        val result = PacingCalculator.compute(week(30, 2_000.0, 8_000), noon, PacingComparison.DAY_OF_WEEK, PacingLookback.THIRTY)
        assertEquals(4, result.calorieSampleDays)
    }

    @Test fun emptyAndExcludedDaysAreNotSamples() {
        val days = week(10, 2_000.0, 8_000).mapIndexed { i, d -> if (i < 2) d.copy(total = 0.0, steps = 0) else d }
        val excluded = setOf(ExcludedDays.key(days[2].date))
        val result = PacingCalculator.compute(days, noon, PacingComparison.ALL_DAYS, PacingLookback.THIRTY, excluded)
        assertEquals(7, result.calorieSampleDays)
    }

    @Test fun dashboardHidesAComparisonUntilEnoughDaysExist() {
        val building = PacingResult(500.0, 3_000, 2, 2).dashboardValues(3, true, true)
        assertNull(building.calories)
        assertTrue(building.caloriesBuilding)
        val ready = PacingResult(500.0, 3_000, 3, 3).dashboardValues(3, true, true)
        assertEquals(500.0, ready.calories)
        assertEquals(3_000, ready.steps)
    }
}
