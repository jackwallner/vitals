package com.jackwallner.vitals.ui.screens

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.jackwallner.vitals.AppGraph
import com.jackwallner.vitals.data.HealthNotice
import com.jackwallner.vitals.data.HealthPermissions
import com.jackwallner.vitals.model.Format
import com.jackwallner.vitals.model.PacingComparison
import com.jackwallner.vitals.model.PacingLookback
import com.jackwallner.vitals.model.TodayCalculator
import com.jackwallner.vitals.model.TodayModel
import com.jackwallner.vitals.model.TodayParams
import com.jackwallner.vitals.ui.LocalNav
import com.jackwallner.vitals.ui.Overlay
import com.jackwallner.vitals.ui.Tab
import com.jackwallner.vitals.ui.openHealthConnectSettings
import com.jackwallner.vitals.ui.openHealthConnectStore
import com.jackwallner.vitals.ui.theme.Card
import com.jackwallner.vitals.ui.theme.Geo
import com.jackwallner.vitals.ui.theme.LoadingBar
import com.jackwallner.vitals.ui.theme.MetricPill
import com.jackwallner.vitals.ui.theme.ProgressRing
import com.jackwallner.vitals.ui.theme.StepProgressBar
import com.jackwallner.vitals.ui.theme.StreakBadge
import com.jackwallner.vitals.ui.theme.TintPill
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.VitalsColors
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/** Resumes refresh Today whenever the app comes to the foreground, like iOS's scene-phase reload. */
@Composable
fun RefreshOnResume(graph: AppGraph) {
    val owner = LocalLifecycleOwner.current
    LaunchedEffect(owner) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            if (graph.settings.hasCompletedSetup) {
                graph.repo.refresh(wantsFood = graph.store.isPro && graph.settings.showNet)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodayScreen(graph: AppGraph, onCelebrate: (String) -> Unit) {
    val settings = graph.settings
    val repo = graph.repo
    val isPro = graph.store.isPro
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val view = LocalView.current
    RefreshOnResume(graph)

    val params = TodayParams(
        pacingComparison = settings.pacingComparison,
        pacingLookback = settings.pacingLookback,
        showPacing = settings.showPacing,
        showCalories = settings.showCalories,
        showSteps = settings.showSteps,
        isPro = isPro,
        showProjections = settings.showProjections,
        showStreaks = settings.showStreaks,
        calorieGoal = settings.calorieGoal,
        stepGoal = settings.stepGoal,
        excludedKeys = settings.excludedKeys(repo.now().toLocalDate()),
    )
    val model = remember(repo.window, repo.lastRefresh, params) { TodayCalculator.compute(repo.window, repo.now(), params) }

    // One celebration per goal per day, paired with a haptic and the review funnel's positive moment.
    LaunchedEffect(model.day.total, model.day.steps, repo.lastRefresh) {
        if (!repo.hasLoaded || repo.notice != null) return@LaunchedEffect
        val message = graph.celebration.check(model.day.total, settings.calorieGoal, model.day.steps, settings.stepGoal) ?: return@LaunchedEffect
        graph.review.recordPositiveMoment()
        view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.LONG_PRESS)
        onCelebrate(message)
    }

    fun refresh() = scope.launch { repo.refresh(wantsFood = isPro && settings.showNet) }

    PullToRefreshBox(isRefreshing = repo.isRefreshing && repo.hasLoaded, onRefresh = { refresh() }, modifier = Modifier.fillMaxSize().background(palette.background)) {
        BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding()) {
            val h = maxHeight.value
            val isNet = isPro && settings.showNet
            val metrics = (if (settings.showCalories) 1 else 0) + (if (settings.showSteps) 1 else 0) + (if (isNet) 1 else 0)
            val single = metrics == 1
            val minimal = settings.calorieGoal == null && settings.stepGoal == null && !settings.showPacing
            val onlyNet = isNet && !settings.showCalories && !settings.showSteps
            val calSize = when {
                single && settings.showCalories && !settings.showSteps && !isNet -> min(h * 0.12f, 100f)
                minimal -> min(h * 0.10f, 88f)
                else -> min(h * 0.06f, 52f)
            }
            val stepSize = when {
                single && settings.showSteps && !settings.showCalories && !isNet -> min(h * 0.12f, 100f)
                minimal -> min(h * 0.08f, 68f)
                else -> min(h * 0.048f, 42f)
            }
            val netSize = when {
                onlyNet -> min(h * 0.12f, 100f)
                minimal -> min(h * 0.08f, 68f)
                else -> min(h * 0.048f, 42f)
            }
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).heightIn(min = maxHeight),
                verticalArrangement = Arrangement.SpaceBetween,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(Modifier.fillMaxWidth()) {
                    Header(graph, onSettings = { nav.push(Overlay.Settings) })
                    repo.notice?.let { notice ->
                        Spacer(Modifier.height(8.dp))
                        NoticeBanner(notice, onAction = { handleNotice(graph, notice, scope, context, ::refresh) })
                    }
                }
                Spacer(Modifier.height(16.dp))
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (settings.showCalories) {
                        CalorieSection(graph, model, isPro, minimal, calSize, h, onOpen = { nav.select(Tab.HISTORY) })
                    }
                    if (settings.showCalories && settings.showSteps) Spacer(Modifier.height(24.dp))
                    if (settings.showSteps) {
                        StepsSection(graph, model, isPro, minimal || (single && !settings.showCalories), stepSize, single, onOpen = { nav.select(Tab.HISTORY) })
                    }
                    if (isNet && (settings.showCalories || settings.showSteps)) Spacer(Modifier.height(24.dp))
                    if (isNet) NetSection(graph, model, onlyNet, netSize, onOpen = { nav.select(Tab.HISTORY) }, onRetry = {
                        scope.launch {
                            graph.permissions.request(HealthPermissions.core(includeFood = true))
                            refresh()
                        }
                    }, onPermissions = { context.openHealthConnectSettings() })
                    if (!settings.showCalories && !settings.showSteps && !isNet) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(Icons.Filled.FavoriteBorder, null, tint = palette.textTertiary, modifier = Modifier.size(48.dp))
                            Text("No metrics selected", style = Type.headline, color = palette.textSecondary)
                            Text("Open Settings", style = Type.rounded(15.sp, FontWeight.Medium), color = VitalsColors.caloriesPrimary, modifier = Modifier.tappable { nav.push(Overlay.Settings) })
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

private fun handleNotice(graph: AppGraph, notice: HealthNotice, scope: kotlinx.coroutines.CoroutineScope, context: android.content.Context, refresh: () -> Unit) {
    when (notice) {
        HealthNotice.UNAVAILABLE -> context.openHealthConnectStore()
        HealthNotice.ACCESS_NEEDED -> scope.launch {
            graph.permissions.request(HealthPermissions.core(includeFood = graph.store.isPro && graph.settings.showNet))
            graph.repo.markPermissionAsked()
            refresh()
        }
        else -> context.openHealthConnectSettings()
    }
}

@Composable
private fun Header(graph: AppGraph, onSettings: () -> Unit) {
    val repo = graph.repo
    val now = repo.now()
    val title = DateTimeFormatter.ofPattern("EEEE, MMMM d", androidx.compose.ui.platform.LocalConfiguration.current.locales[0]).format(now)
    Column(Modifier.padding(horizontal = Geo.gutter).padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = Type.title3, color = palette.textPrimary, modifier = Modifier.weight(1f))
            Box(
                Modifier.size(40.dp).clip(CircleShape).background(palette.cardSurface).tappable("Settings", onClick = onSettings),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.Settings, null, tint = palette.textSecondary, modifier = Modifier.size(20.dp)) }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.height(16.dp)) {
            val notice = repo.notice
            when {
                notice == HealthNotice.ACCESS_NEEDED || notice == HealthNotice.ACCESS_BLOCKED ->
                    Text("Waiting for Health access", style = Type.caption2, color = palette.textTertiary)
                repo.isRefreshing -> {
                    LoadingBar(modifier = Modifier.width(80.dp))
                    Text("Refreshing…", style = Type.caption2, color = palette.textTertiary)
                }
                repo.lastRefresh != null -> {
                    val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).format(repo.lastRefresh)
                    Text("Updated $time", style = Type.caption2, color = palette.textTertiary)
                }
            }
        }
    }
}

