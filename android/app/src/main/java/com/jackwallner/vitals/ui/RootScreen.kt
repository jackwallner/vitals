package com.jackwallner.vitals.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.AppGraph
import com.jackwallner.vitals.DebugLaunchOptions
import com.jackwallner.vitals.ui.screens.ExcludedDaysScreen
import com.jackwallner.vitals.ui.screens.HistoryScreen
import com.jackwallner.vitals.ui.screens.OnboardingScreen
import com.jackwallner.vitals.ui.screens.PaywallScreen
import com.jackwallner.vitals.ui.screens.ProScreen
import com.jackwallner.vitals.ui.screens.ReportPreviewScreen
import com.jackwallner.vitals.ui.screens.SettingsScreen
import com.jackwallner.vitals.ui.screens.TodayScreen
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.VitalsColors
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

val LocalGraph = staticCompositionLocalOf<AppGraph> { error("No AppGraph provided") }
val LocalNav = staticCompositionLocalOf<Navigator> { error("No Navigator provided") }

/** Full-screen destinations raised over the tabs. */
sealed interface Overlay {
    data object Settings : Overlay
    data object ExcludedDays : Overlay
    data class Paywall(val focus: PlusFeature?) : Overlay
    data class Report(val title: String, val file: File, val shareText: String) : Overlay
}

enum class Tab(val label: String) { TODAY("Today"), HISTORY("History"), UPGRADE("Upgrade") }

class Navigator {
    val stack = mutableStateListOf<Overlay>()
    var tab by mutableStateOf(Tab.TODAY)

    fun push(overlay: Overlay) { stack.add(overlay) }
    fun pop() { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }
    fun openPaywall(focus: PlusFeature? = null) = push(Overlay.Paywall(focus))
    fun select(tab: Tab) { this.tab = tab; stack.clear() }
}

/** Onboarding until setup completes, then the tab host. A branch, never a cover, so Today never flashes behind it. */
@Composable
fun RootScreen(graph: AppGraph) {
    val nav = remember { Navigator() }
    val done = graph.settings.hasCompletedSetup
    androidx.compose.runtime.CompositionLocalProvider(LocalNav provides nav) {
        AnimatedContent(done, transitionSpec = { fadeIn(tween(350)) togetherWith fadeOut(tween(350)) }, label = "root") { complete ->
            if (complete) MainShell(graph, nav) else OnboardingScreen(graph)
        }
    }
}

@Composable
private fun MainShell(graph: AppGraph, nav: Navigator) {
    val settings = graph.settings
    val store = graph.store
    var celebration by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        DebugLaunchOptions.tab?.let { name -> Tab.entries.firstOrNull { it.name.equals(name, true) }?.let { nav.tab = it } }
        when (DebugLaunchOptions.overlay) {
            "settings" -> nav.push(Overlay.Settings)
            "excluded" -> nav.push(Overlay.ExcludedDays)
            "paywall" -> nav.push(Overlay.Paywall(null))
        }
    }
    // A lapsed subscriber's Pro-only switches go back off, like iOS.
    LaunchedEffect(store.isPro) {
        if (!store.isPro) settings.switchOffProFeatures()
        graph.review.recordProStatus(store.isPro)
    }

    BackHandler(enabled = nav.stack.isNotEmpty()) { nav.pop() }

    Box(Modifier.fillMaxSize().background(palette.background)) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) {
                when (nav.tab) {
                    Tab.TODAY -> TodayScreen(graph, onCelebrate = { celebration = it })
                    Tab.HISTORY -> HistoryScreen(graph)
                    Tab.UPGRADE -> if (store.isPro) ProScreen(graph) else PaywallScreen(graph, focus = null, onClose = null)
                }
            }
            PausedBanner(graph)
            TabBar(nav, store.isPro)
        }
        celebration?.let { message ->
            LaunchedEffect(message) { delay(2_500); celebration = null }
            CelebrationBanner(message, Modifier.align(Alignment.TopCenter))
        }
        OverlayHost(graph, nav)
    }
    ReviewHost(graph, celebration)
}

