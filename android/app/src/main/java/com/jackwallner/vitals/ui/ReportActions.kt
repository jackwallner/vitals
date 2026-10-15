package com.jackwallner.vitals.ui

import android.content.Context
import com.jackwallner.vitals.AppGraph
import com.jackwallner.vitals.model.ExcludedDays
import com.jackwallner.vitals.model.Format
import com.jackwallner.vitals.model.HistoryCalculator
import com.jackwallner.vitals.model.SummaryReport
import com.jackwallner.vitals.model.SummaryReports
import java.io.File
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

sealed interface ReportResult {
    data class Ready(val title: String, val file: File, val shareText: String) : ReportResult
    data class Failed(val message: String) : ReportResult
}

internal fun shareText(report: SummaryReport): String = buildString {
    append("${report.title}: ")
    append("${Format.number(report.avgCalories)} cal and ${Format.number(report.avgSteps.toDouble())} steps a day ")
    append("over ${report.countedDayCount} days. Made with Total Calories.")
}

/** Builds a Vitals+ PDF summary for a date range, reading the same counted days every other figure uses. */
suspend fun buildReport(graph: AppGraph, context: Context, title: String, start: LocalDate, end: LocalDate): ReportResult {
    val repo = graph.repo
    val settings = graph.settings
    return try {
        val days = repo.stats(start, end)
        if (days.none { it.hasData }) return ReportResult.Failed("There is no history data for that report range yet.")
        val (previousStart, previousEnd) = HistoryCalculator.previousRange(start, end)
        val previous = runCatching { repo.stats(previousStart, previousEnd) }.getOrDefault(emptyList())
        val excluded = settings.excludedKeys(LocalDate.now())
        if (days.all { ExcludedDays.contains(it.date, excluded) }) {
            return ReportResult.Failed("Every day in that range is excluded from your averages, so there is nothing to summarize.")
        }
        val wantsNet = settings.showNet && graph.store.isPro && repo.hasFoodAccess
        val food = if (wantsNet) runCatching { repo.food(start, end) }.getOrNull() else null
        val report = SummaryReports.make(
            title = title, start = start, end = end, allDays = days,
            previousDays = previous.filter { !ExcludedDays.contains(it.date, excluded) },
            excludedKeys = excluded, calorieGoal = settings.calorieGoal, stepGoal = settings.stepGoal,
            food = food, fasting = settings.netFasting,
        )
        val file = withContext(Dispatchers.IO) { ReportPdf.render(report, File(context.cacheDir, "exports")) }
        graph.review.recordOneShotPositiveMoment("report_generated")
        ReportResult.Ready(title, file, shareText(report))
    } catch (e: kotlinx.coroutines.CancellationException) {
        throw e
    } catch (e: Exception) {
        ReportResult.Failed("Could not generate the PDF report. Please try again.")
    }
}
