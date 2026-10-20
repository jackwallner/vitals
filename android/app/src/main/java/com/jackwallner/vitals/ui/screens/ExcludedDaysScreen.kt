package com.jackwallner.vitals.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.AppGraph
import com.jackwallner.vitals.model.ExcludedDays
import com.jackwallner.vitals.model.Format
import com.jackwallner.vitals.model.DayStats
import com.jackwallner.vitals.ui.LocalNav
import com.jackwallner.vitals.ui.PlusFeature
import com.jackwallner.vitals.ui.theme.FormSection
import com.jackwallner.vitals.ui.theme.RowDivider
import com.jackwallner.vitals.ui.theme.ToggleRow
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.VitalsColors
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

/** What a locked tap asked for, carried out if the paywall converts. */
private sealed interface LockedAction {
    data class Exclude(val day: LocalDate) : LockedAction
    data object Pause : LockedAction
}

private const val EFFECT_FOOTER =
    "Excluded days count toward no average, total, best day, pacing figure, or weekly recap, and they neither extend nor break a goal streak. Nothing is deleted: they stay in your charts and CSV export, drawn dimmed."

/** `ExcludedDaysView`: pause switch, month calendar, and the list of excluded days with their numbers. */
@Composable
fun ExcludedDaysScreen(graph: AppGraph, onClose: () -> Unit) {
    val settings = graph.settings
    val isPro = graph.store.isPro
    val nav = LocalNav.current
    val today = LocalDate.now()
    var pending by remember { mutableStateOf<LockedAction?>(null) }
    var stats by remember { mutableStateOf<Map<String, DayStats>>(emptyMap()) }
    val picked = if (isPro) settings.pickedExcludedKeys else emptySet()
    val pausedSince = if (isPro) settings.pausedSince else null

    LaunchedEffect(Unit) { graph.store.trackPaywallImpression("vitals_trial_sheet_excluded_days", oncePerSession = true) }
    // Converting from the pitch carries out the tap that raised it.
    LaunchedEffect(isPro) {
        val action = pending ?: return@LaunchedEffect
        if (!isPro) return@LaunchedEffect
        when (action) {
            is LockedAction.Exclude -> settings.setExcluded(action.day, true)
            LockedAction.Pause -> settings.pauseAverages(today)
        }
        pending = null
    }
    LaunchedEffect(picked, pausedSince) {
        if (picked.isEmpty()) { stats = emptyMap(); return@LaunchedEffect }
        val dates = picked.mapNotNull(ExcludedDays::date)
        val first = dates.minOrNull() ?: return@LaunchedEffect
        val last = dates.maxOrNull() ?: return@LaunchedEffect
        stats = runCatching { graph.repo.stats(first, last) }.getOrDefault(emptyList()).associateBy { ExcludedDays.key(it.date) }
    }

    fun locked(action: LockedAction) { pending = action; nav.openPaywall(PlusFeature.EXCLUDED_DAYS) }

    val pausedCount = ExcludedDays.pausedKeys(pausedSince, today).size
    val pausedLabel = pausedSince?.format(DateTimeFormatter.ofPattern("MMM d"))
    val pauseSubtitle = when {
        settings.pausedSince == null -> "Stop counting new days until you resume"
        !isPro -> "Paused since ${settings.pausedSince?.format(DateTimeFormatter.ofPattern("MMM d"))} · on hold without Vitals+"
        else -> "Paused since $pausedLabel · $pausedCount ${if (pausedCount == 1) "day" else "days"}"
    }
    val pauseFooter = when {
        !isPro && settings.pausedSince != null -> "Your pause and excluded days are saved. Every day is counting toward your averages again until Vitals+ is back."
        !isPro && settings.pickedExcludedKeys.isNotEmpty() -> "Your excluded days are saved. Every day is counting toward your averages until Vitals+ is back."
        pausedSince != null -> "Today and every day until you resume is excluded. Resuming starts counting again and keeps the paused days excluded, and you can drop them from the list below afterwards."
        else -> "For a stretch you can't put an end date on yet: an injury, a trip, a spell off the wrist. Each new day is excluded automatically until you resume."
    }
    val excluded = picked.mapNotNull(ExcludedDays::date).sortedDescending()

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).tappable("Back", onClick = onClose), contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, null, tint = VitalsColors.caloriesPrimary)
            }
            Text("Excluded Days", style = Type.headline, color = palette.textPrimary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
            Box(Modifier.size(44.dp))
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            if (!isPro) LockedCard { locked(LockedAction.Pause) }

            FormSection(footer = pauseFooter) {
                ToggleRow(
                    "Pause Averages", checked = isPro && settings.pausedSince != null,
                    onChange = { on ->
                        when {
                            !isPro -> if (on) locked(LockedAction.Pause)
                            on -> settings.pauseAverages(today)
                            else -> settings.resumeAverages(today)
                        }
                    },
                    locked = !isPro,
                )
                Text(
                    pauseSubtitle, style = Type.caption,
                    color = if (isPro && settings.pausedSince != null) VitalsColors.caloriesPrimary else palette.textSecondary,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 10.dp),
                )
            }

            FormSection(
                header = "Pick Days",
                footer = when {
                    !isPro -> "Tap a day to take it out of your averages with Vitals+."
                    pausedSince != null -> "Tap a day before the pause to take it out too. Tap it again to put it back."
                    else -> "Tap a day to take it out of your averages. Tap it again to put it back."
                },
            ) {
                MonthCalendar(
                    today = today, picked = picked, pausedSince = pausedSince,
                    onTap = { day ->
                        if (!isPro) locked(LockedAction.Exclude(day))
                        else settings.setExcluded(day, ExcludedDays.key(day) !in picked)
                    },
                )
            }

            when {
                !isPro -> Footer(EFFECT_FOOTER)
                excluded.isEmpty() -> {
                    FormSection(footer = EFFECT_FOOTER) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text("No days excluded", style = Type.rounded(15.sp, FontWeight.SemiBold), color = palette.textPrimary)
                            Text(
                                "A week with the flu, a long flight, a day the watch stayed on the charger. Pick those days above and your averages stop counting them.",
                                style = Type.caption, color = palette.textSecondary,
                            )
                        }
                    }
                }
                else -> Column {
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            (if (excluded.size == 1) "1 Excluded Day" else "${excluded.size} Excluded Days").uppercase(),
                            style = Type.rounded(12.sp), color = palette.textSecondary, modifier = Modifier.weight(1f),
                        )
                        Text("Clear All", style = Type.rounded(12.sp, FontWeight.Medium), color = Color(0xFFFF3B30), modifier = Modifier.tappable("Clear all excluded days") { settings.setPickedExcluded(emptySet()) }.padding(4.dp))
                    }
                    FormSection(footer = EFFECT_FOOTER) {
                        excluded.forEachIndexed { index, date ->
                            if (index > 0) RowDivider()
                            ExcludedRow(date, stats[ExcludedDays.key(date)]) { settings.setExcluded(date, false) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Footer(text: String) {
    Text(text, style = Type.rounded(12.sp), color = palette.textSecondary, modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
private fun LockedCard(onTry: () -> Unit) {
    FormSection {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Vitals+", style = Type.rounded(12.sp, FontWeight.Bold), color = VitalsColors.caloriesPrimary)
            Text(PlusFeature.EXCLUDED_DAYS.intentHeadline, style = Type.headline, color = palette.textPrimary)
            Text(PlusFeature.EXCLUDED_DAYS.intentSubheadline, style = Type.subhead, color = palette.textSecondary)
            Box(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(VitalsColors.caloriesPrimary).tappable("Try Excluded Days", onClick = onTry).padding(vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) { Text("Try Excluded Days", style = Type.rounded(15.sp, FontWeight.SemiBold), color = Color.White) }
        }
    }
}

@Composable
private fun ExcludedRow(date: LocalDate, stats: DayStats?, onRemove: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(date.format(DateTimeFormatter.ofPattern("EEEE, MMM d, yyyy")), style = Type.subhead, color = palette.textPrimary, modifier = Modifier.weight(1f))
        if (stats != null && stats.hasData) {
            Text(Format.number(stats.total), style = Type.rounded(12.sp, FontWeight.SemiBold), color = VitalsColors.caloriesPrimary)
            Text(" · ", style = Type.caption, color = palette.textTertiary)
            Text(Format.number(stats.steps.toDouble()), style = Type.rounded(12.sp, FontWeight.SemiBold), color = VitalsColors.stepsPrimary)
        }
        Text("Remove", style = Type.rounded(12.sp, FontWeight.Medium), color = Color(0xFFFF3B30), modifier = Modifier.tappable("Remove ${date}") { onRemove() }.padding(start = 12.dp, top = 4.dp, bottom = 4.dp))
    }
}

/**
 * Month grid with the tapped days drawn filled. Days after today are inert; days
 * covered by a running pause belong to the pause and are drawn outlined and inert.
 */
@Composable
private fun MonthCalendar(today: LocalDate, picked: Set<String>, pausedSince: LocalDate?, onTap: (LocalDate) -> Unit) {
    var month by remember { mutableStateOf(YearMonth.from(today)) }
    val earliest = YearMonth.from(today.minusYears(3))
    val first = month.atDay(1)
    val offset = (first.dayOfWeek.value - DayOfWeek.SUNDAY.value + 7) % 7
    val weekdays = (0..6).map { DayOfWeek.SUNDAY.plus(it.toLong()).getDisplayName(TextStyle.NARROW, androidx.compose.ui.platform.LocalConfiguration.current.locales[0]) }
    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(month.format(DateTimeFormatter.ofPattern("MMMM yyyy")), style = Type.headline, color = palette.textPrimary, modifier = Modifier.weight(1f).padding(start = 4.dp))
            Box(Modifier.size(40.dp).tappable("Previous month") { if (month > earliest) month = month.minusMonths(1) }, contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, null, tint = if (month > earliest) VitalsColors.caloriesPrimary else palette.textTertiary)
            }
            Box(Modifier.size(40.dp).tappable("Next month") { if (month < YearMonth.from(today)) month = month.plusMonths(1) }, contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = if (month < YearMonth.from(today)) VitalsColors.caloriesPrimary else palette.textTertiary)
            }
        }
        Row(Modifier.fillMaxWidth()) {
            weekdays.forEach { Text(it, style = Type.caption, color = palette.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.weight(1f)) }
        }
        val cells = offset + month.lengthOfMonth()
        val rows = (cells + 6) / 7
        for (row in 0 until rows) {
            Row(Modifier.fillMaxWidth()) {
                for (col in 0..6) {
                    val dayNumber = row * 7 + col - offset + 1
                    Box(Modifier.weight(1f).aspectRatio(1f).padding(2.dp), contentAlignment = Alignment.Center) {
                        if (dayNumber in 1..month.lengthOfMonth()) {
                            val date = month.atDay(dayNumber)
                            DayCell(date, today, ExcludedDays.key(date) in picked, pausedSince != null && !date.isBefore(pausedSince), onTap)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DayCell(date: LocalDate, today: LocalDate, selected: Boolean, inPause: Boolean, onTap: (LocalDate) -> Unit) {
    val future = date.isAfter(today)
    val enabled = !future && !inPause
    val fill = when {
        selected -> VitalsColors.caloriesPrimary
        inPause && !future -> VitalsColors.caloriesPrimary.copy(alpha = 0.25f)
        else -> Color.Transparent
    }
    val textColor = when {
        selected -> Color.White
        future -> palette.textTertiary
        else -> palette.textPrimary
    }
    Box(
        Modifier.fillMaxSize().clip(CircleShape).background(fill)
            .let { if (enabled) it.tappable(date.format(DateTimeFormatter.ofPattern("EEEE, MMMM d")) + if (selected) ", excluded" else "") { onTap(date) } else it },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            date.dayOfMonth.toString(),
            style = Type.rounded(15.sp, if (date == today) FontWeight.Bold else FontWeight.Normal),
            color = if (date == today && !selected) VitalsColors.caloriesPrimary else textColor,
        )
    }
}
