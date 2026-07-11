import SwiftUI
import SwiftData
import BackgroundTasks
import StoreKit
import UserNotifications
import os
@preconcurrency import RevenueCat
#if canImport(WatchConnectivity)
@preconcurrency import WatchConnectivity
#endif

private let goalSyncLogger = Logger(subsystem: "com.jackwallner.vitals", category: "GoalSync")

#if canImport(WatchConnectivity)
private final class PhoneGoalSyncService: NSObject, WCSessionDelegate {
    nonisolated(unsafe) static let shared = PhoneGoalSyncService()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    @MainActor
    func pushCurrentGoals(from goals: GoalSettings) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            goalSyncLogger.info("Skipping goal sync because WatchConnectivity is not activated yet")
            return
        }

        let payload: [String: Any] = [
            GoalSyncKeys.calorieGoalEnabled: goals.calorieGoal != nil,
            GoalSyncKeys.stepGoalEnabled: goals.stepGoal != nil,
            GoalSyncKeys.calorieGoal: goals.calorieGoal ?? 2500,
            GoalSyncKeys.stepGoal: goals.stepGoal ?? 10000,
            GoalSyncKeys.showNetCalories: goals.showNetCalories && StoreService.shared.isPro,
            GoalSyncKeys.netDeficitFastingMode: goals.netDeficitFastingMode,
            GoalSyncKeys.showCalories: goals.showCalories,
            GoalSyncKeys.showSteps: goals.showSteps,
        ]

        do {
            try session.updateApplicationContext(payload)
            goalSyncLogger.info("Pushed goal settings to watch")
        } catch {
            goalSyncLogger.error("Failed to push goal settings: \(String(describing: error), privacy: .public)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            goalSyncLogger.error("WatchConnectivity activation failed: \(String(describing: error), privacy: .public)")
            return
        }

        goalSyncLogger.info("WatchConnectivity activated with state \(activationState.rawValue, privacy: .public)")
        Task { @MainActor in
            PhoneGoalSyncService.shared.pushCurrentGoals(from: GoalSettings.shared)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif

@main
struct VitalsApp: App {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared
    @StateObject private var store = StoreService.shared

    private static let refreshTaskID = "com.jackwallner.vitals.refresh"

    init() {
        // Run the launch handler on the main queue. With `using: nil` the system uses a
        // background queue; referencing MainActor-isolated `Self` / `handleAppRefresh`
        // from there trips Swift 6 executor checks (see _dispatch_assert_queue_fail).
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: DispatchQueue.main) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Self.handleAppRefresh(task)
        }
        // Must run on every launch (including background) so observer queries are active
        HealthKitService.shared.enableBackgroundDelivery()
        Self.scheduleAppRefresh()
        // Route weekly-recap notification taps to the recap sheet.
        UNUserNotificationCenter.current().delegate = VitalsNotificationDelegate.shared
        StoreService.shared.start()
        ReviewPromptTracker.recordAppLaunch()
        #if canImport(WatchConnectivity)
        PhoneGoalSyncService.shared.activate()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let snap = PaywallSnapshotRequest.current {
                PaywallScreenshotHarness(request: snap)
                    .environmentObject(store)
                    .preferredColorScheme(goals.appearance.colorScheme)
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
        }
        .modelContainer(DataService.sharedModelContainer)
    }

    @ViewBuilder
    private var mainContent: some View {
            MainTabView()
                .environmentObject(store)
                .preferredColorScheme(goals.appearance.colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task { await store.updateCustomerProductStatus() }
                }
                .task {
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
                .onChange(of: goals.calorieGoal) { _, _ in
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
                .onChange(of: goals.stepGoal) { _, _ in
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
                .onChange(of: goals.showNetCalories) { _, _ in
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
                .onChange(of: goals.netDeficitFastingMode) { _, _ in
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
                .onChange(of: store.isPro) { _, _ in
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
                .onChange(of: goals.showCalories) { _, _ in
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
                .onChange(of: goals.showSteps) { _, _ in
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }

    private static func handleAppRefresh(_ task: BGAppRefreshTask) {
        // Schedule the next one immediately
        scheduleAppRefresh()

        let refreshTask = Task { @MainActor in
            do {
                try await HealthKitService.shared.refreshCache()
                return true
            } catch {
                print("Background app refresh failed: \(error)")
                return false
            }
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        Task {
            let success = await refreshTask.value
            task.setTaskCompleted(success: success)
        }
    }
}

/// App-wide coordinator for routing intent-driven taps (locked Custom range,
/// Net Deficit toggle, etc.) to the Vitals+ trial sheet. Child views set
/// `pendingIntent` and `MainTabView` observes it to present the sheet, so the
/// trial pitch is the high-converting first response to feature-tap intent
/// rather than the full plan picker paywall.
@MainActor
final class TrialOfferCoordinator: ObservableObject {
    static let shared = TrialOfferCoordinator()

    enum Intent: String {
        case lockedCustomRange
        case lockedSummaryReport
        case deepTrendsUpgrade
        case netDeficitToggle
        case activeRestingToggle
        case energyAveragesToggle
        case projectionsToggle
        case streaksToggle
        case weeklyRecapToggle
        case settingsUpgradeRow
        case milestoneCelebration
        case whatsNewAnnouncement
        case bodyProfileDetails

        /// The Vitals+ feature this tap reached for, so the pitch can lead with
        /// it. `nil` for entrypoints with no single feature (the generic
        /// Settings upgrade row, milestone celebrations, the What's New sheet).
        var focusFeature: PlusFeature? {
            switch self {
            case .netDeficitToggle: .netDeficit
            case .activeRestingToggle: .activeResting
            case .energyAveragesToggle: .energyAverages
            case .deepTrendsUpgrade: .deepTrends
            case .lockedCustomRange, .lockedSummaryReport: .customRangesPDF
            case .projectionsToggle: .projections
            case .streaksToggle: .streaks
            case .weeklyRecapToggle: .weeklyRecap
            case .bodyProfileDetails: .bodyProfile
            case .settingsUpgradeRow, .milestoneCelebration, .whatsNewAnnouncement: nil
            }
        }
    }

    @Published var pendingIntent: Intent?

    private init() {}

    func request(_ intent: Intent) { pendingIntent = intent }
    func clear() { pendingIntent = nil }
}

/// App-wide coordinator for celebratory milestone sheets (goal streaks, month
/// recaps). Feature views compute the milestone and post via `request`;
/// `MainTabView` owns the actual sheet presentation.
@MainActor
final class MilestoneCoordinator: ObservableObject {
    static let shared = MilestoneCoordinator()

    @Published var pendingEvent: MilestoneEvent?

    private init() {}

    func request(_ event: MilestoneEvent) { pendingEvent = event }
    func clear() { pendingEvent = nil }
}

/// Routes a tapped weekly-recap notification to the recap sheet. The
/// `UNUserNotificationCenterDelegate` posts here; `MainTabView` presents.
@MainActor
final class WeeklyRecapCoordinator: ObservableObject {
    static let shared = WeeklyRecapCoordinator()

    @Published var pendingPresent = false

    private init() {}

    func request() { pendingPresent = true }
    func clear() { pendingPresent = false }
}

/// Handles weekly-recap notification taps (and foreground presentation) and
/// forwards to `WeeklyRecapCoordinator`. Installed as the notification-center
/// delegate in `VitalsApp.init`.
final class VitalsNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = VitalsNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard info[NotificationService.recapRouteKey] as? String == NotificationService.recapRouteValue else { return }
        await MainActor.run { WeeklyRecapCoordinator.shared.request() }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var store: StoreService
    @StateObject private var goals = GoalSettings.shared
    @StateObject private var trialCoordinator = TrialOfferCoordinator.shared
    @StateObject private var milestoneCoordinator = MilestoneCoordinator.shared
    @StateObject private var recapCoordinator = WeeklyRecapCoordinator.shared
    @StateObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @State private var selectedTab = 0
    @State private var historyHasAppeared = false
    @State private var showWhatsNew = false
    /// Guards the What's New announcement to one evaluation per app session.
    @State private var whatsNewEvaluated = false
    /// Set when the What's New CTA routes a non-subscriber to the trial offer;
    /// read in the sheet's onDismiss to chain it once the sheet is fully gone.
    @State private var pendingTrialAfterWhatsNewDismiss = false
    /// Set when a subscriber taps "Choose in Settings"; opens the dashboard's
    /// Settings sheet after the announcement dismisses.
    @State private var pendingSettingsAfterWhatsNewDismiss = false
    @State private var showTrialOffer = false
    @State private var showTrialPaywall = false
    @State private var showMilestone = false
    @State private var showWeeklyRecap = false
    @State private var pendingMilestone: MilestoneEvent?
    /// Set when the user taps the CTA inside a milestone sheet. Chains the full
    /// plan-picker paywall after dismiss — never another trial sheet on top.
    @State private var pendingPaywallAfterMilestoneDismiss = false
    /// Guards against more than one milestone celebration per app session.
    @State private var milestoneShownThisSession = false
    /// Which trigger opened the current trial offer. Passive sources update the
    /// cooldown timestamp on dismiss; intent taps bypass the cooldown entirely.
    @State private var trialOfferSource: TrialOfferSource = .launch
    /// True once the launch offer has been shown in *this* app session.
    /// Gates the history-load offer so the two never fire back-to-back.
    @State private var launchOfferShownThisSession = false
    /// Set when onboarding completes in this process. Suppresses the passive
    /// TrialOfferSheet for the rest of the session so we don't re-pitch Vitals+
    /// minutes after the onboarding trial step. Next cold launch can pitch at
    /// the strategic value moment.
    @State private var skipPassiveTrialThisSession = false
    /// Set when the Today dashboard posts that its data is on screen (even zeros).
    /// Gates the "What's New" announcement, which is fine over any dashboard state.
    @State private var dashboardDataLoaded = false
    /// Set the first time the dashboard shows real, non-zero burned/step data —
    /// the strategic value moment. The passive launch trial nudge waits for this
    /// instead of a blind timer, so it never pitches over zeros/spinner.
    @State private var dashboardShowedRealData = false
    @State private var trialPurchaseInFlight = false
    @State private var trialPurchaseError: String?
    /// Set when the user opts into the full plan picker from inside the trial-offer
    /// sheet. The `.sheet(onDismiss:)` reads this and presents the paywall *after*
    /// the trial sheet has fully dismissed — presenting both sheets in the same
    /// runloop tick is racy in SwiftUI and frequently drops the second sheet.
    @State private var pendingPaywallAfterTrialDismiss = false
    @State private var trialOfferPackage: Package?
    @State private var trialOfferUsesDirectPurchase = false
    @State private var trialOfferDetent: PresentationDetent = .fraction(0.68)
    @State private var showReviewPrompt = false
    @State private var reviewPromptInitialStep: ReviewPromptSheet.Step = .enjoyment
    @State private var reviewPromptShownThisSession = false
    @State private var pendingNativeReviewAfterDismiss = false
    /// If a goal-hit review ask was blocked by an open trial/paywall sheet, retry
    /// once those sheets clear instead of burning the positive moment.
    @State private var pendingReviewAfterSheetsClear = false
    @Environment(\.requestReview) private var requestReview
    /// The feature an intent tap reached for, so the trial sheet (and the plan
    /// picker it can chain into) lead with it. `nil` for passive offers.
    @State private var trialOfferFocus: PlusFeature?
    /// A toggle-gated feature (Net Deficit, Active/Resting) the user explicitly
    /// tried to turn *on* but got paywalled. When set, we flip the matching
    /// setting on automatically once they upgrade — but only because they
    /// reached for it. Buying from the generic Upgrade tab leaves it `nil`, so
    /// those features stay off until the user chooses them.
    @State private var pendingFeatureEnable: PlusFeature?

    private enum TrialOfferSource {
        case launch
        case historyLoad
        case intent
    }

    init() {
        if ScreenshotConfig.wantsHistoryTab {
            _selectedTab = State(initialValue: 1)
            _historyHasAppeared = State(initialValue: true)
        } else if ScreenshotConfig.wantsPremiumTab {
            _selectedTab = State(initialValue: 2)
        }
    }

    /// True when we have a Vitals+ package with a free-trial intro offer available.
    private var hasTrialOffer: Bool {
        store.products.contains { $0.vitalsIntroOfferLabel != nil }
    }

    /// The package the direct trial purchase buys: prefer the yearly plan that
    /// carries a free-trial intro offer, else any trial-bearing package.
    private var directTrialPackage: Package? {
        let trialPackages = store.products.filter { $0.vitalsIntroOfferLabel != nil }
        return trialPackages.first { $0.vitalsPackageKind == .yearly } ?? trialPackages.first
    }

    /// Hybrid one-tap purchase applies when a trial product is actually loaded;
    /// otherwise fall back to the full plan picker paywall.
    private var trialOfferIsDirect: Bool {
        trialOfferUsesDirectPurchase
    }

    private func presentTrialOffer(source: TrialOfferSource, focus: PlusFeature? = nil) {
        trialOfferSource = source
        trialOfferFocus = focus
        trialOfferPackage = directTrialPackage
        trialOfferUsesDirectPurchase = trialOfferPackage != nil
        trialOfferDetent = .fraction(0.68)
        showTrialOffer = true
    }

    private func startDirectTrialPurchase() {
        guard let package = trialOfferPackage ?? directTrialPackage else {
            // No trial product loaded — fall back to the full plan picker paywall.
            pendingPaywallAfterTrialDismiss = true
            showTrialOffer = false
            return
        }
        trialPurchaseError = nil
        trialPurchaseInFlight = true
        Task { @MainActor in
            defer { trialPurchaseInFlight = false }
            do {
                switch try await store.purchase(package) {
                case .purchased, .pending:
                    markTrialOfferSeen()
                    showTrialOffer = false
                case .cancelled:
                    // Surface a hint so the sheet doesn't sit silent — the StoreKit
                    // sheet dismissed but the user might think the app froze.
                    trialPurchaseError = "Trial wasn't started. Tap again, or pick a different plan."
                }
            } catch {
                trialPurchaseError = "Couldn't start your trial. Please try again."
            }
        }
    }

    /// Presents the one-time "What's New" announcement for existing users who
    /// just updated. Returns true when it took over the launch moment so the
    /// caller skips the passive trial nudge this session. Gated so fresh installs
    /// (seeded past it in GoalSettings) and screenshot runs never see it, and so
    /// it never stacks on top of another sheet.
    @discardableResult
    private func maybeShowWhatsNew() -> Bool {
        guard !whatsNewEvaluated,
              goals.hasCompletedSetup,
              !ScreenshotConfig.isEnabled,
              WhatsNew.shouldShow(lastShown: goals.lastWhatsNewVersionShown),
              selectedTab == 0,
              // Wait for the dashboard's first real paint so the announcement
              // lands over the user's data, not a launch spinner.
              dashboardDataLoaded,
              !showTrialOffer, !showTrialPaywall, !showMilestone,
              !showReviewPrompt, !showWeeklyRecap
        else { return false }
        whatsNewEvaluated = true
        // Mark seen on present so a force-quit can't make it reappear, and so the
        // passive trial nudge stays suppressed for the rest of this session.
        goals.lastWhatsNewVersionShown = WhatsNew.currentVersion
        launchOfferShownThisSession = true
        showWhatsNew = true
        return true
    }

    private func evaluateTrialOffer() {
        // The What's New announcement owns the launch moment for users who just
        // updated; don't stack the passive trial pitch on top of it.
        guard !showWhatsNew else { return }
        // Just finished onboarding this session — they already saw the trial step.
        // Re-pitch on a later cold launch at the value moment, not minutes later.
        guard !skipPassiveTrialThisSession else { return }
        // Passive launch nudge: gated by [[GoalSettings.passiveTrialOfferAllowed]]
        // so the user re-encounters it after a 14-day cooldown rather than
        // being killed forever by a single "Not now". Intent-driven taps
        // bypass this cooldown.
        guard goals.hasCompletedSetup,
              !store.isPro,
              goals.passiveTrialOfferAllowed(),
              hasTrialOffer,
              selectedTab == 0,
              // Strategic value moment: only pitch after the dashboard has shown
              // real, non-zero data — never over a spinner or a row of zeros.
              dashboardShowedRealData
        else { return }
        // Brief settle so the ring/counter first-paint animations finish before
        // the pitch appears over the numbers the user just watched populate.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if directTrialPackage == nil { await store.fetchProducts() }
            guard !skipPassiveTrialThisSession else { return }
            guard !showTrialOffer, !showTrialPaywall, !showWhatsNew else { return }
            guard selectedTab == 0 else { return }
            if goals.passiveTrialOfferAllowed() && !store.isPro {
                launchOfferShownThisSession = true
                presentTrialOffer(source: .launch)
            }
        }
    }

    /// Second-touch trial nudge: fires when History finishes loading. Subject to
    /// the same 14-day passive cooldown, and additionally gated so it never
    /// fires back-to-back with the launch offer in the same session.
    /// Passive review ask after a positive moment (e.g. daily goal). Waits for the
    /// on-dashboard celebration toast to clear; never fires on cold launch.
    private func scheduleReviewPromptAfterPositiveMoment() {
        guard ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: goals.hasCompletedSetup),
              !reviewPromptShownThisSession,
              selectedTab == 0,
              !showMilestone,
              !showReviewPrompt
        else { return }

        // Don't lose the ask to a trial/paywall sheet — retry when those clear.
        if showTrialOffer || showTrialPaywall {
            pendingReviewAfterSheetsClear = true
            return
        }

        Task { @MainActor in
            // Let the goal celebration toast finish (~2.5s) before asking.
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard selectedTab == 0,
                  !showTrialOffer,
                  !showTrialPaywall,
                  !showMilestone,
                  !showReviewPrompt,
                  ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: goals.hasCompletedSetup)
            else {
                if showTrialOffer || showTrialPaywall {
                    pendingReviewAfterSheetsClear = true
                }
                return
            }
            ReviewPromptTracker.consumePendingPositiveMoment()
            reviewPromptInitialStep = .enjoyment
            reviewPromptShownThisSession = true
            showReviewPrompt = true
        }
    }

    private func presentPendingReviewIfNeeded() {
        guard pendingReviewAfterSheetsClear,
              !reviewPromptShownThisSession,
              !showTrialOffer,
              !showTrialPaywall,
              !showMilestone,
              !showReviewPrompt,
              ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: goals.hasCompletedSetup)
        else { return }
        pendingReviewAfterSheetsClear = false
        ReviewPromptTracker.consumePendingPositiveMoment()
        reviewPromptInitialStep = .enjoyment
        reviewPromptShownThisSession = true
        showReviewPrompt = true
    }

    private func handleReviewPromptFinish(_ outcome: ReviewPromptDismissOutcome) {
        showReviewPrompt = false
        if outcome == .enjoyedMaybeLater {
            pendingNativeReviewAfterDismiss = true
        }
    }

    private func presentReviewPrompt(step: ReviewPromptSheet.Step) {
        reviewPromptInitialStep = step
        reviewPromptShownThisSession = true
        showReviewPrompt = true
    }

    private func evaluateHistoryTrialOffer() {
        guard goals.hasCompletedSetup,
              !store.isPro,
              !skipPassiveTrialThisSession,
              goals.passiveHistoryTrialOfferAllowed(),
              !launchOfferShownThisSession,
              hasTrialOffer,
              selectedTab == 1,
              !showTrialOffer,
              !showTrialPaywall
        else { return }
        presentTrialOffer(source: .historyLoad)
    }

    /// Records the last-shown timestamp for whichever trigger opened the offer.
    /// Both intent and passive presentations update the timestamp — the
    /// cooldown then naturally suppresses passive surfaces while still letting
    /// intent taps fire on demand.
    private func markTrialOfferSeen() {
        let now = Date()
        goals.lastTrialOfferShownDate = now
        if trialOfferSource == .historyLoad {
            goals.lastHistoryTrialOfferShownDate = now
        }
    }

    /// Intent-driven entrypoint. Bypasses the passive cooldown so feature-tap
    /// moments (locked Custom range, Net Deficit toggle, PDF icon) always get
    /// the high-converting trial pitch when a trial product is available. Falls
    /// back to the full plan picker paywall when no trial product is loaded.
    private func handleIntentTap(_ intent: TrialOfferCoordinator.Intent) {
        defer { trialCoordinator.clear() }
        guard !store.isPro else { return }
        guard !showTrialOffer, !showTrialPaywall else { return }
        let focus = intent.focusFeature
        trialOfferFocus = focus
        // Only toggle-gated features get auto-enabled on upgrade; Deep Trends /
        // PDF unlock implicitly with Pro and need no stored setting.
        switch intent {
        case .netDeficitToggle: pendingFeatureEnable = .netDeficit
        case .activeRestingToggle: pendingFeatureEnable = .activeResting
        case .energyAveragesToggle: pendingFeatureEnable = .energyAverages
        case .projectionsToggle: pendingFeatureEnable = .projections
        case .streaksToggle: pendingFeatureEnable = .streaks
        case .weeklyRecapToggle: pendingFeatureEnable = .weeklyRecap
        default: pendingFeatureEnable = nil
        }
        if hasTrialOffer {
            presentTrialOffer(source: .intent, focus: focus)
        } else {
            showTrialPaywall = true
        }
    }

    /// Flips on whichever toggle-gated feature the user reached for before they
    /// were paywalled, now that they're Pro. No-op for passive upgrades.
    private func applyPendingFeatureEnable() {
        guard let feature = pendingFeatureEnable else { return }
        pendingFeatureEnable = nil
        switch feature {
        case .netDeficit:
            goals.showNetCalories = true
            Task { try? await HealthKitService.shared.requestDietaryAuthorization() }
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

    /// Presents a celebratory milestone sheet at most once per session, for
    /// non-Pro users only (Pro users have nothing to upsell). Records the
    /// milestone id immediately so the same achievement never re-fires.
    private func handleMilestone(_ event: MilestoneEvent) {
        defer { milestoneCoordinator.clear() }
        guard !store.isPro,
              !milestoneShownThisSession,
              !goals.firedMilestoneIds.contains(event.id),
              !showTrialOffer, !showTrialPaywall, !showMilestone
        else { return }
        goals.firedMilestoneIds.insert(event.id)
        milestoneShownThisSession = true
        pendingMilestone = event
        showMilestone = true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keep both views alive, toggle visibility. `.accessibilityHidden` on the
            // inactive tab prevents VoiceOver's rotor from surfacing elements that are
            // visually invisible (opacity 0) but still in the accessibility tree.
            DashboardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)
                .accessibilityHidden(selectedTab != 0)
            if historyHasAppeared {
                HistoryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
                    .accessibilityHidden(selectedTab != 1)
            }
            Group {
                if store.isPro {
                    PremiumFeaturesView(
                        onOpenNetDeficit: {
                            // Enable the toggle (DashboardView's onChange will request
                            // dietary HK auth + refresh). Also request directly here so
                            // the user gets the system sheet even if the toggle was
                            // already on but auth was previously denied/revoked.
                            GoalSettings.shared.showNetCalories = true
                            Task { try? await HealthKitService.shared.requestDietaryAuthorization() }
                            selectedTab = 0
                        }
                    )
                } else {
                    PaywallView(displayCloseButton: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Reserve space so the native paywall's CTA + footer aren't
                // hidden by the floating tab-bar capsule below.
                Color.clear.frame(height: 68)
            }
            .opacity(selectedTab == 2 ? 1 : 0)
            .allowsHitTesting(selectedTab == 2)
            .accessibilityHidden(selectedTab != 2)

            // Custom tab bar — always visible so the user can navigate away from
            // the paywall. The native paywall scrolls its own auto-renew disclosure,
            // so the tab bar overlay doesn't break 3.1.2(a).
            HStack(spacing: 0) {
                TabButton(
                    icon: "heart.fill",
                    label: "Today",
                    isSelected: selectedTab == 0
                ) { selectedTab = 0 }

                TabButton(
                    icon: "chart.bar.fill",
                    label: "History",
                    isSelected: selectedTab == 1
                ) {
                    if !historyHasAppeared { historyHasAppeared = true }
                    selectedTab = 1
                }

                TabButton(
                    icon: store.isPro ? "sparkles" : "lock.fill",
                    label: store.isPro ? "Vitals+" : "Upgrade",
                    isSelected: selectedTab == 2
                ) { selectedTab = 2 }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            .padding(.bottom, 12)
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            // Wait briefly for products to load, then consider the launch
            // surfaces. What's New (for users who just updated) takes priority
            // over the passive trial nudge.
            if store.products.isEmpty { await store.fetchProducts() }
            if !maybeShowWhatsNew() { evaluateTrialOffer() }
        }
        .onChange(of: store.products.count) { _, _ in evaluateTrialOffer() }
        // First-launch users complete onboarding *after* the .task /
        // products-loaded evaluations have already bailed on
        // `hasCompletedSetup == false`. Mark this session so the passive
        // TrialOfferSheet doesn't re-pitch minutes after the onboarding trial
        // step; the next cold launch can pitch at the value moment.
        .onChange(of: goals.hasCompletedSetup) { _, done in
            if done { skipPassiveTrialThisSession = true }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro {
                applyPendingFeatureEnable()
                showTrialOffer = false
                showMilestone = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalsDashboardDidLoadData)) { _ in
            dashboardDataLoaded = true
            // What's New can show over any dashboard state; the passive trial
            // nudge waits for the real-data value moment below.
            maybeShowWhatsNew()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalsDashboardDidShowRealData)) { _ in
            // Strategic value moment (Rev A): real numbers are on screen. Now the
            // passive trial nudge is allowed to consider firing.
            dashboardShowedRealData = true
            if !maybeShowWhatsNew() { evaluateTrialOffer() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalsHistoryDidFinishLoading)) { _ in
            evaluateHistoryTrialOffer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalsPositiveMomentForReview)) { _ in
            scheduleReviewPromptAfterPositiveMoment()
        }
        .onChange(of: trialCoordinator.pendingIntent) { _, intent in
            guard let intent else { return }
            handleIntentTap(intent)
        }
        .onChange(of: milestoneCoordinator.pendingEvent) { _, event in
            guard let event else { return }
            handleMilestone(event)
        }
        .onChange(of: recapCoordinator.pendingPresent) { _, present in
            guard present else { return }
            recapCoordinator.clear()
            // Land on Today, then present the recap once no other sheet is up.
            guard !showTrialOffer, !showTrialPaywall, !showMilestone, !showReviewPrompt else { return }
            selectedTab = 0
            showWeeklyRecap = true
        }
        .onChange(of: reviewPromptCoordinator.pendingPresentation) { _, presentation in
            guard let presentation else { return }
            defer { reviewPromptCoordinator.clear() }
            guard !showTrialOffer, !showTrialPaywall, !showMilestone else { return }
            switch presentation {
            case .enjoymentPrompt:
                presentReviewPrompt(step: .enjoyment)
            case .feedbackOnly:
                presentReviewPrompt(step: .feedback)
            }
        }
        // Vitals+ tab content stays in the hierarchy (opacity-toggled), so the
        // paywall's own lifecycle hooks can't tell when it's actually on screen.
        // Fire the impression on the real visibility transition instead, and
        // only when the paywall (not the Pro features view) is what renders.
        .onChange(of: selectedTab) { _, tab in
            if tab == 2, !store.isPro {
                store.trackPaywallImpression(id: "vitals_upgrade_tab", oncePerSession: true)
            }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: {
            // Chain the follow-on action only after the announcement has fully
            // dismissed — SwiftUI drops a second sheet presented in the same tick.
            if pendingTrialAfterWhatsNewDismiss {
                pendingTrialAfterWhatsNewDismiss = false
                handleIntentTap(.whatsNewAnnouncement)
            } else if pendingSettingsAfterWhatsNewDismiss {
                pendingSettingsAfterWhatsNewDismiss = false
                NotificationCenter.default.post(name: .vitalsOpenSettings, object: nil)
            }
        }) {
            WhatsNewSheet(
                isPro: store.isPro,
                onTryFree: {
                    pendingTrialAfterWhatsNewDismiss = true
                    showWhatsNew = false
                },
                onOpenSettings: {
                    pendingSettingsAfterWhatsNewDismiss = true
                    showWhatsNew = false
                },
                onDismiss: { showWhatsNew = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTrialOffer, onDismiss: {
            markTrialOfferSeen()
            trialPurchaseInFlight = false
            trialPurchaseError = nil
            trialOfferPackage = nil
            trialOfferUsesDirectPurchase = false
            // Chain the plan picker paywall here rather than setting both bindings in
            // the same tick — SwiftUI can only show one sheet per ancestor at a
            // time and frequently drops the second when they fire together.
            if pendingPaywallAfterTrialDismiss {
                pendingPaywallAfterTrialDismiss = false
                showTrialPaywall = true
            } else if !store.isPro {
                // Dismissed without upgrading and not chaining to the plan
                // picker — drop the intent so a later unrelated purchase doesn't
                // silently flip the feature on.
                pendingFeatureEnable = nil
                presentPendingReviewIfNeeded()
            }
        }) {
            TrialOfferSheet(
                focus: trialOfferFocus,
                offerLabel: trialOfferPackage?.vitalsIntroOfferLabel ?? store.products.compactMap(\.vitalsIntroOfferLabel).first,
                priceLabel: trialOfferPackage?.vitalsPriceLabel,
                directPurchase: trialOfferIsDirect,
                isPurchasing: trialPurchaseInFlight,
                errorMessage: trialPurchaseError,
                onStartTrial: {
                    if trialOfferIsDirect {
                        startDirectTrialPurchase()
                    } else {
                        pendingPaywallAfterTrialDismiss = true
                        showTrialOffer = false
                    }
                },
                onSeeAllPlans: {
                    // Always the full plan picker — never another trial sheet.
                    pendingPaywallAfterTrialDismiss = true
                    showTrialOffer = false
                },
                onDismiss: {
                    showTrialOffer = false
                }
            )
            .presentationDetents([.fraction(0.68), .large], selection: $trialOfferDetent)
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(trialPurchaseInFlight)
        }
        .sheet(isPresented: $showTrialPaywall, onDismiss: {
            trialOfferFocus = nil
            if !store.isPro { pendingFeatureEnable = nil }
            presentPendingReviewIfNeeded()
        }) {
            PaywallView(focus: trialOfferFocus)
                .environmentObject(store)
                // `.task` runs once per sheet presentation — the correct hook
                // for a one-shot impression (unlike onAppear, which re-fires).
                .task { store.trackPaywallImpression(id: "vitals_trial_sheet") }
        }
        .sheet(isPresented: $showMilestone, onDismiss: {
            let chainPaywall = pendingPaywallAfterMilestoneDismiss
            pendingPaywallAfterMilestoneDismiss = false
            pendingMilestone = nil
            // Explore → full plan picker only. Never chain into TrialOfferSheet
            // (trial-on-trial).
            if chainPaywall {
                showTrialPaywall = true
            } else {
                presentPendingReviewIfNeeded()
            }
        }) {
            if let pendingMilestone {
                MilestoneCelebrationSheet(
                    event: pendingMilestone,
                    onContinue: {
                        pendingPaywallAfterMilestoneDismiss = true
                        showMilestone = false
                    },
                    onDismiss: { showMilestone = false }
                )
                .presentationDetents([.fraction(0.7), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showReviewPrompt, onDismiss: {
            ReviewPromptTracker.markShown()
            if pendingNativeReviewAfterDismiss {
                pendingNativeReviewAfterDismiss = false
                requestReview()
            }
        }) {
            ReviewPromptSheet(initialStep: reviewPromptInitialStep, onFinish: handleReviewPromptFinish)
        }
        .sheet(isPresented: $showWeeklyRecap) {
            WeeklyRecapView(goals: goals)
        }
    }

}

private struct PremiumFeaturesView: View {
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject private var store: StoreService
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    @State private var pdfFile: PDFFile?
    @State private var pdfTitle = "Vitals+ Report"
    @State private var pdfShareText = SummaryReportShareText.appStoreURL
    @State private var showPDFPreviewSheet = false
    @State private var isGeneratingReport = false
    @State private var reportErrorMessage: String?
    @State private var showCustomReportSheet = false
    @State private var customStart = DateHelpers.daysAgo(29)
    @State private var customEnd = Date.now

    let onOpenNetDeficit: () -> Void

    @State private var deepTrendInsights: [DeepTrendInsight] = []
    @State private var deepTrendHighlights: [String] = []
    @State private var deepTrendsLoaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        premiumHeader

                        VStack(spacing: 8) {
                            PremiumActionRow(
                                icon: "plus.forwardslash.minus",
                                title: "Net Deficit",
                                detail: "Burn minus Apple Health food on Today + History.",
                                buttonTitle: "Enable",
                                action: onOpenNetDeficit,
                                isEnabled: goals.showNetCalories
                            )
                            PremiumActionRow(
                                icon: "doc.richtext.fill",
                                title: "Monthly Summary PDF",
                                detail: "Generate a 30-day report and preview before sharing.",
                                buttonTitle: "Generate",
                                action: { Task { await generateReport(days: 30, title: "30-Day Summary") } }
                            )
                            PremiumActionRow(
                                icon: "calendar.badge.clock",
                                title: "Custom-Range Reports",
                                detail: "Pick an exact range and review the PDF in-app.",
                                buttonTitle: "Choose Dates",
                                action: { showCustomReportSheet = true }
                            )
                        }

                        deepTrendsSection

                        accountSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 96)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Vitals+")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if !deepTrendsLoaded { await loadDeepTrends() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await loadDeepTrends() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await loadDeepTrends() }
            }
            .sheet(isPresented: $showCustomReportSheet) {
                PremiumCustomReportSheet(start: $customStart, end: $customEnd, isGenerating: isGeneratingReport) {
                    Task { await generateReport(start: customStart, end: customEnd, title: "Custom Summary") }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showPDFPreviewSheet, onDismiss: {
                if let pdfFile {
                    try? FileManager.default.removeItem(at: pdfFile.url)
                    self.pdfFile = nil
                }
            }) {
                if let pdfFile {
                    PDFPreviewSheet(title: pdfTitle, url: pdfFile.url, shareText: pdfShareText)
                }
            }
            .alert("Vitals+", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
            .alert("Report Failed", isPresented: Binding(get: { reportErrorMessage != nil }, set: { if !$0 { reportErrorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(reportErrorMessage ?? "")
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isGeneratingReport {
                    HStack(spacing: 10) {
                        LoadingBar(color: Theme.caloriesPrimary)
                            .frame(width: 60)
                        Text("Generating report…")
                            .font(.system(.footnote, design: .rounded, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.cardSurface, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isGeneratingReport)
        }
    }

    private var deepTrendsSection: some View {
        DeepTrendsCard(
            isPro: true,
            isCalculating: !deepTrendsLoaded,
            insights: deepTrendInsights,
            highlights: deepTrendHighlights,
            periodLabel: "vs. previous 30 days",
            onUpgrade: {}
        )
    }

    private func loadDeepTrends() async {
        do {
            let history = try await healthKit.fetchHistory(days: 30)
            let calendar = Calendar.current
            let priorEnd = calendar.date(byAdding: .day, value: -1, to: history.first?.date ?? DateHelpers.daysAgo(29)) ?? Date.now
            let priorStart = calendar.date(byAdding: .day, value: -29, to: priorEnd) ?? priorEnd
            let previous = (try? await healthKit.fetchHistory(from: priorStart, to: priorEnd)) ?? []

            let currentRecords = history.map { DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps) }
            let previousRecords = previous.map { DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps) }

            deepTrendInsights = DeepTrendsBuilder.insights(currentRecords: currentRecords, previousRecords: previousRecords)
            deepTrendHighlights = DeepTrendsBuilder.highlights(records: currentRecords)
            deepTrendsLoaded = true
        } catch {
            deepTrendsLoaded = true
        }
    }

    private var premiumHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.caloriesGradient)
                    .frame(width: 48, height: 48)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Vitals+ Active")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Premium tools are ready to use.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Button {
                guard !isRestoring else { return }
                isRestoring = true
                Task {
                    defer { isRestoring = false }
                    await store.restorePurchases()
                    // `StoreService.restorePurchases()` clears `lastError` on entry
                    // and writes either the success or the failure message, so the
                    // view doesn't need to invent its own fallback string.
                    restoreMessage = store.isPro
                        ? "Your Vitals+ access is active."
                        : (store.lastError ?? "Couldn't refresh your subscription. Try again.")
                }
            } label: {
                PremiumAccountRow(
                    icon: "arrow.clockwise",
                    title: isRestoring ? "Restoring…" : "Restore Purchases",
                    detail: "Refresh your access after changing devices or reinstalling.",
                    showsActivity: isRestoring
                )
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)
        }
    }

    private func generateReport(days: Int, title: String) async {
        await generateReport(start: nil, end: nil, days: days, title: title)
    }

    private func generateReport(start: Date, end: Date, title: String) async {
        await generateReport(start: start, end: end, days: nil, title: title)
    }

    private func generateReport(start: Date? = nil, end: Date? = nil, days: Int? = nil, title: String) async {
        guard !isGeneratingReport else { return }
        isGeneratingReport = true
        defer { isGeneratingReport = false }
        try? await Task.sleep(nanoseconds: 100_000_000)

        do {
            let history: [(date: Date, active: Double, resting: Double, steps: Int)]
            if let days {
                history = try await healthKit.fetchHistory(days: days)
            } else if let start, let end {
                history = try await healthKit.fetchHistory(from: start, to: end)
            } else {
                history = try await healthKit.fetchHistory(days: 30)
            }

            guard !history.isEmpty else {
                reportErrorMessage = "There is no history data for that report range yet."
                return
            }

            let periodStart = history.map(\.date).min() ?? start ?? Date.now
            let periodEnd = history.map(\.date).max() ?? end ?? Date.now
            let previous = await previousWindow(start: periodStart, end: periodEnd, days: days)
            let foodMap = await dietaryMap(start: start, end: end, days: days)
            let calendar = Calendar.current

            let reportDays = history.map { rec in
                ReportDay(
                    date: rec.date,
                    activeCalories: rec.active,
                    restingCalories: rec.resting,
                    steps: rec.steps,
                    foodCalories: foodMap[calendar.startOfDay(for: rec.date)]
                )
            }
            let previousDays = previous.map { rec in
                ReportDay(
                    date: rec.date,
                    activeCalories: rec.active,
                    restingCalories: rec.resting,
                    steps: rec.steps,
                    foodCalories: nil
                )
            }
            let report = SummaryReportGenerator.make(
                title: title,
                periodStart: periodStart,
                periodEnd: periodEnd,
                days: reportDays,
                previousDays: previousDays,
                calorieGoal: goals.calorieGoal,
                stepGoal: goals.stepGoal
            )
            let url = try SummaryReportPDF.render(report)
            pdfTitle = title
            pdfShareText = SummaryReportShareText.make(report: report)
            pdfFile = PDFFile(url: url)
            showPDFPreviewSheet = true
        } catch {
            reportErrorMessage = "Could not generate the PDF report. Please try again."
        }
    }

    private func previousWindow(start: Date, end: Date, days: Int?) async -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let calendar = Calendar.current
        let lengthDays = days ?? max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        let priorEnd = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let priorStart = calendar.date(byAdding: .day, value: -(lengthDays - 1), to: priorEnd) ?? priorEnd
        return (try? await healthKit.fetchHistory(from: priorStart, to: priorEnd)) ?? []
    }

    private func dietaryMap(start: Date?, end: Date?, days: Int?) async -> [Date: Double] {
        guard goals.showNetCalories else { return [:] }
        let dietary: [(date: Date, foodCalories: Double)]
        do {
            if let days {
                dietary = try await healthKit.fetchDietaryHistory(days: days)
            } else if let start, let end {
                dietary = try await healthKit.fetchDietaryHistory(from: start, to: end)
            } else {
                dietary = try await healthKit.fetchDietaryHistory(days: 30)
            }
        } catch {
            return [:]
        }
        var map: [Date: Double] = [:]
        let calendar = Calendar.current
        for day in dietary {
            map[calendar.startOfDay(for: day.date)] = day.foodCalories
        }
        return map
    }
}

private struct PremiumCustomReportSheet: View {
    @Binding var start: Date
    @Binding var end: Date
    let isGenerating: Bool
    let onGenerate: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        start < end && (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) <= 730
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $start, in: ...Date.now, displayedComponents: .date)
                DatePicker("End", selection: $end, in: ...Date.now, displayedComponents: .date)
                if !isValid {
                    Section {
                        Text(start >= end ? "Start date must be before end date." : "Maximum range is 2 years.")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Custom Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        dismiss()
                        onGenerate()
                    }
                    .bold()
                    .disabled(!isValid || isGenerating)
                }
            }
        }
    }
}

private struct PremiumActionRow: View {
    let icon: String
    let title: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void
    var isEnabled: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.caloriesPrimary)
                .frame(width: 28, height: 28)
                .background(Theme.caloriesPrimary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if isEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Enabled")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                }
                .foregroundStyle(Theme.stepsPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.stepsPrimary.opacity(0.15), in: Capsule())
            } else {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.caloriesGradient, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

private struct PremiumAccountRow: View {
    let icon: String
    let title: String
    let detail: String
    var showsActivity: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.caloriesPrimary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if showsActivity {
                ProgressView().tint(Theme.textTertiary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

struct TrialOfferSheet: View {
    /// When set, the sheet leads with and highlights this feature instead of the
    /// generic toolkit pitch. `nil` for passive launch/history nudges.
    let focus: PlusFeature?
    let offerLabel: String?
    /// Recurring price after the trial, e.g. "$29.99 / year". Only required in
    /// `directPurchase` mode (Apple 3.1.2 needs price + terms before purchase).
    let priceLabel: String?
    /// When true the primary button buys the trial product directly via StoreKit
    /// and the sheet shows compliant billing disclosure + a "See all plans" link.
    /// When false it opens the full native plan picker paywall.
    let directPurchase: Bool
    let isPurchasing: Bool
    let errorMessage: String?
    let onStartTrial: () -> Void
    let onSeeAllPlans: () -> Void
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateGlow = false
    @State private var shimmerPhase: CGFloat = -1

    /// Headline copy. Falls back to a generic title when StoreKit hasn't loaded a
    /// trial-bearing product yet, but in practice `directTrialPackage` gates the
    /// pitch so `offerLabel` is almost always present.
    private var headline: String {
        if let focus { return focus.intentHeadline }
        if let offerLabel {
            return "\(offerLabel.capitalized), on us."
        }
        return "Try Vitals+ free."
    }

    private var subheadline: String {
        if let focus {
            if offerLabel != nil {
                return "\(focus.intentSubheadline) Free for 7 days. Cancel anytime."
            }
            return focus.intentSubheadline
        }
        return offerLabel != nil
            ? "Calories, steps, and trends in one place. No charge until your trial ends."
            : "Calories, steps, and trends in one place."
    }

    /// Focused feature first with two related companions; generic trio when passive.
    private var bulletFeatures: [PlusFeature] {
        if let focus { return [focus] + focus.companionFeatures }
        return [.netDeficit, .deepTrends, .customRangesPDF]
    }

    /// Deal badge text derived from the real offer, e.g. "7-day free trial" →
    /// "7 DAYS FREE". Falls back to a generic label if the day count can't be
    /// parsed. Never invents a number — only reflects the loaded offer.
    private var trialBadgeText: String {
        guard let offerLabel,
              let days = offerLabel.split(whereSeparator: { !$0.isNumber }).first,
              !days.isEmpty else {
            return "FREE TRIAL"
        }
        return "\(days) DAYS FREE"
    }

    /// Repeat-forever animation timing for the ambient glow. Scoped to the
    /// specific views that read `animateGlow` via `.animation(_:value:)` so the
    /// animation context can't leak into unrelated layout changes (e.g. the
    /// error message appearing, which previously caused the bullet rows to
    /// ghost during reflow).
    private var glowAnimation: Animation {
        .easeInOut(duration: 2.2).repeatForever(autoreverses: true)
    }

    private var shimmerAnimation: Animation {
        .linear(duration: 2.6).repeatForever(autoreverses: false).delay(0.4)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // Coral ambient glows (Rev A: deal framing consistent with the coral
            // Vitals theme rather than the teal steps palette).
            Circle()
                .fill(Theme.caloriesPrimary.opacity(0.22))
                .frame(width: 240, height: 240)
                .blur(radius: 38)
                .offset(x: animateGlow ? 96 : -96, y: animateGlow ? -220 : -180)
                .animation(glowAnimation, value: animateGlow)
            Circle()
                .fill(Theme.caloriesSecondary.opacity(0.20))
                .frame(width: 190, height: 190)
                .blur(radius: 34)
                .offset(x: animateGlow ? -110 : 110, y: animateGlow ? 250 : 210)
                .animation(glowAnimation, value: animateGlow)
            // Light "shine" particles drifting behind the hero. Suppressed when
            // Reduce Motion is on so we stay accessibility-compliant.
            if !reduceMotion {
                SparkleField(phase: animateGlow ? 1 : 0)
                    .allowsHitTesting(false)
                    .opacity(0.55)
                    .animation(glowAnimation, value: animateGlow)
            }

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.caloriesGradient)
                        .frame(width: 60, height: 60)
                        .shadow(color: Theme.caloriesPrimary.opacity(0.45), radius: 14, x: 0, y: 4)
                        .scaleEffect(animateGlow ? 1.06 : 0.96)
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 50, height: 50)
                        .scaleEffect(animateGlow ? 1.03 : 0.98)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(animateGlow ? 6 : -6))
                }
                .padding(.top, 4)
                .animation(glowAnimation, value: animateGlow)

                // Prominent deal badge (Rev A): "7 DAYS FREE" in a coral,
                // gradient-filled pill with a soft glow so the offer reads as a
                // deal at a glance. Text derived from the real loaded offer.
                Text(trialBadgeText)
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Theme.caloriesGradient, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: Theme.caloriesPrimary.opacity(0.5), radius: animateGlow ? 12 : 6, x: 0, y: 2)
                    .scaleEffect(animateGlow ? 1.03 : 1.0)
                    .animation(glowAnimation, value: animateGlow)
                    .accessibilityLabel(trialBadgeText.capitalized)

                VStack(spacing: 4) {
                    Text(headline)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .overlay(shimmerOverlay)
                        .mask(
                            // Must mirror the base Text's layout modifiers exactly
                            // (including minimumScaleFactor) or a scaled-down longer
                            // headline misaligns with the mask and renders garbled.
                            Text(headline)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        )
                    Text(subheadline)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 6) {
                    ForEach(bulletFeatures, id: \.self) { feature in
                        TrialBulletRow(
                            bullet: TrialBullet(
                                icon: feature.icon,
                                tint: feature.tint,
                                title: feature.title,
                                detail: feature.detail
                            ),
                            highlighted: feature == focus,
                            compact: focus != nil ? feature != focus : true
                        )
                    }
                }

                Group {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: errorMessage)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if directPurchase, let priceLabel {
                        Text("Free during trial, then \(priceLabel). Auto-renews unless cancelled 24h before trial ends.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onStartTrial) {
                        ZStack {
                            Text("Start My Free Trial")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(isPurchasing ? 0 : 1)
                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.caloriesGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)

                    if directPurchase {
                        Button(action: onSeeAllPlans) {
                            Text("See all plans")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.caloriesPrimary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isPurchasing)
                    }

                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)

                    HStack(spacing: 4) {
                        Link("Terms", destination: PaywallLinks.standardEULA)
                        Text("·")
                        Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
                    }
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            // Plain state set — each animated view applies the repeating
            // animation locally via `.animation(_:value:)`, so the animation
            // context cannot leak into unrelated layout changes (e.g. error
            // message appearing, button spinner toggle). withAnimation here
            // would propagate the repeating animation onto every state change
            // made anywhere in this view tree for the lifetime of the sheet.
            animateGlow = true
            shimmerPhase = 1.4
        }
    }

    /// A diagonal moving highlight masked to the headline. Kept extremely subtle
    /// (white at 0.55 alpha at the peak) so it reads as "premium" rather than
    /// "loading skeleton".
    private var shimmerOverlay: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white.opacity(0.55), location: 0.5),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.5)
            .offset(x: shimmerPhase * width)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .animation(shimmerAnimation, value: shimmerPhase)
        }
    }
}

