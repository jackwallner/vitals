package com.jackwallner.vitals.model

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ExcludedDaysTest {
    private val today = TestDays.today

    @Test fun keyMatchesTheCacheSpelling() {
        assertEquals("2026-07-04", ExcludedDays.key(LocalDate.of(2026, 7, 4)))
    }

    @Test fun pausedKeysCoverPauseDayThroughTodayInclusive() {
        val keys = ExcludedDays.pausedKeys(LocalDate.of(2026, 7, 13), today)
        assertEquals(setOf("2026-07-13", "2026-07-14", "2026-07-15", "2026-07-16"), keys)
    }

    @Test fun notPausedCoversNothing() {
        assertTrue(ExcludedDays.pausedKeys(null, today).isEmpty())
    }

    @Test fun pauseDatedInTheFutureCoversNothing() {
        assertTrue(ExcludedDays.pausedKeys(today.plusDays(2), today).isEmpty())
    }

    @Test fun everyDayOfAYearRoundTripsThroughItsKey() {
        var cursor = LocalDate.of(2026, 1, 1)
        while (cursor.year == 2026) {
            assertEquals(cursor, ExcludedDays.date(ExcludedDays.key(cursor)))
            cursor = cursor.plusDays(1)
        }
    }

    @Test fun malformedKeyParsesToNull() {
        assertNull(ExcludedDays.date("not-a-day"))
        assertNull(ExcludedDays.date("2026-13-40"))
    }

    @Test fun containsIsFalseForAnEmptySet() {
        assertFalse(ExcludedDays.contains(today, emptySet()))
        assertTrue(ExcludedDays.contains(today, setOf("2026-07-16")))
    }

    // Streaks

    private fun history(vararg totals: Pair<Int, Double>) =
        totals.map { (offset, total) -> TestDays.day(today.minusDays(offset.toLong()), total) }

    @Test fun excludedDayNeitherBreaksNorExtendsAStreak() {
        val days = history(1 to 3_000.0, 2 to 100.0, 3 to 3_000.0, 4 to 3_000.0)
        val excluded = setOf(ExcludedDays.key(today.minusDays(2)))
        assertEquals(3, StreakCalculator.currentStreak(days, today, excluded) { it.total >= 2_500 })
        assertEquals(1, StreakCalculator.currentStreak(days, today) { it.total >= 2_500 })
    }

    @Test fun anExcludedDayWithNoRecordAlsoBridgesTheStreak() {
        val days = history(1 to 3_000.0, 3 to 3_000.0)
        val excluded = setOf(ExcludedDays.key(today.minusDays(2)))
        assertEquals(2, StreakCalculator.currentStreak(days, today, excluded) { it.total >= 2_500 })
    }

    @Test fun allDaysExcludedTerminatesWithNoStreak() {
        val days = history(1 to 3_000.0, 2 to 3_000.0)
        val excluded = (1..4000).map { ExcludedDays.key(today.minusDays(it.toLong())) }.toSet()
        assertEquals(0, StreakCalculator.currentStreak(days, today, excluded) { it.total >= 2_500 })
    }

    @Test fun streakStopsAtAMissingDay() {
        val days = history(1 to 3_000.0, 2 to 3_000.0, 4 to 3_000.0)
        assertEquals(2, StreakCalculator.currentStreak(days, today) { it.total >= 2_500 })
    }

    @Test fun todayNeverCountsTowardTheStreak() {
        val days = history(0 to 9_000.0, 1 to 3_000.0)
        assertEquals(1, StreakCalculator.currentStreak(days, today) { it.total >= 2_500 })
    }
}
