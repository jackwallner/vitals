package com.jackwallner.vitals.model

import java.time.LocalDate
import java.util.Locale
import kotlin.math.roundToInt

/** The figures at the top of History. Excluded days are left out of every one of them. */
data class HistorySummary(
    val counted: List<DayStats>,
    val excludedCount: Int,
    val totalCalories: Double,
    val avgCalories: Double,
    val totalSteps: Int,
    val avgSteps: Int,
)

data class NetSummary(val days: List<NetDay>, val total: Double, val average: Double)

object HistoryCalculator {
    const val MAX_CUSTOM_DAYS = 730

    fun summary(days: List<DayStats>, excludedKeys: Set<String>): HistorySummary {
        val counted = days.filter { !ExcludedDays.contains(it.date, excludedKeys) }
        val totalCalories = counted.sumOf { it.total }
        val totalSteps = counted.sumOf { it.steps }
        return HistorySummary(
            counted = counted,
            excludedCount = days.size - counted.size,
            totalCalories = totalCalories,
            avgCalories = if (counted.isEmpty()) 0.0 else totalCalories / counted.size,
            totalSteps = totalSteps,
            avgSteps = if (counted.isEmpty()) 0 else (totalSteps.toDouble() / counted.size).roundToInt(),
        )
    }

    fun net(history: List<DayStats>, food: Map<LocalDate, Double>, fasting: Boolean, excludedKeys: Set<String>): NetSummary {
        val counted = NetDeficit.days(history, food, fasting, excludedKeys).filter { !it.excluded }
        val total = counted.sumOf { it.net }
        return NetSummary(counted, total, if (counted.isEmpty()) 0.0 else total / counted.size)
    }

    /** The window a period covers, ending today. Custom ranges are clamped to today and two years. */
    fun range(period: HistoryPeriod, today: LocalDate, customStart: LocalDate, customEnd: LocalDate): Pair<LocalDate, LocalDate> {
        val days = period.days
        if (days != null) return today.minusDays((days - 1).toLong()) to today
        val end = minOf(customEnd, today)
        var start = minOf(customStart, end)
        if (start.plusDays(MAX_CUSTOM_DAYS.toLong()).isBefore(end)) start = end.minusDays(MAX_CUSTOM_DAYS.toLong())
        return start to end
    }

    /** The equal-length window immediately before `start`, for Deep Trends. */
    fun previousRange(start: LocalDate, end: LocalDate): Pair<LocalDate, LocalDate> {
        val length = java.time.temporal.ChronoUnit.DAYS.between(start, end) + 1
        val previousEnd = start.minusDays(1)
        return previousEnd.minusDays(length - 1) to previousEnd
    }

    fun deepTrendsLabel(period: HistoryPeriod): String = when (period) {
        HistoryPeriod.WEEK -> "vs. previous week"
        HistoryPeriod.MONTH -> "vs. previous 30 days"
        HistoryPeriod.THREE_MONTHS -> "vs. previous 90 days"
        HistoryPeriod.YEAR -> "vs. previous year"
        HistoryPeriod.CUSTOM -> "vs. previous range"
    }
}

/** The CSV export. Excluded days are flagged rather than dropped, so a missing row never reads as a gap in the data. */
object CsvExport {
    private fun escape(field: String): String {
        val needsQuotes = field.any { it == ',' || it == '"' || it == '\n' || it == '\r' }
        return if (needsQuotes) "\"${field.replace("\"", "\"\"")}\"" else field
    }

    private fun whole(value: Double) = String.format(Locale.US, "%.0f", value)

    fun make(days: List<DayStats>, includeNet: Boolean, food: Map<LocalDate, Double>, excludedKeys: Set<String>): String {
        val hasExclusions = days.any { ExcludedDays.contains(it.date, excludedKeys) }
        val columns = buildList {
            addAll(listOf("Date", "Active Calories", "Resting Calories", "Total Calories", "Steps"))
            if (includeNet) addAll(listOf("Food Calories", "Net Deficit"))
            if (hasExclusions) add("Excluded")
        }
        val rows = days.sortedBy { it.date }.map { day ->
            buildList {
                add(day.date.toString())
                add(day.active?.let(::whole) ?: "")
                add(day.resting?.let(::whole) ?: "")
                add(whole(day.total))
                add(day.steps.toString())
                if (includeNet) {
                    val eaten = food[day.date]
                    add(eaten?.let(::whole) ?: "")
                    add(eaten?.let { whole(day.total - it) } ?: "")
                }
                if (hasExclusions) add(if (ExcludedDays.contains(day.date, excludedKeys)) "yes" else "")
            }.joinToString(",") { escape(it) }
        }
        return (listOf(columns.joinToString(",") { escape(it) }) + rows).joinToString("\n")
    }
}
