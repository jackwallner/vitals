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
    /// Height the tab gives the pitch, measured by `CenteredScrollContainer`.
    @State private var fullListHeight: CGFloat = 0
    /// Last honest CTA title. The button never falls back to a spinner-only
    /// control (that made the label flicker and hid it from UI tests).
    @State private var displayedCTATitle: String = "Start Free Trial"

    /// Outcome bullets. Intent taps lead with the feature they asked for plus
    /// two related companions.
    ///
    /// The Upgrade tab used to list all ten benefits, which read as a spec sheet
    /// and pushed the plans off the first screen. It now leads with the five
    /// people actually come for; `remainingBenefitsLine` carries the rest in one
    /// sentence so nothing is hidden.
    private var paywallBullets: [PlusFeature] {
        if let focus { return [focus] + focus.companionFeatures }
        // `full_list` is the 1.8.2 pitch: every feature, spelled out. The
        // catalog arm cut it to five and moved the rest to one summary line.
        // Which of those sells better is the whole point of running them
        // against each other, so both have to exist in the same binary.
        if upgradeTabVariant == .fullList {
            return [
                .netDeficit, .macros, .activeResting, .energyAverages, .deepTrends,
                .projections, .streaks, .customRangesPDF, .weeklyRecap, .bodyProfile,
            ]
        }
        return [.macros, .netDeficit, .energyAverages, .deepTrends, .customRangesPDF]
    }

    /// The benefits the shortened list doesn't spell out, as one line.
    private var remainingBenefitsLine: String? {
        guard focus == nil else { return nil }
        return "Plus projections, streaks, weekly recap, active/resting split, and body profile."
    }

    private var showsFullBenefitList: Bool { focus == nil }

    /// Annual savings vs. paying monthly for a year — loss-aversion anchoring
    /// against the monthly price. Shared with the trial sheet's deal badge.
    private var annualSavingsPercent: Int? { store.annualSavingsPercent }

    /// Which native layout to draw, from offering metadata. Focused (intent)
    /// paywalls stay on the short three-bullet layout and ignore the experiment:
    /// they are answering a specific tap, not pitching the tier.
    private var upgradeTabVariant: PaywallUIVariant {
        focus == nil ? store.upgradeTabVariant : .catalog
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
                VStack(spacing: 12) {
                    switch upgradeTabVariant {
                    case .featureLed:
                        featureLedHero
                    case .maintenanceLed:
                        maintenanceLedHero
                    case .fullList:
                        header(compact: true)
                        paywallFeatureList
                    case .catalog:
                        header(compact: true)
                        paywallFeatureList
                    }
                    planCards
                }
                .padding(.horizontal, 22)
                .padding(.top, displayCloseButton ? 44 : 12)
                .padding(.bottom, 8)
                .frame(minHeight: fullListHeight, alignment: .center)
                .modifier(CenteredScrollContainer(height: $fullListHeight))
                // Names the arm that is actually on screen, so a test can
                // assert the rendered layout instead of the rotator's toast.
                // The toast reports what was *stored*; those two disagreed for
                // two builds. `.contain` keeps every child individually
                // reachable by VoiceOver and only adds the grouping element.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("paywall-arm-\(upgradeTabVariant.rawValue)")
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

    /// CTA + required 3.1.2 copy.
    ///
    /// The copy below the button sits in a slot of *fixed* height. It used to be
    /// a `minHeight`, so picking Lifetime — whose disclosure is two lines rather
    /// than three — shrank the footer and slid the button down under the user's
    /// thumb, mid-decision.
    private var pinnedCheckoutFooter: some View {
        VStack(spacing: 6) {
            Button(action: startPurchase) {
                ZStack {
                    Text(displayedCTATitle)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .opacity(isPurchasing || ctaTitle == nil ? 0 : 1)
                        .animation(nil, value: displayedCTATitle)
                    if isPurchasing || ctaTitle == nil {
                        ProgressView()
                            .tint(.white)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.caloriesGradient, in: Capsule())
                .ctaGlow()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paywall-purchase")
            .accessibilityLabel(displayedCTATitle)
            .disabled(isPurchasing || ctaTitle == nil)
            .onChange(of: ctaTitle) { _, new in
                if let new { displayedCTATitle = new }
            }
            .onAppear {
                if let ctaTitle { displayedCTATitle = ctaTitle }
            }

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
            .frame(height: 62, alignment: .top)
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

    /// Restore, Terms and Privacy on one line. Restore had a line to itself,
    /// which cost a row of the pitch above it to say something almost nobody
    /// taps; it stays the most prominent of the three.
    private var legalFooter: some View {
        HStack(spacing: 6) {
            Button(action: startRestore) {
                Text(isRestoring ? "Restoring…" : "Restore")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing)
            Text("·").foregroundStyle(Theme.textTertiary)
            Link("Terms", destination: PaywallLinks.standardEULA)
            Text("·").foregroundStyle(Theme.textTertiary)
            Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(Theme.textTertiary)
    }

    /// Ten rows have to fit the same space five did, without pushing a plan off
    /// the screen. 1.8.2 did not manage that and hid Lifetime; tightening the
    /// row rhythm is what buys the space back.
    private var featureListSpacing: CGFloat {
        upgradeTabVariant == .fullList ? 3 : 7
    }

    private var paywallFeatureList: some View {
        VStack(alignment: .leading, spacing: featureListSpacing) {
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
            if upgradeTabVariant == .catalog, let remainingBenefitsLine {
                Text(remainingBenefitsLine)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The `feature_led` arm: show the thing, then name it.
    ///
    /// The catalog arm answers "what do I get" with a list, which asks the
    /// reader to imagine ten features. This one renders the single strongest
    /// one as the artifact it actually is, on the theory that a picture of the
    /// macro card does more work than the word "Macros" in a row of nine
    /// siblings. Which is true is the question the experiment exists to answer,
    /// so the two arms deliberately share products, prices, CTA and disclosure:
    /// the pitch is the only variable.
    private var featureLedHero: some View {
        VStack(spacing: 14) {
            // The tier has to be named on the surface that sells it. This arm
            // replaces `header(compact:)`, which was the only place the words
            // "Vitals+" appeared, and neither the plan rows nor the 3.1.2
            // disclosure say it either: the treatment paywall was asking for a
            // subscription it never named. Guideline 3.1.2 wants the title of
            // the subscription visible before purchase, and a reader deserves
            // to know what the macro card is an advert for.
            Text("VITALS+")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.caloriesPrimary)
                .accessibilityAddTraits(.isHeader)

            MacroPitchCard()

            VStack(spacing: 6) {
                Text("Your macros, every day")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("Protein, carbs, and fat read straight from the food app you already use. Nothing to enter twice.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(featureLedSupportingPoints, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(feature.tint)
                            .frame(width: 20)
                        Text(feature.featureListTitle)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Deliberately short. The hero is the pitch; these stop the tier reading as
    /// a single-feature purchase.
    private var featureLedSupportingPoints: [PlusFeature] {
        [.netDeficit, .energyAverages, .deepTrends]
    }

    /// The `maintenance_led` arm.
    ///
    /// The free app already answers "what did I burn today", on the Home Screen
    /// and the watch face. That is the wedge, and a paywall cannot sell it back
    /// to someone who already has it. The paid half of the same question is
    /// "so what can I eat" — maintenance and BMR, averaged over 30 days of
    /// Apple Health energy.
    ///
    /// It is here because it is the only strong Vitals+ feature that asks
    /// nothing of the user: no food logging, no second app, no setup. Macros
    /// and Net Deficit both render blank for someone who logs nothing, which is
    /// most people. This arm is what `feature_led` is for food loggers.
    private var maintenanceLedHero: some View {
        VStack(spacing: 14) {
            Text("VITALS+")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.caloriesPrimary)
                .accessibilityAddTraits(.isHeader)

            MaintenancePitchCard()

            VStack(spacing: 6) {
                Text("Know what you can eat")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("Unlock your maintenance calories and BMR, worked out from 30 days of your own Apple Health data. On your Home Screen. Nothing to log.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(maintenanceLedSupportingPoints, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(feature.tint)
                            .frame(width: 20)
                        Text(feature.featureListTitle)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Three that also work with an empty food log, so the whole arm keeps its
    /// promise to someone who logs nothing. Macros and Net Deficit are
    /// deliberately absent.
    private var maintenanceLedSupportingPoints: [PlusFeature] {
        [.activeResting, .projections, .deepTrends]
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
            Text(focus?.intentSubheadline ?? upgradeTabHeaderSubheadline)
                .font(.system(compact ? .footnote : .subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 2 : nil)
                .minimumScaleFactor(compact ? 0.9 : 1)
        }
    }

    private var planCards: some View {
        VStack(spacing: 6) {
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
                // Unlabelled, VoiceOver read this as "xmark circle fill", which
                // is the only way off the paywall for a nonvisual user.
                .accessibilityLabel("Close")
            }
            Spacer()
        }
    }

    // MARK: - Copy

    private var upgradeTabHeaderSubheadline: String {
        "Calories, steps, and trends in one dashboard."
    }

    /// nil while eligibility is still resolving, so the button never flashes
    /// Continue → Subscribe → Start Free Trial.
    private var ctaTitle: String? {
        guard let package = selectedPackage else { return nil }
        return VitalsConversionCopy.paywallCTATitle(
            packageSelected: true,
            isLifetime: package.vitalsPackageKind == .lifetime,
            hasIntroOffer: package.vitalsIntroOfferLabel != nil,
            eligibilityResolved: store.introEligibilityResolved,
            eligibleForTrial: store.isEligibleForIntroOffer(package)
        )
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
                case .purchased:
                    // isPro flips via apply(); the onChange dismisses the sheet.
                    break
                case .pending:
                    // Previously a silent no-op: the spinner stopped and nothing
                    // else changed, which reads as a button that does not work.
                    errorMessage = store.purchasePendingMessage(for: package)
                case .cancelled:
                    errorMessage = store.purchaseCancelledMessage(for: package)
                case .unavailable:
                    errorMessage = VitalsConversionCopy.purchaseUnavailableMessage
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

    /// The one line worth saying under the plan name: the trial when it applies,
    /// otherwise the per-week equivalent. nil when neither is known.
    private var subline: String? {
        if showsTrialBadge, let trial = package.vitalsIntroOfferLabel { return trial.capitalized }
        if let perWeekLabel { return "Just \(perWeekLabel)/week" }
        return nil
    }

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
                    // Only rendered when there is something to say. It used to
                    // reserve a blank line on every card, which is most of the
                    // dead space between the three of them.
                    if let subline {
                        Text(subline)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.stepsPrimary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(package.vitalsPriceLabel)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    if showsTrialBadge, let perWeekLabel {
                        Text("\(perWeekLabel)/wk")
                            .font(.system(.caption2, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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

/// The macro card as the paywall shows it: the real dashboard component's
/// shape and colours, with representative numbers.
///
/// Static values on purpose. A free user has no macro history to render, and a
/// pitch that draws their empty state is an argument against buying. These are
/// illustrative rather than personal, which is why the card is labelled as an
/// example rather than presented as their data.
/// The Maintenance widget as it actually draws, not a description of it.
///
/// Static numbers, labelled as an example: a free user has no 30-day average
/// yet, and a pitch that renders their empty state argues against itself. Same
/// reasoning as `MacroPitchCard`.
private struct MaintenancePitchCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MAINTENANCE")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.8)
                Spacer(minLength: 0)
                Text("30-day average")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 8) {
                figure(value: "2,450", label: "TDEE", tint: Theme.caloriesPrimary)
                figure(value: "1,780", label: "BMR", tint: Theme.restingPrimary)
            }
            .overlay(alignment: .center) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(9)
                    .background(Theme.cardSurface, in: Circle())
            }
        }
        .padding(14)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked maintenance card. Your TDEE and BMR, worked out from a 30-day average, are a Vitals+ feature. The numbers shown are blurred placeholders, not your own.")
    }

    private func figure(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                // Blurred on purpose. Sharp numbers on a paywall read as a
                // claim about the reader's own body, and these are invented.
                // Out of focus they read as what they are: the shape of the
                // thing, locked. It also stops anyone treating 2,450 as advice.
                .blur(radius: 7)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MacroPitchCard: View {
    private struct Macro {
        let grams: Int
        let name: String
        let tint: Color
    }

    // Theme.macroColor, not hand-picked tints: the pitch shows the dashboard
    // component, so protein/carbs/fat have to be the same blue/amber/orchid the
    // real card uses. Picking colours by eye here had carbs coming out green.
    private let macros = [
        Macro(grams: 142, name: "protein", tint: Theme.macroColor(.protein)),
        Macro(grams: 186, name: "carbs", tint: Theme.macroColor(.carbs)),
        Macro(grams: 61, name: "fat", tint: Theme.macroColor(.fat)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MACROS")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.8)
                Spacer(minLength: 0)
                Text("1,950 cal logged")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 8) {
                ForEach(macros, id: \.name) { macro in
                    VStack(spacing: 1) {
                        Text("\(macro.grams)")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(macro.tint)
                        Text("g \(macro.name)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        // One element, one sentence: VoiceOver should not read six loose numbers,
        // and it must not imply these are the listener's own figures.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example macros card. 142 grams protein, 186 grams carbs, 61 grams fat, from 1,950 calories logged.")
    }
}
