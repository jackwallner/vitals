package com.jackwallner.vitals.model

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.TemporalAdjusters
import kotlin.math.abs
import kotlin.math.roundToInt

/** Stable energy reference figures averaged over recent completed days (`EnergyAveragesCalculator`). */
data class EnergyAverages(val tdee: Double?, val bmr: Double?, val sampleDays: Int)

object EnergyAveragesCalculator {
    const val WINDOW_DAYS = 30

    /** Only completed days in the 30 before `today` count; days with no measured resting energy are non-wear. */
    fun compute(
        history: List<DayStats>,
        today: LocalDate,
        minSamples: Int = 7,
        excludedKeys: Set<String> = emptySet(),
    ): EnergyAverages {
        val windowStart = today.minusDays(WINDOW_DAYS.toLong())
        val valid = history.filter {
            !ExcludedDays.contains(it.date, excludedKeys) &&
                !it.date.isBefore(windowStart) && it.date.isBefore(today) && !it.restingIsEstimated && (it.resting ?: 0.0) > 0
        }
        if (valid.size < minSamples) return EnergyAverages(null, null, valid.size)
        val n = valid.size.toDouble()
        val bmr = valid.sumOf { it.resting ?: 0.0 } / n
        val tdee = valid.sumOf { it.total } / n
        return EnergyAverages(tdee, bmr, valid.size)
    }
}

/** Consecutive completed days that hit a goal, stepping over excluded days (`MilestoneCalculator.currentStreak`). */
object StreakCalculator {
    private const val MAX_LOOKBACK_DAYS = 3650

    fun currentStreak(
        history: List<DayStats>,
        today: LocalDate,
        excludedKeys: Set<String> = emptySet(),
        hit: (DayStats) -> Boolean,
    ): Int {
        val byDay = history.associateBy { it.date }
        var cursor = today.minusDays(1)
        var streak = 0
        var walked = 0
        while (walked < MAX_LOOKBACK_DAYS) {
            walked++
            if (!ExcludedDays.contains(cursor, excludedKeys)) {
                val day = byDay[cursor] ?: break
                if (!hit(day)) break
                streak++
            }
            cursor = cursor.minusDays(1)
        }
        return streak
    }
}

/** One rolling average and its change against the prior window (`CalorieTrendMetric` / `StepTrendMetric`). */
data class TrendMetric(
    val title: String,
    val average: Double?,
    val sampleDays: Int,
    val expectedDays: Int,
    val percentChange: Double?,
) {
    val averageText: String get() = average?.let { Format.number(it) } ?: "—"

    val changeText: String
        get() {
            val change = percentChange ?: return if (sampleDays > 0) "—" else "No data"
            val arrow = if (change >= 0) "↑" else "↓"
            return "$arrow ${abs(change).roundToInt()}%"
        }
}

object Trends {
    fun make(
        title: String,
        periodDays: Int,
        days: List<DayStats>,
        excludedKeys: Set<String>,
        value: (DayStats) -> Double,
    ): TrendMetric {
        val sorted = days.sortedBy { it.date }
        val endDate = sorted.lastOrNull()?.date ?: return TrendMetric(title, null, 0, periodDays, null)
        fun counted(d: DayStats) = value(d) > 0 && !ExcludedDays.contains(d.date, excludedKeys)
        val reference = sorted.lastOrNull { it.date.isBefore(endDate) && counted(it) }?.date
            ?: return TrendMetric(title, null, 0, periodDays, null)
        val currentStart = reference.minusDays((periodDays - 1).toLong())
        val previousStart = currentStart.minusDays(periodDays.toLong())
        val previousEnd = currentStart.minusDays(1)
        val current = sorted.filter { !it.date.isBefore(currentStart) && !it.date.isAfter(reference) && counted(it) }
        val previous = sorted.filter { !it.date.isBefore(previousStart) && !it.date.isAfter(previousEnd) && counted(it) }
        val avg = current.takeIf { it.isNotEmpty() }?.let { c -> c.sumOf(value) / c.size }
        val prev = previous.takeIf { it.isNotEmpty() }?.let { p -> p.sumOf(value) / p.size }
        val change = if (avg != null && prev != null && prev > 0) (avg - prev) / prev * 100 else null
        return TrendMetric(title, avg, current.size, periodDays, change)
    }
}

