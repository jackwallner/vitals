package com.jackwallner.vitals.ui.screens

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.IntrinsicSize.Min
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.combinedClickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.DateRangePicker
import androidx.compose.material3.rememberDateRangePickerState
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.AppGraph
import com.jackwallner.vitals.billing.ConversionCopy
import com.jackwallner.vitals.model.Bucket
import com.jackwallner.vitals.model.Buckets
import com.jackwallner.vitals.model.CsvExport
import com.jackwallner.vitals.model.DayStats
import com.jackwallner.vitals.model.DeepTrendInsight
import com.jackwallner.vitals.model.DeepTrends
import com.jackwallner.vitals.model.ExcludedDays
import com.jackwallner.vitals.model.Format
import com.jackwallner.vitals.model.HistoryCalculator
import com.jackwallner.vitals.model.HistoryPeriod
import com.jackwallner.vitals.model.NetDeficit
import com.jackwallner.vitals.ui.LocalNav
import com.jackwallner.vitals.ui.Overlay
import com.jackwallner.vitals.ui.PlusFeature
import com.jackwallner.vitals.ui.ReportResult
import com.jackwallner.vitals.ui.buildReport
import com.jackwallner.vitals.ui.shareFile
import com.jackwallner.vitals.ui.theme.BarChart
import com.jackwallner.vitals.ui.theme.Card
import com.jackwallner.vitals.ui.theme.Geo
import com.jackwallner.vitals.ui.theme.Gradients
import com.jackwallner.vitals.ui.theme.LoadingBar
import com.jackwallner.vitals.ui.theme.PrimaryButton
import com.jackwallner.vitals.ui.theme.SegmentedControl
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.VitalsColors
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

