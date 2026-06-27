import SwiftUI
@preconcurrency import RevenueCat

/// Static URLs surfaced from the paywall — Apple requires both an EULA (we use the
/// standard one) and a Privacy Policy link before the StoreKit purchase buttons.
/// Kept here so any other surface in the app can link to the same destinations.
enum PaywallLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// A single Vitals+ capability. The one source of truth for paywall copy, so the
/// trial sheet and the full plan picker stay in sync. When a pitch is triggered
/// by tapping a specific locked feature, that feature becomes the `focus` — the
/// pitch then leads with and highlights it instead of a generic "unlock
/// everything" message.
enum PlusFeature: CaseIterable {
    case netDeficit
    case activeResting
    case energyAverages
    case deepTrends
    case customRangesPDF
    case projections
    case streaks
    case weeklyRecap
    case bodyProfile

    var icon: String {
        switch self {
        case .netDeficit: "plus.forwardslash.minus"
        case .activeResting: "flame.fill"
        case .energyAverages: "speedometer"
        case .deepTrends: "chart.line.uptrend.xyaxis"
        case .customRangesPDF: "calendar.badge.clock"
        case .projections: "scope"
        case .streaks: "flame"
        case .weeklyRecap: "calendar.badge.checkmark"
        case .bodyProfile: "figure.stand"
        }
    }

    var tint: Color {
        switch self {
        case .netDeficit: Theme.netDeficitBrand
        case .activeResting: Theme.caloriesPrimary
        case .energyAverages: Theme.caloriesPrimary
        case .deepTrends: Theme.stepsPrimary
        case .customRangesPDF: Theme.stepsSecondary
        case .projections: Theme.stepsPrimary
        case .streaks: Theme.streakPrimary
        case .weeklyRecap: Theme.caloriesPrimary
        case .bodyProfile: Theme.netDeficitBrand
        }
    }

    /// Short title for compact bullet rows (trial sheet).
    var title: String {
        switch self {
        case .netDeficit: "Net Deficit, live"
        case .activeResting: "Active vs. resting calories"
        case .energyAverages: "TDEE & BMR"
        case .deepTrends: "Deep Trends"
        case .customRangesPDF: "Custom ranges + PDF reports"
        case .projections: "End-of-day projections"
        case .streaks: "Goal streaks"
        case .weeklyRecap: "Weekly recap"
        case .bodyProfile: "Body Profile context"
        }
    }

    /// One-line supporting detail for bullet rows.
    var detail: String {
        switch self {
        case .netDeficit: "Calories burned minus food logged in Apple Health, updated all day."
        case .activeResting: "Split your burn into active and resting to see what moved the number."
        case .energyAverages: "Your maintenance calories (TDEE) and resting burn (BMR), averaged from Apple Health."
        case .deepTrends: "Every period compared head-to-head with the one before it."
        case .customRangesPDF: "Pick any window in History and export a clean summary for your coach."
        case .projections: "See where today's calories and steps will land, based on your own pace."
        case .streaks: "Track consecutive days you've hit a goal — and don't break the chain."
        case .weeklyRecap: "A Sunday-night summary of your week vs. the one before, delivered to you."
        case .bodyProfile: "Body fat and calorie context alongside your BMI. BMI stays free."
        }
    }

    /// Single-line label used in the plan picker's flat feature list.
    var featureListTitle: String {
        switch self {
        case .netDeficit: "Net Deficit, live: burned minus food logged"
        case .activeResting: "Active vs. resting calorie breakdown"
        case .energyAverages: "TDEE & BMR from your own Apple Health data"
        case .deepTrends: "Deep Trends: every period vs. the one before"
        case .customRangesPDF: "Custom date ranges + PDF reports"
        case .projections: "End-of-day projections from your own pace"
        case .streaks: "Goal streaks — keep the chain alive"
        case .weeklyRecap: "Weekly recap notification + summary"
        case .bodyProfile: "Body fat + calorie context with your BMI"
        }
    }

    /// Hero headline when this feature is the focus of the pitch.
    var pitchHeadline: String {
        switch self {
        case .netDeficit: "Net Deficit, live."
        case .activeResting: "Break down every calorie."
        case .energyAverages: "Know your TDEE & BMR."
        case .deepTrends: "See your trends, deeper."
        case .customRangesPDF: "Any range. Clean PDF reports."
        case .projections: "Know where today lands."
        case .streaks: "Keep the chain alive."
        case .weeklyRecap: "Your week, in review."
        case .bodyProfile: "Understand your body profile."
        }
    }

