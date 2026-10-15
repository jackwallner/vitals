package com.jackwallner.vitals.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.AppGraph
import com.jackwallner.vitals.BuildConfig
import com.jackwallner.vitals.data.Appearance
import com.jackwallner.vitals.data.HealthPermissions
import com.jackwallner.vitals.model.PacingComparison
import com.jackwallner.vitals.model.PacingLookback
import com.jackwallner.vitals.model.effectiveMinPacingSamples
import com.jackwallner.vitals.ui.Links
import com.jackwallner.vitals.ui.LocalNav
import com.jackwallner.vitals.ui.MailKind
import com.jackwallner.vitals.ui.Overlay
import com.jackwallner.vitals.ui.PlusFeature
import com.jackwallner.vitals.ui.composeSupportMail
import com.jackwallner.vitals.ui.openUrl
import com.jackwallner.vitals.ui.theme.FormSection
import com.jackwallner.vitals.ui.theme.Gradients
import com.jackwallner.vitals.ui.theme.InfoCallout
import com.jackwallner.vitals.ui.theme.NavRow
import com.jackwallner.vitals.ui.theme.RowDivider
import com.jackwallner.vitals.ui.theme.SegmentedControl
import com.jackwallner.vitals.ui.theme.ToggleRow
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.VitalsColors
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable
import kotlinx.coroutines.launch

/** `SettingsInfoTopic`: the explanation under an ⓘ, worded for Health Connect. */
private enum class InfoTopic(val message: String, val detail: String? = null) {
    ACTIVE_RESTING("Splits the ring into the calories you burned moving and the calories your body burned at rest."),
    ENERGY_AVERAGES(
        "TDEE is your maintenance burn, BMR your resting burn, each averaged over the last 30 days of your own Health Connect data. They are reference figures, not goals.",
        "Needs about a month of Health Connect data to settle. Days without measured resting energy are skipped rather than counted as zero.",
    ),
    NET_DEFICIT("Calories burned minus the food energy in Health Connect. A positive number means a deficit."),
    FASTING("Counts days with no food logged toward your Net Deficit history. Off by default, so an unlogged day doesn't read as a full-burn deficit."),
    PROJECTION("Projects where today's calories and steps will land from your pace so far, using the pacing window set above."),
    STREAK("Counts consecutive days you hit a calorie or step goal. Empty days break the streak."),
}

