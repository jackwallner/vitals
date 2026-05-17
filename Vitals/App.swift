import SwiftUI
import SwiftData
import BackgroundTasks
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
        StoreService.shared.start()
        #if canImport(WatchConnectivity)
        PhoneGoalSyncService.shared.activate()
        #endif
    }

    var body: some Scene {
        WindowGroup {
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
        .modelContainer(DataService.sharedModelContainer)
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

struct MainTabView: View {
    @EnvironmentObject private var store: StoreService
    @StateObject private var goals = GoalSettings.shared
    @State private var selectedTab = 0
    @State private var historyHasAppeared = false
    @State private var showTrialOffer = false
    @State private var showTrialPaywall = false
    /// Which trigger opened the current trial offer, so dismissal records the
    /// right one-shot flag.
    @State private var trialOfferSource: TrialOfferSource = .launch
    /// True once the launch (1.5s) offer has been shown in *this* app session.
    /// Gates the history-load offer so the two never fire back-to-back — the
    /// history offer is strictly a later-session second touch.
    @State private var launchOfferShownThisSession = false
    @State private var trialPurchaseInFlight = false
    @State private var trialPurchaseError: String?
    /// Set when the user opts into the hosted paywall from inside the trial-offer
    /// sheet. The `.sheet(onDismiss:)` reads this and presents the paywall *after*
    /// the trial sheet has fully dismissed — presenting both sheets in the same
    /// runloop tick is racy in SwiftUI and frequently drops the second sheet.
    @State private var pendingPaywallAfterTrialDismiss = false
    @State private var trialOfferPackage: Package?
    @State private var trialOfferUsesDirectPurchase = false
    @State private var trialOfferDetent: PresentationDetent = .fraction(0.85)

    private enum TrialOfferSource {
        case launch
        case historyLoad
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
    /// otherwise fall back to the hosted paywall.
    private var trialOfferIsDirect: Bool {
        trialOfferUsesDirectPurchase
    }

    private func presentTrialOffer(source: TrialOfferSource) {
        trialOfferSource = source
        trialOfferPackage = directTrialPackage
        trialOfferUsesDirectPurchase = trialOfferPackage != nil
        trialOfferDetent = .fraction(0.85)
        showTrialOffer = true
    }

    private func startDirectTrialPurchase() {
        guard let package = trialOfferPackage ?? directTrialPackage else {
            // No trial product loaded — fall back to the hosted paywall.
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
                    trialPurchaseError = "Trial wasn't started — tap again, or pick a different plan."
                }
            } catch {
                trialPurchaseError = "Couldn't start your trial. Please try again."
            }
        }
    }

    private func evaluateTrialOffer() {
        // One-time offer for existing non-Pro users. We require:
        // - onboarding finished (so first-launch users aren't double-prompted)
        // - not already Pro
        // - haven't seen the trial offer before
        // - a real trial product loaded from the store
        // - they're on the Today tab (don't fight with the Vitals+ tab paywall)
        guard goals.hasCompletedSetup,
              !store.isPro,
              !goals.hasSeenTrialOffer,
              hasTrialOffer,
              selectedTab == 0
        else { return }
        // Defer ~5s so the user sees their dashboard (ring, counters) populate
        // before the pitch — a cold pitch at first paint converts worse and
        // collides with the dashboard's first-paint animations.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !showTrialOffer, !showTrialPaywall else { return }
            // Re-check the user is still on Today — they may have navigated to
            // History or Vitals+ during the wait, in which case this pitch would
            // pop over the wrong tab.
            guard selectedTab == 0 else { return }
            if !goals.hasSeenTrialOffer && !store.isPro {
                launchOfferShownThisSession = true
                presentTrialOffer(source: .launch)
            }
        }
    }

    /// Second-touch trial nudge: fires when History finishes loading. Originally
    /// gated on the launch offer having already been shown in a prior session,
    /// but that meant users whose products failed to load on session 1 never saw
    /// either pitch. Now it fires whenever the launch offer hasn't run *this*
    /// session — that still prevents back-to-back pitches, while letting History
    /// act as the primary path when the launch path didn't fire.
    private func evaluateHistoryTrialOffer() {
        guard goals.hasCompletedSetup,
              !store.isPro,
              !goals.hasSeenHistoryTrialOffer,
              !launchOfferShownThisSession,
              hasTrialOffer,
              selectedTab == 1,
              !showTrialOffer,
              !showTrialPaywall
        else { return }
        presentTrialOffer(source: .historyLoad)
    }

    /// Records the one-shot flag for whichever trigger opened the offer.
    private func markTrialOfferSeen() {
        goals.hasSeenTrialOffer = true
        if trialOfferSource == .historyLoad {
            goals.hasSeenHistoryTrialOffer = true
        }
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
                // Reserve space so the RevenueCat paywall's CTA + footer aren't
                // hidden by the floating tab-bar capsule below.
                Color.clear.frame(height: 68)
            }
            .opacity(selectedTab == 2 ? 1 : 0)
            .allowsHitTesting(selectedTab == 2)
            .accessibilityHidden(selectedTab != 2)

            // Custom tab bar — always visible so the user can navigate away from
            // the paywall. The RevenueCat-hosted paywall has its own scrollable
            // auto-renew disclosure, so the tab bar overlay doesn't break 3.1.2(a).
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
            // Wait briefly for products to load, then consider the trial nudge.
            if store.products.isEmpty { await store.fetchProducts() }
            evaluateTrialOffer()
        }
        .onChange(of: store.products.count) { _, _ in evaluateTrialOffer() }
        // First-launch users complete onboarding *after* the .task /
        // products-loaded evaluations have already bailed on
        // `hasCompletedSetup == false`. Without this, the launch offer (and
        // therefore the history second-touch it gates) never fires until the
        // 2nd app launch. Re-evaluate the moment onboarding finishes.
        .onChange(of: goals.hasCompletedSetup) { _, done in
            if done { evaluateTrialOffer() }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { showTrialOffer = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalsHistoryDidFinishLoading)) { _ in
            evaluateHistoryTrialOffer()
        }
        .sheet(isPresented: $showTrialOffer, onDismiss: {
            markTrialOfferSeen()
            trialPurchaseInFlight = false
            trialPurchaseError = nil
            trialOfferPackage = nil
            trialOfferUsesDirectPurchase = false
            // Chain the hosted paywall here rather than setting both bindings in
            // the same tick — SwiftUI can only show one sheet per ancestor at a
            // time and frequently drops the second when they fire together.
            if pendingPaywallAfterTrialDismiss {
                pendingPaywallAfterTrialDismiss = false
                showTrialPaywall = true
            }
        }) {
            TrialOfferSheet(
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
                    pendingPaywallAfterTrialDismiss = true
                    showTrialOffer = false
                },
                onDismiss: {
                    showTrialOffer = false
                }
            )
            .presentationDetents([.fraction(0.85), .large], selection: $trialOfferDetent)
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(trialPurchaseInFlight)
        }
        .sheet(isPresented: $showTrialPaywall) {
            PaywallView().environmentObject(store)
        }
    }

}

