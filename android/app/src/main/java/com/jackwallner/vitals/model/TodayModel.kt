package com.jackwallner.vitals.model

import java.time.LocalDate
import java.time.LocalDateTime

/** Everything the Today screen derives from the fetched window, kept pure so JVM tests can pin it. */
data class TodayModel(
    val day: DayStats,
    val calorieTypical: Double?,
    val stepTypical: Double?,
    val projectedCalories: Double?,
    val projectedSteps: Double?,
    /** Days of data so far while pacing is still warming up; null once it can compare. */
    val calorieBuildingSamples: Int?,
    val stepBuildingSamples: Int?,
    val minPacingSamples: Int,
    val calorieStreak: Int,
    val stepStreak: Int,
    val averages: EnergyAverages,
) {
    val total: Double get() = day.total
    val steps: Int get() = day.steps
}

/** The settings the model reads, passed in so the calculator has no Android or Compose dependency. */
data class TodayParams(
    val pacingComparison: PacingComparison,
    val pacingLookback: PacingLookback,
    val showPacing: Boolean,
    val showCalories: Boolean,
    val showSteps: Boolean,
    val isPro: Boolean,
    val showProjections: Boolean,
    val showStreaks: Boolean,
    val calorieGoal: Double?,
    val stepGoal: Int?,
    val excludedKeys: Set<String>,
)

object TodayCalculator {
    /** The fetch window the model needs: the longest of the pacing lookback and the 30-day TDEE window. */
    fun windowDays(lookback: PacingLookback): Int = maxOf(lookback.days, EnergyAveragesCalculator.WINDOW_DAYS)

    fun compute(window: List<DayStats>, now: LocalDateTime, params: TodayParams): TodayModel {
        val today: LocalDate = now.toLocalDate()
        val day = window.firstOrNull { it.date == today } ?: DayStats.empty(today)
        val pacing = if (params.showPacing || (params.isPro && params.showProjections)) {
            PacingCalculator.compute(window, now, params.pacingComparison, params.pacingLookback, params.excludedKeys)
        } else PacingResult.empty
        val minSamples = effectiveMinPacingSamples(params.pacingComparison, params.pacingLookback)
        val shown = pacing.dashboardValues(minSamples, params.showCalories, params.showSteps)
        val projecting = params.isPro && params.showProjections
        val usable = pacing.calorieSampleDays >= minSamples
        val usableSteps = pacing.stepSampleDays >= minSamples
        val streaks = params.isPro && params.showStreaks
        return TodayModel(
            day = day,
            calorieTypical = if (params.showPacing) shown.calories else null,
            stepTypical = if (params.showPacing) shown.steps?.toDouble() else null,
            projectedCalories = if (projecting && params.showCalories && usable) {
                ProjectionCalculator.projectedEndOfDay(day.total, pacing.avgCalories, pacing.avgCaloriesFullDay)
            } else null,
            projectedSteps = if (projecting && params.showSteps && usableSteps) {
                ProjectionCalculator.projectedEndOfDay(day.steps.toDouble(), pacing.avgSteps?.toDouble(), pacing.avgStepsFullDay?.toDouble())
            } else null,
            calorieBuildingSamples = if (params.showPacing && shown.caloriesBuilding) pacing.calorieSampleDays else null,
            stepBuildingSamples = if (params.showPacing && shown.stepsBuilding) pacing.stepSampleDays else null,
            minPacingSamples = minSamples,
            calorieStreak = if (streaks) params.calorieGoal?.let { g ->
                StreakCalculator.currentStreak(window, today, params.excludedKeys) { it.total >= g }
            } ?: 0 else 0,
            stepStreak = if (streaks) params.stepGoal?.let { g ->
                StreakCalculator.currentStreak(window, today, params.excludedKeys) { it.steps >= g }
            } ?: 0 else 0,
            averages = if (params.isPro) EnergyAveragesCalculator.compute(window, today, excludedKeys = params.excludedKeys)
            else EnergyAverages(null, null, 0),
        )
    }
}