@Composable
private fun NoticeBanner(notice: HealthNotice, onAction: () -> Unit) {
    Row(
        Modifier
            .padding(horizontal = Geo.gutter)
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(VitalsColors.caloriesPrimary.copy(alpha = 0.85f))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(if (notice == HealthNotice.LOAD_ERROR) Icons.Filled.ErrorOutline else Icons.Filled.FavoriteBorder, null, tint = Color.White.copy(alpha = 0.95f), modifier = Modifier.padding(top = 2.dp).size(18.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(notice.title, style = Type.rounded(12.sp, FontWeight.SemiBold), color = Color.White)
            Text(notice.message, style = Type.caption2, color = Color.White.copy(alpha = 0.92f))
        }
        notice.button?.let { label ->
            Text(
                label,
                style = Type.rounded(12.sp, FontWeight.SemiBold),
                color = Color.White,
                textAlign = TextAlign.Center,
                modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.2f)).tappable(label, onClick = onAction).padding(horizontal = 10.dp, vertical = 6.dp),
            )
        }
    }
}

@Composable
private fun CalorieSection(graph: AppGraph, model: TodayModel, isPro: Boolean, minimal: Boolean, numberSize: Float, h: Float, onOpen: () -> Unit) {
    val settings = graph.settings
    val goal = settings.calorieGoal
    val progress = goal?.takeIf { it > 0 }?.let { (model.total / it).toFloat() }
    val ringSize = min(h * 0.32f, 260f)
    val line = min(h * 0.022f, 18f)
    val single = !settings.showSteps && !(isPro && settings.showNet)
    val showIcon = goal == null && !settings.showPacing
    val a11y = buildString {
        append("${model.total.roundToInt()} ${if (goal != null) "of ${goal.roundToInt()} " else ""}calories")
        if (isPro && settings.showActiveResting && model.day.active != null) append(". Active ${model.day.active.roundToInt()}, resting ${(model.day.resting ?: 0.0).roundToInt()}.")
        if (settings.showStreaks && model.calorieStreak > 0) append(" ${model.calorieStreak} day goal streak.")
    }
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.tappable("Calorie progress. Opens calorie history", onClick = onOpen).semantics { contentDescription = a11y },
            contentAlignment = Alignment.Center,
        ) {
            if (progress != null) {
                ProgressRing(progress, ringSize.dp, line.dp)
            }
            CalorieLabel(model, goal, numberSize, showIcon, single, settings.showStreaks && model.calorieStreak > 0)
        }
        val showSplit = isPro && settings.showActiveResting && !minimal && model.day.active != null && model.day.resting != null
        if (showSplit) {
            Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                MetricPill("active", model.day.active ?: 0.0, VitalsColors.activePrimary)
                MetricPill(if (model.day.restingIsEstimated) "resting est." else "resting", model.day.resting ?: 0.0, VitalsColors.restingPrimary)
            }
        }
        CalorieInsights(graph, model)
        EnergyAveragesRow(graph, model, isPro, minimal)
    }
}

