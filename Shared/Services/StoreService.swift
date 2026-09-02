import Combine
import Foundation
import os
import WidgetKit

@preconcurrency import RevenueCat

/// Vitals+ subscription product identifiers. Must match App Store Connect and `Vitals.storekit`.
enum VitalsProduct {
    static let lifetime = "lifetime"
    static let yearly = "yearly"
    static let monthly = "monthly"
    static let all: [String] = [lifetime, yearly, monthly]
    static let identifiers = [
        "com.jackwallner.vitals.plus.lifetime",
        "com.jackwallner.vitals.yearly",
        "com.jackwallner.vitals.monthly",
    ]
}

enum RevenueCatConfig {
    #if DEBUG
    static let apiKey = "test_vTWUOqDAlDjyOpIAeDZiFCsmqFQ"
    #else
    static let apiKey = "appl_uiELZiyBHXCKzJyjqwaCbVkZRXB"
    #endif
    /// The entitlement identifier RevenueCat actually ships in `CustomerInfo`.
    /// It is the dashboard *lookup key*, not the display name: every paying
    /// customer on this project holds `entl05bb1ab663`, whose lookup key is the
    /// string below and whose display name is the much shorter "Vitals+".
    ///
    /// This constant is documentation, not a gate. See `hasVitalsProEntitlement`
    /// for why the check stays permissive. It replaces two unused constants,
    /// `proEntitlement = "Vitals+"` and `fallbackEntitlement = "pro"`, that named
    /// no entitlement this project has ever had. Gating on either would have
    /// revoked Vitals+ from every subscriber.
    static let proEntitlementIdentifier = "Total Calories - Daily Tracker Vitals+"
}

/// What actually happened when the customer tapped buy.
///
/// `pending` and `unavailable` are deliberately not folded into `purchased`.
/// A deferred transaction (Ask to Buy, SCA challenge, a StoreKit queue that has
/// not settled) is not an entitlement, and a build that cannot reach RevenueCat
/// never presented a purchase at all. Treating either as success dismisses the
/// pitch on someone who has no access, and counts a conversion that did not
/// happen — which corrupts the numerator of every paywall experiment.
enum PurchaseState {
    /// The expected entitlement is active right now.
    case purchased
    /// The user backed out of Apple's confirm sheet.
    case cancelled
    /// StoreKit accepted the transaction but the entitlement is not active yet.
    /// The purchase surface must stay up and say so.
    case pending
    /// Purchases cannot run in this process (RevenueCat is not configured).
    /// Callers should route to a surface that can recover, not report success.
    case unavailable
}

enum RevenueCatPackageKind: Int {
    case lifetime = 0
    case yearly = 1
    case monthly = 2
    case other = 3
}

extension RevenueCatPackageKind {
    init(package: Package) {
        switch package.packageType {
        case .lifetime:
            self = .lifetime
        case .annual:
            self = .yearly
        case .monthly:
            self = .monthly
        default:
            let identifiers = [package.identifier, package.storeProduct.productIdentifier].map { $0.lowercased() }
            if identifiers.contains(where: { $0.contains(VitalsProduct.lifetime) }) {
                self = .lifetime
            } else if identifiers.contains(where: { $0.contains(VitalsProduct.yearly) || $0.contains("annual") }) {
                self = .yearly
            } else if identifiers.contains(where: { $0.contains(VitalsProduct.monthly) }) {
                self = .monthly
            } else {
                self = .other
            }
        }
    }
}

extension Package {
    var vitalsPriceAmount: Decimal {
        return storeProduct.price
    }

    var vitalsLocalizedPriceString: String {
        return storeProduct.localizedPriceString
    }

    var vitalsPackageKind: RevenueCatPackageKind {
        RevenueCatPackageKind(package: self)
    }

    var vitalsDisplayName: String {
        switch vitalsPackageKind {
        case .lifetime:
            return "Lifetime"
        case .yearly:
            return "Yearly"
        case .monthly:
            return "Monthly"
        case .other:
            return storeProduct.localizedTitle
        }
    }

    var vitalsPriceLabel: String {
        guard let period = storeProduct.subscriptionPeriod else { return vitalsLocalizedPriceString }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.value == 1 {
            return "\(vitalsLocalizedPriceString) / \(unit)"
        } else {
            return "\(vitalsLocalizedPriceString) / \(period.value) \(unit)"
        }
    }

