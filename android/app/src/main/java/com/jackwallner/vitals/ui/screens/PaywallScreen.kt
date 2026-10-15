package com.jackwallner.vitals.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.AppGraph
import com.jackwallner.vitals.billing.ConversionCopy
import com.jackwallner.vitals.billing.PurchaseOutcome
import com.jackwallner.vitals.data.PackageKind
import com.jackwallner.vitals.data.Plan
import com.jackwallner.vitals.ui.Links
import com.jackwallner.vitals.ui.PlusFeature
import com.jackwallner.vitals.ui.findActivity
import com.jackwallner.vitals.ui.openUrl
import com.jackwallner.vitals.ui.theme.Geo
import com.jackwallner.vitals.ui.theme.Gradients
import com.jackwallner.vitals.ui.theme.LoadingBar
import com.jackwallner.vitals.ui.theme.PrimaryButton
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.VitalsColors
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable
import kotlinx.coroutines.launch

/**
 * `PaywallView`. The Upgrade tab (no close button) and the full-screen pitch a
 * locked row raises (`focus` set, with a close button). Prices, trial length
 * and renewal terms all come from Google Play through RevenueCat.
 */
@Composable
fun PaywallScreen(graph: AppGraph, focus: PlusFeature?, onClose: (() -> Unit)?) {
    val store = graph.store
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var selected by remember { mutableStateOf<String?>(null) }
    var purchasing by remember { mutableStateOf(false) }
    var restoring by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }

    val plans = store.plans
    val plan: Plan? = plans.firstOrNull { it.packageId == selected }

    LaunchedEffect(Unit) {
        store.trackPaywallImpression(if (onClose == null) "vitals_upgrade_tab" else "vitals_trial_sheet_${focus?.name?.lowercase() ?: "upgrade"}", oncePerSession = true)
        if (store.plans.isEmpty()) store.fetchProducts()
    }
    LaunchedEffect(plans) {
        if (selected == null || plans.none { it.packageId == selected }) {
            selected = (plans.firstOrNull { it.kind == PackageKind.YEARLY } ?: plans.firstOrNull())?.packageId
        }
    }
    LaunchedEffect(store.isPro) { if (store.isPro) onClose?.invoke() }

    val eligible = plan?.let(store::isEligibleForIntroOffer) ?: false
    val ctaTitle = plan?.let {
        ConversionCopy.paywallCtaTitle(it.kind == PackageKind.LIFETIME, it.introOfferLabel != null, store.introEligibilityResolved, eligible)
    }
    val disclosure = plan?.let {
        if (it.kind == PackageKind.LIFETIME) "${it.priceLabel}. One-time purchase. Lifetime access, no subscription."
        else ConversionCopy.disclosure(it.introOfferLabel, it.priceLabel, eligible)
    }

    fun purchase() {
        val chosen = plan ?: return
        val activity = context.findActivity() ?: return
        error = null
        restoreMessage = null
        purchasing = true
        scope.launch {
            val trial = store.isEligibleForIntroOffer(chosen)
            try {
                when (store.purchase(activity, chosen)) {
                    PurchaseOutcome.PURCHASED -> Unit
                    PurchaseOutcome.PENDING -> error = ConversionCopy.purchasePendingMessage(trial)
                    PurchaseOutcome.CANCELLED -> error = ConversionCopy.purchaseCancelledMessage(trial)
                }
            } catch (e: Exception) {
                error = ConversionCopy.purchaseFailedMessage(trial)
            } finally {
                purchasing = false
            }
        }
    }

    fun restore() {
        error = null
        restoreMessage = null
        restoring = true
        scope.launch {
            store.restorePurchases()
            restoring = false
            if (!store.isPro) restoreMessage = store.lastError ?: "No active Vitals+ purchase found for this Google Play account."
        }
    }

    Box(Modifier.fillMaxSize().background(palette.background).statusBarsPadding()) {
        when {
            store.isLoadingProducts && plans.isEmpty() -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                LoadingBar(modifier = Modifier.size(width = 180.dp, height = 4.dp))
                Text("Loading plans…", style = Type.subhead, color = palette.textSecondary, modifier = Modifier.padding(top = 14.dp))
            }
            plans.isEmpty() -> EmptyState(store.lastError) { scope.launch { store.fetchProducts() } }
            else -> Column(Modifier.fillMaxSize()) {
                Column(
                    Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Geo.gutter).padding(top = if (onClose != null) 40.dp else 12.dp, bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Header(focus)
                    FeatureList(focus)
                    PlanCards(plans, selected, eligible = store::isEligibleForIntroOffer, savings = store.annualSavingsPercent) { selected = it.packageId }
                }
                Footer(ctaTitle, disclosure, error, restoreMessage, purchasing, restoring, onPurchase = ::purchase, onRestore = ::restore, context = context)
            }
        }
        if (onClose != null) {
            Box(
                Modifier.align(Alignment.TopEnd).padding(12.dp).size(36.dp).clip(CircleShape).background(palette.cardSurface).tappable("Close", onClick = onClose),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.Close, null, tint = palette.textSecondary, modifier = Modifier.size(18.dp)) }
        }
    }
}

@Composable
private fun EmptyState(message: String?, onRetry: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Filled.WifiOff, null, tint = palette.textTertiary, modifier = Modifier.size(40.dp))
        Text("Couldn't Load Plans", style = Type.headline, color = palette.textPrimary, modifier = Modifier.padding(top = 12.dp))
        Text(message ?: "Check your connection and try again.", style = Type.subhead, color = palette.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
        Text("Try Again", style = Type.rounded(15.sp, FontWeight.SemiBold), color = VitalsColors.caloriesPrimary, modifier = Modifier.padding(top = 16.dp).tappable("Try Again", onClick = onRetry).padding(8.dp))
    }
}