private data class Loaded(
    val days: List<DayStats>,
    val previous: List<DayStats>,
    val food: Map<LocalDate, Double>,
    val error: String? = null,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(graph: AppGraph) {
    val settings = graph.settings
    val repo = graph.repo
    val isPro = graph.store.isPro
    val nav = LocalNav.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val defaults = graph.defaults
    val today = repo.now().toLocalDate()

    var period by remember { mutableStateOf(HistoryPeriod.entries.firstOrNull { it.name == defaults.getString("history.period") } ?: HistoryPeriod.WEEK) }
    var customStart by remember { mutableStateOf(defaults.getString("history.customStart")?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: today.minusDays(6)) }
    var customEnd by remember { mutableStateOf(defaults.getString("history.customEnd")?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: today) }
    // A lapsed subscriber can't keep the Custom range.
    val activePeriod = if (period == HistoryPeriod.CUSTOM && !isPro) HistoryPeriod.WEEK else period
    var loaded by remember { mutableStateOf<Loaded?>(null) }
    var loading by remember { mutableStateOf(true) }
    var reloads by remember { mutableStateOf(0) }
    var showCustom by remember { mutableStateOf(false) }
    var showExport by remember { mutableStateOf(false) }
    var generating by remember { mutableStateOf(false) }
    var reportError by remember { mutableStateOf<String?>(null) }
    var selectedCalories by remember { mutableStateOf<Int?>(null) }
    var selectedSteps by remember { mutableStateOf<Int?>(null) }
    var selectedNet by remember { mutableStateOf<Int?>(null) }

    val (start, end) = HistoryCalculator.range(activePeriod, today, customStart, customEnd)
    val wantsNet = isPro && settings.showNet

    LaunchedEffect(activePeriod, start, end, wantsNet, repo.lastRefresh, reloads) {
        loading = loaded == null
        selectedCalories = null; selectedSteps = null; selectedNet = null
        try {
            val days = repo.stats(start, end)
            val (ps, pe) = HistoryCalculator.previousRange(start, end)
            val previous = runCatching { repo.stats(ps, pe) }.getOrDefault(emptyList())
            val food = if (wantsNet && repo.hasFoodAccess) runCatching { repo.food(start, end) }.getOrDefault(emptyMap()) else emptyMap()
            loaded = Loaded(days, previous, food)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            loaded = Loaded(emptyList(), emptyList(), emptyMap(), "Couldn't read Health Connect. Pull to refresh to try again.")
        }
        loading = false
    }

    val data = loaded
    val excluded = settings.excludedKeys(today)
    val days = data?.days.orEmpty()
    val summary = remember(days, excluded) { HistoryCalculator.summary(days, excluded) }
    val net = remember(days, data?.food, settings.netFasting, excluded, wantsNet) {
        if (wantsNet) HistoryCalculator.net(days, data?.food.orEmpty(), settings.netFasting, excluded) else null
    }
    val hasNoData = days.isEmpty() || days.all { it.total == 0.0 && it.steps == 0 }

    fun report(title: String, from: LocalDate, to: LocalDate) {
        if (generating) return
        generating = true
        scope.launch {
            when (val result = buildReport(graph, context, title, from, to)) {
                is ReportResult.Ready -> nav.push(Overlay.Report(result.title, result.file, result.shareText))
                is ReportResult.Failed -> reportError = result.message
            }
            generating = false
        }
    }

    fun summaryReportTap() {
        if (!isPro) { nav.openPaywall(PlusFeature.CUSTOM_RANGES_PDF); return }
        val title = when (activePeriod) {
            HistoryPeriod.WEEK -> "7-Day Summary"
            HistoryPeriod.MONTH -> "30-Day Summary"
            HistoryPeriod.THREE_MONTHS -> "90-Day Summary"
            HistoryPeriod.YEAR -> "1-Year Summary"
            HistoryPeriod.CUSTOM -> "Custom Summary"
        }
        report(title, start, end)
    }

    fun export() {
        val csv = CsvExport.make(days, wantsNet, data?.food.orEmpty(), excluded)
        runCatching {
            val file = File(File(context.cacheDir, "exports").also { it.mkdirs() }, "vitals-history-${System.currentTimeMillis() / 1000}.csv")
            file.writeText(csv)
            context.shareFile(file, "text/csv", "Total Calories history")
        }.onFailure { reportError = "Could not save the export file. Please try again." }
    }

    PullToRefreshBox(isRefreshing = false, onRefresh = { scope.launch { repo.refresh(wantsNet); reloads++ } }, modifier = Modifier.fillMaxSize().background(palette.background)) {
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            Row(Modifier.padding(horizontal = Geo.gutter).padding(top = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("History", style = Type.title, color = palette.textPrimary)
                if (loading || generating) {
                    Spacer(Modifier.width(12.dp))
                    LoadingBar(modifier = Modifier.width(60.dp))
                }
                Spacer(Modifier.weight(1f))
                if (!hasNoData) {
                    HeaderIcon(if (isPro) Icons.Filled.PictureAsPdf else Icons.Filled.Lock, if (isPro) "Generate summary report" else "Vitals Plus summary report, locked") { summaryReportTap() }
                    Spacer(Modifier.width(8.dp))
                    HeaderIcon(Icons.Filled.FileUpload, "Export CSV") { showExport = true }
                }
            }
            Box(Modifier.padding(horizontal = Geo.gutter)) {
                SegmentedControl(
                    options = HistoryPeriod.entries.map { it.label },
                    selected = HistoryPeriod.entries.indexOf(activePeriod),
                    onSelect = { index ->
                        val chosen = HistoryPeriod.entries[index]
                        if (chosen == HistoryPeriod.CUSTOM) {
                            if (isPro) showCustom = true else nav.openPaywall(PlusFeature.CUSTOM_RANGES_PDF)
                        } else {
                            period = chosen
                            defaults.putString("history.period", chosen.name)
                        }
                    },
                    locked = if (isPro) emptySet() else setOf(HistoryPeriod.entries.indexOf(HistoryPeriod.CUSTOM)),
                )
            }
            if (activePeriod == HistoryPeriod.CUSTOM) {
                val fmt = DateTimeFormatter.ofPattern("MMM d")
                Text("${fmt.format(start)} – ${DateTimeFormatter.ofPattern("MMM d, yyyy").format(end)}", style = Type.caption, color = palette.textSecondary, modifier = Modifier.padding(horizontal = Geo.gutter).padding(top = 6.dp))
            }
            when {
                loading && data == null -> CenterMessage(null, "Loading history…", null, showBar = true)
                data?.error != null && days.isEmpty() -> CenterMessage(Icons.Filled.ErrorOutline, "Couldn't Load History", data.error, action = "Try Again" to { reloads++ })
                hasNoData -> CenterMessage(
                    Icons.Filled.DirectionsRun, "No Activity Data Yet",
                    "Start moving! Your activity data will appear here once Health Connect records your steps and calories.\n\nMake sure Health Connect permissions are enabled.",
                )
                else -> Column(
                    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = Geo.gutter).padding(top = 16.dp, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    if (isPro && days.size >= 7 && defaults.getString("history.monthlySummaryGeneratedMonth") != "${today.year}-${today.monthValue}") {
                        MonthlySummaryPrompt {
                            defaults.putString("history.monthlySummaryGeneratedMonth", "${today.year}-${today.monthValue}")
                            report("30-Day Summary", today.minusDays(29), today)
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.height(IntrinsicSize.Min)) {
                        AverageCard("Avg Calories", Format.number(summary.avgCalories), VitalsColors.caloriesPrimary, Modifier.weight(1f))
                        AverageCard("Total Calories", Format.number(summary.totalCalories), VitalsColors.caloriesPrimary, Modifier.weight(1f))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.height(IntrinsicSize.Min)) {
                        AverageCard("Avg Steps", Format.number(summary.avgSteps.toDouble()), VitalsColors.stepsPrimary, Modifier.weight(1f))
                        AverageCard("Total Steps", Format.number(summary.totalSteps.toDouble()), VitalsColors.stepsPrimary, Modifier.weight(1f))
                    }
                    if (net != null && net.days.isNotEmpty()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.height(IntrinsicSize.Min)) {
                            AverageCard("Avg Deficit", NetDeficit.signed(net.average), netColor(net.average), Modifier.weight(1f))
                            AverageCard("Total Deficit", NetDeficit.signed(net.total), netColor(net.total), Modifier.weight(1f))
                        }
                    }
                    if (summary.excludedCount > 0) ExcludedNote(summary.excludedCount)

                    val calorieBuckets = remember(days, activePeriod, excluded) { Buckets.make(days, activePeriod, excluded) { it.total } }
                    val stepBuckets = remember(days, activePeriod, excluded) { Buckets.make(days, activePeriod, excluded) { it.steps.toDouble() } }
                    ChartCard("Calories", chartHeader(calorieBuckets, selectedCalories, activePeriod, "cal")) {
                        BarChart(
                            calorieBuckets, Gradients.calories.let { Brush.verticalGradient(listOf(VitalsColors.caloriesSecondary, VitalsColors.caloriesPrimary)) },
                            average = averageOf(calorieBuckets), selected = selectedCalories, onSelect = { selectedCalories = it },
                            label = { chartLabel(it, activePeriod) },
                            description = "Calories chart, ${calorieBuckets.size} bars",
                        )
                    }
                    ChartCard("Steps", chartHeader(stepBuckets, selectedSteps, activePeriod, "steps")) {
                        BarChart(
                            stepBuckets, Brush.verticalGradient(listOf(VitalsColors.stepsSecondary, VitalsColors.stepsPrimary)),
                            average = averageOf(stepBuckets), selected = selectedSteps, onSelect = { selectedSteps = it },
                            label = { chartLabel(it, activePeriod) },
                            description = "Steps chart, ${stepBuckets.size} bars",
                        )
                    }
                    if (wantsNet) {
                        val netBuckets = remember(net) { net?.days.orEmpty().map { Bucket(it.date, it.net, false) } }
                        ChartCard("Net Deficit", chartHeader(netBuckets, selectedNet, HistoryPeriod.MONTH, "net", signed = true)) {
                            if (netBuckets.isEmpty()) {
                                Text("No days with food logged yet.", style = Type.footnote, color = palette.textTertiary, modifier = Modifier.padding(vertical = 24.dp))
                            } else {
                                BarChart(
                                    netBuckets, Brush.verticalGradient(listOf(VitalsColors.netDeficitPositive, VitalsColors.netDeficitPositive)),
                                    average = net?.average, selected = selectedNet, onSelect = { selectedNet = it }, signed = true,
                                    label = { chartLabel(it, HistoryPeriod.MONTH) }, description = "Net deficit chart, ${netBuckets.size} bars",
                                )
                            }
                        }
                    }

                    val insights = remember(summary, data?.previous, excluded) {
                        val prior = data?.previous.orEmpty().filter { !ExcludedDays.contains(it.date, excluded) }
                        DeepTrends.insights(summary.counted, prior)
                    }
                    val highlights = remember(summary) { DeepTrends.highlights(summary.counted) { Format.shortDate(it) } }
                    DeepTrendsCard(isPro, insights, if (isPro) highlights else emptyList(), HistoryCalculator.deepTrendsLabel(activePeriod), graph)
                    RecentDays(graph, days, excluded, isPro)
                }
            }
        }
    }

    if (showExport) {
        AlertDialog(
            onDismissRequest = { showExport = false },
            containerColor = palette.cardSurface,
            title = { Text("Export Health Data", style = Type.headline, color = palette.textPrimary) },
            text = { Text("This export contains sensitive health data including your daily calorie and step counts. Only share it with people and services you trust.", style = Type.subhead, color = palette.textSecondary) },
            confirmButton = { TextButton(onClick = { showExport = false; export() }) { Text("Export", color = VitalsColors.caloriesPrimary) } },
            dismissButton = { TextButton(onClick = { showExport = false }) { Text("Cancel", color = palette.textSecondary) } },
        )
    }
    reportError?.let { message ->
        AlertDialog(
            onDismissRequest = { reportError = null }, containerColor = palette.cardSurface,
            title = { Text("Report Failed", style = Type.headline, color = palette.textPrimary) },
            text = { Text(message, style = Type.subhead, color = palette.textSecondary) },
            confirmButton = { TextButton(onClick = { reportError = null }) { Text("OK", color = VitalsColors.caloriesPrimary) } },
        )
    }
    if (showCustom) {
        CustomRangeSheet(
            initialStart = customStart, initialEnd = customEnd, today = today,
            onDismiss = { showCustom = false },
            onApply = { s, e, makeReport ->
                customStart = s; customEnd = e; period = HistoryPeriod.CUSTOM; showCustom = false
                defaults.putString("history.period", HistoryPeriod.CUSTOM.name)
                defaults.putString("history.customStart", s.toString())
                defaults.putString("history.customEnd", e.toString())
                if (makeReport) report("Custom Summary", s, e)
            },
        )
    }
}

private fun netColor(value: Double) = if (value >= 0) VitalsColors.netDeficitPositive else VitalsColors.netDeficitNegative

private fun averageOf(buckets: List<Bucket>): Double? {
    val counted = buckets.filter { !it.excluded }
    return if (counted.size > 1) counted.sumOf { it.value } / counted.size else null
}

private fun chartLabel(date: LocalDate, period: HistoryPeriod): String = when (period) {
    HistoryPeriod.WEEK -> DateTimeFormatter.ofPattern("EEE", Locale.getDefault()).format(date)
    HistoryPeriod.YEAR -> DateTimeFormatter.ofPattern("MMM", Locale.getDefault()).format(date)
    else -> Format.shortDate(date)
}

private fun chartHeader(buckets: List<Bucket>, selected: Int?, period: HistoryPeriod, unit: String, signed: Boolean = false): Pair<String, String>? {
    val bucket = selected?.let { buckets.getOrNull(it) } ?: return null
    val date = when {
        period.aggregatesByMonth -> DateTimeFormatter.ofPattern("MMMM yyyy", Locale.getDefault()).format(bucket.date)
        period.aggregatesByWeek -> "Week of ${Format.mediumDate(bucket.date)}"
        else -> DateTimeFormatter.ofPattern("EEE, MMM d", Locale.getDefault()).format(bucket.date)
    }
    val value = if (signed) NetDeficit.signed(bucket.value) else Format.number(bucket.value)
    val suffix = if (period.aggregatesByWeek || period.aggregatesByMonth) " $unit/day avg" else " $unit"
    return date to (value + suffix + if (bucket.excluded) " · excluded" else "")
}

@Composable
private fun HeaderIcon(icon: ImageVector, description: String, onClick: () -> Unit) {
    Box(Modifier.size(40.dp).tappable(description, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = palette.textSecondary, modifier = Modifier.size(22.dp))
    }
}

@Composable
private fun CenterMessage(icon: ImageVector?, title: String, message: String?, showBar: Boolean = false, action: Pair<String, () -> Unit>? = null) {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        if (showBar) LoadingBar(modifier = Modifier.width(180.dp))
        if (icon != null) Icon(icon, null, tint = palette.textTertiary, modifier = Modifier.size(44.dp))
        Text(title, style = Type.headline, color = palette.textSecondary, modifier = Modifier.padding(top = 14.dp))
        if (message != null) Text(message, style = Type.subhead, color = palette.textTertiary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
        if (action != null) Text(action.first, style = Type.rounded(15.sp, FontWeight.SemiBold), color = VitalsColors.caloriesPrimary, modifier = Modifier.padding(top = 16.dp).tappable(action.first, onClick = action.second).padding(8.dp))
    }
}

@Composable
private fun AverageCard(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().clip(RoundedCornerShape(Geo.cardRadius)).background(palette.cardSurface).padding(Geo.cardPadding).semantics(mergeDescendants = true) { contentDescription = "$label $value" },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(label.uppercase(), style = Type.rounded(12.sp).copy(letterSpacing = 0.8.sp), color = palette.textSecondary, maxLines = 1)
        Text(value, style = Type.rounded(20.sp, FontWeight.Bold), color = color)
    }
}

