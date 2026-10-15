package com.jackwallner.vitals.model

import java.time.LocalDate

/** Shared builders for the model tests. */
object TestDays {
    val today: LocalDate = LocalDate.of(2026, 7, 16)

    /** `count` completed days ending the day before `reference`, newest first, each with the same burn. */
    fun before(reference: LocalDate, count: Int, active: Double, resting: Double, steps: Int = 0, from: Int = 1): List<DayStats> =
        (from until from + count).map { offset ->
            DayStats(reference.minusDays(offset.toLong()), active + resting, active, resting, steps)
        }

    fun day(date: LocalDate, total: Double, steps: Int = 0) = DayStats(date, total, null, null, steps, RestingSource.UNSPLIT)
}