@Composable
fun SettingsScreen(graph: AppGraph, onClose: () -> Unit) {
    val settings = graph.settings
    val store = graph.store
    val isPro = store.isPro
    val nav = LocalNav.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var open by remember { mutableStateOf<InfoTopic?>(null) }
    var calEnabled by remember { mutableStateOf(settings.calorieGoalEnabled) }
    var calText by remember { mutableStateOf(settings.calorieGoalValue.toString()) }
    var stepEnabled by remember { mutableStateOf(settings.stepGoalEnabled) }
    var stepText by remember { mutableStateOf(settings.stepGoalValue.toString()) }
    var showReviewCode by remember { mutableStateOf(false) }

    val calValid = !calEnabled || (calText.toIntOrNull()?.let { it in 500..50_000 } ?: false)
    val stepValid = !stepEnabled || (stepText.toIntOrNull()?.let { it in 100..500_000 } ?: false)

    fun applyGoals() {
        val calories = if (calEnabled) calText.toIntOrNull()?.takeIf { it in 500..50_000 } ?: settings.calorieGoalValue else null
        val steps = if (stepEnabled) stepText.toIntOrNull()?.takeIf { it in 100..500_000 } ?: settings.stepGoalValue else null
        settings.saveGoals(calories, steps)
    }
    DisposableEffect(Unit) { onDispose { applyGoals() } }

    /** A locked switch: Pro flips it, anyone else is shown the pitch for that feature. */
    fun gated(feature: PlusFeature, apply: (Boolean) -> Unit): (Boolean) -> Unit = { on ->
        if (isPro) apply(on) else if (on) nav.openPaywall(feature)
    }

    fun toggleInfo(topic: InfoTopic) { open = if (open == topic) null else topic }

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Settings", style = Type.title3, color = palette.textPrimary, modifier = Modifier.weight(1f))
            Text(
                "Done", style = Type.rounded(16.sp, FontWeight.Bold),
                color = if (calValid && stepValid) VitalsColors.caloriesPrimary else palette.textTertiary,
                modifier = Modifier.tappable("Done") { if (calValid && stepValid) { applyGoals(); onClose() } }.padding(8.dp),
            )
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            FormSection(header = "Vitals+") {
                if (isPro) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Verified, null, tint = VitalsColors.streakPrimary)
                            Column {
                                Text("Vitals+ Active", style = Type.headline, color = palette.textPrimary)
                                Text("Thanks for supporting the app.", style = Type.footnote, color = palette.textSecondary)
                            }
                        }
                        ActionLinks(graph)
                    }
                } else {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(
                            Modifier.fillMaxWidth().tappable("Unlock Vitals+") { nav.openPaywall(null) },
                            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(Modifier.size(32.dp).clip(CircleShape).background(Gradients.calories), contentAlignment = Alignment.Center) {
                                Icon(Icons.Filled.AutoAwesome, null, tint = Color.White, modifier = Modifier.size(16.dp))
                            }
                            Column(Modifier.weight(1f)) {
                                Text("Unlock Vitals+", style = Type.headline, color = palette.textPrimary)
                                Text("Net Deficit, TDEE & BMR, streaks, PDF reports.", style = Type.footnote, color = palette.textSecondary, maxLines = 2)
                            }
                            Icon(Icons.Filled.ChevronRight, null, tint = palette.textTertiary)
                        }
                        ActionLinks(graph)
                    }
                }
            }

            FormSection(header = "Calorie Burn", footer = "What you burn, from Health Connect. Goal changes save when you close Settings.") {
                ToggleRow("Show Calories", settings.showCalories, { settings.showCalories = it })
                RowDivider()
                ToggleRow("Calorie Goal", calEnabled, { calEnabled = it })
                if (calEnabled) {
                    GoalField("Daily target", calText, { calText = it.filter(Char::isDigit).take(6) }, "cal", calValid, "Enter 500–50,000 calories.")
                }
                RowDivider()
                ToggleRow("Active + Resting Breakdown", isPro && settings.showActiveResting, gated(PlusFeature.ACTIVE_RESTING) { settings.showActiveResting = it }, locked = !isPro, info = { toggleInfo(InfoTopic.ACTIVE_RESTING) }, infoOpen = open == InfoTopic.ACTIVE_RESTING)
                if (open == InfoTopic.ACTIVE_RESTING) InfoCallout(open!!.message, open!!.detail)
                RowDivider()
                ToggleRow("TDEE & BMR", isPro && settings.showEnergyAverages, gated(PlusFeature.ENERGY_AVERAGES) { settings.showEnergyAverages = it }, locked = !isPro, info = { toggleInfo(InfoTopic.ENERGY_AVERAGES) }, infoOpen = open == InfoTopic.ENERGY_AVERAGES)
                if (open == InfoTopic.ENERGY_AVERAGES) InfoCallout(open!!.message, open!!.detail)
            }

            FormSection(header = "Calorie Intake", footer = "Read from the food you log in Health Connect.") {
                ToggleRow(
                    "Net Deficit", isPro && settings.showNet,
                    gated(PlusFeature.NET_DEFICIT) { on ->
                        if (on) scope.launch {
                            graph.permissions.request(HealthPermissions.core(includeFood = true))
                            settings.showNet = true
                            graph.repo.refresh(true)
                        } else settings.showNet = false
                    },
                    locked = !isPro, info = { toggleInfo(InfoTopic.NET_DEFICIT) }, infoOpen = open == InfoTopic.NET_DEFICIT,
                )
                if (open == InfoTopic.NET_DEFICIT) InfoCallout(open!!.message, open!!.detail)
                if (isPro && settings.showNet) {
                    RowDivider()
                    ToggleRow("Fasting Mode", settings.netFasting, { settings.netFasting = it }, locked = false, info = { toggleInfo(InfoTopic.FASTING) }, infoOpen = open == InfoTopic.FASTING)
                    if (open == InfoTopic.FASTING) InfoCallout(open!!.message, open!!.detail)
                }
            }

            FormSection(header = "Steps", footer = "Goal changes save when you close Settings; other settings apply instantly.") {
                ToggleRow("Show Steps", settings.showSteps, { settings.showSteps = it })
                RowDivider()
                ToggleRow("Step Goal", stepEnabled, { stepEnabled = it })
                if (stepEnabled) {
                    GoalField("Daily target", stepText, { stepText = it.filter(Char::isDigit).take(6) }, "steps", stepValid, "Enter 100–500,000 steps.")
                }
            }

            val window = settings.pacingLookback.label.lowercase()
            val basis = if (settings.pacingComparison == PacingComparison.DAY_OF_WEEK) "Past $window, same weekday as today." else "Past $window, every day."
            val minSamples = effectiveMinPacingSamples(settings.pacingComparison, settings.pacingLookback)
            FormSection(
                header = "Pacing & Projections",
                footer = "Compares your progress so far to your usual at this time (Health Connect). $basis Empty days don’t count. Need $minSamples+ ${if (minSamples == 1) "day" else "days"} with data to show a comparison.",
            ) {
                ToggleRow("Show Pacing", settings.showPacing, { settings.showPacing = it })
                if (settings.showPacing) {
                    RowDivider()
                    PickerRow("Usual day is", settings.pacingComparison.label, PacingComparison.entries.map { it.label }) { settings.choosePacingComparison(PacingComparison.entries[it]) }
                    RowDivider()
                    PickerRow("Look back", settings.pacingLookback.label, PacingLookback.entries.map { it.label }) { settings.choosePacingLookback(PacingLookback.entries[it]) }
                }
                RowDivider()
                ToggleRow("End-of-Day Projection", isPro && settings.showProjections, gated(PlusFeature.PROJECTIONS) { settings.showProjections = it }, locked = !isPro, info = { toggleInfo(InfoTopic.PROJECTION) }, infoOpen = open == InfoTopic.PROJECTION)
                if (open == InfoTopic.PROJECTION) InfoCallout(open!!.message, open!!.detail)
                RowDivider()
                ToggleRow("Goal Streak", isPro && settings.showStreaks, gated(PlusFeature.STREAKS) { settings.showStreaks = it }, locked = !isPro, info = { toggleInfo(InfoTopic.STREAK) }, infoOpen = open == InfoTopic.STREAK)
                if (open == InfoTopic.STREAK) InfoCallout(open!!.message, open!!.detail)
            }

            val excludedCount = settings.excludedKeys(java.time.LocalDate.now()).size
            val dayWord = if (excludedCount == 1) "day" else "days"
            val subtitle = when {
                settings.isAveragesPaused -> "Paused · $excludedCount $dayWord excluded"
                excludedCount == 0 -> "None excluded"
                else -> "$excludedCount $dayWord excluded"
            }
            val footer = when {
                isPro && settings.isAveragesPaused -> "Averages are paused: every new day is excluded until you resume. Open this row (or the banner above the tab bar) to resume or edit the days."
                excludedCount == 0 -> "Leave a sick day or a day off the wrist out of every average, total, and streak, or pause averages for a stretch you can't put an end date on. Nothing is deleted, and excluded days still show in your charts, dimmed."
                else -> "Excluded days still show in your charts and export, dimmed. They count toward no average, total, best day, or streak."
            }
            FormSection(header = "Averages", footer = footer) {
                NavRow("Excluded Days", subtitle, onClick = { nav.push(Overlay.ExcludedDays) })
            }

            FormSection(header = "Appearance") {
                Box(Modifier.padding(12.dp)) {
                    SegmentedControl(Appearance.entries.map { it.label }, settings.appearance.ordinal, { settings.chooseAppearance(Appearance.entries[it]) })
                }
            }

            FormSection(header = "Help", footer = "Total Calories reads Health Connect data in read-only mode and keeps your health data on your device.") {
                NavRow("Write a Review", onClick = { graph.review.markOpenedWriteReview(); context.openUrl(Links.LISTING) })
                RowDivider()
                NavRow("Send Feedback", onClick = { graph.review.markFeedbackSubmitted(); context.composeSupportMail(MailKind.FEEDBACK, isPro) })
                RowDivider()
                NavRow("Privacy Policy", onClick = { context.openUrl(Links.PRIVACY) })
                RowDivider()
                NavRow("Terms of Use", onClick = { context.openUrl(Links.TERMS) })
                RowDivider()
                NavRow("Support", onClick = { context.openUrl(Links.SUPPORT) })
                RowDivider()
                NavRow("Contact Support", onClick = { context.composeSupportMail(MailKind.HELP, isPro) })
            }

            FormSection(header = "About") {
                Row(
                    Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = { if (!isPro) showReviewCode = true }).padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Version", style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
                    Text(BuildConfig.VERSION_NAME, style = Type.body, color = palette.textSecondary)
                }
            }
        }
    }
    if (showReviewCode) ReviewCodeDialog(graph) { showReviewCode = false }
}