@Composable
private fun ExcludedNote(count: Int) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(Icons.Filled.Block, null, tint = palette.textTertiary, modifier = Modifier.size(14.dp))
        Text("$count ${if (count == 1) "day" else "days"} excluded from these figures", style = Type.caption, color = palette.textTertiary)
    }
}

@Composable
private fun ChartCard(title: String, selection: Pair<String, String>?, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (selection != null) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(selection.first, style = Type.caption, color = palette.textSecondary)
                Text(selection.second, style = Type.rounded(20.sp, FontWeight.Bold), color = palette.textPrimary)
            }
        } else {
            Text(title, style = Type.headline, color = palette.textPrimary)
        }
        content()
    }
}

@Composable
private fun MonthlySummaryPrompt(onGenerate: () -> Unit) {
    Card {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Your monthly summary is ready", style = Type.rounded(15.sp, FontWeight.Bold), color = palette.textPrimary)
                Text("Generate a fresh 30-day PDF once a month, then preview or share it.", style = Type.caption, color = palette.textSecondary)
            }
            Text("Generate", style = Type.rounded(14.sp, FontWeight.Bold), color = Color.White, modifier = Modifier.clip(CircleShape).background(VitalsColors.caloriesPrimary).tappable("Generate monthly summary", onClick = onGenerate).padding(horizontal = 14.dp, vertical = 8.dp))
        }
    }
}