    /// Supporting line when this feature is the focus of the pitch.
    var pitchSubheadline: String {
        switch self {
        case .netDeficit: "See calories burned minus the food you log, updated all day, plus the rest of Vitals+."
        case .activeResting: "Split active vs. resting burn to see what's really moving your number, plus the rest of Vitals+."
        case .energyAverages: "See your maintenance calories (TDEE) and resting burn (BMR) averaged from Apple Health, plus the rest of Vitals+."
        case .deepTrends: "Compare every period head-to-head with the one before, plus the rest of Vitals+."
        case .customRangesPDF: "Pick any date window and export a polished report for your coach, plus the rest of Vitals+."
        case .projections: "See where today's calories and steps will land based on your own pace, plus the rest of Vitals+."
        case .streaks: "Track every consecutive day you hit a goal and protect your streak, plus the rest of Vitals+."
        case .weeklyRecap: "Get a Sunday-night recap of your week vs. the last one, plus the rest of Vitals+."
        case .bodyProfile: "BMI stays free. Vitals+ adds body-fat and calorie context from your own data, plus the rest of Vitals+."
        }
    }
}

/// Native, self-hosted Vitals+ paywall. Purchases still flow through
/// `StoreService.purchase` → `Purchases.shared.purchase`, so RevenueCat records
/// every transaction, trial start, and renewal exactly as it did with the
/// RevenueCat-hosted UI — only the presentation is ours now.
///
/// Dismisses itself when the user becomes Pro so callers can present this in a
/// sheet without wiring any custom completion handler.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    /// Set to `false` when rendered as tab content rather than in a sheet — the
    /// tab bar handles navigation, so a built-in close button looks off.
    var displayCloseButton: Bool = true

    /// When set (an intent-driven presentation), the list leads with and
    /// highlights this feature. `nil` for the generic Upgrade tab.
    var focus: PlusFeature? = nil

    @State private var selectedPackage: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var restoreMessage: String?
    @State private var isRestoring = false

    /// All features, with the focused one pulled to the front so the user sees
    /// what they tapped for first.
    private var orderedFeatures: [PlusFeature] {
        let base: [PlusFeature] = [.netDeficit, .projections, .streaks, .weeklyRecap, .energyAverages, .deepTrends, .customRangesPDF, .activeResting]
        guard let focus else { return base }
        return [focus] + base.filter { $0 != focus }
    }

    /// Annual savings vs. paying monthly for a year, as a whole percent. Drives
    /// the "SAVE X%" badge — loss-aversion anchoring against the monthly price.
    /// Nil unless both plans are loaded and annual is actually cheaper.
    private var annualSavingsPercent: Int? {
        guard let yearly = store.products.first(where: { $0.vitalsPackageKind == .yearly }),
              let monthly = store.products.first(where: { $0.vitalsPackageKind == .monthly })
        else { return nil }
        let annualized = (monthly.storeProduct.price as NSDecimalNumber).doubleValue * 12
        let yearlyPrice = (yearly.storeProduct.price as NSDecimalNumber).doubleValue
        guard annualized > 0, yearlyPrice > 0 else { return nil }
        let pct = Int(((annualized - yearlyPrice) / annualized * 100).rounded())
        return pct > 0 ? pct : nil
    }

    /// True when the currently selected plan will start a free trial — gates the
    /// trial-timeline section so it only shows when there's a trial to explain.
    private var selectedHasTrial: Bool {
        guard let package = selectedPackage else { return false }
        return store.isEligibleForIntroOffer(package)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if store.isLoadingProducts && store.products.isEmpty {
                loadingState
            } else if store.products.isEmpty {
                emptyState
            } else {
                content
            }

            if displayCloseButton {
                closeButton
            }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
        .task {
            if store.products.isEmpty { await store.fetchProducts() }
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: store.products.count) { _, _ in selectDefaultPackageIfNeeded() }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            LoadingBar(color: Theme.caloriesPrimary).frame(width: 180)
            Text("Loading plans…")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text("Couldn't Load Plans")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text(store.lastError ?? "Check your connection and try again.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await store.fetchProducts(); selectDefaultPackageIfNeeded() }
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.caloriesPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if displayCloseButton {
            // Sheet mode: fit on one screen — pitch is fixed, CTA pinned (no scroll).
            pitchColumn(compact: true)
                .safeAreaInset(edge: .bottom, spacing: 0) { pinnedPurchaseBar }
        } else {
            // Tab mode: pin the purchase CTA + disclosure to the bottom so it's
            // always on screen above the floating tab bar (never hidden behind
            // it) on every device size. The pitch above it scrolls.
            scrollingContent(includePurchase: false)
                .safeAreaInset(edge: .bottom, spacing: 0) { pinnedPurchaseBar }
        }
    }

    private func scrollingContent(includePurchase: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            pitchColumn(compact: false)
            if includePurchase {
                purchaseSection
            }
        }
    }

    private func pitchColumn(compact: Bool) -> some View {
        VStack(spacing: compact ? 14 : 22) {
            header(compact: compact)
            featureList(compact: compact)
            planCards
            if !compact, selectedHasTrial, let days = selectedPackage?.vitalsTrialDayCount {
                TrialTimeline(trialDays: days, priceLabel: selectedPackage?.vitalsPriceLabel)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, displayCloseButton ? 48 : 32)
        .padding(.bottom, compact ? 8 : 16)
    }

    private var pinnedPurchaseBar: some View {
        purchaseSection
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .background(.ultraThinMaterial)
    }

    private func header(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 10) {
            ZStack {
                Circle()
                    .fill(Theme.caloriesGradient)
                    .frame(width: compact ? 52 : 64, height: compact ? 52 : 64)
                    .shadow(color: Theme.caloriesPrimary.opacity(0.35), radius: 12, x: 0, y: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: compact ? 22 : 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Vitals+")
                .font(.system(compact ? .title2 : .title, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(focus?.pitchSubheadline ?? "Unlock every Vitals+ feature.")
                .font(.system(compact ? .footnote : .subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureList(compact: Bool) -> some View {
        let features = compact ? Array(orderedFeatures.prefix(3)) : orderedFeatures
        return VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            ForEach(features, id: \.self) { feature in
                let highlighted = feature == focus
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(feature.tint)
                        .frame(width: 24)
                    Text(feature.featureListTitle)
                        .font(.system(.subheadline, design: .rounded, weight: highlighted ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, highlighted ? 12 : 0)
                .padding(.vertical, highlighted ? 10 : 0)
                .background {
                    if highlighted {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(feature.tint.opacity(0.1))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planCards: some View {
        VStack(spacing: 10) {
            ForEach(store.products, id: \.identifier) { package in
                let isYearly = package.vitalsPackageKind == .yearly
                PlanCard(
                    package: package,
                    isSelected: selectedPackage?.identifier == package.identifier,
                    showsTrialBadge: store.isEligibleForIntroOffer(package),
                    isBestValue: isYearly,
                    savingsPercent: isYearly ? annualSavingsPercent : nil,
                    perWeekLabel: isYearly ? package.vitalsPricePerWeekLabel : nil
                ) {
                    selectedPackage = package
                }
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: displayCloseButton ? 8 : 12) {
            Button(action: startPurchase) {
                ZStack {
                    Text(ctaTitle)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.caloriesGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || selectedPackage == nil)

            if !displayCloseButton {
                HStack(spacing: 14) {
                    reassurancePill(icon: "checkmark.shield.fill", text: "No payment now")
                    reassurancePill(icon: "bell.badge.fill", text: "Reminder before billing")
                    reassurancePill(icon: "xmark.circle.fill", text: "Cancel anytime")
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .opacity(selectedHasTrial ? 1 : 0)
                .accessibilityHidden(!selectedHasTrial)
            }

            Text(disclosureText ?? " ")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.9)
                .frame(minHeight: 64, alignment: .top)
                .opacity(disclosureText == nil ? 0 : 1)
                .accessibilityHidden(disclosureText == nil)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: startRestore) {
                Text(isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing)

            HStack(spacing: 4) {
                Link("Terms", destination: PaywallLinks.standardEULA)
                Text("·")
                Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
            }
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(16)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func reassurancePill(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.stepsPrimary)
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Copy

    private var ctaTitle: String {
        guard let package = selectedPackage else { return "Continue" }
        if package.vitalsPackageKind == .lifetime { return "Unlock Lifetime" }
        if store.isEligibleForIntroOffer(package) { return "Start Free Trial" }
        return "Subscribe"
    }

    /// Apple 3.1.2 disclosure: must state price, that it auto-renews, and how to
    /// cancel — adjacent to the purchase button and before any charge.
    private var disclosureText: String? {
        guard let package = selectedPackage else { return nil }
        let price = package.vitalsPriceLabel
        if package.vitalsPackageKind == .lifetime {
            return "\(price). One-time purchase. Lifetime access, no subscription."
        }
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings."
        if store.isEligibleForIntroOffer(package), let trial = package.vitalsIntroOfferLabel {
            return "\(trial.capitalized), then \(price). \(renew)"
        }
        return "\(price). \(renew)"
    }

    // MARK: - Actions

    private func selectDefaultPackageIfNeeded() {
        #if DEBUG
        if let mode = PaywallScreenshotMode.current, !store.products.isEmpty {
            switch mode {
            case .monthly:
                selectedPackage = store.products.first { $0.vitalsPackageKind == .monthly }
            case .lifetime:
                selectedPackage = store.products.first { $0.vitalsPackageKind == .lifetime }
            case .yearly, .trial:
                selectedPackage = store.products.first { $0.vitalsPackageKind == .yearly }
            }
            return
        }
        #endif
        guard selectedPackage == nil, !store.products.isEmpty else { return }
        // Prefer yearly (best value + usually carries the trial), else first.
        selectedPackage = store.products.first { $0.vitalsPackageKind == .yearly }
            ?? store.products.first
    }

    private func startPurchase() {
        guard let package = selectedPackage else { return }
        errorMessage = nil
        restoreMessage = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            do {
                switch try await store.purchase(package) {
                case .purchased, .pending:
                    // isPro flips via apply(); the onChange dismisses the sheet.
                    break
                case .cancelled:
                    errorMessage = "Purchase cancelled. Tap again to continue."
                }
            } catch {
                errorMessage = "Couldn't complete the purchase. Please try again."
            }
        }
    }

    private func startRestore() {
        errorMessage = nil
        restoreMessage = nil
        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            await store.restorePurchases()
            if !store.isPro {
                restoreMessage = store.lastError ?? "No active Vitals+ purchase found for this Apple ID."
            }
        }
    }
}

/// A single selectable subscription plan row. Restrained styling per the chosen
/// paywall direction: a tinted ring + check when selected, no animation.
private struct PlanCard: View {
    let package: Package
    let isSelected: Bool
    let showsTrialBadge: Bool
    let isBestValue: Bool
    var savingsPercent: Int? = nil
    var perWeekLabel: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
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

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(package.vitalsDisplayName)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        if let savingsPercent {
                            Text("SAVE \(savingsPercent)%")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.caloriesPrimary, in: Capsule())
                        } else if isBestValue {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.caloriesPrimary, in: Capsule())
                        }
                    }
                    if showsTrialBadge, let trial = package.vitalsIntroOfferLabel {
                        Text("\(trial.capitalized), then billed")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.stepsPrimary)
                    } else if let perWeekLabel {
                        Text("Just \(perWeekLabel)/week")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.stepsPrimary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(package.vitalsPriceLabel)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    if showsTrialBadge, let perWeekLabel {
                        // When the trial badge takes the subtitle slot, still
                        // surface the per-week anchor next to the headline price.
                        Text("\(perWeekLabel)/wk")
                            .font(.system(.caption2, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(isSelected ? Theme.caloriesPrimary : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// "How your free trial works" — a three-step timeline that removes the #1
/// reason people decline a trial: not knowing when (or whether) they'll be
/// charged. Modeled on the Blinkist trial-timeline pattern; every claim here is
/// truthful (instant access now, an App Store reminder before billing, and the
/// exact price on the final day, cancellable anytime).
private struct TrialTimeline: View {
    let trialDays: Int
    let priceLabel: String?

    private var reminderDay: Int { max(trialDays - 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How your free trial works")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 12)

            step(
                icon: "lock.open.fill",
                tint: Theme.stepsPrimary,
                title: "Today: full access",
                detail: "Every Vitals+ feature unlocks right away.",
                isLast: false
            )
            step(
                icon: "bell.fill",
                tint: Theme.caloriesPrimary,
                title: "Day \(reminderDay): heads-up",
                detail: "The App Store reminds you before your trial ends.",
                isLast: false
            )
            step(
                icon: "checkmark.seal.fill",
                tint: Theme.netDeficitBrand,
                title: "Day \(trialDays): trial ends",
                detail: priceLabel.map { "Billed \($0) unless you cancel. Cancel anytime." }
                    ?? "You're only billed if you keep it. Cancel anytime.",
                isLast: true
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How your free trial works. Today, full access unlocks. Day \(reminderDay), the App Store reminds you. Day \(trialDays), the trial ends and you're billed unless you cancel.")
    }

    private func step(icon: String, tint: Color, title: String, detail: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                }
                if !isLast {
                    Rectangle()
                        .fill(Theme.textTertiary.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(minHeight: isLast ? 28 : 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 10)
            Spacer(minLength: 0)
        }
    }
}