@Composable
private fun ActionLinks(graph: AppGraph) {
    val context = LocalContext.current
    val isPro = graph.store.isPro
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        val link = Type.rounded(14.sp, FontWeight.Medium)
        Text("Rate App", style = link, color = VitalsColors.caloriesPrimary, modifier = Modifier.tappable("Rate App") { graph.review.markOpenedWriteReview(); context.openUrl(Links.LISTING) })
        Text("·", style = link, color = palette.textTertiary)
        Text("Get Help", style = link, color = VitalsColors.caloriesPrimary, modifier = Modifier.tappable("Get Help") { context.composeSupportMail(MailKind.HELP, isPro) })
        Text("·", style = link, color = palette.textTertiary)
        Text("Feature Request", style = link, color = VitalsColors.caloriesPrimary, modifier = Modifier.tappable("Feature Request") { context.composeSupportMail(MailKind.FEATURE, isPro) })
    }
}

@Composable
private fun GoalField(label: String, text: String, onText: (String) -> Unit, unit: String, valid: Boolean, invalid: String) {
    Column {
        RowDivider()
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
            BasicTextField(
                value = text, onValueChange = onText, singleLine = true,
                textStyle = Type.body.copy(color = palette.textPrimary, textAlign = TextAlign.End),
                cursorBrush = SolidColor(VitalsColors.caloriesPrimary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.width(96.dp),
            )
            Text(" $unit", style = Type.body, color = palette.textSecondary)
        }
        if (!valid) Text(invalid, style = Type.caption, color = Color(0xFFFF3B30), modifier = Modifier.padding(start = 16.dp, bottom = 10.dp))
    }
}

