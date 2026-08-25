import SwiftUI
@preconcurrency import RevenueCat

/// One presentation of the Vitals+ trial pitch, addressed by the feature the
/// user reached for. `Identifiable` so any view can drive it with `.sheet(item:)`.
struct TrialPitchRequest: Identifiable {
    let id = UUID()
    /// The feature the tap reached for; `nil` for a generic upgrade entry point.
    let focus: PlusFeature?
    /// RevenueCat impression id for this entry point.
    let impressionID: String
    /// The toggle-gated feature to switch on if this pitch converts. Only set
    /// when the user explicitly reached for it — buying from a generic row
    /// leaves every setting alone.
    let featureToEnable: PlusFeature?

    /// A feature tap. `impressionID` names the surface, not the feature, so the
    /// RevenueCat series stay comparable across builds.
    init(intent: TrialOfferCoordinator.Intent, impressionID: String) {
        focus = intent.focusFeature
        self.impressionID = impressionID
        featureToEnable = TrialPitchRequest.toggleGatedFeature(for: intent)
    }

    /// A passive nudge (launch, History load): no feature was asked for, so
    /// nothing is switched on if it converts.
    init(passiveImpressionID: String) {
        focus = nil
        impressionID = passiveImpressionID
        featureToEnable = nil
    }

    /// Deep Trends and PDF export unlock with Pro itself and have no stored
    /// setting, so they are not auto-enabled — there is nothing to enable.
    private static func toggleGatedFeature(for intent: TrialOfferCoordinator.Intent) -> PlusFeature? {
        switch intent {
        case .netDeficitToggle: .netDeficit
        case .macrosToggle: .macros
        case .activeRestingToggle: .activeResting
        case .energyAveragesToggle: .energyAverages
        case .projectionsToggle: .projections
        case .streaksToggle: .streaks
        case .weeklyRecapToggle: .weeklyRecap
        default: nil
        }
    }
}

/// The trial pitch packaged with everything it needs to sell: the package it
/// snapshots when it opens, the one-tap purchase, and the failure copy. Any
/// surface can present it — including one that is already a sheet, which is why
/// a locked row in Settings no longer has to close Settings to answer the tap.
struct TrialOfferPitchSheet: View {
    let request: TrialPitchRequest
    /// The sheet asks its presenter to close it; the presenter owns the flag.
    let onDismiss: () -> Void
    /// Products never loaded, so there is nothing to buy in one tap. The
    /// presenter routes to the full plan picker instead of a dead button.
    var onNeedsPlanPicker: () -> Void = {}

    @EnvironmentObject private var store: StoreService
    @ObservedObject private var goals = GoalSettings.shared
    /// Snapshot taken when the sheet opened, with a live fallback for the case
    /// where StoreKit had not answered yet.
    @State private var snapshot: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    /// Set only on the used-trial pitch, where the user picks a plan. nil means
    /// "the one-tap trial target", which is always yearly.
    @State private var selectedPlanID: String?

    private var package: Package? {
        guard let selectedPlanID else { return snapshot ?? store.conversionPackage }
        return store.products.first { $0.identifier == selectedPlanID }
            ?? snapshot
            ?? store.conversionPackage
    }

    /// True while the trial is still on the table for this Apple ID.
    private var eligibleForTrial: Bool {
        guard let package else { return false }
        return store.eligibleIntroLabel(for: package) != nil
    }

    /// Plans to choose between — used-trial accounts only. Someone who still has
    /// a free trial should have exactly one thing to do; someone who has spent it
    /// is deciding on price, so give them the price ladder instead of one number.
    private var planOptions: [TrialPlanOption] {
        guard !eligibleForTrial else { return [] }
        let ladder = store.products.filter { $0.vitalsPackageKind != .other }
        guard ladder.count > 1 else { return [] }
        let order: [RevenueCatPackageKind] = [.yearly, .monthly, .lifetime]
        return ladder
            .sorted { (order.firstIndex(of: $0.vitalsPackageKind) ?? 9) < (order.firstIndex(of: $1.vitalsPackageKind) ?? 9) }
            .map { plan in
                TrialPlanOption(
                    id: plan.identifier,
                    title: plan.vitalsDisplayName,
                    price: plan.vitalsPriceLabel,
                    detail: plan.vitalsPricePerWeekLabel.map { "about \($0) a week" },
                    badge: plan.vitalsPackageKind == .yearly
                        ? store.annualSavingsPercent.map { "SAVE \($0)%" }
                        : nil
                )
            }
    }

