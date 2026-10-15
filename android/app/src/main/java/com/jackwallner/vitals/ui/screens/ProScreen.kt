package com.jackwallner.vitals.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.PlusOne
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.AppGraph
import com.jackwallner.vitals.data.HealthPermissions
import com.jackwallner.vitals.model.DayStats
import com.jackwallner.vitals.model.DeepTrends
import com.jackwallner.vitals.model.ExcludedDays
import com.jackwallner.vitals.model.Format
import com.jackwallner.vitals.model.HistoryCalculator
import com.jackwallner.vitals.ui.Links
import com.jackwallner.vitals.ui.LocalNav
import com.jackwallner.vitals.ui.Overlay
import com.jackwallner.vitals.ui.ReportResult
import com.jackwallner.vitals.ui.buildReport
import com.jackwallner.vitals.ui.openUrl
import com.jackwallner.vitals.ui.theme.Card
import com.jackwallner.vitals.ui.theme.Geo
import com.jackwallner.vitals.ui.theme.Gradients
import com.jackwallner.vitals.ui.theme.LoadingBar
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.VitalsColors
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable
import java.time.LocalDate
import kotlinx.coroutines.launch

/** The Upgrade tab for a subscriber: the Vitals+ tools in one place, plus account actions. */
@Composable
fun ProScreen(graph: AppGraph) {
    val nav = LocalNav.current
    val settings = graph.settings
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val today = LocalDate.now()
    var generating by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var restoring by remember { mutableStateOf(false) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }
    var showRange by remember { mutableStateOf(false) }
    var current by remember { mutableStateOf<List<DayStats>?>(null) }
    var previous by remember { mutableStateOf<List<DayStats>>(emptyList()) }
    val excluded = settings.excludedKeys(today)

    LaunchedEffect(graph.repo.lastRefresh) {
        runCatching {
            val start = today.minusDays(29)
            current = graph.repo.stats(start, today)
            val (ps, pe) = HistoryCalculator.previousRange(start, today)
            previous = graph.repo.stats(ps, pe)
        }.onFailure { if (current == null) current = emptyList() }
    }

    fun report(title: String, from: LocalDate, to: LocalDate) {
        if (generating) return
        generating = true
        scope.launch {
            when (val result = buildReport(graph, context, title, from, to)) {
                is ReportResult.Ready -> nav.push(Overlay.Report(result.title, result.file, result.shareText))
                is ReportResult.Failed -> error = result.message
            }
            generating = false
        }
    }

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding()) {
        if (generating) Row(Modifier.fillMaxWidth().padding(horizontal = Geo.gutter, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            LoadingBar(modifier = Modifier.size(width = 70.dp, height = 4.dp))
            Text("Generating report…", style = Type.footnote, color = palette.textSecondary)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Geo.gutter).padding(top = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(44.dp).clip(CircleShape).background(Gradients.calories), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.AutoAwesome, null, tint = Color.White, modifier = Modifier.size(22.dp))
                }
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Vitals+ Active", style = Type.title3, color = palette.textPrimary)
                    Text("Premium tools are ready to use.", style = Type.footnote, color = palette.textSecondary)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ActionRow(Icons.Filled.PlusOne, "Net Deficit", "Burn minus Health Connect food on Today + History.", if (settings.showNet) "On" else "Enable", settings.showNet) {
                    scope.launch {
                        if (!settings.showNet) {
                            graph.permissions.request(HealthPermissions.core(includeFood = true))
                            settings.showNet = true
                            graph.repo.refresh(true)
                        }
                    }
                }
                ActionRow(Icons.Filled.Description, "Monthly Summary PDF", "Generate a 30-day report and preview before sharing.", "Generate") { report("30-Day Summary", today.minusDays(29), today) }
                ActionRow(Icons.Filled.CalendarMonth, "Custom-Range Reports", "Pick an exact range and review the PDF in-app.", "Choose Dates") { showRange = true }
                ActionRow(Icons.Filled.Block, "Excluded Days", "Leave sick days and days off the wrist out of your averages.", "Open") { nav.push(Overlay.ExcludedDays) }
            }
            val days = current
            val counted = days.orEmpty().filter { !ExcludedDays.contains(it.date, excluded) }
            DeepTrendsCard(
                true, DeepTrends.insights(counted, previous.filter { !ExcludedDays.contains(it.date, excluded) }),
                DeepTrends.highlights(counted) { Format.shortDate(it) }, "vs. previous 30 days", graph,
            )
            val excludedCount = days.orEmpty().size - counted.size
            if (days != null && excludedCount > 0) Text("$excludedCount ${if (excludedCount == 1) "day" else "days"} excluded from these figures", style = Type.caption, color = palette.textTertiary)

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Account", style = Type.headline, color = palette.textPrimary)
                AccountRow(Icons.Filled.Refresh, if (restoring) "Restoring…" else "Restore Purchases", "Refresh your access after changing devices or reinstalling.") {
                    if (restoring) return@AccountRow
                    restoring = true
                    scope.launch {
                        graph.store.restorePurchases()
                        restoring = false
                        restoreMessage = if (graph.store.isPro) "Your Vitals+ access is active." else graph.store.lastError ?: "Couldn't refresh your subscription. Try again."
                    }
                }
                AccountRow(Icons.Filled.ChevronRight, "Manage Subscription", "Change or cancel in Google Play under Payments & subscriptions.") {
                    context.openUrl("${Links.MANAGE_SUBSCRIPTIONS}?package=${Links.PACKAGE}")
                }
            }
        }
    }
    if (showRange) {
        CustomRangeSheet(today.minusDays(29), today, today, onDismiss = { showRange = false }, onApply = { s, e, _ -> showRange = false; report("Custom Summary", s, e) })
    }
    error?.let { message ->
        AlertDialog(
            onDismissRequest = { error = null }, containerColor = palette.cardSurface,
            title = { Text("Report Failed", style = Type.headline, color = palette.textPrimary) },
            text = { Text(message, style = Type.subhead, color = palette.textSecondary) },
            confirmButton = { TextButton(onClick = { error = null }) { Text("OK", color = VitalsColors.caloriesPrimary) } },
        )
    }
    restoreMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { restoreMessage = null }, containerColor = palette.cardSurface,
            title = { Text("Vitals+", style = Type.headline, color = palette.textPrimary) },
            text = { Text(message, style = Type.subhead, color = palette.textSecondary) },
            confirmButton = { TextButton(onClick = { restoreMessage = null }) { Text("OK", color = VitalsColors.caloriesPrimary) } },
        )
    }
}

@Composable
private fun ActionRow(icon: ImageVector, title: String, detail: String, button: String, done: Boolean = false, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Geo.cardRadius)).background(palette.cardSurface).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(VitalsColors.caloriesPrimary.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = VitalsColors.caloriesPrimary, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Type.rounded(15.sp, FontWeight.Bold), color = palette.textPrimary)
            Text(detail, style = Type.caption, color = palette.textSecondary)
        }
        Text(
            button, style = Type.rounded(13.sp, FontWeight.Bold),
            color = if (done) VitalsColors.streakPrimary else Color.White,
            modifier = Modifier.clip(CircleShape).background(if (done) VitalsColors.streakPrimary.copy(alpha = 0.14f) else VitalsColors.caloriesPrimary)
                .tappable("$title, $button", onClick = onClick).padding(horizontal = 14.dp, vertical = 8.dp),
        )
    }
}

@Composable
private fun AccountRow(icon: ImageVector, title: String, detail: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Geo.cardRadius)).background(palette.cardSurface).tappable(title, onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, tint = palette.textSecondary, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Type.rounded(15.sp, FontWeight.SemiBold), color = palette.textPrimary)
            Text(detail, style = Type.caption, color = palette.textSecondary)
        }
    }
}