private struct PremiumFeaturesView: View {
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject private var store: StoreService
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared
    @State private var restoreMessage: String?
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
                                action: onOpenNetDeficit
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
            .overlay(alignment: .center) {
                if isGeneratingReport {
                    VStack(spacing: 12) {
                        LoadingBar(color: Theme.caloriesPrimary)
                            .frame(width: 180)
                        Text("Generating report…")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(20)
                    .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12)
                }
            }
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
                Task {
                    await store.restorePurchases()
                    // `StoreService.restorePurchases()` clears `lastError` on entry
                    // and writes either the success or the failure message, so the
                    // view doesn't need to invent its own fallback string.
                    restoreMessage = store.isPro
                        ? "Your Vitals+ access is active."
                        : (store.lastError ?? "Couldn't refresh your subscription. Try again.")
                }
            } label: {
                PremiumAccountRow(icon: "arrow.clockwise", title: "Restore Purchases", detail: "Refresh your access after changing devices or reinstalling.")
            }
            .buttonStyle(.plain)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

private struct PremiumAccountRow: View {
    let icon: String
    let title: String
    let detail: String

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
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

private struct TrialOfferSheet: View {
    let offerLabel: String?
    /// Recurring price after the trial, e.g. "$29.99 / year". Only required in
    /// `directPurchase` mode (Apple 3.1.2 needs price + terms before purchase).
    let priceLabel: String?
    /// When true the primary button buys the trial product directly via StoreKit
    /// and the sheet shows compliant billing disclosure + a "See all plans" link.
    /// When false it opens the RevenueCat-hosted paywall fallback.
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
        if let offerLabel {
            return "\(offerLabel.capitalized), on us."
        }
        return "Try Vitals+ free."
    }