    var body: some View {
        TrialOfferSheet(
            focus: request.focus,
            logsFood: goals.logsFoodInHealth,
            // Trial language only when this Apple ID is still eligible —
            // otherwise the sheet frames a straight yearly purchase.
            offerLabel: package.flatMap { store.eligibleIntroLabel(for: $0) },
            priceLabel: package?.vitalsPriceLabel,
            ctaTitle: ctaTitle,
            disclosureText: disclosureText,
            directPurchase: package != nil,
            isPurchasing: isPurchasing,
            errorMessage: errorMessage,
            onStartTrial: startPurchase,
            onDismiss: onDismiss,
            onRestore: startRestore,
            isRestoring: isRestoring,
            restoreMessage: restoreMessage,
            // The ladder prints a per-week figure on every row; saying it in the
            // subhead too is the same number twice in one glance.
            perWeekLabel: planOptions.isEmpty ? store.yearlyPackage?.vitalsPricePerWeekLabel : nil,
            annualSavingsPercent: store.annualSavingsPercent,
            planOptions: planOptions,
            selectedPlanID: selectedPlanID ?? planOptions.first?.id,
            onSelectPlan: { selectedPlanID = $0 }
        )
        .presentationDetents([TrialOfferSheet.pitchDetent])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
        .interactiveDismissDisabled(isPurchasing)
        .task {
            if store.products.isEmpty { await store.fetchProducts() }
            snapshot = store.conversionPackage
            store.trackPaywallImpression(id: request.impressionID)
        }
    }

    /// CTA and disclosure follow the *selected* plan, not the yearly default —
    /// a monthly pick that still said "$29.99 / year" would be a 3.1.2 problem
    /// as well as a lie.
    private var ctaTitle: String {
        guard let package else { return store.onboardingTrialCTALabel }
        if package.vitalsPackageKind == .lifetime { return "Unlock Lifetime" }
        return VitalsConversionCopy.ctaLabel(
            trialLabel: package.vitalsIntroOfferLabel,
            priceLabel: package.vitalsPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(package)
        )
    }

    private var disclosureText: String? {
        guard let package else { return store.yearlySheetDisclosureText }
        if package.vitalsPackageKind == .lifetime {
            return "\(package.vitalsPriceLabel). One-time purchase. Lifetime access, no subscription."
        }
        return VitalsConversionCopy.sheetDisclosure(
            trialLabel: package.vitalsIntroOfferLabel,
            priceLabel: package.vitalsPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(package)
        )
    }

    /// A restore that says nothing is barely a restore. `restorePurchases`
    /// already distinguishes "nothing on this Apple ID" from a network failure
    /// in `store.lastError`; this puts that answer where the user can read it.
    /// A successful one flips `isPro`, which dismisses the sheet on its own.
    private func startRestore() {
        errorMessage = nil
        restoreMessage = nil
        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            await store.restorePurchases()
            guard !store.isPro else { return }
            restoreMessage = store.lastError
                ?? "No active Vitals+ purchase was found for this Apple ID."
        }
    }

    private func startPurchase() {
        guard let package else {
            onNeedsPlanPicker()
            return
        }
        errorMessage = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            // Re-check eligibility so a used-trial account that was mis-cached
            // as eligible flips to paid copy before/after the attempt.
            await store.refreshIntroEligibility()
            do {
                switch try await store.purchase(package) {
                case .purchased:
                    onDismiss()
                case .pending:
                    // A deferred transaction is not access. Leave the sheet up
                    // saying so rather than dismissing someone into an app that
                    // still has the feature locked.
                    errorMessage = store.purchasePendingMessage(for: package)
                case .cancelled:
                    errorMessage = store.purchaseCancelledMessage(for: package)
                case .unavailable:
                    // Purchases cannot run here; the full paywall owns retry.
                    onNeedsPlanPicker()
                }
            } catch {
                await store.refreshIntroEligibility()
                errorMessage = store.purchaseFailedMessage(for: package)
            }
        }
    }
}

/// Flips on whichever toggle-gated feature the user reached for before they were
/// paywalled, now that they're Pro.
///
/// Net Deficit and Macros need a HealthKit permission sheet, which the system
/// suppresses while a modal still covers the window. Both go out as
/// notifications so `DashboardView` can close whatever is open first and then
/// ask — the same path the trial sheet on the dashboard uses.
@MainActor
enum PlusFeatureActivation {
    static func apply(_ feature: PlusFeature?, goals: GoalSettings) {
        guard let feature else { return }
        switch feature {
        case .netDeficit:
            NotificationCenter.default.post(name: .vitalsEnableNetDeficitWithDietaryAuth, object: nil)
        case .macros:
            NotificationCenter.default.post(name: .vitalsEnableMacrosWithHealthAuth, object: nil)
        case .activeResting:
            goals.showActiveRestingBreakdown = true
        case .energyAverages:
            goals.showEnergyAverages = true
        case .projections:
            goals.showProjections = true
        case .streaks:
            goals.showStreaks = true
        case .weeklyRecap:
            goals.weeklyRecapEnabled = true
            Task { await NotificationService.scheduleWeeklyRecap() }
        default:
            break
        }
    }
}