@Composable
private fun OverlayHost(graph: AppGraph, nav: Navigator) {
    val top = nav.stack.lastOrNull()
    AnimatedVisibility(
        visible = top != null,
        enter = slideInVertically(tween(260)) { it / 6 } + fadeIn(tween(220)),
        exit = slideOutVertically(tween(200)) { it / 6 } + fadeOut(tween(160)),
    ) {
        Box(Modifier.fillMaxSize().background(palette.background)) {
            when (val overlay = top ?: return@Box) {
                Overlay.Settings -> SettingsScreen(graph, onClose = nav::pop)
                Overlay.ExcludedDays -> ExcludedDaysScreen(graph, onClose = nav::pop)
                is Overlay.Paywall -> PaywallScreen(graph, overlay.focus, onClose = nav::pop)
                is Overlay.Report -> ReportPreviewScreen(overlay.title, overlay.file, overlay.shareText, onClose = nav::pop)
            }
        }
    }
}

/** Asks for a Play review after a positive moment, with no question first and never from a button. */
@Composable
private fun ReviewHost(graph: AppGraph, celebration: String?) {
    val context = LocalContext.current
    LaunchedEffect(celebration, graph.repo.hasLoaded) {
        if (!graph.repo.hasLoaded) return@LaunchedEffect
        delay(if (celebration != null) 3_200 else 1_500)
        if (graph.review.shouldShowAfterPositiveMoment(graph.settings.hasCompletedSetup)) {
            graph.review.markShown()
            context.launchPlayReview()
        }
    }
}

@Composable
private fun CelebrationBanner(message: String, modifier: Modifier = Modifier) {
    Row(
        modifier
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(top = 8.dp)
            .shadow(8.dp, CircleShape, ambientColor = VitalsColors.caloriesPrimary, spotColor = VitalsColors.caloriesPrimary)
            .clip(CircleShape)
            .background(com.jackwallner.vitals.ui.theme.Gradients.calories)
            .padding(horizontal = 18.dp, vertical = 12.dp)
            .semantics { contentDescription = message },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.LocalFireDepartment, null, tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.size(18.dp))
        Text(message, style = Type.rounded(15.sp, FontWeight.Bold), color = androidx.compose.ui.graphics.Color.White)
    }
}

@Composable
private fun PausedBanner(graph: AppGraph) {
    val settings = graph.settings
    val since = settings.pausedSince
    val nav = LocalNav.current
    if (!graph.store.isPro || since == null) return
    val today = LocalDate.now()
    val days = com.jackwallner.vitals.model.ExcludedDays.pausedKeys(since, today).size
    val label = DateTimeFormatter.ofPattern("MMM d").format(since)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 6.dp)
            .clip(CircleShape)
            .background(palette.cardSurface)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .weight(1f)
                .tappable("Averages paused since $label") { nav.push(Overlay.ExcludedDays) },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Filled.PauseCircle, null, tint = VitalsColors.caloriesPrimary, modifier = Modifier.size(20.dp))
            Column(Modifier.weight(1f)) {
                Text("Averages paused", style = Type.rounded(13.sp, FontWeight.SemiBold), color = palette.textPrimary)
                Text("Since $label · $days ${if (days == 1) "day" else "days"} excluded", style = Type.caption2, color = palette.textSecondary)
            }
            Icon(Icons.Filled.ChevronRight, null, tint = palette.textTertiary, modifier = Modifier.size(18.dp))
        }
        Text(
            "Resume",
            style = Type.rounded(13.sp, FontWeight.Bold),
            color = VitalsColors.caloriesPrimary,
            modifier = Modifier.padding(start = 8.dp).tappable("Resume averages") { settings.resumeAverages(today) },
        )
    }
}

@Composable
private fun TabBar(nav: Navigator, isPro: Boolean) {
    Column(Modifier.fillMaxWidth().background(palette.background)) {
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(palette.textTertiary.copy(alpha = 0.4f)))
        Row(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars).height(56.dp)) {
            Tab.entries.forEach { tab ->
                val selected = nav.tab == tab
                val tint = if (selected) VitalsColors.caloriesPrimary else palette.textSecondary
                val icon: ImageVector = when (tab) {
                    Tab.TODAY -> Icons.Filled.LocalFireDepartment
                    Tab.HISTORY -> Icons.Filled.BarChart
                    Tab.UPGRADE -> Icons.Filled.AutoAwesome
                }
                val label = if (tab == Tab.UPGRADE && isPro) "Vitals+" else tab.label
                Column(
                    Modifier.weight(1f).fillMaxSize().tappable(label) { nav.select(tab) }.semantics { contentDescription = "$label tab" },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(icon, null, tint = tint, modifier = Modifier.size(24.dp))
                    Text(label, style = Type.rounded(11.sp, if (selected) FontWeight.SemiBold else FontWeight.Medium), color = tint)
                }
            }
        }
    }
}
