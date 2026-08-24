import SwiftUI
import SwiftData
import BackgroundTasks
import StoreKit
import UserNotifications
import WidgetKit
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
            GoalSyncKeys.showMacros: goals.showMacros && StoreService.shared.isPro,
            GoalSyncKeys.visibleMacros: goals.visibleMacros.map(\.rawValue),
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
            if HealthKitLabConfig.isEnabled {
                HealthKitLabHarness()
            } else if let snap = PaywallSnapshotRequest.current {
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
                // Local midnight (also a timezone change or a manual clock change).
                // Finalizes the day that just ended and rewrites today's row, so an
                // app left running across midnight doesn't keep showing the old day
                // and the widgets don't inherit a partial final day.
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task {
                        await HealthKitService.shared.finalizeDayRolloverIfNeeded()
                        try? await HealthKitService.shared.refreshCache()
                    }
                }
                .task {
                    #if DEBUG
                    if DebugLaunchConfig.seedHealth {
                        await HealthKitSeeder.run()
                    }
                    #endif
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
                // Also finalize recent completed days so the Maintenance/TDEE
                // widget (which reads only the cache and excludes today) matches
                // the in-app live figure even when the app isn't opened. Best
                // effort: a failure here shouldn't fail the whole refresh.
                do {
                    try await HealthKitService.shared.refreshHistoryCache()
                } catch {
                    print("Background history cache refresh failed: \(error)")
                }
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

    /// True while a sheet the dashboard owns (Settings, onboarding) is covering
    /// the window. A passive pitch raised from `MainTabView` cannot rise above
    /// one: SwiftUI keeps the flag true and shows the sheet later, when the user
    /// closes Settings — a pitch arriving out of nowhere, out of context.
    @Published var coveringSheetIsPresented = false

    enum Intent: String {
        case lockedCustomRange
        case lockedSummaryReport
        case deepTrendsUpgrade
        case netDeficitToggle
        case macrosToggle
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
            case .macrosToggle: .macros
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
    /// Taps on the Upgrade tab while already on it, counted toward the hidden
    /// arm rotator. Resets itself after three seconds of no tapping.
    @State private var rotatorTapCount = 0
    @State private var rotatorLastTapAt = Date.distantPast
    @State private var variantToastLabel: String?
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
    @State private var showTrialPaywall = false
    @State private var showWeeklyRecap = false
    @State private var pendingMilestone: MilestoneEvent?
    /// Set when the user taps the CTA inside a milestone sheet. Chains a direct
    /// yearly trial purchase after dismiss (Apple confirm sheet), never the
    /// plan-picker paywall.
    @State private var pendingDirectTrialAfterMilestoneDismiss = false
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
    /// Set the first time the dashboard shows real, non-zero burned/step data -
    /// the strategic value moment. The passive launch trial nudge waits for this
    /// instead of a blind timer, so it never pitches over zeros/spinner.
    @State private var dashboardShowedRealData = false
    /// The pitch currently on screen, or nil. Owns its own package snapshot and
    /// purchase — see `TrialOfferPitchSheet`.
    ///
    /// Drives the sheet through `.sheet(item:)`, never a parallel `isPresented`
    /// bool: setting the flag and the payload in one tick let SwiftUI build the
    /// sheet body against a payload it hadn't seen yet, and `if let` over a nil
    /// payload renders an empty sheet — the blank white card.
    @State private var trialPitch: TrialPitchRequest?
    @State private var showReviewPrompt = false
    @State private var reviewPromptInitialStep: ReviewPromptSheet.Step = .enjoyment
    @State private var reviewPromptShownThisSession = false
    /// If a goal-hit review ask was blocked by an open trial/paywall sheet, retry
    /// once those sheets clear instead of burning the positive moment.
    @State private var pendingReviewAfterSheetsClear = false
    /// One WidgetKit query per session is plenty; the moment itself is one-shot.
    @State private var widgetMomentEvaluated = false
    /// The feature an intent tap reached for, so the trial sheet (and the plan
    /// picker it can chain into) lead with it. `nil` for passive offers.
    @State private var trialOfferFocus: PlusFeature?
    /// A toggle-gated feature (Net Deficit, Active/Resting) the user explicitly
    /// tried to turn *on* but got paywalled. When set, we flip the matching
    /// setting on automatically once they upgrade — but only because they
    /// reached for it. Buying from the generic Upgrade tab leaves it `nil`, so
    /// those features stay off until the user chooses them.
    @State private var pendingFeatureEnable: PlusFeature?

    private enum TrialOfferSource: String {
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

    /// True when yearly can honestly be pitched as a free trial (product has an
    /// intro offer AND RevenueCat says this Apple ID is still eligible).
    private var canPitchFreeTrial: Bool {
        store.canPitchFreeTrial
    }

    /// Always the yearly package. StoreKit applies the free trial when eligible;
    /// used-trial accounts pay the yearly price on the same product — no separate
    /// SKU and no nested plan picker required.
    private var directConversionPackage: Package? {
        store.conversionPackage
    }

    private func presentTrialOffer(source: TrialOfferSource, request: TrialPitchRequest) {
        trialOfferSource = source
        trialOfferFocus = request.focus
        trialPitch = request
    }

    /// Passive nudges keep the surface-level impression id they have always
    /// reported, so their conversion series doesn't restart on this build.
    private func presentPassiveTrialOffer(source: TrialOfferSource) {
        presentTrialOffer(
            source: source,
            request: TrialPitchRequest(passiveImpressionID: "vitals_trial_offer_\(source.rawValue)")
        )
    }

    /// Milestone CTA: buy yearly in place (Apple confirm). Trial applies only
    /// when eligible; otherwise it's a straight yearly purchase.
    /// Ten taps on the Upgrade tab, while already on the Upgrade tab, rotates
    /// the paywall layout: full list, short list, macro card, maintenance, then
    /// back to whatever RevenueCat says.
    ///
    /// It lives on the tab button because the first attempt did not. That was
    /// an invisible strip at the top of the paywall, and a UI test tapping
    /// where it was supposed to be never triggered it: the strip sat inside the
    /// scroll container's centred frame, not where a thumb would land. A hidden
    /// gesture nobody can find is worse than no gesture, so this one is on a
    /// control that is always in the same place, always hittable, and does
    /// nothing when you are already on the tab.
    ///
    /// Deliberately not `#if DEBUG`: the arms are only worth judging on a real
    /// phone, and TestFlight ships a Release build. It picks between layouts
    /// already in the binary that RevenueCat could serve anyone, and cannot
    /// touch a price, a product, an entitlement, or what a purchase does.
    private func countRotatorTap() {
        // A gap rule, not a stopwatch. The first version gave the whole run
        // three seconds, which a UI test tapping the button ten times could not
        // meet, and neither could an unhurried thumb. What actually
        // distinguishes a deliberate sequence from a stray tap is that the taps
        // keep coming, so the count survives as long as no gap exceeds 1.5s.
        let now = Date.now
        if now.timeIntervalSince(rotatorLastTapAt) > 1.5 {
            rotatorTapCount = 0
        }
        rotatorLastTapAt = now
        rotatorTapCount += 1
        guard rotatorTapCount >= 10 else { return }
        rotatorTapCount = 0
        let next = PaywallVariantOverride.advance()
        variantToastLabel = PaywallVariantOverride.label(for: next)
        Task {
            try? await Task.sleep(for: .seconds(2))
            variantToastLabel = nil
        }
    }

    @ViewBuilder
    private var variantToast: some View {
        if let variantToastLabel {
            Text(variantToastLabel)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.82), in: Capsule())
                .offset(y: -46)
                .allowsHitTesting(false)
                .accessibilityIdentifier("variant-toast")
        }
    }

    private func startMilestoneDirectTrial() {
        guard let package = directConversionPackage else {
            selectedTab = 2
            return
        }
        Task { @MainActor in
            await store.refreshIntroEligibility()
            do {
                switch try await store.purchase(package) {
                case .purchased:
                    markTrialOfferSeen()
                case .pending:
                    // Not a trial yet. Do not burn the offer cooldown on a
                    // transaction that may never settle: the passive pitch is
                    // the only thing that would re-offer it.
                    break
                case .cancelled:
                    break
                case .unavailable:
                    selectedTab = 2
                }
            } catch {
                await store.refreshIntroEligibility()
                selectedTab = 2
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
              trialPitch == nil, !showTrialPaywall, pendingMilestone == nil,
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
              canPitchFreeTrial,
              selectedTab == 0,
              !trialCoordinator.coveringSheetIsPresented,
              // Strategic value moment: only pitch after the dashboard has shown
              // real, non-zero data — never over a spinner or a row of zeros.
              dashboardShowedRealData
        else { return }
        // Brief settle so the ring/counter first-paint animations finish before
        // the pitch appears over the numbers the user just watched populate.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if directConversionPackage == nil { await store.fetchProducts() }
            guard !skipPassiveTrialThisSession else { return }
            guard trialPitch == nil, !showTrialPaywall, !showWhatsNew else { return }
            guard selectedTab == 0, !trialCoordinator.coveringSheetIsPresented else { return }
            if canPitchFreeTrial && !store.isPro {
                launchOfferShownThisSession = true
                presentPassiveTrialOffer(source: .launch)
            }
        }
    }

    /// Positive moments that don't depend on clearing a goal: a week of actually
    /// using the app, and a subscriber who has kept Vitals+ for a month.
    /// Evaluated once real numbers are on screen so the ask never lands on an
    /// empty dashboard. Each fires at most once ever.
    private func evaluateHabitMilestones() {
        let habit = ReviewPromptTracker.recordTrackedDay()
        let subscriber = ReviewPromptTracker.recordProStatus(isPro: store.isPro)
        evaluateWidgetInstallMoment()
        // A moment recorded away from Today (a report generated on History, a
        // recap read as the app went to background) has nowhere to surface at
        // the time. Pick it up here instead of losing the ask entirely.
        guard habit || subscriber || ReviewPromptTracker.hasPendingPositiveMoment else { return }
        scheduleReviewPromptAfterPositiveMoment()
    }

    /// Someone who put Vitals on their Home Screen or a watch face has already
    /// voted for it with the most contested real estate they own. That's a
    /// stronger signal than any in-app tap, and it was going unread.
    private func evaluateWidgetInstallMoment() {
        guard !widgetMomentEvaluated else { return }
        widgetMomentEvaluated = true
        Task { @MainActor in
            guard await hasInstalledWidget else { return }
            guard ReviewPromptTracker.recordOneShotPositiveMoment(key: "widget_installed") else { return }
            scheduleReviewPromptAfterPositiveMoment()
        }
    }

    /// `getCurrentConfigurations` throws when the user has never granted the
    /// extension a slot, which we read the same as "no widget".
    private var hasInstalledWidget: Bool {
        get async {
            await withCheckedContinuation { continuation in
                WidgetCenter.shared.getCurrentConfigurations { result in
                    let installed = (try? result.get())?.isEmpty == false
                    continuation.resume(returning: installed)
                }
            }
        }
    }

    /// Passive review ask after a positive moment (e.g. a daily goal). Waits for
    /// the on-dashboard celebration toast to clear; never fires on cold launch.
    private func scheduleReviewPromptAfterPositiveMoment() {
        guard ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: goals.hasCompletedSetup),
              !reviewPromptShownThisSession,
              selectedTab == 0,
              pendingMilestone == nil,
              !showReviewPrompt
        else { return }

        // Don't lose the ask to a trial/paywall sheet — retry when those clear.
        if trialPitch != nil || showTrialPaywall {
            pendingReviewAfterSheetsClear = true
            return
        }

        Task { @MainActor in
            // Let the goal celebration toast finish (~2.5s) before asking.
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard selectedTab == 0,
                  trialPitch == nil,
                  !showTrialPaywall,
                  pendingMilestone == nil,
                  !showReviewPrompt,
                  ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedSetup: goals.hasCompletedSetup)
            else {
                if trialPitch != nil || showTrialPaywall {
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
              trialPitch == nil,
              !showTrialPaywall,
              pendingMilestone == nil,
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
    }

    private func presentReviewPrompt(step: ReviewPromptSheet.Step) {
        reviewPromptInitialStep = step
        reviewPromptShownThisSession = true
        showReviewPrompt = true
    }

    /// Second-touch trial nudge: fires when History finishes loading. Subject to
    /// the same 14-day passive cooldown, and additionally gated so it never
    /// fires back-to-back with the launch offer in the same session.
    private func evaluateHistoryTrialOffer() {
        guard goals.hasCompletedSetup,
              !store.isPro,
              !skipPassiveTrialThisSession,
              goals.passiveHistoryTrialOfferAllowed(),
              !launchOfferShownThisSession,
              canPitchFreeTrial,
              selectedTab == 1,
              trialPitch == nil,
              !showTrialPaywall
        else { return }
        presentPassiveTrialOffer(source: .historyLoad)
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
        guard trialPitch == nil, !showTrialPaywall else { return }
        let request = TrialPitchRequest(intent: intent, impressionID: "vitals_trial_offer_intent")
        trialOfferFocus = request.focus
        // Only toggle-gated features get auto-enabled on upgrade; Deep Trends /
        // PDF unlock implicitly with Pro and need no stored setting.
        pendingFeatureEnable = request.featureToEnable
        if directConversionPackage != nil {
            presentTrialOffer(source: .intent, request: request)
        } else {
            // No products loaded - Upgrade tab is the plan browser.
            selectedTab = 2
        }
    }

    /// Flips on whichever toggle-gated feature the user reached for before they
    /// were paywalled, now that they're Pro. No-op for passive upgrades.
    ///
    /// Net Deficit dietary HealthKit auth MUST wait until conversion sheets are
    /// gone. Requesting while a trial sheet is visible or dismissing causes
    /// HealthKit to silently suppress the system permission UI.
    private func applyPendingFeatureEnable() {
        guard let feature = pendingFeatureEnable else { return }
        pendingFeatureEnable = nil
        switch feature {
        case .netDeficit:
            Task { @MainActor in
                // Wait for sheet dismiss animation + any StoreKit UI to clear.
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard trialPitch == nil, !showTrialPaywall, pendingMilestone == nil else {
                    // Sheet re-appeared; retry once shortly after.
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard trialPitch == nil, !showTrialPaywall, pendingMilestone == nil else { return }
                    NotificationCenter.default.post(name: .vitalsEnableNetDeficitWithDietaryAuth, object: nil)
                    return
                }
                NotificationCenter.default.post(name: .vitalsEnableNetDeficitWithDietaryAuth, object: nil)
            }
        case .macros:
            // Same deferral as Net Deficit: the macro HealthKit permission sheet
            // is suppressed while any conversion sheet is still on screen.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard trialPitch == nil, !showTrialPaywall, pendingMilestone == nil else {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard trialPitch == nil, !showTrialPaywall, pendingMilestone == nil else { return }
                    NotificationCenter.default.post(name: .vitalsEnableMacrosWithHealthAuth, object: nil)
                    return
                }
                NotificationCenter.default.post(name: .vitalsEnableMacrosWithHealthAuth, object: nil)
            }
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
        // Reaching a streak or finishing a reviewable month is a good day
        // whether or not there is anything to sell — subscribers never see the
        // celebration sheet below, and were losing the signal entirely.
        if case .goalStreak = event {
            if ReviewPromptTracker.recordOneShotPositiveMoment(key: "milestone_\(event.id)") {
                scheduleReviewPromptAfterPositiveMoment()
            }
        }
        guard !store.isPro,
              !milestoneShownThisSession,
              !goals.firedMilestoneIds.contains(event.id),
              trialPitch == nil, !showTrialPaywall, pendingMilestone == nil
        else { return }
        goals.firedMilestoneIds.insert(event.id)
        milestoneShownThisSession = true
        pendingMilestone = event
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
                Group {
                    if ScreenshotConfig.wantsMacroHistory {
                        HistoryView(focusMetric: .macros)
                    } else {
                        HistoryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == 1 ? 1 : 0)
                .allowsHitTesting(selectedTab == 1)
                .accessibilityHidden(selectedTab != 1)
            }
            Group {
                if store.isPro {
                    PremiumFeaturesView(
                        onOpenNetDeficit: {
                            // Dismiss covering UI, enable Net Deficit, then request
                            // dietary HealthKit auth once the window is clear.
                            NotificationCenter.default.post(
                                name: .vitalsEnableNetDeficitWithDietaryAuth,
                                object: nil
                            )
                            selectedTab = 0
                        },
                        onOpenMacros: {
                            NotificationCenter.default.post(
                                name: .vitalsEnableMacrosWithHealthAuth,
                                object: nil
                            )
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
                ) {
                    if selectedTab == 2 { countRotatorTap() }
                    selectedTab = 2
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            .padding(.bottom, 12)
            .overlay(alignment: .top) { variantToast }
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
                // If a trial/milestone sheet is up, wait for its onDismiss to apply
                // the pending feature. Requesting dietary HealthKit auth while that
                // sheet is still visible (or dismissing) suppresses the system prompt.
                let conversionSheetUp = trialPitch != nil || showTrialPaywall || pendingMilestone != nil
                trialPitch = nil
                pendingMilestone = nil
                if !conversionSheetUp {
                    applyPendingFeatureEnable()
                }
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
            evaluateHabitMilestones()
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
            guard trialPitch == nil, !showTrialPaywall, pendingMilestone == nil, !showReviewPrompt else { return }
            selectedTab = 0
            showWeeklyRecap = true
        }
        .onChange(of: reviewPromptCoordinator.pendingPresentation) { _, presentation in
            guard let presentation else { return }
            defer { reviewPromptCoordinator.clear() }
            guard trialPitch == nil, !showTrialPaywall, pendingMilestone == nil else { return }
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
                // The arm is part of the id, not a footnote on it. One shared
                // id would pool four different screens into a single
                // impression count, and impression-to-purchase per arm is the
                // number the experiment is for. Distinct ids also make the tap
                // rotator visible: swapping arms and reopening the tab fires a
                // new impression instead of being swallowed by oncePerSession.
                store.trackPaywallImpression(
                    id: "vitals_upgrade_tab_\(store.upgradeTabVariant.rawValue)",
                    oncePerSession: true
                )
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
                tryFreeCTATitle: store.shortConversionCTALabel,
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
        .sheet(item: $trialPitch, onDismiss: {
            markTrialOfferSeen()
            if store.isPro {
                // Sheet is fully gone - safe to enable Net Deficit + request dietary auth.
                applyPendingFeatureEnable()
            } else {
                // Dismissed without upgrading - drop the intent so a later
                // unrelated purchase doesn't silently flip the feature on.
                pendingFeatureEnable = nil
                presentPendingReviewIfNeeded()
            }
        }) { pitch in
            // The sheet that actually sells the trial. It reports its own
            // impression: it was the one surface never reported, which is
            // why encounters and trials came out nearly equal and the
            // encounter rate read as 13%.
            TrialOfferPitchSheet(
                request: pitch,
                onDismiss: { trialPitch = nil },
                onNeedsPlanPicker: {
                    // Products failed to load - Upgrade tab is the plan browser.
                    trialPitch = nil
                    selectedTab = 2
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showTrialPaywall, onDismiss: {
            trialOfferFocus = nil
            if !store.isPro { pendingFeatureEnable = nil }
            presentPendingReviewIfNeeded()
        }) {
            PaywallView(focus: trialOfferFocus)
                .environmentObject(store)
                .task { store.trackPaywallImpression(id: "vitals_trial_sheet") }
        }
        .sheet(item: $pendingMilestone, onDismiss: {
            let startTrial = pendingDirectTrialAfterMilestoneDismiss
            pendingDirectTrialAfterMilestoneDismiss = false
            if startTrial {
                startMilestoneDirectTrial()
            } else {
                presentPendingReviewIfNeeded()
            }
        }) { event in
            MilestoneCelebrationSheet(
                event: event,
                ctaTitle: store.shortConversionCTALabel,
                onContinue: {
                    pendingDirectTrialAfterMilestoneDismiss = true
                    pendingMilestone = nil
                },
                onDismiss: { pendingMilestone = nil }
            )
            .presentationDetents([.fraction(0.7), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReviewPrompt, onDismiss: {
            // A soft defer recorded on an older build is still a 30-day promise.
            // Calling markShown() over it would jail the ask for 120 days.
            if !ReviewPromptTracker.isSoftDeferred {
                ReviewPromptTracker.markShown()
            }
        }) {
            ReviewPromptSheet(initialStep: reviewPromptInitialStep, onFinish: handleReviewPromptFinish)
        }
        .sheet(isPresented: $showWeeklyRecap, onDismiss: {
            // They opened their week and read it. One of the better-disposed
            // moments the app gets, and it was going unused.
            if ReviewPromptTracker.recordOneShotPositiveMoment(key: "weekly_recap_read") {
                scheduleReviewPromptAfterPositiveMoment()
            }
        }) {
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
    /// URL of the temp report being previewed, kept so the sheet's
    /// `onDismiss` can delete it after the item binding has been cleared.
    @State private var tempFileToDelete: URL?
    @State private var isGeneratingReport = false
    @State private var reportErrorMessage: String?
    @State private var showCustomReportSheet = false
    @State private var customStart = DateHelpers.daysAgo(29)
    @State private var customEnd = Date.now

    let onOpenNetDeficit: () -> Void
    let onOpenMacros: () -> Void

    @State private var deepTrendInsights: [DeepTrendInsight] = []
    @State private var deepTrendHighlights: [String] = []
    @State private var deepTrendsLoaded = false

    @StateObject private var bodyProfile = BodyProfileStore.shared
    @State private var resolvedBMI: Double?
    @State private var showBodyProfile = false

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
                            // Macros is the other half of Calorie Intake, so it
                            // sits beside Net Deficit rather than being the one
                            // Vitals+ feature you can only find in Settings.
                            PremiumActionRow(
                                icon: "chart.pie.fill",
                                title: "Macros",
                                detail: "Protein, carbs, and fat from the food you already log.",
                                buttonTitle: "Enable",
                                action: onOpenMacros,
                                isEnabled: goals.showMacros
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
                            // Body Profile belongs here rather than on Today.
                            // BMI moves on the scale of weeks; Today is a
                            // dashboard of numbers that change hourly, and a
                            // static figure under the ring reads as noise. Here
                            // it sits with the other things a subscriber opens
                            // deliberately, and body fat is the Vitals+ half.
                            PremiumActionRow(
                                icon: "figure",
                                title: "Body Profile",
                                detail: bodyProfileDetail,
                                buttonTitle: "Open",
                                action: { showBodyProfile = true }
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
            .navigationDestination(isPresented: $showBodyProfile) {
                BodyProfileView()
            }
            .task {
                if !deepTrendsLoaded { await loadDeepTrends() }
                await loadBodyProfile()
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
            .sheet(item: $pdfFile, onDismiss: {
                // The item binding is already nil here, so the URL to clean up
                // is held separately.
                if let url = tempFileToDelete {
                    try? FileManager.default.removeItem(at: url)
                    tempFileToDelete = nil
                }
            }) { file in
                PDFPreviewSheet(title: pdfTitle, url: file.url, shareText: pdfShareText)
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

    /// Reads as a status line: the BMI itself once it resolves, which is the
    /// only "is this set up" signal that also tells you something.
    private var bodyProfileDetail: String {
        guard let resolvedBMI else {
            return "Free BMI from Apple Health, plus body fat and calorie context."
        }
        return String(
            format: "BMI %.1f · body fat and calorie context inside.",
            resolvedBMI
        )
    }

    private func loadBodyProfile() async {
        let health = (try? await healthKit.fetchBodyProfileFromHealth()) ?? .empty
        resolvedBMI = bodyProfile.resolved(health: health).bmi
    }

    private var deepTrendsSection: some View {
        DeepTrendsCard(
            isPro: true,
            isCalculating: !deepTrendsLoaded,
            insights: deepTrendInsights,
            highlights: deepTrendHighlights,
            periodLabel: "vs. previous 30 days"
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
            let macrosByDay = await macroMap(start: start, end: end, days: days)
            let calendar = Calendar.current

            let reportDays = history.map { rec in
                ReportDay(
                    date: rec.date,
                    activeCalories: rec.active,
                    restingCalories: rec.resting,
                    steps: rec.steps,
                    foodCalories: foodMap[calendar.startOfDay(for: rec.date)],
                    macros: macrosByDay[calendar.startOfDay(for: rec.date)]
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
                stepGoal: goals.stepGoal,
                macroKinds: goals.visibleMacros
            )
            let url = try SummaryReportPDF.render(report)
            pdfTitle = title
            pdfShareText = SummaryReportShareText.make(report: report)
            tempFileToDelete = url
            pdfFile = PDFFile(url: url)
            // Building a report of your own data is about as deliberate as this
            // app gets, and it ends with something the user is proud enough of
            // to share. Counts once, however many reports they make.
            ReviewPromptTracker.recordOneShotPositiveMomentAndNotify(key: "report_generated")
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

    private func macroMap(start: Date?, end: Date?, days: Int?) async -> [Date: MacroTotals] {
        guard goals.showMacros else { return [:] }
        let daily: [(date: Date, macros: MacroTotals)]
        do {
            if let days {
                daily = try await healthKit.fetchMacroHistory(days: days)
            } else if let start, let end {
                daily = try await healthKit.fetchMacroHistory(from: start, to: end)
            } else {
                daily = try await healthKit.fetchMacroHistory(days: 30)
            }
        } catch {
            return [:]
        }
        var map: [Date: MacroTotals] = [:]
        let calendar = Calendar.current
        for day in daily {
            map[calendar.startOfDay(for: day.date)] = day.macros
        }
        return map
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

/// One plan on the used-trial pitch. A free trial is not a choice, so this list
/// is empty whenever the trial is still on the table.
struct TrialPlanOption: Identifiable, Equatable {
    let id: String
    let title: String
    let price: String
    /// Smallest honest unit of the same price, e.g. "about $0.58 / week".
    let detail: String?
    /// "SAVE 64%" / "BEST VALUE" — only when it's computed from real prices.
    let badge: String?
}

struct TrialOfferSheet: View {
    /// When set, the sheet leads with and highlights this feature instead of the
    /// generic toolkit pitch. `nil` for passive launch/history nudges.
    let focus: PlusFeature?
    /// Free-trial label only when the user is eligible; nil frames a paid yearly buy.
    let offerLabel: String?
    /// Recurring price, e.g. "$29.99 / year". Required in directPurchase mode.
    let priceLabel: String?
    /// Primary button title (trial or paid yearly), from StoreService.
    let ctaTitle: String
    /// Apple 3.1.2 disclosure under the CTA. Hidden while an error is shown so
    /// the two never overlap in the fixed footer.
    let disclosureText: String?
    /// When true the primary button buys the yearly product directly via StoreKit.
    /// When false (products not loaded) the CTA still calls `onStartTrial`, which
    /// routes to the Upgrade tab rather than nesting a plan picker.
    let directPurchase: Bool
    let isPurchasing: Bool
    let errorMessage: String?
    let onStartTrial: () -> Void
    let onDismiss: () -> Void
    /// Restore belongs on every surface that asks for money. A returning
    /// subscriber who reinstalls meets this sheet before they ever reach the
    /// Upgrade tab, and without it their only options were to pay again or
    /// leave. Terms and Privacy were already here; Restore was the one missing.
    var onRestore: () -> Void = {}
    var isRestoring: Bool = false
    /// Outcome of the last restore. Nil until one runs.
    var restoreMessage: String?

    /// Per-week equivalent of the yearly price. Only used when there is no trial
    /// left to pitch, where price framing is the whole argument.
    var perWeekLabel: String?
    /// Annual saving vs. twelve monthly payments, for the deal badge.
    var annualSavingsPercent: Int?
    /// Plans to choose between. Empty for the trial pitch — see `TrialPlanOption`.
    var planOptions: [TrialPlanOption] = []
    var selectedPlanID: String?
    var onSelectPlan: (String) -> Void = { _ in }

    /// One detent, sized to hold the whole pitch. It used to open at 0.68 with
    /// a `.large` companion: the third benefit was clipped by the footer, so the
    /// sheet scrolled, and the first flick both scrolled the hero and promoted
    /// the sheet to full height — the pitch appeared to leap off the top.
    static let pitchDetent: PresentationDetent = .fraction(0.78)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateGlow = false
    @State private var shimmerPhase: CGFloat = -1
    /// Height the sheet gives the pitch, measured by `CenteredScrollContainer`.
    @State private var sheetContentHeight: CGFloat = 0

    /// Headline copy. Trial language only when `offerLabel` is set (eligible).
    private var headline: String {
        VitalsConversionCopy.headline(
            focusHeadline: focus?.intentHeadline,
            trialLabel: offerLabel,
            eligibleForTrial: offerLabel != nil
        )
    }

    private var subheadline: String {
        VitalsConversionCopy.subheadline(
            focusSubheadline: focus?.intentSubheadline,
            eligibleForTrial: offerLabel != nil,
            perWeekLabel: perWeekLabel
        )
    }

    /// Focused feature first with two related companions; generic trio when
    /// passive. A three-plan ladder needs the height of one bullet, and the
    /// benefit list is the part that repeats itself — the plans don't.
    private var bulletFeatures: [PlusFeature] {
        let all = focus.map { [$0] + $0.companionFeatures } ?? [.netDeficit, .deepTrends, .customRangesPDF]
        return planOptions.count >= 3 ? Array(all.prefix(2)) : all
    }

    /// Deal badge text derived from the real offer, e.g. "7-day free trial" →
    /// "7 DAYS FREE"; the annual saving once the trial is spent. Never invents a
    /// number — only reflects what the store actually returned.
    private var trialBadgeText: String {
        VitalsConversionCopy.badgeText(
            trialLabel: offerLabel,
            eligibleForTrial: offerLabel != nil,
            annualSavingsPercent: annualSavingsPercent
        )
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

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.caloriesGradient)
                        .frame(width: 52, height: 52)
                        .shadow(color: Theme.caloriesPrimary.opacity(0.45), radius: 14, x: 0, y: 4)
                        .scaleEffect(animateGlow ? 1.06 : 0.96)
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 43, height: 43)
                        .scaleEffect(animateGlow ? 1.03 : 0.98)
                    Image(systemName: "sparkles")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(animateGlow ? 6 : -6))
                }
                .padding(.top, 2)
                .animation(glowAnimation, value: animateGlow)

                // Deal badge: the trial when there is one, the annual saving
                // when there isn't. Suppressed only when neither is knowable.
                if trialBadgeText != "VITALS+" {
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
                }

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
                            // A plan chooser needs the room the descriptions
                            // were using; the titles still carry the pitch.
                            // Companions of a focused feature stay title-only so
                            // the highlighted row keeps the eye. With no focus
                            // there is nothing to contrast against, and three
                            // one-word pills waste the space they sit in, so the
                            // generic pitch shows what each feature actually does.
                            compact: !planOptions.isEmpty || (focus != nil && feature != focus)
                        )
                    }
                }

                if !planOptions.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(planOptions) { option in
                            TrialPlanRow(
                                option: option,
                                isSelected: option.id == selectedPlanID,
                                onSelect: { onSelectPlan(option.id) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
            // Centred in whatever height the detent gives it, scrolling only when
            // the content is taller than that. The old fixed Spacer pushed the
            // pitch to the top and left a band of dead white above the button.
            .frame(minHeight: sheetContentHeight, alignment: .center)
            .modifier(CenteredScrollContainer(height: $sheetContentHeight))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    // Error replaces disclosure in the same slot — never stack both
                    // (that was the overlapping red/grey text on purchase failure).
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if directPurchase, let disclosureText {
                        Text(disclosureText)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onStartTrial) {
                        ZStack {
                            Text(ctaTitle)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .multilineTextAlignment(.center)
                                .opacity(isPurchasing ? 0 : 1)
                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.caloriesGradient, in: Capsule())
                        .ctaGlow()
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)

                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)

                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 4) {
                        Button(action: onRestore) {
                            Text(isRestoring ? "Restoring…" : "Restore")
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestoring || isPurchasing)
                        Text("·")
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
    let ctaTitle: String
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
                        Text(ctaTitle)
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

/// Wraps content in a scroll view that reports its own height, so the content
/// can be centred while it fits and scroll once it does not. Sheets with a fixed
/// detent need both: short pitches should sit centred rather than stranded above
/// a band of white, and long ones (large Dynamic Type, a focused feature with a
/// three-line subheadline) must not clip.
/// Centres content in whatever height it is given, scrolling only when the
/// content is taller than that. Shared by the trial sheet and the Upgrade tab,
/// both of which otherwise pool their spare height into one dead band above the
/// pinned button.
struct CenteredScrollContainer: ViewModifier {
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { height = proxy.size.height }
            .onChange(of: proxy.size.height) { _, new in height = new }
        }
    }
}

/// One selectable plan on the used-trial pitch. Deliberately flatter than the
/// Upgrade tab's `PlanCard`: two or three of these have to sit inside a sheet
/// that is still mostly pitch.
private struct TrialPlanRow: View {
    let option: TrialPlanOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.caloriesPrimary : Theme.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge = option.badge {
                            Text(badge)
                                .font(.system(size: 10, design: .rounded).weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.caloriesGradient, in: Capsule())
                        }
                    }
                    if let detail = option.detail {
                        Text(detail)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Text(option.price)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Theme.caloriesPrimary.opacity(0.10) : Theme.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.caloriesPrimary.opacity(0.55) : Theme.textTertiary.opacity(0.20),
                            lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
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
        // The tint and the capsule say which tab is current to anyone who can
        // see them. VoiceOver was told nothing.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