@Composable
internal fun DeepTrendsCard(isPro: Boolean, insights: List<DeepTrendInsight>, highlights: List<String>, periodLabel: String, graph: AppGraph) {
    val nav = LocalNav.current
    val store = graph.store
    LaunchedEffect(isPro) { if (!isPro) store.trackPaywallImpression("vitals_history_deep_trends", oncePerSession = true) }
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(if (isPro) Icons.Filled.ShowChart else Icons.Filled.Lock, null, tint = VitalsColors.stepsPrimary, modifier = Modifier.size(18.dp))
                Text("Deep Trends", style = Type.headline, color = palette.textPrimary)
                Spacer(Modifier.weight(1f))
                Text(if (isPro) "Active" else "Vitals+", style = Type.rounded(11.sp, FontWeight.Bold), color = if (isPro) VitalsColors.stepsPrimary else VitalsColors.caloriesPrimary)
            }
            Text(periodLabel, style = Type.caption, color = palette.textSecondary)
            if (isPro) {
                if (insights.isEmpty()) {
                    Text("Deep Trends need a previous matching range with calories or steps before they can compare your momentum.", style = Type.footnote, color = palette.textSecondary)
                } else {
                    insights.forEach { InsightRow(it, blur = false) }
                    highlights.forEach { line ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                            Icon(Icons.Filled.CheckCircle, null, tint = VitalsColors.stepsPrimary, modifier = Modifier.padding(top = 2.dp).size(14.dp))
                            Text(line, style = Type.footnote, color = palette.textSecondary)
                        }
                    }
                }
            } else {
                if (insights.isEmpty()) {
                    Text("This period compared to the last: averages, percent movement, and peak days.", style = Type.footnote, color = palette.textSecondary)
                } else insights.forEach { InsightRow(it, blur = true) }
                Text("Also in Vitals+: custom date ranges and PDF reports from this History tab.", style = Type.caption, color = palette.textTertiary)
                store.sheetDisclosure?.let { Text(it, style = Type.caption2, color = palette.textTertiary) }
                PrimaryButton(
                    ConversionCopy.shortCtaLabel(store.canPitchFreeTrial),
                    onClick = { nav.openPaywall(PlusFeature.DEEP_TRENDS) },
                    enabled = store.conversionCtaReady, loading = !store.conversionCtaReady,
                )
            }
        }
    }
}