@Composable
private fun CalorieLabel(model: TodayModel, goal: Double?, numberSize: Float, showIcon: Boolean, single: Boolean, streak: Boolean) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (showIcon) Icon(Icons.Filled.LocalFireDepartment, null, tint = VitalsColors.caloriesPrimary, modifier = Modifier.size(if (single) 34.dp else 24.dp))
            Text(Format.number(model.total), style = Type.bigNumber(numberSize.sp), color = palette.textPrimary, maxLines = 1)
        }
        if (goal != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("/ ${Format.number(goal)} cal", style = Type.caption, color = palette.textSecondary)
                Icon(Icons.Filled.ChevronRight, null, tint = palette.textTertiary, modifier = Modifier.size(14.dp))
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("CALORIES", style = Type.rounded(if (single) 20.sp else 15.sp).copy(letterSpacing = 1.5.sp), color = palette.textSecondary)
                Icon(Icons.Filled.ChevronRight, null, tint = palette.textTertiary, modifier = Modifier.size(16.dp))
            }
        }
        if (streak) Box(Modifier.padding(top = 6.dp)) { StreakBadge(model.calorieStreak, "calorie") }
    }
}

@Composable
private fun CalorieInsights(graph: AppGraph, model: TodayModel) {
    val settings = graph.settings
    val hasPill = model.calorieTypical != null || model.projectedCalories != null
    val building = settings.showPacing && model.calorieBuildingSamples != null && model.calorieTypical == null
    if (!hasPill && !building) return
    Box(Modifier.padding(top = 16.dp)) {
        if (hasPill) {
            PacingPill(model.total, model.calorieTypical, model.projectedCalories, "cal", VitalsColors.caloriesPrimary, settings.pacingComparison, settings.pacingLookback)
        } else {
            Text(buildingText(model.calorieBuildingSamples ?: 0, model.minPacingSamples), style = Type.caption2, color = palette.textTertiary)
        }
    }
}