/** Net calories for a day: burned minus the food Health Connect holds for it. */
data class NetDay(val date: LocalDate, val burned: Double, val food: Double, val excluded: Boolean) {
    val net: Double get() = burned - food
}

object NetDeficit {
    /** A day shows in net history when it has burn and food (or Fasting Mode is on); `counts` also drops excluded days. */
    fun days(
        history: List<DayStats>,
        food: Map<LocalDate, Double>,
        fasting: Boolean,
        excludedKeys: Set<String>,
    ): List<NetDay> = history.mapNotNull { day ->
        val burned = maxOf(day.total, 0.0)
        val eaten = maxOf(food[day.date] ?: 0.0, 0.0)
        if (burned <= 0 || !(fasting || eaten > 0)) null
        else NetDay(day.date, burned, eaten, ExcludedDays.contains(day.date, excludedKeys))
    }

    fun signed(value: Double): String {
        val r = value.roundToInt()
        return if (r > 0) "+${Format.number(r.toDouble())}" else Format.number(r.toDouble())
    }
}

enum class HistoryPeriod(val label: String, val days: Int?) {
    WEEK("7D", 7), MONTH("30D", 30), THREE_MONTHS("90D", 90), YEAR("1Y", 365), CUSTOM("Custom", null);

    val aggregatesByWeek get() = this == THREE_MONTHS
    val aggregatesByMonth get() = this == YEAR
}

/** A chart bar: one day, or a week or month of averaged days on the long periods. */
data class Bucket(val date: LocalDate, val value: Double, val excluded: Boolean)

object Buckets {
    fun weekStart(date: LocalDate): LocalDate = date.with(TemporalAdjusters.previousOrSame(DayOfWeek.SUNDAY))

    fun make(
        days: List<DayStats>,
        period: HistoryPeriod,
        excludedKeys: Set<String>,
        value: (DayStats) -> Double,
    ): List<Bucket> {
        val sorted = days.sortedBy { it.date }
        if (!period.aggregatesByWeek && !period.aggregatesByMonth) {
            return sorted.map { Bucket(it.date, value(it), ExcludedDays.contains(it.date, excludedKeys)) }
        }
        val counted = sorted.filter { !ExcludedDays.contains(it.date, excludedKeys) }
        val groups = counted.groupBy { if (period.aggregatesByMonth) YearMonth.from(it.date).atDay(1) else weekStart(it.date) }
        return groups.toSortedMap().map { (start, group) ->
            Bucket(start, group.sumOf(value) / group.size, false)
        }
    }
}

data class DeepTrendInsight(
    val title: String,
    val current: String,
    val previous: String,
    val change: String,
    val percent: String,
    val narrative: String,
    val isUp: Boolean,
    val isFlat: Boolean,
)

object DeepTrends {
    private fun average(values: List<Double>): Double? =
        values.filter { it > 0 }.takeIf { it.isNotEmpty() }?.let { it.sum() / it.size }

    private fun signedValue(value: String) = if (value.startsWith("-")) value else "+$value"

    private fun signedPercent(value: Double): String {
        val r = value.roundToInt()
        return when {
            r == 0 -> "0%"
            r > 0 -> "+$r%"
            else -> "$r%"
        }
    }

    fun insights(current: List<DayStats>, previous: List<DayStats>): List<DeepTrendInsight> {
        val out = mutableListOf<DeepTrendInsight>()
        fun add(title: String, noun: String, cur: Double?, prev: Double?) {
            if (prev == null || prev <= 0 || cur == null) return
            val delta = cur - prev
            val percent = delta / prev * 100
            val rounded = delta.roundToInt()
            out += DeepTrendInsight(
                title = title,
                current = Format.number(cur),
                previous = Format.number(prev),
                change = signedValue(Format.number(rounded.toDouble())),
                percent = signedPercent(percent),
                narrative = if (abs(delta) < 1) "$title held steady day-to-day."
                else "You averaged ${Format.number(abs(rounded).toDouble())} ${if (delta >= 0) "more" else "fewer"} $noun per day.",
                isUp = delta >= 0,
                isFlat = percent.roundToInt() == 0,
            )
        }
        add("Calories", "calories", average(current.map { it.total }), average(previous.map { it.total }))
        add("Steps", "steps", average(current.map { it.steps.toDouble() }), average(previous.map { it.steps.toDouble() }))
        return out
    }

