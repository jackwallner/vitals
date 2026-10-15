package com.jackwallner.vitals.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.PlusOne
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Whatshot
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.AppGraph
import com.jackwallner.vitals.DebugLaunchOptions
import com.jackwallner.vitals.billing.ConversionCopy
import com.jackwallner.vitals.billing.PurchaseOutcome
import com.jackwallner.vitals.data.HealthPermissions
import com.jackwallner.vitals.ui.Links
import com.jackwallner.vitals.ui.LocalNav
import com.jackwallner.vitals.ui.findActivity
import com.jackwallner.vitals.ui.openUrl
import com.jackwallner.vitals.ui.theme.Gradients
import com.jackwallner.vitals.ui.theme.drawWithBrush
import com.jackwallner.vitals.ui.theme.PrimaryButton
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.VitalsColors
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class Step { WELCOME, GOALS, TRIAL }

private data class Point(val icon: ImageVector, val color: Color, val title: String, val detail: String)

private val trialPoints = listOf(
    Point(Icons.Filled.PlusOne, VitalsColors.caloriesPrimary, "Net deficit", "Burned minus food logged in Health Connect"),
    Point(Icons.Filled.Whatshot, VitalsColors.streakPrimary, "Streaks & projections", "Keep the chain and see end-of-day pace"),
    Point(Icons.Filled.ShowChart, VitalsColors.stepsPrimary, "Deeper trends", "TDEE, BMR, and period comparisons"),
    Point(Icons.Filled.Description, VitalsColors.netDeficitBrand, "Summary reports", "Export a PDF for any date range"),
)

