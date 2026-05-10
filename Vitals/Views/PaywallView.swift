import SwiftUI
@preconcurrency import RevenueCat

/// Static URLs surfaced from the paywall — Apple requires both an EULA (we use the
/// standard one) and a Privacy Policy link before the StoreKit purchase buttons.
enum PaywallLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

struct PaywallView: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackageID: String? = nil
    @State private var purchaseError: String? = nil
    @State private var restoreMessage: String? = nil
    @State private var showSuccess = false

    private var monthlyPackage: Package? {
        store.products.first { $0.vitalsPackageKind == .monthly }
    }

    private var yearlyPackage: Package? {
        store.products.first { $0.vitalsPackageKind == .yearly }
    }

    private var lifetimePackage: Package? {
        store.products.first { $0.vitalsPackageKind == .lifetime }
    }

    private var resolvedSelection: Package? {
        if let selectedPackageID, let selected = store.products.first(where: { $0.identifier == selectedPackageID }) {
            return selected
        }
        return yearlyPackage ?? monthlyPackage ?? lifetimePackage
    }

    private var trialPitch: String? {
        if ScreenshotConfig.isEnabled && store.products.isEmpty {
            return "7-day free trial"
        }
        return [yearlyPackage, monthlyPackage].compactMap { $0?.vitalsIntroOfferLabel }.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        featureList
                        productOptions
                        ctaButton
                        legalFooter
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") {
                        Task {
                            await store.restorePurchases()
                            if store.isPro {
                                showSuccess = true
                            } else {
                                restoreMessage = store.lastError ?? "No active Vitals+ purchase was found for this Apple ID."
                            }
                        }
                    }
                    .foregroundStyle(Theme.caloriesPrimary)
                }
            }
            .task {
                if store.products.isEmpty {
                    await store.fetchProducts()
                }
                if selectedPackageID == nil {
                    selectedPackageID = resolvedSelection?.identifier
                }
            }
            .onChange(of: store.isPro) { _, isPro in
                if isPro {
                    showSuccess = true
                }
            }
            .alert("Welcome to Vitals+", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your access is active. Generate Monthly Summary PDFs and unlock Deep Trends from the History tab.")
            }
            .alert("Purchase Failed", isPresented: Binding(get: { purchaseError != nil }, set: { if !$0 { purchaseError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
            .alert("Restore Purchases", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.caloriesGradient)
                    .frame(width: 56, height: 56)
                    .shadow(color: Theme.caloriesPrimary.opacity(0.4), radius: 10, x: 0, y: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Vitals+")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            Text(trialPitch.map { "Start with a \($0) — unlock deeper insights and shareable PDF reports." } ?? "Deeper insights and shareable PDF reports for power users.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 7) {
            FeatureRow(
                icon: "doc.richtext.fill",
                title: "Monthly PDFs",
                detail: "Print-ready reports with charts and trends."
            )
            FeatureRow(
                icon: "calendar.badge.clock",
                title: "Custom-Range Reports",
                detail: "Export any date range — quarterly, year-end, or custom."
            )
            FeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Deep Trends",
                detail: "Period-over-period comparison on every history view."
            )
            FeatureRow(
                icon: "plus.forwardslash.minus",
                title: "Net Deficit",
                detail: "Calories burned minus food energy from Apple Health."
            )
            FeatureRow(
                icon: "flame.fill",
                title: "Active + Resting",
                detail: "See movement vs. metabolism breakdown in real time."
            )
            FeatureRow(
                icon: "lock.shield.fill",
                title: "Stays Private",
                detail: "Everything generated on-device. Nothing leaves your phone."
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    @ViewBuilder
    private var productOptions: some View {
        if ScreenshotConfig.isEnabled && store.products.isEmpty {
            screenshotProductCards
        } else if store.isLoadingProducts && store.products.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 24)
        } else if store.products.isEmpty {
            VStack(spacing: 8) {
                Text(store.lastError ?? "Subscriptions unavailable. Check your connection and try again.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await store.fetchProducts() }
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.caloriesPrimary)
            }
            .padding(.vertical, 16)
        } else {
            VStack(spacing: 8) {
                if let yearly = yearlyPackage {
                    ProductCard(
                        package: yearly,
                        isSelected: selectedPackageID == yearly.identifier,
                        badge: savingsBadge(monthly: monthlyPackage, yearly: yearly)
                    ) {
                        selectedPackageID = yearly.identifier
                    }
                }
                if let monthly = monthlyPackage {
                    ProductCard(
                        package: monthly,
                        isSelected: selectedPackageID == monthly.identifier,
                        badge: nil
                    ) {
                        selectedPackageID = monthly.identifier
                    }
                }
                if let lifetime = lifetimePackage {
                    ProductCard(
                        package: lifetime,
                        isSelected: selectedPackageID == lifetime.identifier,
                        badge: "One-time"
                    ) {
                        selectedPackageID = lifetime.identifier
                    }
                }
            }
        }
    }

    private var ctaButton: some View {
        VStack(spacing: 6) {
            Button {
                guard let package = resolvedSelection else { return }
                Task {
                    do {
                        _ = try await store.purchase(package)
                    } catch {
                        purchaseError = (error as NSError).localizedDescription
                    }
                }
            } label: {
                HStack {
                    if store.purchaseInFlight {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 4)
                    }
                    Text(ctaLabel)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.caloriesGradient, in: Capsule())
                .foregroundStyle(.white)
                .opacity(resolvedSelection == nil && !(ScreenshotConfig.isEnabled && store.products.isEmpty) ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled((resolvedSelection == nil && !(ScreenshotConfig.isEnabled && store.products.isEmpty)) || store.purchaseInFlight)

            if store.purchaseInFlight {
                Text("Waiting for the App Store purchase sheet…")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            } else if ScreenshotConfig.isEnabled && store.products.isEmpty {
                Text("Includes a 7-day free trial. Cancel anytime.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            } else if resolvedSelection?.vitalsPackageKind == .lifetime {
                Text("One-time purchase. No subscription or renewal.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            } else if let intro = resolvedSelection?.vitalsIntroOfferLabel {
                Text("Includes a \(intro). Cancel anytime.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            } else if resolvedSelection != nil {
                Text("Auto-renews until cancelled.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var ctaLabel: String {
        if ScreenshotConfig.isEnabled && store.products.isEmpty {
            return "Start Free Trial"
        }
        guard let package = resolvedSelection else {
            return store.isLoadingProducts ? "Loading…" : "Subscriptions Unavailable"
        }
        if package.vitalsIntroOfferLabel != nil {
            return "Start Free Trial"
        }
        if package.vitalsPackageKind == .lifetime {
            return "Buy Lifetime — \(package.storeProduct.localizedPriceString)"
        }
        return "Subscribe — \(package.storeProduct.localizedPriceString)"
    }

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text(disclaimerText)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
                Text("·")
                    .foregroundStyle(Theme.textTertiary)
                Link("Terms of Use", destination: PaywallLinks.standardEULA)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.caloriesPrimary)
        }
    }

    private var disclaimerText: String {
        "Payment will be charged to your Apple ID account at confirmation of purchase. Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings → Apple ID → Subscriptions. Lifetime access is a one-time purchase."
    }

    // MARK: - Helpers

    private var screenshotProductCards: some View {
        VStack(spacing: 8) {
            ScreenshotProductCard(
                name: "Yearly",
                price: "$14.99 / year",
                badge: "Save 38%",
                introLabel: "7-day free trial",
                isSelected: true
            )
            ScreenshotProductCard(
                name: "Monthly",
                price: "$1.99 / month",
                badge: nil,
                introLabel: "7-day free trial",
                isSelected: false
            )
            ScreenshotProductCard(
                name: "Lifetime",
                price: "$29.99",
                badge: "One-time",
                introLabel: nil,
                isSelected: false
            )
        }
    }

    private func savingsBadge(monthly: Package?, yearly: Package?) -> String? {
        guard let monthly, let yearly else { return nil }
        let monthlyDouble = NSDecimalNumber(decimal: monthly.storeProduct.price).doubleValue
        let yearlyDouble = NSDecimalNumber(decimal: yearly.storeProduct.price).doubleValue
        let monthlyAnnualized = monthlyDouble * 12
        guard monthlyAnnualized > 0 else { return nil }
        let savings = (monthlyAnnualized - yearlyDouble) / monthlyAnnualized
        let pct = Int((savings * 100).rounded())
        guard pct >= 5 else { return nil }
        return "Save \(pct)%"
    }
}

// MARK: - Subviews

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.caloriesPrimary)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ProductCard: View {
    let package: Package
    let isSelected: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Theme.caloriesPrimary : Theme.textTertiary.opacity(0.4), lineWidth: 2)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Theme.caloriesPrimary)
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(package.vitalsDisplayName)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.caloriesPrimary.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.caloriesPrimary)
                        }
                    }
                    Text(package.vitalsPriceLabel)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    if let intro = package.vitalsIntroOfferLabel {
                        Text(intro + " — then renews")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.caloriesPrimary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ScreenshotProductCard: View {
    let name: String
    let price: String
    let badge: String?
    let introLabel: String?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .stroke(isSelected ? Theme.caloriesPrimary : Theme.textTertiary.opacity(0.4), lineWidth: 2)
                    .frame(width: 18, height: 18)
                if isSelected {
                    Circle()
                        .fill(Theme.caloriesPrimary)
                        .frame(width: 10, height: 10)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.caloriesPrimary.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.caloriesPrimary)
                    }
                }
                Text(price)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                if let intro = introLabel {
                    Text("\(intro) — then renews")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Theme.caloriesPrimary : Color.clear, lineWidth: 2)
        )
    }
}
