package com.jackwallner.vitals.billing

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.vitals.BuildConfig
import com.jackwallner.vitals.data.KeyValueStore
import com.jackwallner.vitals.data.PackageKind
import com.jackwallner.vitals.data.Plan
import com.jackwallner.vitals.data.PlanPeriod
import com.jackwallner.vitals.data.PeriodUnit
import com.jackwallner.vitals.data.ReviewAccess
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.paywalls.events.CustomPaywallImpressionParams
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

enum class PurchaseOutcome { PURCHASED, PENDING, CANCELLED }

class PurchaseException(message: String) : Exception(message)

internal fun purchaseOutcome(code: PurchasesErrorCode, userCancelled: Boolean): PurchaseOutcome? = when {
    userCancelled || code == PurchasesErrorCode.PurchaseCancelledError -> PurchaseOutcome.CANCELLED
    code == PurchasesErrorCode.PaymentPendingError -> PurchaseOutcome.PENDING
    else -> null
}

internal fun restoreFailureMessage(code: PurchasesErrorCode): String =
    if (code == PurchasesErrorCode.PaymentPendingError) {
        "Google Play is still processing your payment. Vitals+ unlocks as soon as it completes."
    } else "Couldn't restore purchases. Try again."

private fun Period.toPlanPeriod(): PlanPeriod? {
    val unit = when (unit) {
        Period.Unit.DAY -> PeriodUnit.DAY
        Period.Unit.WEEK -> PeriodUnit.WEEK
        Period.Unit.MONTH -> PeriodUnit.MONTH
        Period.Unit.YEAR -> PeriodUnit.YEAR
        else -> return null
    }
    return PlanPeriod(value, unit)
}

/**
 * RevenueCat behind Vitals+. Like iOS, any active entitlement unlocks Pro, so a
 * renamed entitlement can never silently revoke a paying customer. Debug builds
 * use the Test Store key and release builds the Play key; neither runs on the
 * other. Every price and trial the paywall shows comes from the store.
 */
