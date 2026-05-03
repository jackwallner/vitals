import Foundation
import StoreKit
import Combine
import os

/// Vitals+ subscription product identifiers. Must match App Store Connect and `Vitals.storekit`.
enum VitalsProduct {
    static let monthly = "com.jackwallner.vitals.plus.monthly"
    static let yearly = "com.jackwallner.vitals.plus.yearly"
    static let all: [String] = [monthly, yearly]
}

@MainActor
final class StoreService: ObservableObject {
    static let shared = StoreService()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro: Bool = false
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.jackwallner.vitals", category: "Store")

    private init() {}

    /// Call once on app launch — starts the long-running Transaction.updates listener and
    /// hydrates `isPro` from current entitlements.
    func start() {
        if updatesTask == nil {
            updatesTask = Task(priority: .background) { [weak self] in
                guard let self else { return }
                for await result in Transaction.updates {
                    await self.handle(transactionResult: result)
                }
            }
        }
        Task { await updateCustomerProductStatus() }
        Task { await fetchProducts() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func fetchProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: VitalsProduct.all)
            // Sort: monthly first, then yearly. Stable order means the paywall doesn't
            // shuffle as products load.
            products = fetched.sorted { lhs, rhs in
                guard let lIdx = VitalsProduct.all.firstIndex(of: lhs.id),
                      let rIdx = VitalsProduct.all.firstIndex(of: rhs.id) else {
                    return lhs.id < rhs.id
                }
                return lIdx < rIdx
            }
            lastError = nil
        } catch {
            logger.error("Product fetch failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't load subscription options. Check your connection and try again."
        }
    }

    /// Performs a purchase. Returns the verified Transaction on success, nil on user cancel
    /// or pending state. Throws on unverified or system errors so the caller can present them.
    @discardableResult
    func purchase(_ product: Product) async throws -> Transaction? {
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updateCustomerProductStatus()
            return transaction
        case .userCancelled:
            return nil
        case .pending:
            // "Ask to Buy" or SCA — entitlement will arrive later via Transaction.updates.
            return nil
        @unknown default:
            return nil
        }
    }

    /// Re-checks the device's current entitlements. Call on launch and on
    /// foregrounding so cancellations / billing failures flip `isPro` off promptly.
    func updateCustomerProductStatus() async {
        var hasActiveSubscription = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if VitalsProduct.all.contains(transaction.productID) {
                if transaction.revocationDate == nil {
                    hasActiveSubscription = true
                }
            }
        }
        if isPro != hasActiveSubscription {
            isPro = hasActiveSubscription
            logger.info("isPro updated to \(hasActiveSubscription, privacy: .public)")
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateCustomerProductStatus()
            lastError = nil
        } catch {
            logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't restore purchases. Try again."
        }
    }

    // MARK: - Private

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(transactionResult) else { return }
        await transaction.finish()
        await updateCustomerProductStatus()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}

extension Product {
    /// Localized "/month" or "/year" suffix for paywall display.
    var pricePeriodLabel: String {
        guard let period = subscription?.subscriptionPeriod else { return displayPrice }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.value == 1 {
            return "\(displayPrice) / \(unit)"
        } else {
            return "\(displayPrice) / \(period.value) \(unit)"
        }
    }

    /// "7-day free trial" type string when an introductory free offer is configured.
    var introOfferLabel: String? {
        guard let intro = subscription?.introductoryOffer, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.period
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        let count: Int
        if period.unit == .week {
            count = period.value * 7
            return "\(count)-day free trial"
        } else {
            return "\(period.value)-\(unit.dropLast(period.value == 1 ? 0 : 1)) free trial"
        }
    }
}