/// Celebratory sheet shown when the user hits a goal streak or completes a
/// reviewable month. Frames Vitals+ as the natural "go deeper" next step —
/// "you've earned this" rather than "buy this". The CTA chains into the trial
/// offer; dismissing just closes.
private struct MilestoneCelebrationSheet: View {
    let event: MilestoneEvent
    let onContinue: () -> Void
    let onDismiss: () -> Void

    private var heroIcon: String {
        switch event {
        case .goalStreak: return "flame.fill"
        case .monthReview: return "calendar"
        }
    }

    private var headline: String {
        switch event {
        case .goalStreak(let n): return "\(n)-day streak!"
        case .monthReview(let month, _): return "\(Self.monthName(month)) recap"
        }
    }

    private var subheadline: String {
        switch event {
        case .goalStreak(let n):
            return "You hit your goal \(n) days in a row. That consistency is the whole game."
        case .monthReview(_, let days):
            return "You logged \(days) days last month. There's a story in that data worth seeing."
        }
    }

    private var bullets: [TrialBullet] {
        [
            TrialBullet(
                icon: "chart.line.uptrend.xyaxis",
                tint: Theme.stepsPrimary,
                title: "Deep Trends",
                detail: "See how this run stacks up against your past, period over period."
            ),
            TrialBullet(
                icon: "doc.richtext.fill",
                tint: Theme.caloriesPrimary,
                title: "PDF report",
                detail: "Export a clean summary of this milestone to keep or share with a coach."
            )
        ]
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.caloriesGradient)
                        .frame(width: 76, height: 76)
                        .shadow(color: Theme.caloriesPrimary.opacity(0.4), radius: 16, x: 0, y: 6)
                    Image(systemName: heroIcon)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text(headline)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(subheadline)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                }

                VStack(spacing: 10) {
                    ForEach(bullets) { bullet in
                        TrialBulletRow(bullet: bullet)
                    }
                }
                .padding(.horizontal, 4)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button(action: onContinue) {
                        Text("Explore with Vitals+")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.caloriesGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Text("Maybe later")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// "2025-04" → "April". Falls back to the raw key if parsing fails.
    private static func monthName(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]), (1...12).contains(month) else {
            return key
        }
        var comps = DateComponents()
        comps.month = month
        comps.day = 1
        comps.year = Int(parts[0])
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        if let date = Calendar.current.date(from: comps) {
            return formatter.string(from: date)
        }
        return key
    }
}