@Composable
private fun PickerRow(title: String, value: String, options: List<String>, onPick: (Int) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().tappable(title) { expanded = true }.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
            Text(value, style = Type.body, color = palette.textSecondary)
        }
        DropdownMenu(expanded, { expanded = false }, containerColor = palette.cardSurface) {
            options.forEachIndexed { index, option ->
                DropdownMenuItem(text = { Text(option, style = Type.body, color = palette.textPrimary) }, onClick = { expanded = false; onPick(index) })
            }
        }
    }
}

/** Play reviewers unlock Vitals+ with a code that is checked against a hash baked into the release build. */
@Composable
private fun ReviewCodeDialog(graph: AppGraph, onDismiss: () -> Unit) {
    var code by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = palette.cardSurface,
        title = { Text("Reviewer access", style = Type.headline, color = palette.textPrimary) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Enter the review code from the Play Console app access notes.", style = Type.footnote, color = palette.textSecondary)
                BasicTextField(
                    value = code, onValueChange = { code = it; failed = false }, singleLine = true,
                    textStyle = Type.body.copy(color = palette.textPrimary), cursorBrush = SolidColor(VitalsColors.caloriesPrimary),
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(palette.background).padding(12.dp),
                )
                if (failed) Text("That code didn't match.", style = Type.caption, color = Color(0xFFFF3B30))
            }
        },
        confirmButton = {
            TextButton(onClick = { if (graph.store.activateReviewAccess(code)) onDismiss() else failed = true }) { Text("Unlock", color = VitalsColors.caloriesPrimary) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel", color = palette.textSecondary) } },
    )
}