    fun highlights(days: List<DayStats>, shortDate: (LocalDate) -> String): List<String> {
        val out = mutableListOf<String>()
        val active = days.count { it.total > 0 || it.steps > 0 }
        if (days.isNotEmpty()) out += "$active of ${days.size} days had calories or steps logged."
        days.maxByOrNull { it.total }?.takeIf { it.total > 0 }?.let {
            out += "Peak calories: ${Format.number(it.total)} on ${shortDate(it.date)}."
        }
        days.maxByOrNull { it.steps }?.takeIf { it.steps > 0 }?.let {
            out += "Peak steps: ${Format.number(it.steps.toDouble())} on ${shortDate(it.date)}."
        }
        return out
    }
}

/** What the PDF report quotes. Every figure reads the counted days; charts also draw excluded ones. */
data class SummaryReport(
    val title: String,
    val start: LocalDate,
    val end: LocalDate,
    val days: List<DayStats>,
    val excludedKeys: Set<String>,
    val countedDayCount: Int,
    val excludedDayCount: Int,
    val totalCalories: Double,
    val avgCalories: Double,
    val avgActive: Double?,
    val avgResting: Double?,
    val totalSteps: Int,
    val avgSteps: Int,
    val activeDayCount: Int,
    val peakCalorieDay: DayStats?,
    val peakStepDay: DayStats?,
    val calorieTrendPct: Double?,
    val stepTrendPct: Double?,
    val calorieGoal: Double?,
    val stepGoal: Int?,
    val calorieGoalHitDays: Int,
    val stepGoalHitDays: Int,
    val avgNet: Double?,
    val netDayCount: Int,
)

object SummaryReports {
    fun make(
        title: String,
        start: LocalDate,
        end: LocalDate,
        allDays: List<DayStats>,
        previousDays: List<DayStats>,
        excludedKeys: Set<String>,
        calorieGoal: Double?,
        stepGoal: Int?,
        food: Map<LocalDate, Double>? = null,
        fasting: Boolean = false,
    ): SummaryReport {
        val days = allDays.filter { !ExcludedDays.contains(it.date, excludedKeys) }
        val prior = previousDays.filter { !ExcludedDays.contains(it.date, excludedKeys) }
        val count = maxOf(days.size, 1)
        val total = days.sumOf { it.total }
        val steps = days.sumOf { it.steps }
        val avgSteps = (steps.toDouble() / count).roundToInt()
        val avgCal = total / count
        fun trend(current: Double, previous: Double) = if (previous > 0) (current - previous) / previous * 100 else null
        val priorCal = prior.filter { it.total > 0 }.let { p -> if (p.isEmpty()) 0.0 else p.sumOf { it.total } / p.size }
        val priorSteps = prior.filter { it.steps > 0 }.let { p -> if (p.isEmpty()) 0.0 else p.sumOf { it.steps }.toDouble() / p.size }
        val withSplit = days.filter { it.active != null && it.resting != null }
        val net = food?.let { NetDeficit.days(days, it, fasting, emptySet()) }.orEmpty()
        return SummaryReport(
            title = title,
            start = start,
            end = end,
            days = allDays.sortedBy { it.date },
            excludedKeys = excludedKeys,
            countedDayCount = days.size,
            excludedDayCount = allDays.size - days.size,
            totalCalories = total,
            avgCalories = avgCal,
            avgActive = withSplit.takeIf { it.isNotEmpty() }?.let { w -> w.sumOf { it.active ?: 0.0 } / w.size },
            avgResting = withSplit.takeIf { it.isNotEmpty() }?.let { w -> w.sumOf { it.resting ?: 0.0 } / w.size },
            totalSteps = steps,
            avgSteps = avgSteps,
            activeDayCount = days.count { it.total > 0 },
            peakCalorieDay = days.maxByOrNull { it.total },
            peakStepDay = days.maxByOrNull { it.steps },
            calorieTrendPct = trend(avgCal, priorCal),
            stepTrendPct = trend(avgSteps.toDouble(), priorSteps),
            calorieGoal = calorieGoal,
            stepGoal = stepGoal,
            calorieGoalHitDays = calorieGoal?.let { g -> days.count { it.total >= g } } ?: 0,
            stepGoalHitDays = stepGoal?.let { g -> days.count { it.steps >= g } } ?: 0,
            avgNet = net.takeIf { it.isNotEmpty() }?.let { n -> n.sumOf { it.net } / n.size },
            netDayCount = net.size,
        )
    }
}