    /// Per-week equivalent of the recurring price, e.g. "$0.29". Drives the
    /// "just 33¢/day" style anchoring that lifts annual-plan adoption — we show
    /// it on the annual card so the headline yearly figure feels small.
    var vitalsPricePerWeekLabel: String? {
        guard storeProduct.subscriptionPeriod != nil else { return nil }
        return formattedEquivalent(divisor: vitalsPackageKind == .yearly ? 52 : 4.345)
    }

    /// Per-month equivalent of the recurring price, e.g. "$1.25". Powers the
    /// deal-framing "just $1.25/month, billed yearly" value line on the passive
    /// trial sheet so the annual figure feels small. nil for non-subscriptions.
    var vitalsPricePerMonthLabel: String? {
        guard storeProduct.subscriptionPeriod != nil else { return nil }
        return formattedEquivalent(divisor: vitalsPackageKind == .yearly ? 12 : 1)
    }

    private func formattedEquivalent(divisor: Decimal) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = storeProduct.priceFormatter?.locale ?? Locale(identifier: "en_US")
        return formatter.string(from: (vitalsPriceAmount / divisor) as NSDecimalNumber)
    }

    /// Number of free-trial days this package grants (P1W → 7), or nil if it
    /// carries no free trial. Used by the trial badge and CTA copy.
    var vitalsTrialDayCount: Int? {
        #if DEBUG && targetEnvironment(simulator)
        if RevenueCatConfig.apiKey.hasPrefix("test_"),
           vitalsPackageKind == .monthly || vitalsPackageKind == .yearly {
            return 7
        }
        #endif
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    var vitalsIntroOfferLabel: String? {
        #if DEBUG && targetEnvironment(simulator)
        if RevenueCatConfig.apiKey.hasPrefix("test_"),
           vitalsPackageKind == .monthly || vitalsPackageKind == .yearly {
            return "7-day free trial"
        }
        #endif
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.unit == .week {
            return "\(period.value * 7)-day free trial"
        } else {
            return "\(period.value)-\(unit.dropLast(period.value == 1 ? 0 : 1)) free trial"
        }
    }
}

extension CustomerInfo {
    /// Vitals only ships a single premium tier, so any active entitlement unlocks
    /// Vitals+. This is intentionally permissive: it survives renames or casing
    /// drift in the RevenueCat dashboard.
    ///
    /// Deliberately *not* narrowed to `RevenueCatConfig.proEntitlementIdentifier`.
    /// The project has exactly one active entitlement, and all six products
    /// (three App Store, three Test Store) grant it, so "any active entitlement"
    /// and "Vitals+ is active" are the same set today. Narrowing buys nothing and
    /// risks everything: the identifier is a long lookup key that is easy to get
    /// wrong, and one wrong string here silently revokes Pro for every paying
    /// customer, on a path no test exercises because tests run against the Test
    /// Store. If a second entitlement is ever added to the project, narrow this
    /// then, and verify against a real subscriber's `CustomerInfo` first.
    var hasVitalsProEntitlement: Bool {
        !entitlements.active.isEmpty
    }
}

