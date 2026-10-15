package com.jackwallner.vitals.model

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime

enum class PacingComparison(val raw: Int, val label: String) {
    DAY_OF_WEEK(0, "Same weekday"),
    ALL_DAYS(1, "All days");

    companion object {
        fun from(raw: Int) = entries.firstOrNull { it.raw == raw } ?: DAY_OF_WEEK
    }
}

enum class PacingLookback(val days: Int, val label: String) {
    FOURTEEN(14, "14 days"),
    THIRTY(30, "30 days"),
    NINETY(90, "90 days"),
    YEAR(365, "1 year");

    companion object {
        val default = THIRTY
        fun from(days: Int) = entries.firstOrNull { it.days == days } ?: default
    }
}

/** Mirrors `effectiveMinPacingSamples`. */
fun effectiveMinPacingSamples(comparison: PacingComparison, lookback: PacingLookback): Int = when (comparison) {
    PacingComparison.DAY_OF_WEEK -> minOf(maxOf(lookback.days / 7, 1), 3)
    PacingComparison.ALL_DAYS -> 3
}

/** Usual calories and steps by this time of day; sample counts exclude empty days per metric. */
data class PacingResult(
    val avgCalories: Double?,
    val avgSteps: Int?,
    val calorieSampleDays: Int,
    val stepSampleDays: Int,
    val avgCaloriesFullDay: Double? = null,
    val avgStepsFullDay: Int? = null,
) {
    data class Dashboard(
        val calories: Double?,
        val caloriesBuilding: Boolean,
        val steps: Int?,
        val stepsBuilding: Boolean,
    )

    fun dashboardValues(minSamples: Int, showCalories: Boolean, showSteps: Boolean): Dashboard {
        var calories: Double? = null
        var caloriesBuilding = false
        if (showCalories) {
            val avg = avgCalories
            if (avg != null && calorieSampleDays >= minSamples && avg > 0) calories = avg
            else caloriesBuilding = calorieSampleDays in 1 until minSamples
        }
        var steps: Int? = null
        var stepsBuilding = false
        if (showSteps) {
            val avg = avgSteps
            if (avg != null && stepSampleDays >= minSamples && avg > 0) steps = avg
            else stepsBuilding = stepSampleDays in 1 until minSamples
        }
        return Dashboard(calories, caloriesBuilding, steps, stepsBuilding)
    }

    companion object {
        val empty = PacingResult(null, null, 0, 0)
    }
}

object PacingCalculator {
    /** No pacing before this hour: too little of the day has happened to compare. */
    const val FIRST_HOUR = 6

    /**
     * Port of `fetchPacing`: each completed day in the window that qualifies
     * contributes its full-day total weighted by how much of today has elapsed.
     * Days with no data and excluded days are not samples.
     */
    fun compute(
        history: List<DayStats>,
        now: LocalDateTime,
        comparison: PacingComparison,
        lookback: PacingLookback,
        excludedKeys: Set<String> = emptySet(),
    ): PacingResult {
        if (now.hour < FIRST_HOUR) return PacingResult.empty
        val today = now.toLocalDate()
        val dayFraction = minOf(java.time.Duration.between(today.atStartOfDay(), now).seconds / 86_400.0, 1.0)
        val byDate = history.associateBy { it.date }
        val targetWeekday: DayOfWeek = today.dayOfWeek
        var calWeighted = 0.0
        var stepWeighted = 0.0
        var calFull = 0.0
        var stepFull = 0.0
        var calDays = 0
        var stepDays = 0
        for (offset in 1..lookback.days) {
            val day: LocalDate = today.minusDays(offset.toLong())
            if (comparison == PacingComparison.DAY_OF_WEEK && day.dayOfWeek != targetWeekday) continue
            if (ExcludedDays.contains(day, excludedKeys)) continue
            val stats = byDate[day] ?: continue
            if (stats.total > 0) {
                calDays++
                calWeighted += stats.total * dayFraction
                calFull += stats.total
            }
            if (stats.steps > 0) {
                stepDays++
                stepWeighted += stats.steps * dayFraction
                stepFull += stats.steps
            }
        }
        return PacingResult(
            avgCalories = if (calDays > 0) calWeighted / calDays else null,
            avgSteps = if (stepDays > 0) (stepWeighted / stepDays).toInt() else null,
            calorieSampleDays = calDays,
            stepSampleDays = stepDays,
            avgCaloriesFullDay = if (calDays > 0) calFull / calDays else null,
            avgStepsFullDay = if (stepDays > 0) (stepFull / stepDays).toInt() else null,
        )
    }
}

sealed interface GoalOutlook {
    data class OnTrack(val margin: Double) : GoalOutlook
    data class Behind(val shortfall: Double) : GoalOutlook
}

object ProjectionCalculator {
    /** `projected = current + max(0, usualFullDay - usualByNow)`; never below what is banked. */
    fun projectedEndOfDay(current: Double, usualByNow: Double?, usualFullDay: Double?): Double? {
        if (usualFullDay == null || usualFullDay <= 0) return null
        if (usualByNow == null) return maxOf(current, usualFullDay)
        return current + maxOf(0.0, usualFullDay - usualByNow)
    }

    fun goalOutlook(projected: Double?, goal: Double?): GoalOutlook? {
        if (projected == null || goal == null || goal <= 0) return null
        val delta = projected - goal
        val tolerance = goal * 0.02
        return if (delta >= -tolerance) GoalOutlook.OnTrack(maxOf(0.0, delta)) else GoalOutlook.Behind(-delta)
    }
}
