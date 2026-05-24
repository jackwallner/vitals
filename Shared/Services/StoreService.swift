import Foundation
import Combine
import os
@preconcurrency import RevenueCat

/// Vitals+ subscription product identifiers. Must match App Store Connect and `Vitals.storekit`.
enum VitalsProduct {
    static let lifetime = "lifetime"
    static let yearly = "yearly"
    static let monthly = "monthly"
    static let all: [String] = [lifetime, yearly, monthly]
}

enum RevenueCatConfig {
    static let apiKey = "appl_uiELZiyBHXCKzJyjqwaCbVkZRXB"
    static let proEntitlement = "Vitals+"
    static let fallbackEntitlement = "pro"
}

enum PurchaseState {
    case purchased
    case cancelled
    case pending
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
        guard let period = storeProduct.subscriptionPeriod else { return storeProduct.localizedPriceString }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.value == 1 {
            return "\(storeProduct.localizedPriceString) / \(unit)"
        } else {
            return "\(storeProduct.localizedPriceString) / \(period.value) \(unit)"
        }
    }

    var vitalsIntroOfferLabel: String? {
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
    /// drift in the RevenueCat dashboard (e.g. `Vitals+` vs `vitals+` vs `pro`).
    var hasVitalsProEntitlement: Bool {
        !entitlements.active.isEmpty
    }
}

extension Offering {
    var vitalsSortedPackages: [Package] {
        availablePackages.sorted {
            let lhsKind = $0.vitalsPackageKind
            let rhsKind = $1.vitalsPackageKind
            if lhsKind.rawValue != rhsKind.rawValue {
                return lhsKind.rawValue < rhsKind.rawValue
            }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

extension Offerings {
    var vitalsPaywallOffering: Offering? {
        offering(identifier: "default") ?? current
    }
}

@MainActor
final class StoreService: NSObject, ObservableObject {
    static let shared = StoreService()

    @Published private(set) var products: [Package] = []
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isPro: Bool = false
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var lastError: String?

    /// Per-product-identifier free-trial / intro-offer eligibility. Populated
    /// alongside `fetchProducts`. The native paywall reads this so it only
    /// advertises a free trial to users who will actually receive one — the
    /// RevenueCat-hosted paywall did this implicitly, and Apple 3.1.2 requires
    /// the offer shown to match what StoreKit will grant.
    @Published private(set) var introEligibility: [String: Bool] = [:]

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
    /// products carrying an intro offer are queried; on any failure we leave the
    /// map empty so the paywall conservatively hides trial framing rather than
    /// over-promising.
    private func refreshIntroEligibility() async {
        let identifiers = products
            .filter { $0.storeProduct.introductoryDiscount != nil }
            .map { $0.storeProduct.productIdentifier }
        guard !identifiers.isEmpty else {
            introEligibility = [:]
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: identifiers)
        introEligibility = result.mapValues { $0.status == .eligible }
    }

    /// True when this package advertises a free trial AND the user is eligible
    /// for it. Eligibility-unknown resolves to true so a transient lookup
    /// failure doesn't suppress a trial the user likely qualifies for.
    func isEligibleForIntroOffer(_ package: Package) -> Bool {
        guard package.vitalsIntroOfferLabel != nil else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? true
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
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
    }

    /// Performs a RevenueCat package purchase and updates customer info.
    @discardableResult
    func purchase(_ product: Package) async throws -> PurchaseState {
        configureIfNeeded()
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        let result = try await Purchases.shared.purchase(package: product)
        apply(customerInfo: result.customerInfo)
        if result.userCancelled {
            return .cancelled
        } else if result.customerInfo.hasVitalsProEntitlement {
            return .purchased
        } else {
            return .pending
        }
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