extension Offering {
    var vitalsSortedPackages: [Package] {
        func rank(_ kind: RevenueCatPackageKind) -> Int {
            switch kind {
            case .yearly: return 0
            case .monthly: return 1
            case .lifetime: return 2
            case .other: return 3
            }
        }
        return availablePackages.sorted {
            let lhsKind = $0.vitalsPackageKind
            let rhsKind = $1.vitalsPackageKind
            if rank(lhsKind) != rank(rhsKind) {
                return rank(lhsKind) < rank(rhsKind)
            }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

extension Offerings {
    /// Experiments and Targeting assign `current`. Pinning `"default"` by name
    /// threw those assignments away, so the native paywall could never A/B.
    var vitalsPaywallOffering: Offering? {
        current ?? offering(identifier: "default")
    }
}

extension Offering {
    var vitalsUpgradeTabVariant: PaywallUIVariant {
        PaywallUIVariant.from(metadata: metadata)
    }

    var vitalsOnboardingPitchRouting: OnboardingPitchRouting {
        OnboardingPitchRouting.from(metadata: metadata)
    }
}

@MainActor
final class StoreService: NSObject, ObservableObject {
    static let shared = StoreService()

    @Published private(set) var products: [Package] = []
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isPro: Bool = false {
        didSet {
            guard oldValue != isPro else { return }
            // Mirror the entitlement into the App Group so extensions (the TDEE
            // widget) can gate the paid figure without a StoreKit round-trip,
            // then nudge widget timelines to re-render against the new state.
            StoreService.cachedProDefaults?.set(isPro, forKey: StoreService.cachedProKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// App Group key mirroring the live `isPro` entitlement for widget gating.
    /// `nonisolated` because the widget and complication timeline providers read
    /// it off the main actor, and an immutable String has nothing to isolate.
    nonisolated static let cachedProKey = "isProCached"
    private static let cachedProDefaults = UserDefaults(suiteName: vitalsAppGroupID)
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var lastError: String?

    /// Per-product-identifier free-trial / intro-offer eligibility. Populated
    /// alongside `fetchProducts`. The native paywall reads this so it only
    /// advertises a free trial to users who will actually receive one — the
    /// RevenueCat-hosted paywall did this implicitly, and Apple 3.1.2 requires
    /// the offer shown to match what StoreKit will grant.
    @Published private(set) var introEligibility: [String: Bool] = [:]
    /// True after the first eligibility check finishes (success or empty). Until
    /// then, trial copy stays off so we never promise a used-trial user a free week.
    @Published private(set) var introEligibilityResolved: Bool = false

    #if DEBUG
    /// Mirror of `PaywallVariantOverride.current`, published so the Upgrade tab
    /// actually redraws when the hidden rotator advances an arm. DEBUG only,
    /// with the rotator itself: a Release build draws the arm RevenueCat
    /// assigned and has no way to be talked out of it.
    ///
    /// The rotator used to write UserDefaults and nothing else, and
    /// `upgradeTabVariant` read that store directly. UserDefaults is not an
    /// observation source: SwiftUI had no reason to re-evaluate the paywall, so
    /// the arm changed in storage, the toast reported the new name, and the
    /// screen kept drawing the old layout until some unrelated `@Published`
    /// (an entitlement refresh, intro eligibility landing) happened to
    /// invalidate the view. That is the "it says feature_led but I'm still
    /// looking at catalog" report, and why an arm sometimes appeared minutes
    /// later. Seeded from storage so an override survives a relaunch.
    @Published private(set) var manualVariantOverride: PaywallUIVariant? = PaywallVariantOverride.current
    #endif

    private let logger = Logger(subsystem: "com.jackwallner.vitals", category: "Store")
    private var isConfigured = false
    /// Dedupes session-scoped paywall impressions (e.g. the Vitals+ tab, which
    /// the user can re-select many times per launch).
    private var paywallImpressionsThisSession: Set<String> = []

    private override init() {}

    /// Call once on app launch to configure RevenueCat and hydrate `isPro`.
    /// The initial customer info fetch uses `.fetchCurrent` to bypass any stale cache
    /// from a previous install — critical for sandbox testing where the purchase
    /// history may have been cleared but the RevenueCat cache on-device has not.
    func start() {
        configureIfNeeded()
        #if DEBUG
        if ScreenshotConfig.wantsPremiumActive {
            isPro = true
        }
        #endif
        Task { await updateCustomerProductStatus(fetchPolicy: .fetchCurrent) }
        Task { await fetchProducts() }
    }

    func fetchProducts() async {
        configureIfNeeded()
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        #if DEBUG
        if DebugLaunchConfig.failProductLoad {
            currentOffering = nil
            products = []
            lastError = "Couldn't load subscription options. Check your connection and try again."
            return
        }
        #endif
        guard isConfigured else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.vitalsPaywallOffering
            currentOffering = offering
            products = offering?.vitalsSortedPackages ?? []
            lastError = nil
            await refreshIntroEligibility()
        } catch {
            logger.error("Product fetch failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't load subscription options. Check your connection and try again."
        }
    }

    /// Resolves StoreKit intro-offer eligibility for the loaded products. Only
    /// products carrying an intro offer are queried; on any failure we mark
    /// resolved with an empty map so callers hide trial framing rather than
    /// over-promising.
    func refreshIntroEligibility() async {
        #if DEBUG
        // Checked before the simulator shortcut below: an explicit "pretend the
        // trial is spent" override has to win, or the used-trial copy can't be
        // exercised on the same simulator that fakes eligibility for everyone.
        if ScreenshotConfig.forceIntroIneligible {
            introEligibility = Dictionary(
                uniqueKeysWithValues: products.map { ($0.storeProduct.productIdentifier, false) }
            )
            introEligibilityResolved = true
            return
        }
        #endif
        #if DEBUG && targetEnvironment(simulator)
        if RevenueCatConfig.apiKey.hasPrefix("test_") {
            introEligibility = Dictionary(uniqueKeysWithValues: products.compactMap { package in
                package.vitalsIntroOfferLabel == nil ? nil : (package.storeProduct.productIdentifier, true)
            })
            introEligibilityResolved = true
            return
        }
        #endif
        let identifiers = products
            .filter { $0.storeProduct.introductoryDiscount != nil }
            .map { $0.storeProduct.productIdentifier }
        guard !identifiers.isEmpty else {
            introEligibility = [:]
            introEligibilityResolved = true
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: identifiers)
        introEligibility = result.mapValues { $0.status == .eligible }
        introEligibilityResolved = true
    }

    /// True when this package advertises a free trial AND the user is eligible
    /// for it. Until eligibility resolves, returns false so we never advertise a
    /// trial StoreKit will not grant (used-trial / sandbox-exhausted accounts).
    func isEligibleForIntroOffer(_ package: Package) -> Bool {
        guard package.vitalsIntroOfferLabel != nil else { return false }
        #if DEBUG
        if ScreenshotConfig.forceIntroIneligible { return false }
        #endif
        guard introEligibilityResolved else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? false
    }

    /// Intro label only when the user will actually receive the trial.
    func eligibleIntroLabel(for package: Package) -> String? {
        guard isEligibleForIntroOffer(package) else { return nil }
        return package.vitalsIntroOfferLabel
    }

    /// True when the yearly plan can honestly be pitched as a free trial.
    var canPitchFreeTrial: Bool {
        guard let yearly = yearlyPackage else { return false }
        return isEligibleForIntroOffer(yearly)
    }

    /// The yearly package — the one-tap conversion target. StoreKit applies the
    /// free trial automatically when eligible; ineligible users pay the yearly
    /// price on the same product. nil until `fetchProducts` completes.
    var yearlyPackage: Package? {
        products.first { $0.vitalsPackageKind == .yearly }
    }

    /// The package a one-tap pitch buys. Yearly when it's loaded; otherwise
    /// whatever carries an intro offer, then whatever loaded at all, so the
    /// trial sheet never renders a dead button. nil until products load.
    var conversionPackage: Package? {
        yearlyPackage
            ?? products.first { $0.vitalsIntroOfferLabel != nil }
            ?? products.first
    }

    /// Annual saving vs. paying monthly for a year, as a whole percent. nil
    /// unless both plans are loaded and annual is actually cheaper — the badge
    /// it drives must never quote a number we can't stand behind.
    var annualSavingsPercent: Int? {
        guard let yearly = yearlyPackage, let monthly = monthlyPackage else { return nil }
        let annualized = (monthly.vitalsPriceAmount as NSDecimalNumber).doubleValue * 12
        let yearlyPrice = (yearly.vitalsPriceAmount as NSDecimalNumber).doubleValue
        guard annualized > 0, yearlyPrice > 0 else { return nil }
        let pct = Int(((annualized - yearlyPrice) / annualized * 100).rounded())
        return pct > 0 ? pct : nil
    }

    /// The lower-commitment onboarding target. The full paywall still leads
    /// with yearly and its quantified savings.
    var monthlyPackage: Package? {
        products.first { $0.vitalsPackageKind == .monthly }
    }

    /// The package the onboarding one-tap CTA buys. Yearly: Health & Fitness sells
    /// 68% annual, the highest share of any category, and yearly renews at 86.4%
    /// against monthly's 39.2%. Kept behind one accessor so the arm can be moved
    /// to an offering-driven experiment without touching the views.
    var onboardingTrialPackage: Package? { yearlyPackage }

    /// CTA label for the direct onboarding purchase.
    var onboardingTrialCTALabel: String {
        guard let package = onboardingTrialPackage else { return "Continue with Vitals+" }
        return VitalsConversionCopy.ctaLabel(
            trialLabel: package.vitalsIntroOfferLabel,
            priceLabel: package.vitalsPriceLabel,
            eligibleForTrial: isEligibleForIntroOffer(package)
        )
    }

    /// Apple 3.1.2 disclosure for the onboarding purchase.
    ///
    /// Uses the shorter renewal clause: the full one ran to three dense grey
    /// lines directly above the button, which is the single busiest thing on the
    /// page and pushed the CTA down. This still names the trial, the price, that
    /// it auto-renews, and where to cancel, which is what 3.1.2 asks for.
    var onboardingTrialDisclosureText: String? {
        guard let package = onboardingTrialPackage else { return nil }
        return VitalsConversionCopy.disclosure(
            trialLabel: package.vitalsIntroOfferLabel,
            priceLabel: package.vitalsPriceLabel,
            eligibleForTrial: isEligibleForIntroOffer(package),
            renewClause: "Auto-renews unless cancelled 24h before it ends. Cancel in Settings."
        )
    }

    /// Short CTA for milestone / What's New capsules.
    var shortConversionCTALabel: String {
        VitalsConversionCopy.shortCTALabel(eligibleForTrial: canPitchFreeTrial)
    }

    /// Native Upgrade-tab layout from offering metadata. Missing key → catalog,
    /// the layout that ships as the default. See `PaywallUIVariant`.
    var upgradeTabVariant: PaywallUIVariant {
        #if DEBUG
        if let override = DebugLaunchConfig.upgradeTabOverride { return override }
        // Set by the hidden gesture on the Upgrade tab. Read the published
        // mirror, not UserDefaults, see the property. Neither exists in a
        // Release build, so nothing but RevenueCat picks the arm in the wild.
        if let manual = manualVariantOverride { return manual }
        #endif
        return currentOffering?.vitalsUpgradeTabVariant ?? .catalog
    }

    /// The allocation rules currently in force, straight off the offering.
    /// `.disabled` when RevenueCat has not answered yet or carries no table,
    /// which draws the shipping pitch rather than entering a test blind.
    var onboardingPitchRouting: OnboardingPitchRouting {
        currentOffering?.vitalsOnboardingPitchRouting ?? .disabled
    }

    /// Which onboarding pitch to draw for this customer, given their answer to
    /// the food question. Stable for a given RevenueCat id and salt, so the arm
    /// does not change if onboarding is restarted.
    ///
    /// The last drawn value is mirrored into `ConversionDiagnostics` rather than
    /// returned and forgotten: what matters for reading the test is the arm that
    /// actually rendered, which is not always the arm the table nominated.
    func onboardingPitchVariant(logsFood: Bool?) -> OnboardingPitchVariant {
        #if DEBUG
        if let override = DebugLaunchConfig.onboardingPitchOverride { return override }
        #endif
        let resolved = onboardingPitchRouting.variant(
            forID: onboardingAssignmentID,
            logsFood: logsFood
        )
        ConversionDiagnostics.recordOnboardingVariant(resolved.rawValue)
        return resolved
    }

    /// The id the arm is hashed from. RevenueCat's app user id is the right
    /// choice because it survives a reinstall that restores the same customer,
    /// so a returning user is not silently reassigned mid-test.
    private var onboardingAssignmentID: String {
        guard isConfigured else { return "unconfigured" }
        return Purchases.shared.appUserID
    }

    #if DEBUG
    /// Advance the hidden rotator one arm and publish the change.
    ///
    /// Persistence still lives in `PaywallVariantOverride`; this only makes the
    /// result observable. Assigning the mirror is the part that repaints the
    /// tab, so the rotator must go through here rather than calling
    /// `PaywallVariantOverride.advance()` directly.
    @discardableResult
    func advanceVariantOverride() -> PaywallUIVariant? {
        let next = PaywallVariantOverride.advance()
        manualVariantOverride = next
        return next
    }
    #endif

    /// True once the purchase button can name the action without flashing
    /// "Continue" into "Start Free Trial".
    var conversionCTAReady: Bool {
        guard let package = conversionPackage else { return false }
        if package.vitalsIntroOfferLabel != nil { return introEligibilityResolved }
        return true
    }

    /// Full Apple-3.1.2 auto-renew disclosure for the yearly plan.
    var yearlyCTADisclosureText: String? {
        guard let yearly = yearlyPackage else { return nil }
        return VitalsConversionCopy.disclosure(
            trialLabel: yearly.vitalsIntroOfferLabel,
            priceLabel: yearly.vitalsPriceLabel,
            eligibleForTrial: isEligibleForIntroOffer(yearly)
        )
    }

    /// Compact sheet disclosure under the trial-offer CTA.
    var yearlySheetDisclosureText: String? {
        guard let yearly = yearlyPackage else { return nil }
        return VitalsConversionCopy.sheetDisclosure(
            trialLabel: yearly.vitalsIntroOfferLabel,
            priceLabel: yearly.vitalsPriceLabel,
            eligibleForTrial: isEligibleForIntroOffer(yearly)
        )
    }

    /// Puts the one attribute RevenueCat needs *before* it assigns an offering
    /// onto the customer: whether this person logs food anywhere Health can see.
    ///
    /// `syncConversionAttributes()` already carries `logs_food`, but it stays
    /// silent until at least one pitch has been counted, which is after the
    /// assignment this answer is supposed to steer. Audience targeting is
    /// evaluated when offerings are fetched, so an experiment split by food
    /// logging needs the attribute on the customer at the moment they answer
    /// the onboarding question, not at the moment they first see a paywall.
    ///
    /// The refetch afterwards re-asks with the attribute in place. RevenueCat
    /// caches offerings for a few minutes, so a customer who reaches the
    /// Upgrade tab inside that window can still be served the assignment made
    /// before the answer landed; the next cold launch corrects it.
    func recordLogsFood(_ logsFood: Bool) {
        configureIfNeeded()
        guard isConfigured else { return }
        #if DEBUG
        if ScreenshotConfig.isEnabled { return }
        #endif
        Purchases.shared.attribution.setAttributes(["logs_food": logsFood ? "true" : "false"])
        Task { await fetchProducts() }
    }

    /// Mirrors the on-device conversion record onto the RevenueCat customer.
    ///
    /// Attributes rather than extra impressions: RevenueCat treats every
    /// impression id as a paywall encounter, so funnel steps sent that way would
    /// drive the encounter rate to 100% and destroy the one server-side number
    /// that currently works. Attributes stay off the charts and are readable per
    /// customer.
    func syncConversionAttributes() {
        guard isConfigured else { return }
        #if DEBUG
        if ScreenshotConfig.isEnabled { return }
        #endif
        var attributes = ConversionDiagnostics.subscriberAttributes
        guard !attributes.isEmpty else { return }
        // Which arm this customer is actually rendering. RevenueCat splits the
        // experiment by offering on its own, but that says which offering they
        // were assigned, not which layout this binary knew how to draw: a build
        // older than the arm falls back to catalog and would otherwise be
        // counted as having seen the treatment.
        attributes["paywall_variant"] = upgradeTabVariant.rawValue
        if let offering = currentOffering?.identifier {
            attributes["offering_id"] = offering
        }
        Purchases.shared.attribution.setAttributes(attributes)
    }

    func purchaseCancelledMessage(for package: Package) -> String {
        VitalsConversionCopy.purchaseCancelledMessage(eligibleForTrial: isEligibleForIntroOffer(package))
    }

    func purchaseFailedMessage(for package: Package) -> String {
        VitalsConversionCopy.purchaseFailedMessage(eligibleForTrial: isEligibleForIntroOffer(package))
    }

    func purchasePendingMessage(for package: Package) -> String {
        VitalsConversionCopy.purchasePendingMessage(eligibleForTrial: isEligibleForIntroOffer(package))
    }

    /// Reports a custom-paywall impression to RevenueCat so the native paywall
    /// still feeds RC's impression count, conversion %, and experiment
    /// enrollment (the RevenueCat-hosted UI did this automatically; there is no
    /// custom-paywall *close* event in the SDK, so conversion is derived from
    /// impression-vs-purchase). `id` distinguishes entry points.
    ///
    /// - Parameter oncePerSession: When `true`, the same `id` is only sent once
    ///   per app launch. Use for the Vitals+ tab, where `onChange(of: selectedTab)`
    ///   would otherwise fire on every revisit. Sheet presentations should pass
    ///   `false` so each open counts as its own impression.
    func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        configureIfNeeded()
        #if DEBUG
        if ScreenshotConfig.isEnabled { return }
        #endif
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        // Counted whether or not RevenueCat is configured: the on-device tally
        // is the thing that answers "how many pitches before they bought", and
        // it has to survive a launch where configuration failed.
        ConversionDiagnostics.recordPitchView(impressionID: id)
        syncConversionAttributes()
        guard isConfigured else { return }
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
    }

    /// Performs a RevenueCat package purchase and updates customer info.
    @discardableResult
    func purchase(_ product: Package) async throws -> PurchaseState {
        configureIfNeeded()
        guard isConfigured else { return .unavailable }
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        let startedTrial = isEligibleForIntroOffer(product)
        let result = try await Purchases.shared.purchase(package: product)
        apply(customerInfo: result.customerInfo)
        if result.userCancelled {
            return .cancelled
        }
        // The entitlement check gates the conversion record, not the other way
        // round. A deferred transaction that later fails would otherwise be
        // frozen into the funnel as a sale, and there is no second write to
        // take it back: recordConversion only ever records the first one.
        guard result.customerInfo.hasVitalsProEntitlement else {
            syncConversionAttributes()
            return .pending
        }
        // Freeze what the funnel looked like at the moment of sale: which
        // surface was last on screen, and how many pitches came before it.
        ConversionDiagnostics.recordConversion(
            plan: String(describing: product.vitalsPackageKind),
            startedTrial: startedTrial,
            variant: upgradeTabVariant.rawValue,
            offeringID: currentOffering?.identifier
        )
        syncConversionAttributes()
        return .purchased
    }

    /// Re-checks RevenueCat customer info so cancellations / billing failures flip `isPro` off promptly.
    /// Uses `.fetchCurrent` to bypass the local cache and get the latest entitlement state from RevenueCat's servers.
    func updateCustomerProductStatus(fetchPolicy: CacheFetchPolicy = .default) async {
        configureIfNeeded()
        #if DEBUG
        if ScreenshotConfig.wantsPremiumActive {
            isPro = true
            return
        }
        #endif
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo(fetchPolicy: fetchPolicy)
            apply(customerInfo: info)
            lastError = nil
        } catch {
            logger.error("Customer info refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't refresh your subscription status. Check your connection and try again."
        }
    }

    func restorePurchases() async {
        configureIfNeeded()
        lastError = nil
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
            lastError = isPro ? nil : "No active Vitals+ purchase was found for this Apple ID."
        } catch {
            logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't restore purchases. Try again."
        }
    }

    func apply(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        #if DEBUG
        // Capture runs force `isPro` on in `start()`. RevenueCat configures with
        // the test key on simulator and pushes anonymous customer info a moment
        // later, which has no entitlements: without this guard that push flips
        // `isPro` back off mid-capture, and DashboardView's isPro observer then
        // switches Net Deficit and Macros off with it. That race is why premium
        // scenes sometimes rendered in the free state.
        if ScreenshotConfig.wantsPremiumActive { return }
        #endif
        let activeKeys = customerInfo.entitlements.active.keys.sorted().joined(separator: ", ")
        let allKeys = customerInfo.entitlements.all.keys.sorted().joined(separator: ", ")
        logger.info("Applied customerInfo — active: [\(activeKeys, privacy: .public)] all: [\(allKeys, privacy: .public)]")
        let hasActiveSubscription = customerInfo.hasVitalsProEntitlement
        if isPro != hasActiveSubscription {
            isPro = hasActiveSubscription
            logger.info("isPro updated to \(hasActiveSubscription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if targetEnvironment(simulator)
        guard RevenueCatConfig.apiKey.hasPrefix("test_") else { return }
        #endif
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        Purchases.shared.delegate = self
        isConfigured = true
    }
}

extension StoreService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            StoreService.shared.apply(customerInfo: customerInfo)
        }
    }
}
