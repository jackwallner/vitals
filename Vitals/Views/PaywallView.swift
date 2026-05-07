import SwiftUI
import StoreKit

/// Static URLs surfaced from the paywall — Apple requires both an EULA (we use the
/// standard one) and a Privacy Policy link before the StoreKit purchase buttons.
enum PaywallLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

struct PaywallView: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductID: String? = nil
    @State private var purchaseError: String? = nil
    @State private var showSuccess = false

    private var monthlyProduct: Product? {
        store.products.first { $0.id == VitalsProduct.monthly }
    }

    private var yearlyProduct: Product? {
        store.products.first { $0.id == VitalsProduct.yearly }
    }

    private var lifetimeProduct: Product? {
        store.products.first { $0.id == VitalsProduct.lifetime }
    }

    private var resolvedSelection: Product? {
        let id = selectedProductID ?? VitalsProduct.yearly
        return store.products.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: paywallSectionSpacing) {
                            header
                            featureList
                            productOptions
                            ctaButton
                                .id("paywallCTA")
                            legalFooter
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, paywallTopPadding)
                        .padding(.bottom, 32)
                    }
                    .onAppear {
                        #if DEBUG
                        if ScreenshotConfig.wantsPaywall {
                            // Scroll so the CTA + products are both visible in the
                            // App Store screenshot. .bottom centers it lower in the
                            // viewport, leaving the products and disclaimer in frame.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(nil) {
                                    proxy.scrollTo("paywallCTA", anchor: .bottom)
                                }
                            }
                        }
                        #endif
                    }
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
                if selectedProductID == nil {
                    selectedProductID = VitalsProduct.yearly
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
                Text("Your subscription is active. Generate Monthly Summary PDFs and unlock Deep Trends from the History tab.")
            }
            .alert("Purchase Failed", isPresented: Binding(get: { purchaseError != nil }, set: { if !$0 { purchaseError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.caloriesGradient)
                    .frame(width: 84, height: 84)
                    .shadow(color: Theme.caloriesPrimary.opacity(0.4), radius: 16, x: 0, y: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Vitals+")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            Text("Deeper insights and shareable PDF reports for power users.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(
                icon: "doc.richtext.fill",
                title: "PDF Reports — Any Range",
                detail: "Print-ready summaries with charts, trends, and a daily breakdown table."
            )
            FeatureRow(
                icon: "calendar.badge.clock",
                title: "Quarterly & Annual Recaps",
                detail: "Multi-page reports auto-paginate with weekly aggregation for long ranges."
            )
            FeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Deep Trends",
                detail: "Period-over-period comparison cards on every history view."
            )
            FeatureRow(
                icon: "lock.shield.fill",
                title: "Stays Private",
                detail: "Reports are generated on-device. Nothing leaves your phone."
            )
        }
        .padding(20)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    @ViewBuilder
    private var productOptions: some View {
        #if DEBUG
        if ScreenshotConfig.wantsPaywall {
            screenshotProductOptions
        } else {
            productOptionsLive
        }
        #else
        productOptionsLive
        #endif
    }

    #if DEBUG
    private var screenshotProductOptions: some View {
        VStack(spacing: 12) {
            ScreenshotProductCard(
                title: "Vitals+ Yearly",
                priceLine: "$14.99/year",
                introLine: "7-day free trial — then renews",
                badge: "Save 37%",
                isSelected: true
            )
            ScreenshotProductCard(
                title: "Vitals+ Monthly",
                priceLine: "$1.99/month",
                introLine: "7-day free trial — then renews",
                badge: nil,
                isSelected: false
            )
            ScreenshotProductCard(
                title: "Vitals+ Lifetime",
                priceLine: "$29.99 · pay once",
                introLine: nil,
                badge: "One-time",
                isSelected: false
            )
        }
    }
    #endif

    @ViewBuilder
    private var productOptionsLive: some View {
        if store.isLoadingProducts && store.products.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 24)
        } else if store.products.isEmpty {
            VStack(spacing: 8) {
                Text(store.lastError ?? "Subscriptions unavailable.")
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
            VStack(spacing: 12) {
                if let yearly = yearlyProduct {
                    ProductCard(
                        product: yearly,
                        isSelected: selectedProductID == yearly.id,
                        badge: savingsBadge(monthly: monthlyProduct, yearly: yearly)
                    ) {
                        selectedProductID = yearly.id
                    }
                }
                if let monthly = monthlyProduct {
                    ProductCard(
                        product: monthly,
                        isSelected: selectedProductID == monthly.id,
                        badge: nil
                    ) {
                        selectedProductID = monthly.id
                    }
                }
                if let lifetime = lifetimeProduct {
                    ProductCard(
                        product: lifetime,
                        isSelected: selectedProductID == lifetime.id,
                        badge: "One-time"
                    ) {
                        selectedProductID = lifetime.id
                    }
                }
            }
        }
    }

    private var ctaButton: some View {
        VStack(spacing: 10) {
            Button {
                guard let product = resolvedSelection else { return }
                Task {
                    do {
                        _ = try await store.purchase(product)
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
                        .font(.system(.headline, design: .rounded, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.caloriesGradient, in: Capsule())
                .foregroundStyle(.white)
                .opacity(resolvedSelection == nil ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(resolvedSelection == nil || store.purchaseInFlight)

            ctaSubtitle
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var paywallSectionSpacing: CGFloat {
        #if DEBUG
        if ScreenshotConfig.wantsPaywall { return 18 }
        #endif
        return 28
    }

    private var paywallTopPadding: CGFloat {
        #if DEBUG
        if ScreenshotConfig.wantsPaywall { return 4 }
        #endif
        return 16
    }

    @ViewBuilder
    private var ctaSubtitle: some View {
        #if DEBUG
        if ScreenshotConfig.wantsPaywall {
            Text("Includes a 7-day free trial. Cancel anytime.")
        } else if let product = resolvedSelection, product.isLifetime {
            Text("One-time purchase. No subscription.")
        } else if let intro = resolvedSelection?.introOfferLabel {
            Text("Includes a \(intro). Cancel anytime.")
        } else {
            Text("Auto-renews until cancelled.")
        }
        #else
        if let product = resolvedSelection, product.isLifetime {
            Text("One-time purchase. No subscription.")
        } else if let intro = resolvedSelection?.introOfferLabel {
            Text("Includes a \(intro). Cancel anytime.")
        } else {
            Text("Auto-renews until cancelled.")
        }
        #endif
    }

    private var ctaLabel: String {
        #if DEBUG
        if ScreenshotConfig.wantsPaywall { return "Start Free Trial" }
        #endif
        guard let product = resolvedSelection else { return "Subscribe" }
        if product.isLifetime {
            return "Buy Lifetime — \(product.displayPrice)"
        }
        if product.introOfferLabel != nil {
            return "Start Free Trial"
        }
        return "Subscribe — \(product.displayPrice)"
    }

    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text(disclaimerText)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
                Text("·")
                    .foregroundStyle(Theme.textTertiary)
                Link("Terms of Use (EULA)", destination: PaywallLinks.standardEULA)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.caloriesPrimary)
        }
        .padding(.top, 4)
    }

    private var disclaimerText: String {
        #if DEBUG
        if ScreenshotConfig.wantsPaywall {
            return "Payment will be charged to your Apple ID account at confirmation of purchase. Subscription auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings → Apple ID → Subscriptions."
        }
        #endif
        if let product = resolvedSelection, product.isLifetime {
            return "Lifetime is a one-time purchase charged to your Apple ID at confirmation. It does not auto-renew. Restoring is available on any device signed in to the same Apple ID."
        }
        return "Payment will be charged to your Apple ID account at confirmation of purchase. Subscription auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings → Apple ID → Subscriptions."
    }

    // MARK: - Helpers

    private func savingsBadge(monthly: Product?, yearly: Product?) -> String? {
        guard let monthly, let yearly else { return nil }
        let monthlyDouble = NSDecimalNumber(decimal: monthly.price).doubleValue
        let yearlyDouble = NSDecimalNumber(decimal: yearly.price).doubleValue
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
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.caloriesPrimary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

#if DEBUG
private struct ScreenshotProductCard: View {
    let title: String
    let priceLine: String
    let introLine: String?
    let badge: String?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .stroke(isSelected ? Theme.caloriesPrimary : Theme.textTertiary.opacity(0.4), lineWidth: 2)
                    .frame(width: 22, height: 22)
                if isSelected {
                    Circle()
                        .fill(Theme.caloriesPrimary)
                        .frame(width: 12, height: 12)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.caloriesPrimary.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.caloriesPrimary)
                    }
                }
                Text(priceLine)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                if let introLine {
                    Text(introLine)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(isSelected ? Theme.caloriesPrimary : Color.clear, lineWidth: 2)
        )
    }
}
#endif

private struct ProductCard: View {
    let product: Product
    let isSelected: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Theme.caloriesPrimary : Theme.textTertiary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Theme.caloriesPrimary)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.caloriesPrimary.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.caloriesPrimary)
                        }
                    }
                    Text(product.isLifetime ? product.displayPrice + " · pay once" : product.pricePeriodLabel)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    if !product.isLifetime, let intro = product.introOfferLabel {
                        Text(intro + " — then renews")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(isSelected ? Theme.caloriesPrimary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
