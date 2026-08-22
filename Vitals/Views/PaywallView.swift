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
    case macros
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
        case .macros: "chart.pie.fill"
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
        case .macros: Theme.macrosBrand
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

    /// Short title for compact bullet rows (trial sheet companions).
    var title: String {
        switch self {
        case .netDeficit: "Net Deficit"
        case .macros: "Macros"
        case .activeResting: "Active vs. resting"
        case .energyAverages: "TDEE & BMR"
        case .deepTrends: "Deep Trends"
        case .customRangesPDF: "Custom ranges + PDF"
        case .projections: "End-of-day projections"
        case .streaks: "Goal streaks"
        case .weeklyRecap: "Weekly recap"
        case .bodyProfile: "Body profile"
        }
    }

    /// Supporting line on the focused trial bullet (intent sheet).
    var detail: String {
        switch self {
        case .netDeficit: "Burned minus food logged in Apple Health, updated through the day."
        case .macros: "Protein, carbs, and fat from the food you already log in Apple Health."
        case .activeResting: "See how much of today's burn came from activity vs. resting."
        case .energyAverages: "30-day maintenance (TDEE) and resting burn (BMR) from your data."
        case .deepTrends: "Compare any period to the one before it."
        case .customRangesPDF: "Pick any dates in History and export a summary PDF."
        case .projections: "Where today's calories and steps will land at your current pace."
        case .streaks: "See how many days in a row you've hit your goal."
        case .weeklyRecap: "Sunday summary of this week vs. last."
        case .bodyProfile: "Body fat and calorie context next to your BMI."
        }
    }

    /// Outcome bullets on the full paywall (generic, no focus).
    var featureListTitle: String {
        switch self {
        case .netDeficit: "Net Deficit: burned minus food logged, live"
        case .macros: "Macros: protein, carbs, and fat, every day"
        case .activeResting: "Active vs. resting calorie breakdown"
        case .energyAverages: "TDEE & BMR from your Apple Health averages"
        case .deepTrends: "Deep Trends: every period vs. the one before"
        case .customRangesPDF: "Custom date ranges + PDF reports"
        case .projections: "End-of-day projections from your pace"
        case .streaks: "Goal streaks: keep the chain alive"
        case .weeklyRecap: "Weekly recap notification + summary"
        case .bodyProfile: "Body fat + calorie context with your BMI"
        }
    }

    /// Headline when the user tapped to enable this specific feature.
    var intentHeadline: String {
        switch self {
        case .netDeficit: "Track your live deficit"
        case .macros: "See your macros here too"
        case .activeResting: "Split active and resting burn"
        case .energyAverages: "See your maintenance calories"
        case .deepTrends: "Compare every period"
        case .customRangesPDF: "Export any date range"
        case .projections: "Know where today lands"
        case .streaks: "Keep your streak alive"
        case .weeklyRecap: "Get your week in review"
        case .bodyProfile: "Understand your body profile"
        }
    }

    /// One sentence under the headline — what they get from the feature they asked for.
    var intentSubheadline: String {
        switch self {
        case .netDeficit: "Calories burned minus food logged, updated all day from Apple Health."
        case .macros: "Protein, carbs, and fat read straight from the food app you already use."
        case .activeResting: "See what actually moved today's calorie number."
        case .energyAverages: "TDEE and BMR averaged over the last 30 days from your own data."
        case .deepTrends: "Stack this week against last week, this month against the last."
        case .customRangesPDF: "Pull any window from History into a clean PDF."
        case .projections: "Projected calories and steps based on your pace so far today."
        case .streaks: "Track consecutive days you hit your goal."
        case .weeklyRecap: "A Sunday night summary of this week vs. last."
        case .bodyProfile: "Body fat and calorie context alongside BMI. BMI stays free."
        }
    }

    /// Two related features shown under an intent-driven pitch (not random extras).
    var companionFeatures: [PlusFeature] {
        switch self {
        case .netDeficit: [.macros, .projections]
        case .macros: [.netDeficit, .deepTrends]
        case .activeResting: [.netDeficit, .energyAverages]
        case .energyAverages: [.netDeficit, .projections]
        case .deepTrends: [.customRangesPDF, .projections]
        case .customRangesPDF: [.deepTrends, .netDeficit]
        case .projections: [.netDeficit, .streaks]
        case .streaks: [.projections, .weeklyRecap]
        case .weeklyRecap: [.streaks, .deepTrends]
        case .bodyProfile: [.energyAverages, .netDeficit]
        }
    }

    var pitchHeadline: String { intentHeadline }
    var pitchSubheadline: String { intentSubheadline }

    #if DEBUG
    /// Suffix for `-PaywallSnapshot trial-<slug>` capture scripts.
    var snapshotSlug: String {
        switch self {
        case .netDeficit: "net-deficit"
        case .macros: "macros"
        case .activeResting: "active-resting"
        case .energyAverages: "tdee"
        case .deepTrends: "deep-trends"
        case .customRangesPDF: "custom-range"
        case .projections: "projections"
        case .streaks: "streaks"
        case .weeklyRecap: "weekly-recap"
        case .bodyProfile: "body-profile"
        }
    }

    static func fromSnapshotSlug(_ slug: String) -> PlusFeature? {
        switch slug {
        case "net-deficit": .netDeficit
        case "macros": .macros
        case "active-resting": .activeResting
        case "tdee": .energyAverages
        case "deep-trends": .deepTrends
        case "custom-range": .customRangesPDF
        case "projections": .projections
        case "streaks": .streaks
        case "weekly-recap": .weeklyRecap
        case "body-profile": .bodyProfile
        default: nil
        }
    }

    /// Every feature-gate a free user can hit (settings toggles + History + Body Profile).
    static let allSnapshotGates: [PlusFeature] = [
        .netDeficit, .macros, .activeResting, .energyAverages, .projections, .streaks,
        .weeklyRecap, .deepTrends, .customRangesPDF, .bodyProfile
    ]
    #endif
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

    /// Outcome bullets. Intent taps lead with the feature they asked for plus
    /// two related companions; the Upgrade tab lists every Vitals+ benefit.
    private var paywallBullets: [PlusFeature] {
        if let focus { return [focus] + focus.companionFeatures }
        return [
            .netDeficit, .macros, .activeResting, .energyAverages, .projections,
            .streaks, .deepTrends, .customRangesPDF, .weeklyRecap, .bodyProfile
        ]
    }

    private var showsFullBenefitList: Bool { focus == nil }

    /// Annual savings vs. paying monthly for a year — loss-aversion anchoring
    /// against the monthly price. Shared with the trial sheet's deal badge.
    private var annualSavingsPercent: Int? { store.annualSavingsPercent }

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
        paywallContent
    }

    /// Hero + benefits + plans; checkout pinned slim below. Full Upgrade-tab
    /// benefit list scrolls so every Vitals+ capability stays visible.
    private var paywallContent: some View {
        Group {
            if showsFullBenefitList {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        header(compact: true)
                        paywallFeatureList
                        planCards
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, displayCloseButton ? 44 : 12)
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                // A focused pitch is short: three benefits and the plans. Space
                // is split above and below so it sits centred, instead of all of
                // it pooling into one dead band above the button.
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    header(compact: true)
                    paywallFeatureList
                    planCards
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, displayCloseButton ? 44 : 20)
                .padding(.bottom, 4)
                .frame(maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedCheckoutFooter
        }
    }

    /// CTA + required 3.1.2 copy. Disclosure/legal sit in a fixed-height slot so the
    /// button never jumps when the selected plan changes (lifetime vs trial copy).
    private var pinnedCheckoutFooter: some View {
        VStack(spacing: 6) {
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

            VStack(spacing: 4) {
                // Error replaces disclosure in the same slot — never ZStack both
                // (overlapping red + grey text on purchase failure).
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity)
                } else if let restoreMessage {
                    Text(restoreMessage)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity)
                } else if let disclosureText {
                    Text(disclosureText)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity)
                }

                legalFooter
            }
            .frame(minHeight: 68, alignment: .top)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, displayCloseButton ? 10 : 22)
        .background(alignment: .top) {
            // A hard edge across the plan list read as a broken card: the third
            // plan was sliced in half by an opaque bar. The scrim fades the list
            // out instead, which also says "there is more below".
            Theme.background
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Theme.background.opacity(0), Theme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 22)
                    .offset(y: -22)
                }
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 4) {
            Button(action: startRestore) {
                Text(isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
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

    private var paywallFeatureList: some View {
        // Ten benefits and three plans on one screen: the list gives up a little
        // rhythm so the cheapest and the one-off plan are visible without a
        // scroll, rather than the third card being a sliver under the button.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(paywallBullets, id: \.self) { feature in
                let highlighted = feature == focus
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(feature.tint)
                        .frame(width: 22)
                    Text(feature.featureListTitle)
                        .font(.system(.subheadline, design: .rounded, weight: highlighted ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, highlighted ? 10 : 0)
                .padding(.vertical, highlighted ? 8 : 0)
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

    private func header(compact: Bool) -> some View {
        VStack(spacing: compact ? 4 : 10) {
            ZStack {
                Circle()
                    .fill(Theme.caloriesGradient)
                    .frame(width: compact ? 46 : 64, height: compact ? 46 : 64)
                    .shadow(color: Theme.caloriesPrimary.opacity(0.35), radius: 12, x: 0, y: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: compact ? 20 : 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(focus?.intentHeadline ?? "Vitals+")
                .font(.system(compact ? .title2 : .title, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(focus == nil ? 1 : 2)
                .minimumScaleFactor(0.85)
            Text(focus?.intentSubheadline ?? "Calories, steps, and trends in one dashboard.")
                .font(.system(compact ? .footnote : .subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 2 : nil)
                .minimumScaleFactor(compact ? 0.9 : 1)
        }
    }

    private var planCards: some View {
        VStack(spacing: 8) {
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
        if let snap = PaywallSnapshotRequest.current, !store.products.isEmpty {
            switch snap.plan {
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
                    errorMessage = store.purchaseCancelledMessage(for: package)
                }
            } catch {
                await store.refreshIntroEligibility()
                errorMessage = store.purchaseFailedMessage(for: package)
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
                    Group {
                        if showsTrialBadge, let trial = package.vitalsIntroOfferLabel {
                            Text(trial.capitalized)
                        } else if let perWeekLabel {
                            Text("Just \(perWeekLabel)/week")
                        } else {
                            Text(" ")
                        }
                    }
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.stepsPrimary)
                    .lineLimit(1)
                    .frame(height: 14, alignment: .leading)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(package.vitalsPriceLabel)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Text(showsTrialBadge ? (perWeekLabel.map { "\($0)/wk" } ?? " ") : " ")
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .frame(height: 14, alignment: .trailing)
                }
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