    private var subheadline: String {
        offerLabel != nil
            ? "Unlock the full Vitals+ toolkit free. No charge until your trial ends."
            : "Unlock the full Vitals+ toolkit free for eligible new subscribers."
    }

    private var trialBullets: [TrialBullet] {
        [
            TrialBullet(
                icon: "plus.forwardslash.minus",
                tint: Theme.netDeficitBrand,
                title: "Net Deficit, live",
                detail: "Calories burned minus food logged in Apple Health, updated all day."
            ),
            TrialBullet(
                icon: "chart.line.uptrend.xyaxis",
                tint: Theme.stepsPrimary,
                title: "Deep Trends",
                detail: "Every period compared head-to-head with the one before it."
            ),
            TrialBullet(
                icon: "calendar.badge.clock",
                tint: Theme.stepsSecondary,
                title: "Custom date ranges + PDF reports",
                detail: "Pick any window in History, export a clean summary for your coach."
            )
        ]
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Circle()
                .fill(Theme.stepsPrimary.opacity(0.2))
                .frame(width: 220, height: 220)
                .blur(radius: 36)
                .offset(x: animateGlow ? 96 : -96, y: animateGlow ? -220 : -180)
            Circle()
                .fill(Theme.stepsSecondary.opacity(0.18))
                .frame(width: 180, height: 180)
                .blur(radius: 34)
                .offset(x: animateGlow ? -110 : 110, y: animateGlow ? 250 : 210)
            // Light "shine" particles drifting behind the hero. Suppressed when
            // Reduce Motion is on so we stay accessibility-compliant.
            if !reduceMotion {
                SparkleField(phase: animateGlow ? 1 : 0)
                    .allowsHitTesting(false)
                    .opacity(0.55)
            }

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.stepsGradient)
                        .frame(width: 76, height: 76)
                        .shadow(color: Theme.stepsPrimary.opacity(0.4), radius: 16, x: 0, y: 6)
                        .scaleEffect(animateGlow ? 1.07 : 0.96)
                    // Subtle inner shine ring.
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 64, height: 64)
                        .scaleEffect(animateGlow ? 1.04 : 0.98)
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(animateGlow ? 6 : -6))
                }
                .padding(.top, 18)

                VStack(spacing: 6) {
                    Text(headline)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .overlay(shimmerOverlay)
                        .mask(
                            Text(headline)
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .multilineTextAlignment(.center)
                        )
                    Text(subheadline)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                }

                VStack(spacing: 10) {
                    ForEach(trialBullets) { bullet in
                        TrialBulletRow(bullet: bullet)
                    }
                }
                .padding(.horizontal, 4)

                if directPurchase, let priceLabel {
                    Text("Free during your trial, then \(priceLabel). Auto-renews unless cancelled at least 24 hours before the trial ends.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
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
                        .padding(.vertical, 14)
                        .background(Theme.caloriesGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)

                    Text("Apple-managed subscription. Cancel anytime.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)

                    if directPurchase {
                        Button(action: onSeeAllPlans) {
                            Text("See all plans")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.caloriesPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isPurchasing)
                    }

                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)
                }

                HStack(spacing: 4) {
                    Link("Terms", destination: PaywallLinks.standardEULA)
                    Text("·")
                    Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
                }
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                animateGlow = true
            }
            // Independent timing from the hero glow so the two motions don't
            // sync up into a single pulse — keeps the surface feeling alive.
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false).delay(0.4)) {
                shimmerPhase = 1.4
            }
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
        }
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(bullet.tint.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: bullet.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(bullet.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bullet.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(bullet.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardSurface.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(bullet.tint.opacity(0.18), lineWidth: 1)
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