/** First launch: welcome (and the one Health Connect prompt), goals, then the Vitals+ trial. */
@Composable
fun OnboardingScreen(graph: AppGraph) {
    val settings = graph.settings
    val store = graph.store
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val nav = LocalNav.current
    var step by remember { mutableStateOf(DebugLaunchOptions.onboardingStep?.let { name -> Step.entries.firstOrNull { it.name.equals(name, true) } } ?: Step.WELCOME) }
    var wantCalories by remember { mutableStateOf(true) }
    var calText by remember { mutableStateOf("2500") }
    var wantSteps by remember { mutableStateOf(true) }
    var stepText by remember { mutableStateOf("10000") }
    var starting by remember { mutableStateOf(false) }
    var restoring by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var waitExpired by remember { mutableStateOf(false) }

    val calValid = !wantCalories || (calText.toDoubleOrNull()?.let { it in 500.0..50_000.0 } ?: false)
    val stepValid = !wantSteps || (stepText.toIntOrNull()?.let { it in 100..500_000 } ?: false)

    LaunchedEffect(Unit) { store.fetchProducts() }
    // The trial CTA is live once RevenueCat has named the action, and live anyway after the wait limit.
    LaunchedEffect(step) {
        if (step == Step.TRIAL) {
            store.trackPaywallImpression("vitals_trial_onboarding", oncePerSession = true)
            delay(6_000)
            waitExpired = true
        }
    }
    LaunchedEffect(store.isPro) { if (store.isPro && step == Step.TRIAL) settings.completeSetup() }

    fun saveGoals() = settings.saveGoals(
        calories = if (wantCalories) calText.toDoubleOrNull()?.toInt() else null,
        steps = if (wantSteps) stepText.toIntOrNull() else null,
    )

    fun startTrial() {
        val plan = store.onboardingPlan
        val activity = context.findActivity()
        if (plan == null || activity == null) {
            error = store.lastError ?: ConversionCopy.UNAVAILABLE
            scope.launch { store.fetchProducts() }
            return
        }
        error = null
        starting = true
        scope.launch {
            val eligible = store.isEligibleForIntroOffer(plan)
            try {
                when (store.purchase(activity, plan)) {
                    PurchaseOutcome.PURCHASED -> settings.completeSetup()
                    PurchaseOutcome.PENDING -> error = ConversionCopy.purchasePendingMessage(eligible)
                    PurchaseOutcome.CANCELLED -> error = ConversionCopy.purchaseCancelledMessage(eligible)
                }
            } catch (e: Exception) {
                error = e.message ?: ConversionCopy.purchaseFailedMessage(eligible)
            } finally {
                starting = false
            }
        }
    }

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding().imePadding()) {
        AnimatedContent(
            step,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            transitionSpec = { (slideInHorizontally { it / 4 } + fadeIn()) togetherWith (slideOutHorizontally { -it / 4 } + fadeOut()) },
            label = "onboarding",
        ) { page ->
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                when (page) {
                    Step.WELCOME -> WelcomePage()
                    Step.GOALS -> GoalsPage(wantCalories, { wantCalories = it }, calText, { calText = it.filter(Char::isDigit).take(6) }, calValid, wantSteps, { wantSteps = it }, stepText, { stepText = it.filter(Char::isDigit).take(6) }, stepValid)
                    Step.TRIAL -> TrialPage()
                }
            }
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 12.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            // Welcome and trial keep a fixed-height slot above the button; goals gives the room back to its two cards.
            if (step != Step.GOALS) Box(Modifier.heightIn(min = 46.dp).fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
                when (step) {
                    Step.WELCOME -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Icon(Icons.Filled.Lock, null, tint = palette.textTertiary, modifier = Modifier.size(12.dp))
                        Text("Read-only. Stays on your device. No account.", style = Type.caption, color = palette.textSecondary, textAlign = TextAlign.Center)
                    }
                    Step.GOALS -> Unit
                    Step.TRIAL -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Get Started", style = Type.rounded(15.sp, FontWeight.Medium), color = palette.textSecondary, modifier = Modifier.tappable("Get Started") { settings.completeSetup() }.padding(vertical = 4.dp))
                        error?.let { Text(it, style = Type.caption, color = VitalsColors.caloriesPrimary, textAlign = TextAlign.Center) }
                    }
                }
            }
            if (step != Step.GOALS) DisclosureSlot(step == Step.TRIAL, store.onboardingDisclosure)
            when (step) {
                Step.WELCOME -> PrimaryButton("Continue", onClick = {
                    scope.launch {
                        step = Step.GOALS
                        graph.permissions.request(HealthPermissions.core(includeFood = false))
                        graph.repo.markPermissionAsked()
                    }
                })
                Step.GOALS -> PrimaryButton("Continue", onClick = { saveGoals(); step = Step.TRIAL }, enabled = calValid && stepValid)
                Step.TRIAL -> {
                    val ready = store.conversionCtaReady || waitExpired
                    PrimaryButton(
                        if (store.conversionCtaReady) store.onboardingCtaLabel else "See Vitals+ Plans",
                        onClick = { if (store.onboardingPlan == null) { nav.openPaywall(); settings.completeSetup() } else startTrial() },
                        enabled = ready, loading = starting || !ready,
                    )
                }
            }
            if (step != Step.GOALS) Row(Modifier.alpha(if (step == Step.TRIAL) 1f else 0f), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                val enabled = step == Step.TRIAL
                FooterLink("Terms", enabled) { context.openUrl(Links.TERMS) }
                FooterLink("Privacy", enabled) { context.openUrl(Links.PRIVACY) }
                FooterLink(if (restoring) "Restoring…" else "Restore", enabled) {
                    restoring = true
                    scope.launch {
                        error = null
                        store.restorePurchases()
                        restoring = false
                        if (store.isPro) settings.completeSetup() else error = store.lastError
                    }
                }
            }
        }
    }
}

@Composable
private fun FooterLink(text: String, enabled: Boolean, onClick: () -> Unit) {
    Text(
        text, style = Type.caption, color = palette.textSecondary,
        modifier = Modifier.then(if (enabled) Modifier.tappable(text, onClick = onClick) else Modifier).padding(vertical = 6.dp),
    )
}

/** The billing disclosure, real on the trial page and an invisible placeholder of the same height elsewhere. */
@Composable
private fun DisclosureSlot(real: Boolean, text: String?) {
    val shown = if (real) text else null
    Text(
        shown ?: "7-day free trial, then $00.00 / year. ${ConversionCopy.ONBOARDING_RENEW_CLAUSE}",
        style = Type.caption2, color = palette.textTertiary, textAlign = TextAlign.Center,
        modifier = Modifier.alpha(if (shown != null) 1f else 0f),
    )
}