class StoreService(
    private val context: Context,
    private val defaults: KeyValueStore,
    private val diagnostics: ConversionDiagnostics,
) {
    private val reviewAccess = ReviewAccess(defaults, BuildConfig.PLAY_REVIEW_CODE_SHA256)
    val entitlementStatus = EntitlementStatus(defaults)
    private val entitlementActive: Boolean get() = entitlementStatus.resolution == EntitlementStatus.Resolution.ACTIVE
    private var overrideActive by mutableStateOf(BuildConfig.DEBUG && defaults.getBoolean(LOCAL_OVERRIDE))
    private var reviewGranted by mutableStateOf(reviewAccess.isGranted)

    /** The single gate the whole app reads. */
    val isPro: Boolean get() = entitlementStatus.isPro || overrideActive || reviewGranted

    var isConfigured by mutableStateOf(false)
        private set
    var isLoadingProducts by mutableStateOf(false)
        private set
    var lastError by mutableStateOf<String?>(null)
        private set
    var packages by mutableStateOf<List<Package>>(emptyList())
        private set
    var plans by mutableStateOf<List<Plan>>(emptyList())
        private set
    var hasSubscriptionHistory by mutableStateOf(false)
        private set

    /** Until customer info has answered, never promise a trial (it may already be used). */
    var introEligibilityResolved by mutableStateOf(false)
        private set

    private var offering: Offering? = null
    private var customerInfoLoaded = false
    private var isPreview = false
    private val impressionsThisSession = mutableSetOf<String>()

    // Debug and review access

    fun setLocalOverride(value: Boolean) {
        if (!BuildConfig.DEBUG) return
        defaults.putBoolean(LOCAL_OVERRIDE, value)
        overrideActive = value
    }

    /** Debug screenshots and UI tests: a local plan stack with no store behind it. */
    fun loadPreviewPlans(plans: List<Plan>, history: Boolean = false) {
        if (!BuildConfig.DEBUG) return
        this.plans = plans
        packages = emptyList()
        hasSubscriptionHistory = history
        introEligibilityResolved = true
        isConfigured = true
        isPreview = true
        lastError = null
    }

    fun activateReviewAccess(code: String): Boolean {
        if (!reviewAccess.activate(code)) return false
        reviewGranted = true
        return true
    }

    // Store

    suspend fun start() {
        if (!configureIfNeeded()) return
        refreshCustomerInfo()
        fetchProducts()
    }

    suspend fun refreshCustomerInfo() {
        if (!configureIfNeeded() || isPreview) return
        runCatching { Purchases.sharedInstance.awaitCustomerInfo() }
            .onSuccess(::apply)
            .onFailure {
                if (it is CancellationException) throw it
                entitlementStatus.refreshFailed()
            }
    }

    suspend fun fetchProducts() {
        if (!configureIfNeeded() || isPreview) return
        if (isLoadingProducts) {
            while (isLoadingProducts) delay(50)
            return
        }
        isLoadingProducts = true
        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val chosen: Offering? = offerings.all[ANDROID_OFFERING_ID] ?: offerings.current
            val loaded = chosen?.availablePackages.orEmpty().sortedWith(
                compareBy<Package> { kind(it).rank }.thenBy { it.product.id },
            )
            offering = chosen
            packages = loaded
            plans = loaded.map(::plan)
            lastError = if (loaded.isEmpty()) "Plans are temporarily unavailable. Please try again in a moment." else null
            if (!customerInfoLoaded) refreshCustomerInfo()
            introEligibilityResolved = customerInfoLoaded
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            packages = emptyList()
            plans = emptyList()
            lastError = "Couldn't load subscription options. Check your connection and try again."
        } finally {
            isLoadingProducts = false
        }
    }

    fun isEligibleForIntroOffer(plan: Plan): Boolean = plan.trial != null && introEligibilityResolved && !hasSubscriptionHistory

    val yearlyPlan: Plan? get() = plans.firstOrNull { it.kind == PackageKind.YEARLY }
    val monthlyPlan: Plan? get() = plans.firstOrNull { it.kind == PackageKind.MONTHLY }
    val canPitchFreeTrial: Boolean get() = plans.any(::isEligibleForIntroOffer)

    /** The plan the one-tap onboarding trial buys: yearly first, then monthly. */
    val onboardingPlan: Plan? get() = yearlyPlan ?: monthlyPlan ?: plans.firstOrNull { it.kind != PackageKind.LIFETIME }

    val annualSavingsPercent: Int? get() = yearlyPlan?.savingsPercent(monthlyPlan)

    val conversionCtaReady: Boolean get() = onboardingPlan != null && introEligibilityResolved

    val onboardingCtaLabel: String
        get() {
            val plan = onboardingPlan ?: return "Continue with Vitals+"
            return ConversionCopy.ctaLabel(plan.introOfferLabel, plan.priceLabel, isEligibleForIntroOffer(plan))
        }

    val onboardingDisclosure: String?
        get() {
            val plan = onboardingPlan ?: return null
            return ConversionCopy.disclosure(
                plan.introOfferLabel,
                plan.priceLabel,
                isEligibleForIntroOffer(plan),
                ConversionCopy.ONBOARDING_RENEW_CLAUSE,
            )
        }

    val sheetDisclosure: String?
        get() {
            val plan = onboardingPlan ?: return null
            return ConversionCopy.sheetDisclosure(plan.introOfferLabel, plan.priceLabel, isEligibleForIntroOffer(plan))
        }

    /** Feeds RevenueCat's paywall encounters; a custom paywall emits none of its own. */
    fun trackPaywallImpression(id: String, oncePerSession: Boolean = false) {
        if (oncePerSession && !impressionsThisSession.add(id)) return
        diagnostics.recordPitchView(id)
        if (!isConfigured || isPreview) return
        syncConversionAttributes()
        val params = offering?.let { CustomPaywallImpressionParams(id, it) } ?: CustomPaywallImpressionParams(id)
        runCatching { Purchases.sharedInstance.trackCustomPaywallImpression(params) }
    }

    fun syncConversionAttributes() {
        if (!isConfigured || isPreview) return
        val attributes = diagnostics.subscriberAttributes
        if (attributes.isEmpty()) return
        runCatching { Purchases.sharedInstance.setAttributes(attributes) }
    }

    /** A cancel is an outcome, not an error. Throws only with a user-facing message. */
    suspend fun purchase(activity: Activity, plan: Plan?): PurchaseOutcome {
        if (isPreview && plan != null) {
            setLocalOverride(true)
            return PurchaseOutcome.PURCHASED
        }
        val pkg = plan?.let { p -> packages.firstOrNull { it.identifier == p.packageId } }
        if (!configureIfNeeded() || pkg == null) throw PurchaseException(ConversionCopy.UNAVAILABLE)
        val startedTrial = isEligibleForIntroOffer(plan)
        val option = if (startedTrial) pkg.product.defaultOption else pkg.product.subscriptionOptions?.basePlan
        val params = if (option != null) {
            PurchaseParams.Builder(activity, option).presentedOfferingContext(pkg.presentedOfferingContext).build()
        } else PurchaseParams.Builder(activity, pkg).build()
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(params)
            apply(result.customerInfo)
            if (!entitlementActive) return PurchaseOutcome.PENDING
            diagnostics.recordConversion(pkg.product.id, pkg.presentedOfferingContext.offeringIdentifier)
            syncConversionAttributes()
            PurchaseOutcome.PURCHASED
        } catch (error: PurchasesTransactionException) {
            purchaseOutcome(error.code, error.userCancelled)
                ?: throw PurchaseException(ConversionCopy.purchaseFailedMessage(startedTrial))
        }
    }

    /** Play says the money moved; the entitlement can take a beat to catch up. */
    suspend fun confirmEntitlement(attempts: Int = 3): Boolean {
        if (!isConfigured) return isPro
        repeat(attempts) { attempt ->
            refreshCustomerInfo()
            if (isPro) return true
            if (attempt < attempts - 1) delay(1_200)
        }
        return isPro
    }

    /** Leaves `lastError` set when nothing was restored, like iOS. */
    suspend fun restorePurchases() {
        lastError = null
        if (isPreview) return
        if (!configureIfNeeded()) {
            lastError = ConversionCopy.UNAVAILABLE
            return
        }
        try {
            apply(Purchases.sharedInstance.awaitRestore())
            if (!entitlementActive) lastError = "No active Vitals+ purchase was found for this Google Play account."
        } catch (error: CancellationException) {
            throw error
        } catch (error: PurchasesException) {
            lastError = restoreFailureMessage(error.code)
        } catch (_: Throwable) {
            lastError = "Couldn't restore purchases. Try again."
        }
    }

    private fun apply(info: CustomerInfo) {
        customerInfoLoaded = true
        hasSubscriptionHistory = info.allExpirationDatesByProduct.isNotEmpty()
        introEligibilityResolved = plans.isNotEmpty() || packages.isNotEmpty()
        entitlementStatus.resolve(info.entitlements.active.isNotEmpty())
    }

    private fun configureIfNeeded(): Boolean {
        if (isConfigured) return true
        val key = BuildConfig.REVENUECAT_API_KEY
        if (key.isBlank()) return false
        // Never the production Play key in a debug build, and never a test key in release.
        if (BuildConfig.DEBUG && key.startsWith("goog_")) return false
        if (!BuildConfig.DEBUG && !key.startsWith("goog_")) return false
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        val builder = PurchasesConfiguration.Builder(context, key)
        // Test Store runs share one tester instead of a fresh anonymous customer
        // per install, so test runs count at most once a day in the live
        // project's New and Active Customers. Never with the Play key: real
        // buyers would share one identity.
        if (key.startsWith("test_")) builder.appUserID(QA_APP_USER_ID)
        Purchases.configure(builder.build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        isConfigured = true
        return true
    }

    private fun kind(pkg: Package): PackageKind = when (pkg.packageType) {
        PackageType.LIFETIME -> PackageKind.LIFETIME
        PackageType.ANNUAL -> PackageKind.YEARLY
        PackageType.MONTHLY -> PackageKind.MONTHLY
        else -> PackageKind.fromIdentifiers(pkg.identifier, pkg.product.id)
    }

    private val PackageKind.rank: Int
        get() = when (this) {
            PackageKind.YEARLY -> 0
            PackageKind.MONTHLY -> 1
            PackageKind.LIFETIME -> 2
            PackageKind.OTHER -> 3
        }

    private fun plan(pkg: Package): Plan {
        val price = pkg.product.price
        val free = pkg.product.subscriptionOptions?.firstOrNull { it.freePhase != null }?.freePhase
            ?: pkg.product.defaultOption?.freePhase
        return Plan(
            packageId = pkg.identifier,
            productId = pkg.product.id,
            kind = kind(pkg),
            priceMicros = price.amountMicros,
            priceFormatted = price.formatted,
            currencyCode = price.currencyCode,
            period = pkg.product.period?.toPlanPeriod(),
            trial = free?.billingPeriod?.toPlanPeriod(),
            title = pkg.product.title,
        )
    }

    companion object {
        private const val ANDROID_OFFERING_ID = "android"
        private const val QA_APP_USER_ID = "qa-android"
        private const val LOCAL_OVERRIDE = "subscription.localProOverride"
    }
}