private fun buildingText(samples: Int, min: Int) = "Building pace data: $samples/$min ${if (min == 1) "day" else "days"}"

@Composable
private fun EnergyAveragesRow(graph: AppGraph, model: TodayModel, isPro: Boolean, minimal: Boolean) {
    if (!(isPro && graph.settings.showEnergyAverages && graph.settings.showCalories && !minimal)) return
    val tdee = model.averages.tdee
    val bmr = model.averages.bmr
    Column(Modifier.padding(top = 14.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (tdee != null && bmr != null) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.semantics { contentDescription = "Maintenance calories ${tdee.roundToInt()} TDEE, resting ${bmr.roundToInt()} BMR, 30-day average." },
            ) {
                MetricPill("TDEE", tdee, VitalsColors.activePrimary)
                MetricPill("BMR", bmr, VitalsColors.restingPrimary)
            }
            Text("Maintenance · 30-day avg from Health Connect", style = Type.caption2, color = palette.textTertiary)
        } else {
            Text("TDEE & BMR estimate building: ${model.averages.sampleDays}/7 days", style = Type.caption, color = palette.textSecondary)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PacingPill(
    current: Double,
    typical: Double?,
    projected: Double?,
    label: String,
    color: Color,
    comparison: PacingComparison,
    lookback: PacingLookback,
) {
    var showExplainer by remember { mutableStateOf(false) }
    val diff = typical?.let { current - it }
    val tint = if (diff == null) color else if (diff >= 0) VitalsColors.ahead else VitalsColors.caloriesPrimary
    val parts = buildList {
        if (diff != null) add("${Format.number(abs(diff))} $label ${if (diff >= 0) "ahead of" else "behind"} usual pace")
        if (projected != null) add("on pace for ${Format.number(projected)} $label")
    }
    val message = parts.joinToString(", ")
    val leading = when {
        diff == null -> Icons.AutoMirrored.Filled.TrendingUp
        diff >= 0 -> Icons.Filled.ArrowUpward
        else -> Icons.Filled.ArrowDownward
    }
    TintPill(
        message, tint, leading = leading, trailing = if (typical != null) Icons.Filled.Info else null,
        modifier = if (typical != null) Modifier.tappable(message) { showExplainer = true } else Modifier.semantics { contentDescription = message },
    )
    if (showExplainer && typical != null) {
        ModalBottomSheet(onDismissRequest = { showExplainer = false }, containerColor = palette.background) {
            PacingExplainer(typical, label, comparison, lookback)
        }
    }
}

@Composable
private fun PacingExplainer(typical: Double, label: String, comparison: PacingComparison, lookback: PacingLookback) {
    val window = lookback.label.lowercase()
    val basis = when (comparison) {
        PacingComparison.DAY_OF_WEEK -> {
            val weekday = java.time.LocalDate.now().dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, androidx.compose.ui.platform.LocalConfiguration.current.locales[0])
            "your average on past ${weekday}s over the last $window"
        }
        PacingComparison.ALL_DAYS -> "your average on every day over the last $window"
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(Icons.Filled.Speed, null, tint = VitalsColors.caloriesPrimary, modifier = Modifier.size(40.dp))
        Text("How pace works", style = Type.title3, color = palette.textPrimary)
        Text("“Usual pace” compares your $label so far today to $basis, measured at this same time of day.", style = Type.subhead, color = palette.textSecondary, textAlign = TextAlign.Center)
        Text("Usual by now: ${Format.number(typical)} $label", style = Type.rounded(15.sp, FontWeight.SemiBold), color = palette.textPrimary, modifier = Modifier.clip(CircleShape).background(palette.cardSurface).padding(horizontal = 14.dp, vertical = 8.dp))
        Text("Empty days don’t count. You can change the comparison window in Settings.", style = Type.footnote, color = palette.textTertiary, textAlign = TextAlign.Center)
    }
}

@Composable
private fun StepsSection(graph: AppGraph, model: TodayModel, isPro: Boolean, centered: Boolean, numberSize: Float, single: Boolean, onOpen: () -> Unit) {
    val settings = graph.settings
    val goal = settings.stepGoal
    val progress = goal?.takeIf { it > 0 }?.let { (model.steps.toFloat() / it) }
    val streak = settings.showStreaks && isPro && model.stepStreak > 0
    val a11y = "${model.steps} steps" + if (streak) ". ${model.stepStreak} day goal streak." else ""
    val pill: @Composable () -> Unit = {
        if (model.stepTypical != null || model.projectedSteps != null) {
            PacingPill(model.steps.toDouble(), model.stepTypical, model.projectedSteps, "steps", VitalsColors.stepsPrimary, settings.pacingComparison, settings.pacingLookback)
        } else if (settings.showPacing && model.stepBuildingSamples != null) {
            Text(buildingText(model.stepBuildingSamples, model.minPacingSamples), style = Type.caption2, color = palette.textTertiary)
        }
    }
    if (centered) {
        Column(
            Modifier.tappable("Steps. Opens step history", onClick = onOpen).semantics { contentDescription = a11y },
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Filled.DirectionsWalk, null, tint = VitalsColors.stepsPrimary, modifier = Modifier.size(if (single) 34.dp else 28.dp))
                Text(Format.number(model.steps.toDouble()), style = Type.bigNumber(numberSize.sp), color = palette.textPrimary, maxLines = 1)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("STEPS", style = Type.rounded(if (single) 20.sp else 15.sp).copy(letterSpacing = 1.5.sp), color = palette.textSecondary)
                Icon(Icons.Filled.ChevronRight, null, tint = palette.textTertiary, modifier = Modifier.size(16.dp))
            }
            if (streak) Box(Modifier.padding(top = 4.dp)) { StreakBadge(model.stepStreak, "step") }
            Box(Modifier.padding(top = 8.dp)) { pill() }
        }
    } else {
        Card(Modifier.padding(horizontal = Geo.gutter).tappable("Steps. Opens step history", onClick = onOpen).semantics { contentDescription = a11y }) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.DirectionsWalk, null, tint = VitalsColors.stepsPrimary, modifier = Modifier.size(24.dp))
                    Text(Format.number(model.steps.toDouble()), style = Type.bigNumber(numberSize.sp), color = palette.textPrimary, maxLines = 1)
                    if (goal != null) Text("/ ${Format.number(goal.toDouble())}", style = Type.caption, color = palette.textSecondary)
                    else Text("STEPS", style = Type.rounded(15.sp).copy(letterSpacing = 1.5.sp), color = palette.textSecondary)
                    Spacer(Modifier.weight(1f))
                    if (streak) StreakBadge(model.stepStreak, "step", compact = true)
                    Icon(Icons.Filled.ChevronRight, null, tint = palette.textTertiary, modifier = Modifier.size(16.dp))
                }
                if (progress != null) StepProgressBar(progress)
                pill()
            }
        }
    }
}