@Composable
private fun InsightRow(insight: DeepTrendInsight, blur: Boolean) {
    val isCalories = insight.title == "Calories"
    val color = if (isCalories) VitalsColors.caloriesPrimary else VitalsColors.stepsPrimary
    val tint = if (insight.isFlat) palette.textSecondary else if (insight.isUp) VitalsColors.netDeficitPositive else VitalsColors.netDeficitNegative
    val blurModifier = if (blur) (if (Build.VERSION.SDK_INT >= 31) Modifier.blur(8.dp) else Modifier.alpha(0.12f)) else Modifier
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(color.copy(alpha = 0.08f)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.size(28.dp).clip(CircleShape).background(color.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
                Icon(if (isCalories) Icons.Filled.LocalFireDepartment else Icons.Filled.DirectionsWalk, null, tint = color, modifier = Modifier.size(16.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(insight.title, style = Type.rounded(15.sp, FontWeight.Bold), color = palette.textPrimary)
                Text(insight.narrative, style = Type.caption, color = palette.textSecondary)
            }
            Row(blurModifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(if (insight.isFlat) Icons.AutoMirrored.Filled.ArrowForward else if (insight.isUp) Icons.Filled.ArrowUpward else Icons.Filled.ArrowDownward, null, tint = tint, modifier = Modifier.size(14.dp))
                Text(insight.percent, style = Type.rounded(15.sp, FontWeight.Bold), color = tint)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MiniStat("Current", insight.current, Modifier.weight(1f))
            MiniStat("Previous", insight.previous, Modifier.weight(1f).then(blurModifier))
            MiniStat("Change", insight.change, Modifier.weight(1f).then(blurModifier))
        }
    }
}

@Composable
private fun MiniStat(label: String, value: String, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(label.uppercase(), style = Type.rounded(9.sp, FontWeight.Bold).copy(letterSpacing = 0.6.sp), color = palette.textTertiary)
        Text(value, style = Type.rounded(12.sp, FontWeight.Bold), color = palette.textPrimary, maxLines = 1)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecentDays(graph: AppGraph, days: List<DayStats>, excluded: Set<String>, isPro: Boolean) {
    val nav = LocalNav.current
    val settings = graph.settings
    val rows = days.filter { it.total > 0 || it.steps > 0 }.sortedByDescending { it.date }.take(14)
    val fmt = DateTimeFormatter.ofPattern("EEE, MMM d", Locale.getDefault())
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Recent Days", style = Type.headline, color = palette.textPrimary)
        if (rows.isEmpty()) Text("No recent activity to show.", style = Type.footnote, color = palette.textTertiary)
        rows.forEachIndexed { index, day ->
            val isExcluded = ExcludedDays.contains(day.date, excluded)
            var menu by remember { mutableStateOf(false) }
            val text = "${Format.number(day.total)} cal · ${Format.number(day.steps.toDouble())} steps"
            Box {
                Row(
                    Modifier.fillMaxWidth().alpha(if (isExcluded) 0.45f else 1f)
                        .combinedClickable(onClick = {}, onLongClick = { if (isPro) menu = true else nav.openPaywall(PlusFeature.EXCLUDED_DAYS) })
                        .semantics(mergeDescendants = true) { contentDescription = "${fmt.format(day.date)}: $text${if (isExcluded) ", excluded from averages" else ""}" }
                        .padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(fmt.format(day.date), style = Type.rounded(14.sp, FontWeight.Medium), color = palette.textPrimary)
                    if (isExcluded) Text("EXCLUDED", style = Type.rounded(9.sp, FontWeight.Bold).copy(letterSpacing = 0.5.sp), color = palette.textTertiary, modifier = Modifier.clip(CircleShape).background(palette.textTertiary.copy(alpha = 0.12f)).padding(horizontal = 6.dp, vertical = 2.dp))
                    Spacer(Modifier.weight(1f))
                    Text(text, style = Type.rounded(13.sp, FontWeight.SemiBold), color = palette.textSecondary, maxLines = 1)
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, containerColor = palette.cardSurface) {
                    DropdownMenuItem(
                        text = { Text(if (isExcluded) "Include in Averages" else "Exclude from Averages", style = Type.body, color = palette.textPrimary) },
                        onClick = { menu = false; settings.setExcluded(day.date, !isExcluded) },
                    )
                }
            }
            if (index < rows.lastIndex) Box(Modifier.fillMaxWidth().height(0.5.dp).background(palette.textTertiary.copy(alpha = 0.2f)))
        }
        if (rows.isNotEmpty()) Text(if (isPro) "Press and hold a day to leave it out of your averages." else "Vitals+ can leave a day out of your averages. Press and hold a day to try it.", style = Type.caption2, color = palette.textTertiary)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CustomRangeSheet(initialStart: LocalDate, initialEnd: LocalDate, today: LocalDate, onDismiss: () -> Unit, onApply: (LocalDate, LocalDate, Boolean) -> Unit) {
    fun millis(d: LocalDate) = d.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    fun toDate(ms: Long) = Instant.ofEpochMilli(ms).atZone(ZoneOffset.UTC).toLocalDate()
    val state = rememberDateRangePickerState(
        initialSelectedStartDateMillis = millis(initialStart), initialSelectedEndDateMillis = millis(initialEnd),
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                val date = toDate(utcTimeMillis)
                return !date.isAfter(today) && !date.isBefore(today.minusDays(HistoryCalculator.MAX_CUSTOM_DAYS.toLong()))
            }
        },
    )
    val s = state.selectedStartDateMillis?.let(::toDate)
    val e = state.selectedEndDateMillis?.let(::toDate)
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = palette.background) {
        Column(Modifier.padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Custom Range", style = Type.title3, color = palette.textPrimary, modifier = Modifier.padding(horizontal = 24.dp))
            DateRangePicker(state, modifier = Modifier.height(440.dp), title = null, headline = null, showModeToggle = false)
            Column(Modifier.padding(horizontal = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PrimaryButton("Apply", onClick = { if (s != null && e != null) onApply(s, e, false) }, enabled = s != null && e != null)
                Text(
                    "Apply and create PDF", style = Type.rounded(15.sp, FontWeight.SemiBold), color = if (s != null && e != null) VitalsColors.caloriesPrimary else palette.textTertiary,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().tappable("Apply and create PDF") { if (s != null && e != null) onApply(s, e, true) }.padding(10.dp),
                )
            }
        }
    }
}