@Composable
private fun WelcomePage() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(28.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            BrandGlyph(Icons.Filled.Favorite)
            Text("Welcome to Total Calories", style = Type.title, color = palette.textPrimary, textAlign = TextAlign.Center)
            Text("Track your calories and steps from Health Connect in one simple view.", style = Type.body, color = palette.textSecondary, textAlign = TextAlign.Center)
        }
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            WelcomePoint(Icons.Filled.Favorite, VitalsColors.caloriesPrimary, "Reads from Health Connect", "Next we’ll ask permission to read your active and resting calories and steps. The app only reads; it never writes anything back.")
            WelcomePoint(Icons.Filled.Lock, VitalsColors.stepsPrimary, "Stays on your device", "Your health data never leaves your phone. No account, no cloud sync.")
        }
    }
}

@Composable
private fun BrandGlyph(icon: ImageVector) {
    Icon(icon, null, modifier = Modifier.size(52.dp).graphicsBrush(Gradients.calories), tint = Color.Unspecified)
}

/** Paints an icon with the calories gradient. */
private fun Modifier.graphicsBrush(brush: Brush): Modifier = drawWithBrush(brush)

@Composable
private fun WelcomePoint(icon: ImageVector, color: Color, title: String, detail: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = color, modifier = Modifier.padding(top = 2.dp).size(24.dp))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = Type.headline, color = palette.textPrimary)
            Text(detail, style = Type.footnote, color = palette.textSecondary)
        }
    }
}

@Composable
private fun GoalsPage(
    wantCal: Boolean, onCal: (Boolean) -> Unit, calText: String, onCalText: (String) -> Unit, calValid: Boolean,
    wantSteps: Boolean, onSteps: (Boolean) -> Unit, stepText: String, onStepText: (String) -> Unit, stepValid: Boolean,
) {
    Column(verticalArrangement = Arrangement.spacedBy(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            BrandGlyph(Icons.Filled.GpsFixed)
            Text("Set your daily goals", style = Type.title, color = palette.textPrimary, textAlign = TextAlign.Center)
            Text("Or turn both off to use Total Calories as a simple counter.", style = Type.subhead, color = palette.textSecondary, textAlign = TextAlign.Center)
        }
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            GoalRow(Icons.Filled.LocalFireDepartment, VitalsColors.caloriesPrimary, "Calorie Goal", wantCal, onCal, calText, onCalText, calValid, "Enter 500–50,000 calories.")
            GoalRow(Icons.Filled.DirectionsWalk, VitalsColors.stepsPrimary, "Step Goal", wantSteps, onSteps, stepText, onStepText, stepValid, "Enter 100–500,000 steps.")
            if (!wantCal && !wantSteps) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Filled.Info, null, tint = palette.textTertiary, modifier = Modifier.size(16.dp))
                    Text("Today will show live calorie and step totals without target rings. You can add goals later in Settings.", style = Type.caption, color = palette.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun GoalRow(icon: ImageVector, color: Color, title: String, enabled: Boolean, onEnabled: (Boolean) -> Unit, text: String, onText: (String) -> Unit, valid: Boolean, invalidMessage: String) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(palette.cardSurface.copy(alpha = 0.5f)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(icon, null, tint = color)
            Text(title, style = Type.headline, color = palette.textPrimary, modifier = Modifier.weight(1f))
            Switch(
                checked = enabled, onCheckedChange = onEnabled,
                colors = SwitchDefaults.colors(checkedTrackColor = VitalsColors.streakPrimary, checkedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent, uncheckedTrackColor = palette.ringTrack, uncheckedThumbColor = Color.White),
            )
        }
        if (enabled) {
            BasicTextField(
                value = text, onValueChange = onText, singleLine = true,
                textStyle = Type.body.copy(color = palette.textPrimary),
                cursorBrush = SolidColor(VitalsColors.caloriesPrimary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(palette.cardSurface).padding(12.dp),
            )
            if (!valid) Text(invalidMessage, style = Type.caption, color = Color(0xFFFF3B30))
        }
    }
}

@Composable
private fun TrialPage() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        BrandGlyph(Icons.Filled.AutoAwesome)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Go further with Vitals+", style = Type.title, color = palette.textPrimary, textAlign = TextAlign.Center)
            Text("Extras that sit on top of your daily calories and steps.", style = Type.subhead, color = palette.textSecondary, textAlign = TextAlign.Center)
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            trialPoints.forEach { point ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                    Icon(point.icon, null, tint = point.color, modifier = Modifier.padding(top = 2.dp).size(22.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(point.title, style = Type.rounded(15.sp, FontWeight.SemiBold), color = palette.textPrimary)
                        Text(point.detail, style = Type.caption, color = palette.textSecondary)
                    }
                }
            }
        }
    }
}