@Composable
private fun NetSection(graph: AppGraph, model: TodayModel, only: Boolean, numberSize: Float, onOpen: () -> Unit, onRetry: () -> Unit, onPermissions: () -> Unit) {
    val repo = graph.repo
    val net = model.total - repo.foodToday
    val ready = repo.foodReady && !repo.foodFailed
    val tint = if (net >= 0) VitalsColors.netDeficitPositive else VitalsColors.netDeficitNegative
    val word = if (net >= 0) "deficit" else "surplus"
    val numeric = if (ready) { val r = net.roundToInt(); if (r > 0) "+$r" else "$r" } else "—"
    val a11y = when {
        repo.foodFailed -> "Net calories. Food data unavailable"
        !repo.foodReady -> "Net calories. Waiting for Health permission or loading food data"
        else -> "Net calories. ${net.roundToInt()} calories, $word, burned minus food from Health Connect"
    }
    val body: @Composable () -> Unit = {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (only) {
                Text(numeric, style = Type.bigNumber(numberSize.sp), color = if (ready) tint else palette.textTertiary)
                if (ready) Text(word.uppercase(), style = Type.rounded(15.sp, FontWeight.SemiBold).copy(letterSpacing = 1.5.sp), color = tint)
            } else {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(numeric, style = Type.bigNumber(numberSize.sp), color = if (ready) tint else palette.textTertiary)
                    Text(if (ready) word else "net", style = Type.rounded(16.sp, FontWeight.Medium), color = if (ready) tint else palette.textTertiary, modifier = Modifier.padding(bottom = 6.dp))
                    Spacer(Modifier.weight(1f))
                    Icon(Icons.Filled.ChevronRight, null, tint = palette.textTertiary, modifier = Modifier.size(16.dp).padding(bottom = 0.dp))
                }
            }
            if (ready) {
                TintPill("${Format.number(model.total)} burned − ${Format.number(repo.foodToday)} eaten", tint, leading = if (net >= 0) Icons.Filled.ArrowUpward else Icons.Filled.ArrowDownward)
            }
            if (only) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("NET CALORIES", style = Type.rounded(15.sp).copy(letterSpacing = 1.5.sp), color = palette.textSecondary)
                    Icon(Icons.Filled.ChevronRight, null, tint = palette.textTertiary, modifier = Modifier.size(16.dp))
                }
            }
            NetFootnote(graph, ready, onRetry, onPermissions)
        }
    }
    val modifier = Modifier.tappable("Net calories. Opens net deficit history", onClick = onOpen).semantics { contentDescription = a11y }
    if (only) Box(modifier) { body() }
    else Card(Modifier.padding(horizontal = Geo.gutter).then(modifier)) { Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { body() } }
}

@Composable
private fun NetFootnote(graph: AppGraph, ready: Boolean, onRetry: () -> Unit, onPermissions: () -> Unit) {
    val repo = graph.repo
    when {
        repo.foodFailed -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Couldn't read food calories. Check Health permissions.", style = Type.caption2, color = palette.textTertiary, textAlign = TextAlign.Center)
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Retry food calories", style = Type.rounded(11.sp, FontWeight.SemiBold), color = VitalsColors.caloriesPrimary, modifier = Modifier.tappable(onClick = onRetry))
                Text("Health permissions", style = Type.rounded(11.sp, FontWeight.SemiBold), color = VitalsColors.caloriesPrimary, modifier = Modifier.tappable(onClick = onPermissions))
            }
        }
        ready && repo.foodToday <= 0 ->
            Text("No food calories logged in Health Connect today.", style = Type.caption2, color = palette.textTertiary, textAlign = TextAlign.Center)
    }
}