@Composable
private fun Header(focus: PlusFeature?) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(52.dp).clip(CircleShape).background(Gradients.calories), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.AutoAwesome, null, tint = Color.White, modifier = Modifier.size(26.dp))
        }
        Text(focus?.intentHeadline ?: "Vitals+", style = Type.title, color = palette.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
        Text(
            focus?.intentSubheadline ?: "Calories, steps, and trends in one dashboard.",
            style = Type.footnote, color = palette.textSecondary, textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun FeatureList(focus: PlusFeature?) {
    val bullets = if (focus != null) listOf(focus) + focus.companions else PlusFeature.catalog
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        bullets.forEach { feature ->
            val highlighted = feature == focus
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (highlighted) feature.tint.copy(alpha = 0.1f) else Color.Transparent).padding(horizontal = 8.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top,
            ) {
                Icon(feature.icon, null, tint = feature.tint, modifier = Modifier.padding(top = 1.dp).size(20.dp))
                Text(feature.featureListTitle, style = Type.rounded(15.sp, if (highlighted) FontWeight.SemiBold else FontWeight.Medium), color = palette.textPrimary)
            }
        }
        if (focus == null) Text(PlusFeature.REMAINING, style = Type.caption, color = palette.textSecondary, modifier = Modifier.padding(horizontal = 8.dp))
    }
}

@Composable
private fun PlanCards(plans: List<Plan>, selected: String?, eligible: (Plan) -> Boolean, savings: Int?, onSelect: (Plan) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        plans.forEach { plan ->
            val yearly = plan.kind == PackageKind.YEARLY
            PlanCard(plan, plan.packageId == selected, eligible(plan), yearly, if (yearly) savings else null, onClick = { onSelect(plan) })
        }
    }
}

@Composable
private fun PlanCard(plan: Plan, isSelected: Boolean, showsTrial: Boolean, isBestValue: Boolean, savings: Int?, onClick: () -> Unit) {
    val perWeek = if (plan.kind == PackageKind.YEARLY) plan.perWeekLabel else null
    val subline = when {
        showsTrial && plan.introOfferLabel != null -> plan.introOfferLabel!!.replaceFirstChar(Char::uppercaseChar)
        perWeek != null -> "Just $perWeek/week"
        else -> null
    }
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Geo.cardRadius))
            .background(palette.cardSurface)
            .border(2.dp, if (isSelected) VitalsColors.caloriesPrimary else Color.Transparent, RoundedCornerShape(Geo.cardRadius))
            .tappable("${plan.displayName} ${plan.priceLabel}", onClick = onClick)
            .semantics { contentDescription = "${plan.displayName}, ${plan.priceLabel}${if (isSelected) ", selected" else ""}" }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(22.dp).border(2.dp, if (isSelected) VitalsColors.caloriesPrimary else palette.textTertiary.copy(alpha = 0.6f), CircleShape), contentAlignment = Alignment.Center) {
            if (isSelected) Box(Modifier.size(12.dp).clip(CircleShape).background(VitalsColors.caloriesPrimary))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(plan.displayName, style = Type.headline, color = palette.textPrimary)
                val badge = if (savings != null) "SAVE $savings%" else if (isBestValue) "BEST VALUE" else null
                if (badge != null) {
                    Text(
                        badge, style = Type.rounded(10.sp, FontWeight.Bold).copy(letterSpacing = 0.4.sp), color = Color.White,
                        modifier = Modifier.clip(CircleShape).background(VitalsColors.stepsPrimary).padding(horizontal = 7.dp, vertical = 2.dp),
                    )
                }
            }
            if (subline != null) Text(subline, style = Type.caption, color = palette.textSecondary, maxLines = 1)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(plan.priceLabel, style = Type.rounded(15.sp, FontWeight.Bold), color = palette.textPrimary, maxLines = 1)
            if (showsTrial && perWeek != null) Text("$perWeek/wk", style = Type.caption2, color = palette.textSecondary, maxLines = 1)
        }
    }
}

@Composable
private fun Footer(
    ctaTitle: String?, disclosure: String?, error: String?, restoreMessage: String?,
    purchasing: Boolean, restoring: Boolean, onPurchase: () -> Unit, onRestore: () -> Unit, context: android.content.Context,
) {
    Column(Modifier.fillMaxWidth().background(palette.background).navigationBarsPadding().padding(horizontal = Geo.gutter).padding(top = 8.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        PrimaryButton(ctaTitle ?: "Continue", onClick = onPurchase, enabled = ctaTitle != null, loading = purchasing || ctaTitle == null)
        val message = error ?: restoreMessage ?: disclosure
        if (message != null) {
            Text(message, style = Type.caption2, color = if (error != null) VitalsColors.caloriesPrimary else palette.textTertiary, textAlign = TextAlign.Center, maxLines = 4)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (restoring) "Restoring…" else "Restore", style = Type.caption, color = palette.textSecondary, modifier = Modifier.tappable("Restore purchases") { if (!restoring && !purchasing) onRestore() }.padding(6.dp))
            Text("·", style = Type.caption, color = palette.textTertiary)
            Text("Terms", style = Type.caption, color = palette.textSecondary, modifier = Modifier.tappable("Terms") { context.openUrl(Links.TERMS) }.padding(6.dp))
            Text("·", style = Type.caption, color = palette.textTertiary)
            Text("Privacy Policy", style = Type.caption, color = palette.textSecondary, modifier = Modifier.tappable("Privacy Policy") { context.openUrl(Links.PRIVACY) }.padding(6.dp))
        }
    }
}