private struct TrialBullet: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let detail: String
}

private struct TrialBulletRow: View {
    let bullet: TrialBullet
    /// The feature the user tapped for: render it with a stronger tinted fill and
    /// border so it reads as the headline benefit of this pitch.
    var highlighted: Bool = false
    /// Title-only rows for the one-screen trial sheet.
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 10 : 12) {
            ZStack {
                Circle()
                    .fill(bullet.tint.opacity(0.18))
                    .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                Image(systemName: bullet.icon)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(bullet.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bullet.title)
                    .font(.system(compact ? .footnote : .subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !compact {
                    Text(bullet.detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 7 : 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(highlighted ? bullet.tint.opacity(0.12) : Theme.cardSurface.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(bullet.tint.opacity(highlighted ? 0.45 : 0.18), lineWidth: highlighted ? 1.5 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bullet.title). \(bullet.detail)")
    }
}

/// Lightweight ambient "shine" — a handful of tiny dots that drift + pulse
/// behind the hero icon. Driven by `phase` (0…1) so the parent owns the
/// animation lifecycle.
private struct SparkleField: View {
    let phase: CGFloat

    private struct Sparkle: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let driftX: CGFloat
        let driftY: CGFloat
        let opacity: Double
        let phaseOffset: CGFloat
    }

    private static let sparkles: [Sparkle] = (0..<14).map { i in
        // Deterministic pseudo-random so layout doesn't jitter on re-render.
        let seed = Double(i) * 12.9898
        let r1 = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let r2 = (sin(seed + 1) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let r3 = (sin(seed + 2) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let r4 = (sin(seed + 3) * 43758.5453).truncatingRemainder(dividingBy: 1)
        return Sparkle(
            id: i,
            x: CGFloat(abs(r1)) * 320 - 160,
            y: CGFloat(abs(r2)) * 460 - 230,
            size: 2 + CGFloat(abs(r3)) * 3,
            driftX: CGFloat(r4) * 12,
            driftY: CGFloat(r3 - 0.5) * 18,
            opacity: 0.35 + abs(r2) * 0.5,
            phaseOffset: CGFloat(abs(r1))
        )
    }

    var body: some View {
        ZStack {
            ForEach(Self.sparkles) { sparkle in
                Circle()
                    .fill(.white)
                    .frame(width: sparkle.size, height: sparkle.size)
                    .opacity(sparkle.opacity * (0.4 + 0.6 * Double(abs(sin(.pi * (phase + sparkle.phaseOffset))))))
                    .offset(x: sparkle.x + sparkle.driftX * phase,
                            y: sparkle.y + sparkle.driftY * phase)
                    .blur(radius: 0.4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Theme.caloriesPrimary : Theme.textTertiary)
            .frame(width: 72, height: 44)
            .background(
                isSelected ? Theme.caloriesPrimary.opacity(0.12) : .clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
