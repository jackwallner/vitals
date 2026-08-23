import SwiftUI
import HealthKit
import UIKit
import os

private let dashboardLogger = Logger(subsystem: "com.jackwallner.vitals", category: "Dashboard")

private enum VitalsLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let support = URL(string: "https://jackwallner.github.io/vitals/support.html")!
    static let supportEmail = URL(string: "mailto:jackwallner+tc@gmail.com")!
    static let coachServices = URL(string: "https://www.e3fit.me/#services")!
    static let coachContact = URL(string: "https://www.e3fit.me/#contact")!
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// Tracks which goals have been celebrated for a given day so we don't buzz
/// repeatedly on every refresh once the user crosses their goal.
@MainActor
private enum GoalCelebration {
    private static let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
    private static let calorieKey = "goalCelebration.calorieDate"
    private static let stepKey = "goalCelebration.stepDate"

    static func shouldCelebrateCalories(for todayKey: String) -> Bool {
        defaults.string(forKey: calorieKey) != todayKey
    }

    static func markCaloriesCelebrated(for todayKey: String) {
        defaults.set(todayKey, forKey: calorieKey)
    }

    static func shouldCelebrateSteps(for todayKey: String) -> Bool {
        defaults.string(forKey: stepKey) != todayKey
    }

    static func markStepsCelebrated(for todayKey: String) {
        defaults.set(todayKey, forKey: stepKey)
    }
}

private enum HealthNotice: Equatable {
    case accessNeeded
    case accessBlocked
    case noData
    case loadError

    var iconName: String {
        switch self {
        case .accessNeeded: "heart.text.square.fill"
        case .accessBlocked: "lock.shield"
        case .noData: "heart.text.clipboard"
        case .loadError: "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch self {
        case .accessNeeded: "Health access needed"
        case .accessBlocked: "Health access is off"
        case .noData: "No Health data yet"
        case .loadError: "Couldn't refresh Health data"
        }
    }

    var message: String {
        switch self {
        case .accessNeeded:
            "Grant Apple Health access so Total Calories can load your active calories, resting calories, and steps."
        case .accessBlocked:
            "In Apple Health: Profile → Privacy → Apps → Total Calories, then turn on each category to load your data."
        case .noData:
            "If you just granted access, Apple Health may still be catching up. If this seems wrong, check Health access."
        case .loadError:
            "Try reopening the app in a moment, or check Apple Health access."
        }
    }

    var buttonTitle: String? {
        switch self {
        case .accessNeeded:
            "Enable Health"
        case .accessBlocked:
            "Open Health"
        case .noData, .loadError:
            "Open Health"
        }
    }
}

struct DashboardView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared
    @EnvironmentObject private var store: StoreService
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0
    @State private var pacingCalories: Double? = nil
    @State private var pacingSteps: Int? = nil
    @State private var isLoading = true
    @State private var animateRing = false
    @State private var animateContent = false
    @State private var showSettings = false
    @State private var showOnboarding = false
    /// Set when Pro enables Net Deficit while Settings (or another sheet) may be
    /// covering the window. Auth runs from `showSettings` onDismiss / a follow-up
    /// task so HealthKit's permission sheet isn't suppressed.
    @State private var pendingNetDeficitDietaryAuth = false
    /// Macros equivalent of `pendingNetDeficitDietaryAuth`. See that property.
    @State private var pendingMacrosHealthAuth = false
    @State private var pacingCaloriesInsufficient = false
    @State private var pacingStepsInsufficient = false
    @State private var pacingCalorieSamples = 0
    @State private var pacingStepSamples = 0
    @State private var pacingMinSamples = 3
    // Vitals+ projection inputs: raw "usual by now" + "usual full day" over the
    // same sample set, ungated by showCalories/showSteps so the projection works
    // even when the pacing pills themselves are hidden.
    @State private var usualCaloriesByNow: Double? = nil
    @State private var usualCaloriesFullDay: Double? = nil
    @State private var usualStepsByNow: Double? = nil
    @State private var usualStepsFullDay: Double? = nil
    // Vitals+ per-metric streaks: consecutive completed days (ending yesterday)
    // that hit each goal independently. 0 = no streak (badge hidden).
    @State private var calorieStreak: Int = 0
    @State private var stepStreak: Int = 0
    @State private var isRefreshing = false
    @State private var healthNotice: HealthNotice? = nil
    @State private var lastRefreshDate: Date? = nil
    @State private var foodCalories: Double = 0
    /// True after we’ve successfully read dietary energy at least once this session (while net is on).
    @State private var dietaryEnergyReady = false
    /// True when the last dietary fetch failed (don’t treat as “0 kcal logged”).
    @State private var dietaryEnergyFetchFailed = false
    @State private var macros: MacroTotals = .zero
    /// True after a successful macro read this session (while Macros is on).
    @State private var macrosReady = false
    /// True when the last macro fetch failed (don’t treat as “0 g logged”).
    @State private var macrosFetchFailed = false
    /// Transient celebration banner shown once per goal per day (paired with the haptic).
    @State private var celebrationMessage: String? = nil
    // Vitals+ energy averages: stable 30-day maintenance (TDEE) and resting (BMR)
    // figures from Apple Health. nil until enough sample days exist (see loadEnergyAverages).
    @State private var energyTDEE: Double? = nil
    @State private var energyBMR: Double? = nil
    @State private var energySampleDays: Int = 0
    /// Measured top safe-area inset (status bar / Dynamic Island height), used to
    /// size the mask that keeps scrolled content from colliding with the status bar.
    @State private var topSafeAreaInset: CGFloat = 0

    private var totalCalories: Double { activeCalories + restingCalories }

    /// Positive = burned more than logged food (deficit); negative = surplus.
    private var netDeficit: Double { totalCalories - foodCalories }

    /// Whether we can show a numeric net (not loading, not failed).
    private var netDeficitNumericReady: Bool {
        isNetDeficitEnabled && dietaryEnergyReady && !dietaryEnergyFetchFailed
    }

    private var isNetDeficitEnabled: Bool {
        store.isPro && goals.showNetCalories
    }

    /// Macros are Vitals+ and opt-in, and independent of Net Deficit. Tracking
    /// protein without caring about burn-minus-eaten is a perfectly normal way
    /// to use the app (it's what the diabetes/macro crowd asked for).
    private var isMacrosEnabled: Bool {
        store.isPro && goals.showMacros
    }

    /// Active/resting breakdown is Vitals+ only and gated by the user's setting.
    /// Hidden in minimal mode (no goals + no pacing) to keep that layout uncluttered.
    private var showActiveResting: Bool {
        store.isPro && goals.showActiveRestingBreakdown && !isMinimalMode
    }

    /// TDEE/BMR averages are Vitals+ only, gated by the user's setting, and only
    /// meaningful alongside the calorie ring — hidden in minimal mode and when
    /// calories are turned off.
    private var showEnergyAverages: Bool {
        store.isPro && goals.showEnergyAverages && goals.showCalories && !isMinimalMode
    }

    /// Vitals+ end-of-day projection, gated by subscription + setting.
    private var isProjectionEnabled: Bool {
        store.isPro && goals.showProjections
    }

    /// Streaks are a Vitals+ feature, gated by subscription + setting. Each metric
    /// then tracks its own streak and shows a badge only when it has a goal and a
    /// live streak (0 = hidden) — so calories and steps can run independently.
    private var streaksUnlocked: Bool {
        store.isPro && goals.showStreaks
    }

    private var showCalorieStreak: Bool {
        streaksUnlocked && goals.showCalories && goals.calorieGoal != nil && calorieStreak > 0
    }

    private var showStepStreak: Bool {
        streaksUnlocked && goals.showSteps && goals.stepGoal != nil && stepStreak > 0
    }

    /// "Usual by now" feeding the pace clause of the pill, nil when pacing is off
    /// so the pill can still render a projection-only line.
    private var calorieTypical: Double? { goals.showPacing ? pacingCalories : nil }
    private var stepTypical: Double? { goals.showPacing ? pacingSteps.map(Double.init) : nil }

    private var projectedCalories: Double? {
        guard isProjectionEnabled, goals.showCalories else { return nil }
        return ProjectionCalculator.projectedEndOfDay(
            current: totalCalories,
            usualByNow: usualCaloriesByNow,
            usualFullDay: usualCaloriesFullDay
        )
    }

    private var projectedSteps: Double? {
        guard isProjectionEnabled, goals.showSteps else { return nil }
        return ProjectionCalculator.projectedEndOfDay(
            current: Double(steps),
            usualByNow: usualStepsByNow,
            usualFullDay: usualStepsFullDay
        )
    }

    private var visibleMetricCount: Int {
        (goals.showCalories ? 1 : 0) + (goals.showSteps ? 1 : 0) + (isNetDeficitEnabled ? 1 : 0)
    }

    /// Only the net-deficit row is visible (no calorie ring / steps).
    private var onlyNetMetric: Bool {
        isNetDeficitEnabled && !goals.showCalories && !goals.showSteps
    }

    private var calorieProgress: Double? {
        guard let goal = goals.calorieGoal, goal > 0 else { return nil }
        return totalCalories / goal
    }

    private var stepProgress: Double? {
        guard let goal = goals.stepGoal, goal > 0 else { return nil }
        return Double(steps) / Double(goal)
    }

    private var isMinimalMode: Bool {
        goals.calorieGoal == nil && goals.stepGoal == nil && !goals.showPacing
    }

    /// When goals are off and pacing is hidden, show a calorie icon so the Today
    /// layout matches the steps row (which always shows `figure.walk`).
    private var showCalorieMetricIcon: Bool {
        goals.calorieGoal == nil && !goals.showPacing
    }

    /// Exactly one of calories / steps / net is enabled.
    private var isSingleMetric: Bool {
        visibleMetricCount == 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                    .ignoresSafeArea()
                    .overlay {
                        // The base layer spans under the status bar, so a reader
                        // over it sees the real top inset (0 on devices without
                        // one). Captured here so the status-bar mask can be sized.
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { topSafeAreaInset = proxy.safeAreaInsets.top }
                                .onChange(of: proxy.safeAreaInsets.top) { _, v in topSafeAreaInset = v }
                        }
                    }

                if isLoading {
                    loadingView
                } else {
                    GeometryReader { geo in
                        ScrollView(showsIndicators: false) {
                            mainContent(availableHeight: geo.size.height)
                                .frame(minHeight: geo.size.height)
                        }
                        .refreshable { await refresh() }
                    }
                }
            }
            // The dashboard hides the navigation bar for its custom date header,
            // which also removes the system scroll-edge treatment that normally
            // masks content scrolling up behind the status bar. Without this the
            // header/cards slide under the transparent status bar and collide with
            // the clock and battery on devices tall enough to scroll (a bug that
            // only shows when the content stack overflows the screen). Repaint the
            // status-bar strip with the page background, above the scroll content.
            .overlay(alignment: .top) { statusBarMask }
            .overlay(alignment: .top) {
                if let message = celebrationMessage {
                    celebrationBanner(message)
                        .padding(.horizontal, 24)
                        .transition(reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(InteractivePopGestureEnabler())
            .navigationDestination(for: HistoryMetric.self) { metric in
                HistoryView(focusMetric: metric)
                    .environmentObject(store)
            }
        .onChange(of: goals.showNetCalories) { _, enabled in
            guard enabled, store.isPro else { return }
            // Covering-sheet path uses `pendingNetDeficitDietaryAuth` and requests
            // after Settings dismisses. Skip the immediate request here so we don't
            // fire while Settings is still animating closed.
            guard !pendingNetDeficitDietaryAuth, !showSettings else { return }
            Task {
                await requestDietaryAuthAndReload()
            }
        }
        .onChange(of: goals.showMacros) { _, enabled in
            guard enabled, store.isPro else { return }
            guard !pendingMacrosHealthAuth, !showSettings else { return }
            Task {
                await requestMacroAuthAndReload()
            }
        }
        .onChange(of: store.isPro) { oldValue, isPro in
            if oldValue && !isPro && goals.showNetCalories {
                goals.showNetCalories = false
            } else if isPro && goals.showNetCalories {
                Task { await refresh() }
            }
            if oldValue && !isPro && goals.showMacros {
                goals.showMacros = false
            } else if isPro && goals.showMacros {
                Task { await refresh() }
            }
            // Weekly recap notifications are scheduled in the system, so they'd
            // outlive a lapsed subscription. Cancel on lapse; restore on regain
            // if the user still has the toggle on.
            if oldValue && !isPro {
                NotificationService.cancelWeeklyRecap()
            } else if !oldValue && isPro && goals.weeklyRecapEnabled {
                Task { await NotificationService.scheduleWeeklyRecap() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Skip during first-launch onboarding — refresh() calls
            // synchronizeAuthorizationStateForFetching(), which would trigger
            // the HealthKit permission sheet before the user has even tapped
            // Continue on the welcome screen.
            guard goals.hasCompletedSetup else { return }
            if newPhase == .active {
                Task { await refresh() }
            }
        }
        // Local midnight. Without this the dashboard sits on the previous day —
        // header date, ring, and totals — until the app is backgrounded and
        // reopened, because nothing else re-reads the day while it stays active.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            guard goals.hasCompletedSetup else { return }
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalsOpenSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalsDismissSettings)) { _ in
            showSettings = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalsEnableNetDeficitWithDietaryAuth)) { _ in
            beginEnableNetDeficitWithDietaryAuth()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalsEnableMacrosWithHealthAuth)) { _ in
            beginEnableMacrosWithHealthAuth()
        }
        .task {
            if ScreenshotConfig.wantsOnboarding {
                showOnboarding = true
            } else if !goals.hasCompletedSetup {
                showOnboarding = true
            } else {
                // Capture runs present Settings before the first refresh: the
                // sheet is what the run exists to photograph, and a loaded
                // machine can leave that HealthKit round trip pending for a
                // minute.
                if ScreenshotConfig.wantsSettingsSheet {
                    showSettings = true
                }
                await refresh()
            }
        }
        .onChange(of: showSettings) { _, isUp in
            TrialOfferCoordinator.shared.coveringSheetIsPresented = isUp || showOnboarding
        }
        .onChange(of: showOnboarding) { _, isUp in
            TrialOfferCoordinator.shared.coveringSheetIsPresented = isUp || showSettings
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            if pendingNetDeficitDietaryAuth {
                Task { await finishEnableNetDeficitWithDietaryAuth() }
            } else if pendingMacrosHealthAuth {
                Task { await finishEnableMacrosWithHealthAuth() }
            } else {
                Task { await refresh() }
            }
        }) {
            SettingsSheet(goals: goals)
                .environmentObject(store)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            if !goals.hasCompletedSetup {
                goals.hasCompletedSetup = true
            }
            Task { await refresh() }
        }) {
            OnboardingSheet(goals: goals)
                .environmentObject(store)
                .interactiveDismissDisabled()
        }
        }
    }

    /// Opaque page-background strip sized to the top safe-area inset, drawn over
    /// the scroll content so anything scrolling upward is hidden before it reaches
    /// the status bar. The GeometryReader ignores the safe area so `safeAreaInsets`
    /// still reports the real inset (0 on devices without one, so this is a no-op
    /// there). Non-interactive so it never intercepts scroll/taps.
    private var statusBarMask: some View {
        Theme.background
            .frame(height: topSafeAreaInset)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    private func celebrationBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.caloriesGradient, in: Capsule())
        .shadow(color: Theme.caloriesPrimary.opacity(0.35), radius: 12, x: 0, y: 6)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isStaticText)
    }

    private func healthNoticeBanner(_ notice: HealthNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.iconName)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                Text(notice.message)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let buttonTitle = notice.buttonTitle {
                Button(buttonTitle) {
                    handleHealthNoticeAction(notice)
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white.opacity(0.2), in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.caloriesPrimary.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private var loadingView: some View {
        ProgressView()
            .tint(Theme.textTertiary)
    }

    private func mainContent(availableHeight: CGFloat) -> some View {
        // Scale fonts based on mode
        let calNumberSize: CGFloat = {
            if isSingleMetric && goals.showCalories && !goals.showSteps && !isNetDeficitEnabled {
                return min(availableHeight * 0.12, 100)
            }
            if isMinimalMode { return min(availableHeight * 0.10, 88) }
            return min(availableHeight * 0.06, 52)
        }()
        let stepsNumberSize: CGFloat = {
            if isSingleMetric && goals.showSteps && !goals.showCalories && !isNetDeficitEnabled {
                return min(availableHeight * 0.12, 100)
            }
            if isMinimalMode { return min(availableHeight * 0.08, 68) }
            return min(availableHeight * 0.048, 42)
        }()
        let netNumberSize: CGFloat = {
            if onlyNetMetric { return min(availableHeight * 0.12, 100) }
            if isMinimalMode { return min(availableHeight * 0.08, 68) }
            return min(availableHeight * 0.048, 42)
        }()
        let ringSize: CGFloat = min(availableHeight * 0.32, 260)
        let ringLineWidth: CGFloat = min(availableHeight * 0.022, 18)

        return VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(10)
                            .background(Theme.cardSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                HStack(spacing: 8) {
                    if healthNotice == .accessNeeded || healthNotice == .accessBlocked {
                        Text("Waiting for Health access")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    } else if isRefreshing {
                        LoadingBar(color: Theme.caloriesPrimary)
                            .frame(width: 80)
                        Text("Refreshing…")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    } else if let date = lastRefreshDate {
                        Text("Updated \(date, format: .dateTime.hour().minute())")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isRefreshing)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 10)

            if let healthNotice {
                healthNoticeBanner(healthNotice)
                    .opacity(animateContent ? 1 : 0)
            }

            Spacer(minLength: 16)

            // Calories section
            if goals.showCalories {
                NavigationLink(value: HistoryMetric.calories) {
                    Group {
                        if let progress = calorieProgress {
                            ZStack {
                                ProgressRing(
                                    progress: animateRing ? progress : 0,
                                    gradient: Theme.caloriesGradient,
                                    glowColor: Theme.caloriesGlow,
                                    lineWidth: ringLineWidth,
                                    size: ringSize
                                )
                                calorieLabel(numberSize: calNumberSize)
                            }
                        } else {
                            calorieLabel(numberSize: calNumberSize)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Calorie progress")
                .accessibilityHint("Opens calorie history")
                .accessibilityValue((showActiveResting
                    ? (calorieProgress != nil
                        ? "\(Int(totalCalories)) of \(Int(goals.calorieGoal ?? 0)) calories. Active \(Int(activeCalories)), resting \(Int(restingCalories))."
                        : "\(Int(totalCalories)) calories. Active \(Int(activeCalories)), resting \(Int(restingCalories)).")
                    : (calorieProgress != nil
                        ? "\(Int(totalCalories)) of \(Int(goals.calorieGoal ?? 0)) calories"
                        : "\(Int(totalCalories)) calories"))
                    + (showCalorieStreak ? " \(calorieStreak) day goal streak." : ""))

                // Active/Resting breakdown is a Vitals+ feature. Toggle lives in Settings.
                if showActiveResting {
                    HStack(spacing: 16) {
                        MetricPill(label: "active", value: activeCalories, color: Theme.activePrimary)
                        MetricPill(label: "resting", value: restingCalories, color: Theme.restingPrimary)
                    }
                    .padding(.top, 14)
                    .opacity(animateContent ? 1 : 0)
                }

                // Pacing and end-of-day projection — the "how's today going"
                // signals coupled directly under the ring.
                calorieInsights

                // TDEE/BMR reference figures (Vitals+). Toggle lives in Settings.
                energyAveragesView
            }

            if goals.showCalories && goals.showSteps {
                Spacer(minLength: 16)
            }

            // Steps section
            if goals.showSteps {
                NavigationLink(value: HistoryMetric.steps) {
                Group {
                if isMinimalMode || (isSingleMetric && goals.showSteps && !goals.showCalories) {
                    // Clean centered layout
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "figure.walk")
                                .font(isSingleMetric ? .largeTitle : .title)
                                .foregroundStyle(Theme.stepsPrimary)
                            Text(steps, format: .number)
                                .font(Theme.bigNumber(stepsNumberSize))
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(.numericText())
                        }
                        HStack(spacing: 4) {
                            Text("steps")
                                .font(.system(isSingleMetric ? .title3 : .subheadline, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                                .textCase(.uppercase)
                                .tracking(1.5)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        // Streak rides with the metric label, not the pacing row.
                        if showStepStreak {
                            streakBadge(count: stepStreak, metric: "step")
                                .padding(.top, 4)
                        }

                        if stepTypical != nil || projectedSteps != nil {
                            PacingPill(
                                current: Double(steps),
                                typical: stepTypical,
                                projected: projectedSteps,
                                label: "steps",
                                color: Theme.stepsPrimary,
                                comparison: goals.pacingComparison,
                                lookback: goals.pacingLookback
                            )
                            .padding(.top, 8)
                        } else if goals.showPacing && pacingStepsInsufficient {
                            Text(pacingBuildingText(samples: pacingStepSamples))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.top, 8)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Steps")
                    .accessibilityValue("\(steps) steps"
                        + (showStepStreak ? ". \(stepStreak) day goal streak." : ""))
                    .opacity(animateContent ? 1 : 0)
                    .scaleEffect(animateContent ? 1 : 0.9)
                } else {
                    // Card layout with goals/pacing
                    VStack(spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "figure.walk")
                                .font(.title2)
                                .foregroundStyle(Theme.stepsPrimary)
                            Text(steps, format: .number)
                                .font(Theme.bigNumber(stepsNumberSize))
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(.numericText())
                            if let goal = goals.stepGoal {
                                Text("/ \(goal.formatted(.number))")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                Text("steps")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                    .textCase(.uppercase)
                                    .tracking(1.5)
                            }
                            Spacer()
                            // Compact streak chip in the badge corner of the card.
                            if showStepStreak {
                                streakBadge(count: stepStreak, metric: "step", compact: true)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }

                        if let progress = stepProgress {
                            StepProgressBar(
                                progress: animateRing ? progress : 0,
                                gradient: Theme.stepsGradient,
                                glowColor: Theme.stepsGlow
                            )
                        }

                        if stepTypical != nil || projectedSteps != nil {
                            PacingPill(
                                current: Double(steps),
                                typical: stepTypical,
                                projected: projectedSteps,
                                label: "steps",
                                color: Theme.stepsPrimary,
                                comparison: goals.pacingComparison,
                                lookback: goals.pacingLookback
                            )
                        } else if goals.showPacing && pacingStepsInsufficient {
                            Text(pacingBuildingText(samples: pacingStepSamples))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Steps")
                    .accessibilityValue("\(steps) steps"
                        + (showStepStreak ? ". \(stepStreak) day goal streak." : ""))
                    .padding(Theme.cardPadding)
                    .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .padding(.horizontal, 24)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                }
                }
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens step history")
            }

            if isNetDeficitEnabled && (goals.showCalories || goals.showSteps) {
                Spacer(minLength: 16)
            }

            if isNetDeficitEnabled {
                NavigationLink(value: HistoryMetric.net) {
                    netDeficitSection(netNumberSize: netNumberSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens net deficit history")
            }

            // Macros sit below net deficit: both come from the same logged food,
            // and macros are always a supporting card rather than a headline
            // number, so they never compete with the ring for the top of the view.
            if isMacrosEnabled && (goals.showCalories || goals.showSteps || isNetDeficitEnabled) {
                Spacer(minLength: 16)
            }

            if isMacrosEnabled {
                NavigationLink(value: HistoryMetric.macros) {
                    macrosSection()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens macro history")
            }

            // Nothing enabled — gentle prompt
            if !goals.showCalories && !goals.showSteps && !isNetDeficitEnabled && !isMacrosEnabled {
                VStack(spacing: 12) {
                    Image(systemName: "heart.text.clipboard")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No metrics selected")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Open Settings") { showSettings = true }
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Theme.caloriesPrimary)
                }
                .opacity(animateContent ? 1 : 0)
            }

            Spacer(minLength: 16)
        }
        .padding(.bottom, 90)
    }

    /// TDEE/BMR averages row (Vitals+). A steady 30-day reference figure, visually
    /// distinct from the live "today" number above it. Shows a building state until
    /// enough sample days exist, mirroring how pacing reports its warm-up.
    @ViewBuilder
    private var energyAveragesView: some View {
        if showEnergyAverages {
            VStack(spacing: 6) {
                if let tdee = energyTDEE, let bmr = energyBMR {
                    HStack(spacing: 16) {
                        MetricPill(label: "TDEE", value: tdee, color: Theme.activePrimary)
                        MetricPill(label: "BMR", value: bmr, color: Theme.restingPrimary)
                    }
                    Text("Maintenance · 30-day avg from Apple Health")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Text("TDEE & BMR estimate building: \(energySampleDays)/7 days")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 14)
            .opacity(animateContent ? 1 : 0)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(energyTDEE != nil
                ? "Maintenance calories \(Int(energyTDEE ?? 0)) TDEE, resting \(Int(energyBMR ?? 0)) BMR, 30-day average."
                : "TDEE and BMR estimate building, \(energySampleDays) of 7 days.")
        }
    }

    /// Calorie pace + projection (one pill) grouped directly under the ring so the
    /// "how's today going" signal lives with the number it's about. The streak
    /// badge lives inside `calorieLabel` with the metric itself. Vitals+ rows are
    /// absent unless the user is Pro and opted in.
    @ViewBuilder
    private var calorieInsights: some View {
        let hasPill = calorieTypical != nil || projectedCalories != nil
        let building = goals.showPacing && pacingCaloriesInsufficient && calorieTypical == nil
        if hasPill || building {
            VStack(spacing: 8) {
                if hasPill {
                    PacingPill(
                        current: totalCalories,
                        typical: calorieTypical,
                        projected: projectedCalories,
                        label: "cal",
                        color: Theme.caloriesPrimary,
                        comparison: goals.pacingComparison,
                        lookback: goals.pacingLookback
                    )
                } else if building {
                    Text(pacingBuildingText(samples: pacingCalorieSamples))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.top, 16)
            .opacity(animateContent ? 1 : 0)
        }
    }

    /// Small green flame chip for a goal streak. Green for every metric — a live
    /// streak is a win, so it shouldn't borrow the calorie coral and read as a
    /// warning. `compact` drops the wordy label for tight header rows.
    private func streakBadge(count: Int, metric: String, compact: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
            Text(compact ? "\(count)d" : "\(count)-day streak")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(Theme.streakPrimary)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, 4)
        .background(Theme.streakPrimary.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) day \(metric) goal streak")
    }

    private func netDeficitDisplayText(_ value: Double) -> String {
        let r = Int(value.rounded())
        if r > 0 {
            return "+\(r)"
        }
        return "\(r)"
    }

    private var netDeficitColor: Color {
        netDeficit >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative
    }

    /// Everyday word for the current net value: people think "deficit" / "surplus",
    /// not "+500" / "-500".
    private var netDeficitWord: String {
        netDeficit >= 0 ? "deficit" : "surplus"
    }


    @ViewBuilder
    private func netDeficitBreakdownRow(centered: Bool) -> some View {
        if netDeficitNumericReady {
            let burned = Int(totalCalories.rounded())
            let eaten = Int(foodCalories.rounded())
            let pillColor = netDeficitColor

            HStack(spacing: 5) {
                Image(systemName: netDeficit >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                Text("\(burned.formatted(.number)) burned − \(eaten.formatted(.number)) eaten")
                    .font(.system(.caption2, design: .rounded))
            }
            .foregroundStyle(pillColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(pillColor.opacity(0.1), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else if !dietaryEnergyFetchFailed {
            // Reserve the pill's footprint with a skeleton so the row doesn't pop
            // into existence and shift the surrounding layout when food data lands.
            SkeletonBlock(cornerRadius: 12)
                .frame(width: 150, height: 25)
        }
    }

    private func netDeficitSection(netNumberSize: CGFloat) -> some View {
        let deficit = netDeficit

        return Group {
            if onlyNetMetric {
                VStack(spacing: 10) {
                    if netDeficitNumericReady {
                        Text(netDeficitDisplayText(deficit))
                            .font(Theme.bigNumber(netNumberSize))
                            .foregroundStyle(netDeficitColor)
                            .contentTransition(.numericText())
                        Text(netDeficitWord)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(netDeficitColor)
                            .textCase(.uppercase)
                            .tracking(1.5)
                    } else {
                        Text("—")
                            .font(Theme.bigNumber(netNumberSize))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    netDeficitBreakdownRow(centered: true)
                    HStack(spacing: 4) {
                        Text("net calories")
                            .font(.system(isSingleMetric ? .title3 : .subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(1.5)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    netDeficitFootnote(centered: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Net calories")
                .accessibilityValue(netDeficitAccessibilitySummary(deficit: deficit))
                .opacity(animateContent ? 1 : 0)
                .scaleEffect(animateContent ? 1 : 0.9)
            } else {
                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        if netDeficitNumericReady {
                            Text(netDeficitDisplayText(deficit))
                                .font(Theme.bigNumber(netNumberSize))
                                .foregroundStyle(netDeficitColor)
                                .contentTransition(.numericText())
                        } else {
                            Text("—")
                                .font(Theme.bigNumber(netNumberSize))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Text(netDeficitNumericReady ? netDeficitWord : "net")
                            .font(.system(.callout, design: .rounded, weight: .medium))
                            .foregroundStyle(netDeficitNumericReady ? netDeficitColor : Theme.textTertiary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    netDeficitBreakdownRow(centered: true)
                    netDeficitFootnote(centered: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Net calories")
                .accessibilityValue(netDeficitAccessibilitySummary(deficit: deficit))
                .padding(Theme.cardPadding)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .padding(.horizontal, 24)
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 20)
            }
        }
    }

    @ViewBuilder
    private func netDeficitFootnote(centered: Bool) -> some View {
        let align: TextAlignment = centered ? .center : .leading
        if dietaryEnergyFetchFailed {
            VStack(spacing: 6) {
                Text("Couldn't read food calories. Check Health permissions.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(align)
                HStack(spacing: 14) {
                    Button("Retry food calories") {
                        Task {
                            // Re-prompt if HealthKit still hasn't asked; no-op when
                            // already determined (user must use Health permissions).
                            try? await healthKit.requestDietaryAuthorization()
                            await loadDietaryEnergy()
                        }
                    }
                    Button("Health permissions") {
                        openHealthApp()
                    }
                }
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.caloriesPrimary)
            }
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.horizontal, centered ? 12 : 0)
        } else if !dietaryEnergyReady {
            // Loading state is conveyed by the skeleton pill in the breakdown row.
            EmptyView()
        } else if foodCalories <= 0 {
            Text("No food calories logged in Apple Health today.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(align)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, centered ? 12 : 0)
        }
    }

    private func netDeficitAccessibilitySummary(deficit: Double) -> String {
        if dietaryEnergyFetchFailed {
            return "Food data unavailable"
        }
        if !dietaryEnergyReady {
            return "Waiting for Health permission or loading food data"
        }
        let n = Int(deficit.rounded())
        return "\(n) calories, \(deficit < 0 ? "surplus" : "deficit"), burned minus food from Health"
    }

    // MARK: - Macros

    /// Protein / carbs / fat for today, straight from whatever food app writes to
    /// Apple Health. The calorie figure in the header is the food energy the
    /// user's own app logged (`dietaryEnergyConsumed`), not grams run back
    /// through Atwater factors: inventing a second, slightly different calorie
    /// total for the same meals is the one thing guaranteed to read as a bug.
    /// The 4/4/9 factors still drive the percentage split below, where they're
    /// a ratio rather than a competing number.
    private func macrosSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text("macros")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.5)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 8)
                if isMacrosEnabled, goals.macroSplitEnabled, !isNetDeficitEnabled, dietaryEnergyReady, !dietaryEnergyFetchFailed, foodCalories > 0 {
                    // Only when Net Deficit is off: its breakdown pill already
                    // prints "… − 1,950 eaten" higher up the same screen, and the
                    // same number twice invites the reader to look for a
                    // difference between them. "logged" is doing real work too —
                    // the ring above is calories *burned*, so an unqualified
                    // count here would read as part of that number.
                    Text("\(Int(foodCalories.rounded()).formatted(.number)) cal logged")
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityLabel("\(Int(foodCalories.rounded())) calories logged in Health today")
                }
            }

            macrosContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .padding(.horizontal, 24)
        .opacity(animateContent ? 1 : 0)
        .offset(y: animateContent ? 0 : 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Macros")
    }

    @ViewBuilder
    private var macrosContent: some View {
        if macrosFetchFailed {
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't read macros. Check Health permissions.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 14) {
                    Button("Retry macros") {
                        Task {
                            try? await healthKit.requestMacroAuthorization()
                            await loadMacros()
                        }
                    }
                    Button("Health permissions") {
                        openHealthApp()
                    }
                }
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.caloriesPrimary)
            }
        } else if !macrosReady {
            // Reserve the rows' footprint so the card doesn't jump when data lands.
            VStack(spacing: 10) {
                ForEach(goals.visibleMacros) { kind in
                    SkeletonBlock(cornerRadius: 6)
                        .frame(height: 14)
                        .accessibilityHidden(true)
                        .id(kind)
                }
            }
        } else if macros.hasData(in: goals.visibleMacroSet) {
            // Two presentations for two different jobs, the same split the app
            // already makes for calories: with a goal you get a progress bar,
            // without one you get the number. The two mix freely, because a
            // protein target alongside carbs and fat as a reference readout is a
            // normal way to eat. Goal-less macros use the same pill row as
            // TDEE / BMR.
            let barred = goals.goaledMacros
            let pilled = goals.ungoaledMacros
            VStack(spacing: 10) {
                ForEach(barred) { kind in
                    MacroBarRow(
                        kind: kind,
                        grams: macros.grams(kind),
                        goal: goals.macroGoal(for: kind) ?? kind.defaultGoal
                    )
                }
                if !pilled.isEmpty {
                    macroPillRow(pilled, centered: barred.isEmpty)
                }
            }
            macroSplitCaption
        } else if foodCalories > 0 {
            // Food energy is arriving but macros aren't: the food app is sharing
            // Energy without the Nutrition sub-categories. Naming the fix beats
            // telling someone who is already logging to start logging.
            VStack(alignment: .leading, spacing: 8) {
                Text("Food calories are syncing, but macros aren't. In your food app's Apple Health sharing settings, turn on Protein, Carbohydrates, and Fat. (In MyFitnessPal: More → Settings → Sharing & Privacy → HealthKit Sharing.)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Health permissions") { openHealthApp() }
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.caloriesPrimary)
            }
        } else {
            Text("No macros logged in Apple Health today. Log meals in a food app that writes protein, carbs, and fat to Health (MyFitnessPal, Cronometer, Lose It, and most others).")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The goal-less macros as capsules. Two or three divide the row evenly; a
    /// lone pill keeps its natural width and is centred when it's the whole card
    /// (a capsule pinned to the left edge of an otherwise empty row reads as a
    /// layout bug), or left-aligned under progress bars so it lines up with the
    /// macro labels above it.
    private func macroPillRow(_ kinds: [MacroKind], centered: Bool) -> some View {
        HStack(spacing: 8) {
            if centered && kinds.count == 1 { Spacer(minLength: 0) }
            ForEach(kinds) { kind in
                MacroPill(kind: kind, grams: macros.grams(kind), stretch: kinds.count > 1)
            }
            if kinds.count == 1 { Spacer(minLength: 0) }
        }
    }

    /// Calorie split under the macro readout. The percentages are tinted to match
    /// the pills (or bars) directly above rather than repeating "protein / carbs /
    /// fat", which those rows already spell out.
    @ViewBuilder
    private var macroSplitCaption: some View {
        if goals.macroSplitEnabled, let percentages = macros.sharePercentages() {
            let visible = goals.visibleMacros
            HStack(spacing: 5) {
                ForEach(Array(visible.enumerated()), id: \.element) { index, kind in
                    Text("\(percentages[kind] ?? 0)%")
                        .foregroundStyle(Theme.macroColor(kind))
                    if index < visible.count - 1 {
                        Text("·")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Text(macroSplitDenominatorText)
                    .foregroundStyle(Theme.textTertiary)
            }
            .font(.system(.caption2, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(macroSplitAccessibilityText(percentages))
        }
    }

    /// Hidden macros stay in the denominator on purpose. The split of a day's
    /// food doesn't change because you stopped looking at fat, so when one is
    /// hidden the visible percentages no longer sum to 100. Saying "all macro
    /// calories" is the difference between an honest split and an arithmetic bug.
    private var macroSplitDenominatorText: String {
        goals.visibleMacros.count == MacroKind.allCases.count
            ? "of macro calories"
            : "of all macro calories"
    }

    private func macroSplitAccessibilityText(_ percentages: [MacroKind: Int]) -> String {
        let parts = goals.visibleMacros.map { "\(percentages[$0] ?? 0) percent \($0.label.lowercased())" }
        return parts.joined(separator: ", ") + ", \(macroSplitDenominatorText)"
    }

    private func loadMacros() async {
        guard isMacrosEnabled else {
            macros = .zero
            macrosReady = false
            macrosFetchFailed = false
            return
        }
        do {
            let totals = try await healthKit.fetchMacrosToday()
            macros = totals
            // As with dietary energy, HealthKit hides read authorization, so a
            // successful fetch is the only signal we get. All-zero is a valid
            // result (nothing logged), not a failure.
            macrosFetchFailed = false
            macrosReady = true
            try? healthKit.updateCachedMacros(totals)
        } catch {
            macrosFetchFailed = true
            macrosReady = false
            dashboardLogger.error("Macro fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Pro enable path for Macros, mirroring `beginEnableNetDeficitWithDietaryAuth`:
    /// dismiss Settings only when HealthKit still has a permission sheet to show,
    /// otherwise flip the switch in place and leave the user where they were.
    private func beginEnableMacrosWithHealthAuth() {
        Task {
            let status = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true, includeMacros: true)
            guard status == .shouldRequest else {
                goals.showMacros = true
                await refresh()
                return
            }
            pendingMacrosHealthAuth = true
            if showSettings {
                showSettings = false
            } else {
                await finishEnableMacrosWithHealthAuth()
            }
        }
    }

    @MainActor
    private func finishEnableMacrosWithHealthAuth() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        goals.showMacros = true
        pendingMacrosHealthAuth = false
        await requestMacroAuthAndReload()
    }

    @MainActor
    private func requestMacroAuthAndReload() async {
        do {
            try await healthKit.requestMacroAuthorization()
        } catch {
            macrosFetchFailed = true
            dashboardLogger.error("Macro auth request failed: \(String(describing: error), privacy: .public)")
        }
        await refresh()
    }

    private func calorieLabel(numberSize: CGFloat) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: showCalorieMetricIcon ? 10 : 0) {
                if showCalorieMetricIcon {
                    Image(systemName: "flame.fill")
                        .font(isSingleMetric ? .largeTitle : .title2)
                        .foregroundStyle(Theme.caloriesPrimary)
                }
                Text(totalCalories, format: .number.precision(.fractionLength(0)))
                    .font(Theme.bigNumber(numberSize))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
            }
            if let goal = goals.calorieGoal {
                HStack(spacing: 3) {
                    Text("/ \(goal, format: .number.precision(.fractionLength(0))) cal")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                HStack(spacing: 4) {
                    Text("calories")
                        .font(.system(isSingleMetric ? .title3 : .subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.5)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            // Streak rides with the metric itself (inside the ring when one is
            // shown) rather than floating in the insights row below.
            if showCalorieStreak {
                streakBadge(count: calorieStreak, metric: "calorie")
                    .padding(.top, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calories")
        .accessibilityValue("\(Int(totalCalories)) calories")
        .opacity(animateContent ? 1 : 0)
        .scaleEffect(animateContent ? 1 : 0.9)
    }

    private func openHealthApp() {
        if let url = URL(string: "x-apple-health://") {
            UIApplication.shared.open(url)
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Pro enable path: clear Settings first, then flip Net Deficit + request dietary auth.
    ///
    /// Only when a permission sheet is actually coming. HealthKit suppresses that
    /// sheet while Settings covers the window, so the dismiss is necessary the
    /// first time — but once Health has been asked, `requestAuthorization` is a
    /// silent no-op, and closing Settings for it just looks like the screen
    /// collapsing on its own.
    private func beginEnableNetDeficitWithDietaryAuth() {
        Task {
            let status = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true)
            guard status == .shouldRequest else {
                goals.showNetCalories = true
                await refresh()
                return
            }
            pendingNetDeficitDietaryAuth = true
            if showSettings {
                showSettings = false
            } else {
                await finishEnableNetDeficitWithDietaryAuth()
            }
        }
    }

    @MainActor
    private func finishEnableNetDeficitWithDietaryAuth() async {
        // Let the Settings dismiss animation finish — HealthKit suppresses the
        // permission sheet while any modal is still covering the window.
        try? await Task.sleep(nanoseconds: 500_000_000)
        goals.showNetCalories = true
        // Clear the pending flag only after the setting flips so onChange skips
        // the mid-dismiss request, then we request explicitly below.
        pendingNetDeficitDietaryAuth = false
        await requestDietaryAuthAndReload()
    }

    @MainActor
    private func requestDietaryAuthAndReload() async {
        let statusBefore = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true)
        dashboardLogger.debug("NetDeficit dietary auth — status before: \(String(describing: statusBefore?.rawValue), privacy: .public)")
        do {
            try await healthKit.requestDietaryAuthorization()
            let statusAfter = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true)
            dashboardLogger.debug("NetDeficit dietary auth — status after: \(String(describing: statusAfter?.rawValue), privacy: .public)")
        } catch {
            dietaryEnergyFetchFailed = true
            dashboardLogger.error("NetDeficit dietary auth request failed: \(String(describing: error), privacy: .public)")
        }
        await refresh()
    }

    private func handleHealthNoticeAction(_ notice: HealthNotice) {
        switch notice {
        case .accessNeeded:
            Task {
                // If the system has already prompted (status == .unnecessary),
                // requestAuthorization is a silent no-op for previously-denied
                // categories. Surface a Settings deeplink instead so the user
                // can recover.
                let status = await healthKit.authorizationRequestStatus()
                if status == .unnecessary {
                    healthNotice = .accessBlocked
                    return
                }
                do {
                    try await healthKit.requestAuthorization()
                    await refresh()
                } catch {
                    dashboardLogger.error("HealthKit authorization request failed: \(String(describing: error), privacy: .public)")
                    healthNotice = .loadError
                }
            }
        case .accessBlocked:
            openHealthApp()
        case .noData, .loadError:
            openHealthApp()
        }
    }

    /// One-shot guard so the "real data on screen" value-moment notification
    /// (Rev A passive-trial trigger) is posted only once per app session.
    @State private var postedRealData = false

    private func applyStats(_ stats: (active: Double, resting: Double, steps: Int)) {
        activeCalories = stats.active
        restingCalories = stats.resting
        steps = stats.steps

        // Strategic value moment (Rev A): the first time the dashboard actually
        // has non-zero burned-calorie or step data on screen, signal it so the
        // passive Vitals+ trial nudge can fire after real value is demonstrated
        // rather than on a blind post-launch timer.
        if !postedRealData, stats.active + stats.resting > 0 || stats.steps > 0 {
            postedRealData = true
            NotificationCenter.default.post(name: .vitalsDashboardDidShowRealData, object: nil)
        }

        celebrateGoalsIfNeeded()
    }

    /// Fire a single haptic when the user first crosses a goal today.
    /// Previously we required `prevTotal < goal` to ensure this represented a "transition",
    /// but on cold-launch `prevTotal` is always 0 so the gate was vacuous anyway. Instead
    /// we rely entirely on the persistent per-day key in `GoalCelebration` for dedupe:
    /// first observation of (today, crossed) triggers one buzz; subsequent observations
    /// of the same day are silent.
    private func celebrateGoalsIfNeeded() {
        let todayKey = DailyHealthRecord.key(for: Date())
        let newTotal = activeCalories + restingCalories

        var crossedCalories = false
        var crossedSteps = false

        if let calGoal = goals.calorieGoal,
           calGoal > 0,
           newTotal >= calGoal,
           GoalCelebration.shouldCelebrateCalories(for: todayKey) {
            GoalCelebration.markCaloriesCelebrated(for: todayKey)
            crossedCalories = true
        }

        if let stepGoal = goals.stepGoal,
           stepGoal > 0,
           steps >= stepGoal,
           GoalCelebration.shouldCelebrateSteps(for: todayKey) {
            GoalCelebration.markStepsCelebrated(for: todayKey)
            crossedSteps = true
        }

        guard crossedCalories || crossedSteps else { return }

        ReviewPromptTracker.recordPositiveMoment()
        NotificationCenter.default.post(name: .vitalsPositiveMomentForReview, object: nil)

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        let message: String
        if crossedCalories && crossedSteps {
            message = "Both goals reached!"
        } else if crossedCalories {
            message = "Calorie goal reached!"
        } else {
            message = "Step goal reached!"
        }
        showCelebration(message)
    }

    private func showCelebration(_ message: String) {
        withAnimation(reduceMotion ? .none : .spring(duration: 0.4, bounce: 0.3)) {
            celebrationMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.4)) {
                celebrationMessage = nil
            }
        }
    }

    private func showLoadedStateIfNeeded() {
        if isLoading {
            isLoading = false
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
            withAnimation(.spring(duration: 1.0, bounce: 0.15).delay(0.3)) {
                animateRing = true
            }
            // Signal that the dashboard has its data on screen so the passive
            // trial nudge can start its delay from here rather than app launch.
            NotificationCenter.default.post(name: .vitalsDashboardDidLoadData, object: nil)
        }
    }

    private func clearPacing() {
        pacingCalories = nil
        pacingSteps = nil
        pacingCaloriesInsufficient = false
        pacingStepsInsufficient = false
        pacingCalorieSamples = 0
        pacingStepSamples = 0
        usualCaloriesByNow = nil
        usualCaloriesFullDay = nil
        usualStepsByNow = nil
        usualStepsFullDay = nil
    }

    /// Also runs for Macros-only users: the macro card's "energy is syncing but
    /// nutrition isn't" diagnostic needs today's food calories to know which of
    /// the two empty states it's looking at. Read denials surface as zero
    /// samples, not errors, so a user who never granted dietary energy simply
    /// gets 0 and the generic empty state.
    private func loadDietaryEnergy() async {
        guard isNetDeficitEnabled || isMacrosEnabled else {
            foodCalories = 0
            dietaryEnergyReady = false
            dietaryEnergyFetchFailed = false
            return
        }
        do {
            let food = try await healthKit.fetchDietaryEnergyToday()
            foodCalories = food
            // Apple intentionally hides read authorization status; a successful
            // fetch is the only reliable signal. 0 kcal is a valid result
            // (no food logged), not an error. Display the numeric result.
            dietaryEnergyFetchFailed = false
            dietaryEnergyReady = true
            // Only Net Deficit users' widgets read this; a Macros-only user who
            // never granted dietary energy would otherwise write a hollow 0 over
            // whatever the cache already holds.
            if isNetDeficitEnabled {
                try? healthKit.updateCachedFoodCalories(food)
            }
        } catch {
            dietaryEnergyFetchFailed = true
            dietaryEnergyReady = false
            dashboardLogger.error("Dietary energy fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadPacing(stats: (active: Double, resting: Double, steps: Int)?) async {
        // The pacing query also feeds the Vitals+ projection, so fetch it whenever
        // either the pacing pills or projections are enabled.
        guard goals.showPacing || isProjectionEnabled else {
            clearPacing()
            return
        }
        if let stats, isAllZero(stats) {
            clearPacing()
            return
        }
        guard let pacing = try? await healthKit.fetchPacing(
            comparison: goals.pacingComparison,
            lookback: goals.pacingLookback
        ) else {
            clearPacing()
            return
        }
        // Shared helper keeps the Settings footer description in sync with
        // the effective gate (dayOfWeek caps at 4, allDays fixed at 3).
        let minSamples = effectiveMinPacingSamples(
            for: goals.pacingComparison,
            lookback: goals.pacingLookback
        )
        pacingMinSamples = minSamples
        pacingCalorieSamples = pacing.calorieSampleDays
        pacingStepSamples = pacing.stepSampleDays

        // Projection inputs: raw usuals (ungated by show toggles), only when the
        // sample set clears the same minimum the pacing pills use.
        let calReady = pacing.calorieSampleDays >= minSamples
        let stepReady = pacing.stepSampleDays >= minSamples
        usualCaloriesByNow = calReady ? pacing.avgCalories : nil
        usualCaloriesFullDay = calReady ? pacing.avgCaloriesFullDay : nil
        usualStepsByNow = stepReady ? pacing.avgSteps.map(Double.init) : nil
        usualStepsFullDay = stepReady ? pacing.avgStepsFullDay.map(Double.init) : nil

        // Pacing pills respect showPacing; when pacing is off but projections are
        // on, leave the pill state cleared so nothing pacing-specific renders.
        guard goals.showPacing else {
            pacingCalories = nil
            pacingSteps = nil
            pacingCaloriesInsufficient = false
            pacingStepsInsufficient = false
            return
        }
        let v = pacing.dashboardValues(minSamples: minSamples, showCalories: goals.showCalories, showSteps: goals.showSteps)
        pacingCalories = v.calories
        pacingCaloriesInsufficient = v.caloriesBuilding
        pacingSteps = v.steps
        pacingStepsInsufficient = v.stepsBuilding
    }

    /// Load the Vitals+ TDEE/BMR averages. No-op (and clears) when the feature is
    /// off so a disabled toggle never leaves a stale figure on screen.
    private func loadEnergyAverages() async {
        guard showEnergyAverages else {
            energyTDEE = nil
            energyBMR = nil
            energySampleDays = 0
            return
        }
        guard let avg = try? await healthKit.fetchEnergyAverages() else {
            energyTDEE = nil
            energyBMR = nil
            energySampleDays = 0
            return
        }
        energyTDEE = avg.tdee
        energyBMR = avg.bmr
        energySampleDays = avg.sampleDays
    }

    private func pacingBuildingText(samples: Int) -> String {
        let dayWord = pacingMinSamples == 1 ? "day" : "days"
        return "Building pace data: \(samples)/\(pacingMinSamples) \(dayWord)"
    }

    private func isAllZero(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        HealthKitService.isAllZero(stats)
    }

    /// Classify the dashboard's recovery notice based on the most recent fetch result and
    /// HealthKit authorization request status. Runs only when both live HK and the cache
    /// were empty — otherwise the merged display values speak for themselves.
    ///
    /// - `shouldRequest`: system has not yet presented the sheet (or it was interrupted) →
    ///   surface `.accessNeeded` so users can retry the prompt.
    /// - `unnecessary`: sheet was already presented. We cannot tell granted-but-empty apart
    ///   from denied via the API, so we prefer `.accessBlocked` (Settings deep-link) because
    ///   it's strictly more useful recovery than `.noData` (Health app) for denied users.
    ///   A brand-new device that genuinely has no HealthKit samples will show `.accessBlocked`
    ///   once; as soon as any sample arrives (including from the Watch) the banner clears.
    private func classifyEmptyFetchNotice(
        requestStatus: HKAuthorizationRequestStatus?
    ) -> HealthNotice {
        switch requestStatus {
        case .shouldRequest:
            return .accessNeeded
        case .unnecessary:
            return .accessBlocked
        default:
            return .noData
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let cachedStats = try? healthKit.fetchCachedTodayStats()

        // Paint cached values immediately — even zero rows beat the gray spinner
        // and reassure the user the app remembers them. The header pill still
        // shows that a fresh read is in flight.
        if isLoading, let cachedStats {
            applyStats(cachedStats)
            showLoadedStateIfNeeded()
        }

        // Fail-safe: if HealthKit is slow on a cold launch with no cache, drop
        // the blocking spinner after ~1s so the user sees zeros + the refresh
        // pill instead of staring at a gray spinner indefinitely.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if isLoading {
                applyStats((active: 0, resting: 0, steps: 0))
                showLoadedStateIfNeeded()
            }
        }

        defer { isRefreshing = false }

        // Skip the HK auth-status IPC roundtrip when already authorized —
        // status doesn't change between refreshes, and the only branch that
        // does anything new is `.shouldRequest`, which can't fire post-auth.
        if !healthKit.isAuthorized {
            await healthKit.synchronizeAuthorizationStateForFetching()
        }

        // Kick off the independent HK reads concurrently with today's stats so
        // wall-clock latency is `max(...)` rather than the sum. Dietary and the
        // pacing window don't depend on today's totals; the previous code only
        // started them after `fetchTodayStats` returned.
        async let dietaryEarly: Void = loadDietaryEnergy()
        async let macrosEarly: Void = loadMacros()
        async let pacingEarly: Void = loadPacing(stats: nil)
        async let energyEarly: Void = loadEnergyAverages()

        do {
            let stats = try await healthKit.fetchTodayStats()
            // Per-field max of live iPhone HK and the shared SwiftData cache.
            // The Watch reads its local HealthKit store directly and writes the
            // result to the shared cache during background refresh, which can
            // lead the iPhone's HK view by minutes (Watch → iPhone HK sync is
            // not instantaneous). Calories and steps within a single day only
            // ever increase, so taking the per-field max can never invent a
            // value — it just keeps Today from regressing behind whichever
            // device most recently observed a higher total.
            let displayStats: (active: Double, resting: Double, steps: Int)
            if let cachedStats {
                displayStats = (
                    active: max(stats.active, cachedStats.active),
                    resting: max(stats.resting, cachedStats.resting),
                    steps: max(stats.steps, cachedStats.steps)
                )
            } else {
                displayStats = stats
            }
            applyStats(displayStats)

            if isAllZero(displayStats) {
                // An all-zero today read is normal early in the day (e.g. just
                // after midnight, before any active/step/basal samples land). If
                // we have ANY historical data, access clearly works — showing
                // "Health access is off" then is a false alarm. Only surface the
                // recovery banner when there's no evidence we've ever read data.
                let hasHistory = (try? healthKit.fetchCachedHistory(days: 30))?
                    .contains { $0.active > 0 || $0.resting > 0 || $0.steps > 0 } ?? false
                if hasHistory {
                    healthNotice = nil
                } else {
                    let status = await healthKit.authorizationRequestStatus()
                    healthNotice = classifyEmptyFetchNotice(requestStatus: status)
                }
            } else {
                // We have data to show — either fresh from iPhone HK, or merged
                // up to the Watch's higher cached value. The cache is part of
                // the normal data path (Watch writes to it via background
                // refresh), so a momentarily-empty live read with a populated
                // cache is not an error condition. Don't surface a banner.
                healthNotice = nil
            }
            // Only advance the "Updated HH:mm" header after a successful read
            // so users aren't misled into thinking cached-after-failure data is fresh.
            lastRefreshDate = .now

            // Show UI immediately, don't wait for pacing/cache
            showLoadedStateIfNeeded()

            // Fire-and-forget: stats are already applied; the SwiftData write
            // and widget reload don't need to gate dietary/pacing fetches.
            // Write the merged values, not the live ones — otherwise we'd
            // overwrite a higher cache reading (set by the Watch) with the
            // iPhone's behind-by-sync live value, and the next refresh would
            // lose the merge benefit entirely.
            let cacheStats = displayStats
            Task {
                do {
                    try await healthKit.refreshCache(stats: cacheStats)
                } catch {
                    dashboardLogger.error("Today cache refresh failed: \(String(describing: error), privacy: .public)")
                }
            }

            // Background history sync for the watch shared cache AND the
            // Maintenance/TDEE widget (which reads only finalized completed days).
            Task(priority: .utility) {
                do {
                    try await healthKit.refreshHistoryCache(days: 90)
                    await checkGoalStreakMilestone(
                        history: (try? healthKit.fetchCachedHistory(days: 90)) ?? []
                    )
                } catch {
                    dashboardLogger.error("Background history cache sync failed: \(String(describing: error), privacy: .public)")
                }
            }

            // Wait for the in-flight dietary + pacing reads we kicked off above.
            await dietaryEarly
            await macrosEarly
            await pacingEarly
            await energyEarly
            // Pacing compares "what we've done so far today" against a typical
            // baseline; if we have no totals at all (live empty and cache empty),
            // that comparison is meaningless. Use the merged display so cached
            // non-zero values still keep pacing live.
            if isAllZero(displayStats) {
                clearPacing()
            }
        } catch {
            let ns = error as NSError
            dashboardLogger.error("Today stats fetch failed — domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public): \(String(describing: error), privacy: .public)")
            // Drain the in-flight reads first so their state writes can't land
            // after we reset below.
            await dietaryEarly
            await macrosEarly
            await pacingEarly
            await energyEarly
            if let cachedStats = try? healthKit.fetchCachedTodayStats() {
                // Fall back to whatever the cache last captured. The header's
                // "Updated HH:mm" timestamp won't advance (lastRefreshDate is
                // only bumped on success), so the user gets a passive signal
                // that the data is stale without an explicit error banner.
                applyStats(cachedStats)
                healthNotice = nil
            } else {
                applyStats((active: 0, resting: 0, steps: 0))
                healthNotice = .loadError
            }
            clearPacing()
            foodCalories = 0
            dietaryEnergyReady = false
            dietaryEnergyFetchFailed = false
            macros = .zero
            macrosReady = false
            macrosFetchFailed = false
            showLoadedStateIfNeeded()
        }
    }

    /// Detects whether the user has reached an uncelebrated goal-streak tier and,
    /// if so, asks the milestone coordinator to surface a celebration. Non-Pro
    /// gating and one-per-session limits live in the coordinator's handler.
    @MainActor
    private func checkGoalStreakMilestone(
        history: [(date: Date, active: Double, resting: Double, steps: Int)]
    ) {
        let days = history.map {
            MilestoneDay(date: $0.date, calories: $0.active + $0.resting, steps: $0.steps)
        }
        // Per-metric streaks drive the Vitals+ inline badges (gated at render).
        calorieStreak = goals.calorieGoal.map { goal in
            MilestoneCalculator.currentStreak(records: days) { $0.calories >= goal }
        } ?? 0
        stepStreak = goals.stepGoal.map { goal in
            MilestoneCalculator.currentStreak(records: days) { $0.steps >= goal }
        } ?? 0

        // Celebration sheets are a non-Pro upsell, fired off the *combined* streak
        // (hit either goal) - the broadest "on a roll" signal, best for conversion.
        let streak = MilestoneCalculator.currentGoalStreak(
            records: days,
            calorieGoal: goals.calorieGoal,
            stepGoal: goals.stepGoal
        )
        guard !store.isPro else { return }

        // First evaluation after install/update: adopt whatever streak already
        // exists in HealthKit history without celebrating it. Otherwise a user
        // with a long-running goal streak gets "7-day streak!" on first open.
        if !goals.hasSeededStreakMilestones {
            var seeded = goals.firedMilestoneIds
            MilestoneCalculator.seedFiredStreakIds(currentStreak: streak, into: &seeded)
            goals.firedMilestoneIds = seeded
            goals.hasSeededStreakMilestones = true
            return
        }

        guard let milestone = MilestoneCalculator.unfiredStreakMilestone(
            currentStreak: streak,
            firedIds: goals.firedMilestoneIds
        ) else { return }
        MilestoneCoordinator.shared.request(milestone)
    }
}

// MARK: - Pacing Pill

private struct PacingPill: View {
    let current: Double
    /// "Usual by now" — drives the ahead/behind clause and the green/red tint.
    /// nil when pacing is off, leaving a projection-only pill.
    let typical: Double?
    /// End-of-day projection — drives the "on pace for X" clause. nil when off.
    let projected: Double?
    let label: String
    let color: Color
    let comparison: PacingComparison
    let lookback: PacingLookback

    @State private var showExplainer = false

    private var diff: Double? { typical.map { current - $0 } }

    /// Whole-pill tint: green/red by pace when there's a comparison, otherwise the
    /// metric color for a projection-only pill.
    private var tint: Color {
        guard let diff else { return color }
        return diff >= 0 ? .green : Color(red: 1.0, green: 0.42, blue: 0.42)
    }

    private var icon: String {
        guard let diff else { return "chart.line.uptrend.xyaxis" }
        return diff >= 0 ? "arrow.up.right" : "arrow.down.right"
    }

    /// Both signals in one condensed line, e.g.
    /// "1,069 cal ahead of usual pace, on pace for 3,663 cal".
    private var message: String {
        var parts: [String] = []
        if let diff {
            let dir = diff >= 0 ? "ahead of" : "behind"
            parts.append("\(abs(Int(diff)).formatted(.number)) \(label) \(dir) usual pace")
        }
        if let projected {
            parts.append("on pace for \(Int(projected.rounded()).formatted(.number)) \(label)")
        }
        return parts.joined(separator: ", ")
    }

    private var pill: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(.caption2, design: .rounded, weight: .bold))
            Text(message)
                .font(.system(.caption2, design: .rounded))
            if typical != nil {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1), in: Capsule())
    }

    var body: some View {
        // The explainer is about pace, so it's only reachable when a pace
        // comparison is present; a projection-only pill is a plain capsule.
        if let typical {
            Button { showExplainer = true } label: { pill }
                .buttonStyle(.plain)
                .accessibilityLabel(message)
                .accessibilityHint("Explains how pace is calculated")
                .sheet(isPresented: $showExplainer) {
                    PacingExplainerSheet(typical: typical, label: label, comparison: comparison, lookback: lookback)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
        } else {
            pill
                .accessibilityElement(children: .combine)
                .accessibilityLabel(message)
        }
    }
}

// MARK: - Settings feature explainers

private enum SettingsInfoTopic: Identifiable {
    case activeResting
    case energyAverages
    case netDeficit
    case fastingMode
    case macros
    case calorieSplit
    case endOfDayProjection
    case goalStreak
    case weeklyRecap
    case bodyProfile

    var id: Self { self }

    var title: String {
        switch self {
        case .activeResting: "Active + Resting"
        case .energyAverages: "TDEE & BMR"
        case .netDeficit: "Net Deficit"
        case .fastingMode: "Fasting Mode"
        case .macros: "Macros"
        case .calorieSplit: "Calorie Split"
        case .endOfDayProjection: "End-of-Day Projection"
        case .goalStreak: "Goal Streak"
        case .weeklyRecap: "Weekly Recap"
        case .bodyProfile: "Body Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .activeResting: "flame.fill"
        case .energyAverages: "speedometer"
        case .netDeficit: "minus.plus.batteryblock"
        case .fastingMode: "moon.zzz"
        case .macros: "chart.pie.fill"
        case .calorieSplit: "chart.pie"
        case .endOfDayProjection: "chart.line.uptrend.xyaxis"
        case .goalStreak: "flame.fill"
        case .weeklyRecap: "calendar.badge.clock"
        case .bodyProfile: "figure"
        }
    }

    /// Kept to a couple of sentences: this is the body of a popover anchored to
    /// an ⓘ, not a page. Anything longer than the reader will stand still for
    /// belongs in `detail`, which renders quieter and below.
    var message: String {
        switch self {
        case .activeResting:
            "Splits the ring into the calories you burned moving and the calories your body burned at rest."
        case .energyAverages:
            "TDEE is your maintenance burn, BMR your resting burn, each averaged over the last 30 days of your own Apple Health data. They are reference figures, not goals."
        case .netDeficit:
            "Calories burned minus the food energy in Apple Health. A positive number means a deficit."
        case .fastingMode:
            "Counts days with no food logged toward your Net Deficit history. Off by default, so an unlogged day doesn't read as a full-burn deficit."
        case .macros:
            "The protein, carbs, and fat your food app writes to Apple Health. Log meals wherever you already do and they appear beside your calories. Vitals only reads them."
        case .calorieSplit:
            "Adds the food energy you logged today and each macro's share of it."
        case .endOfDayProjection:
            "Projects where today's calories and steps will land from your pace so far, using the pacing window set above."
        case .goalStreak:
            "Counts consecutive days you hit a calorie or step goal. Empty days break the streak."
        case .weeklyRecap:
            "A Sunday evening notification summarizing your week. Turning it on asks permission to notify you."
        case .bodyProfile:
            "Your BMI, free, calculated from the height and weight already in Apple Health. No Health data? Enter them by hand instead."
        }
    }

    /// Secondary paragraphs: caveats and troubleshooting that used to live in a
    /// section footer where every reader paid for them. Rendered smaller, under
    /// a divider, so the popover opens on the sentence that answers the question.
    var detail: String? {
        switch self {
        case .macros:
            "Show only the ones you track: carbs alone for carb counting, protein alone for training. Macro Goals adds a daily gram target, one macro at a time: hit a protein number while carbs and fat stay a plain readout.\n\nIf your calories sync but macros stay empty, your food app is sharing Energy without the Nutrition categories. In MyFitnessPal: More → Settings → Sharing & Privacy → HealthKit Sharing."
        case .calorieSplit:
            "The percentages come from grams the way food labels do it (4 per gram of protein and carbs, 9 for fat), so they won't match the logged figure exactly. Hiding a macro hides its row but keeps its share in the split, so visible percentages may not total 100%."
        case .energyAverages:
            "Needs about a month of Apple Health data to settle. Days without resting energy are skipped rather than counted as zero."
        case .bodyProfile:
            "It gives your calorie numbers something to sit against: BMI puts today's burn in the context of your size rather than leaving it as a bare figure. Body fat percentage is a Vitals+ extra; the BMI readout never is."
        default:
            nil
        }
    }
}

/// The ⓘ beside a settings row.
///
/// Inline rather than a `.popover`, because Settings is itself a sheet and a
/// popover here would be a second presentation stacked on the first — the exact
/// weight this replaced. Expanding under the row keeps the setting and its
/// explanation on screen together, which is the point when the reader is
/// deciding whether to flip the switch.
///
/// A tap gesture on an enlarged content shape rather than a `Button`: a
/// `.borderless` Button sharing a row with a Toggle has unreliable hit testing
/// in a Form. `SettingsSheetUITests.testInfoDotRevealsExplanation` covers it.
private struct SettingsInfoDot: View {
    let topic: SettingsInfoTopic
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Image(systemName: isOpen ? "info.circle.fill" : "info.circle")
            .foregroundStyle(isOpen ? Theme.textSecondary : Theme.textTertiary)
            // Fixed 32pt box rather than padding around a ~17pt glyph: padding
            // made every ⓘ row ~10pt taller than a plain toggle row, which read
            // as ragged spacing down the section. 32pt still clears the switch
            // beside it, so the row height is set by the switch either way.
            // 22pt matches the label text's line height, so the ⓘ never makes
            // its row taller than a plain toggle row. The tap target is grown
            // back past the glyph with a negative-inset content shape, which
            // hit-tests wider without taking up any layout height.
            .frame(width: 22, height: 22)
            .contentShape(Rectangle().inset(by: -11))
            // The dot lives inside the Toggle's label, so a plain tap gesture
            // loses to the label's own "flip the switch" tap. High priority wins
            // it back without the row having to be hand-built (which is what
            // made these rows taller than every plain toggle beside them).
            .highPriorityGesture(TapGesture().onEnded { toggle() })
            .accessibilityElement()
            .accessibilityLabel("About \(topic.title)")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOpen ? "Shown" : "Hidden")
    }
}

/// The explanation itself, shown under its row while the ⓘ is on. Reads as a
/// callout rather than a list row: tinted, inset, and quieter than the setting
/// it describes.
private struct SettingsInfoCallout: View {
    let topic: SettingsInfoTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(topic.message)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            if let detail = topic.detail {
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 2)
    }
}

/// Lightweight sheet explaining what "usual pace" is compared against, so users can
/// trust the pacing number without reading the Settings footer.
private struct PacingExplainerSheet: View {
    let typical: Double
    let label: String
    let comparison: PacingComparison
    let lookback: PacingLookback
    @Environment(\.dismiss) private var dismiss

    private var basisText: String {
        let window = lookback.label.lowercased()
        switch comparison {
        case .dayOfWeek:
            let weekday = Date().formatted(.dateTime.weekday(.wide))
            return "your average on past \(weekday)s over the last \(window)"
        case .allDays:
            return "your average on every day over the last \(window)"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "speedometer")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.caloriesPrimary)
                    .padding(.top, 12)

                Text("How pace works")
                    .font(.system(.title2, design: .rounded, weight: .bold))

                Text("“Usual pace” compares your \(label) so far today to \(basisText), measured at this same time of day.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.textTertiary)
                    Text("Usual by now: \(Int(typical.rounded()).formatted(.number)) \(label)")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.cardSurface, in: Capsule())

                Text("Empty days don’t count. You can change the comparison window in Settings.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Metric Pill

private struct MetricPill: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(value, format: .number.precision(.fractionLength(0)))")
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.cardSurface, in: Capsule())
    }
}

// MARK: - Macro Pill

/// One macro as a compact capsule, deliberately the same shape and rhythm as
/// `MetricPill` (TDEE / BMR): a reference readout, not a progress tracker.
/// Used when no macro goals are set, where there is nothing to make progress
/// against and a bar would be inventing a denominator.
private struct MacroPill: View {
    let kind: MacroKind
    let grams: Double
    /// Two or three pills divide the row evenly. A lone pill doesn't: stretching
    /// one capsule the full width of the card leaves a number marooned in the
    /// middle of it, so a single tracked macro keeps its natural width.
    var stretch: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Text("\(Int(grams.rounded()))")
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.macroColor(kind))
            Text("g")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Text(kind.label.lowercased())
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, stretch ? 0 : 16)
        .frame(maxWidth: stretch ? .infinity : nil)
        .padding(.vertical, 8)
        // The pills live inside the macros card, so they need the lighter
        // surface to read as raised — MetricPill sits on the page background
        // and can use cardSurface directly.
        .background(Theme.cardSurfaceLight, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.label)
        .accessibilityValue("\(Int(grams.rounded())) grams")
    }
}

// MARK: - Macro Row

/// One macronutrient as a labelled progress bar. Only used when the user has set
/// macro goals; without a target there is nothing to make progress against and
/// the card falls back to `MacroPill`, matching how calories drop the ring when
/// no calorie goal is set.
private struct MacroBarRow: View {
    let kind: MacroKind
    let grams: Double
    let goal: Int

    /// Capped at full so an over-goal day doesn't overflow the track; the
    /// overage stays readable in the number beside it.
    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(grams / Double(goal), 1)
    }

    private var valueText: String {
        "\(Int(grams.rounded()).formatted(.number)) / \(goal.formatted(.number)) g"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(kind.label)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 54, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.ringTrack)
                    Capsule()
                        .fill(Theme.macroColor(kind))
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 8)

            Text(valueText)
                .font(.system(.caption, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 88, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.label)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        "\(Int(grams.rounded())) of \(goal) grams"
    }
}

// MARK: - Onboarding Sheet (first launch only)

private struct OnboardingSheet: View {
    private enum Step {
        case welcome
        case goals
        case food
        case trial
    }

    @ObservedObject var goals: GoalSettings
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .welcome
    @State private var wantCalGoal = true
    @State private var calText = "2500"
    @State private var wantStepGoal = true
    @State private var stepText = "10000"
    @State private var hasRequestedHealthAccess = false
    /// Answer to the food question, held locally until Continue commits it.
    @State private var logsFoodChoice: Bool?
    @State private var isRequestingFoodAccess = false
    @State private var isStartingTrial = false
    @State private var trialError: String?
    /// Set when the trial CTA has waited long enough for RevenueCat that a
    /// spinner is no longer an honest answer. See `trialCTAWaitLimit`.
    @State private var trialCTAWaitExpired = false
    @State private var isRestoring = false
    /// Emergency fallback: presented only when the onboarding package failed to load,
    /// so the primary CTA is never a dead disabled button.
    @State private var showPaywallFallback = false

    private var calValid: Bool {
        !wantCalGoal || (Double(calText).map { (500...50000).contains($0) } ?? false)
    }

    private var stepValid: Bool {
        !wantStepGoal || (Int(stepText).map { (100...500000).contains($0) } ?? false)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step == .trial {
                    // Trial must NOT live in a ScrollView: Spacers need a bounded
                    // height to center the pitch above the zero-shift CTA bar.
                    trialPage
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            // A returning subscriber (reinstall, restored
                            // entitlement) reaches this step already Pro. Pitch
                            // them nothing: set their goals, then let them in.
                            guard !store.isPro else {
                                finishOnboarding()
                                return
                            }
                            store.trackPaywallImpression(id: "vitals_onboarding_trial", oncePerSession: true)
                        }
                        .task(id: store.conversionCTAReady) {
                            guard !store.conversionCTAReady else { return }
                            // One more fetch before giving up: the warm-up in
                            // the parent `.task` may have run while the device
                            // was still offline.
                            if store.products.isEmpty { await store.fetchProducts() }
                            guard !store.conversionCTAReady else { return }
                            try? await Task.sleep(for: Self.trialCTAWaitLimit)
                            guard !Task.isCancelled else { return }
                            trialCTAWaitExpired = true
                        }
                } else {
                    ScrollView {
                        Group {
                            switch step {
                            case .welcome: welcomePage
                            case .goals: goalsPage
                            case .food: foodPage
                            case .trial: EmptyView()
                            }
                        }
                        .padding(.top, 48)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                bottomBar
            }
        }
        // Warm the products early so the trial step has live price/trial copy by
        // the time the user reaches it (StatScout pattern).
        .task {
            if store.products.isEmpty { await store.fetchProducts() }
        }
        // A purchase or restore *made on the trial step* finishes onboarding.
        // Deliberately not any flip to Pro: on a reinstall, StoreKit resolves an
        // existing subscription a second or two after launch, and finishing here
        // would yank a returning subscriber out of the goal step they were still
        // filling in.
        .onChange(of: store.isPro) { _, isPro in
            if isPro, step == .trial { finishOnboarding() }
        }
        .sheet(isPresented: $showPaywallFallback) {
            PaywallView()
                .environmentObject(store)
                .task { store.trackPaywallImpression(id: "vitals_onboarding_fallback") }
        }
    }

    /// Completes onboarding and dismisses. Does **not** stamp the passive trial
    /// cooldown — that would block the thoughtful 2nd-session re-pitch. Same-session
    /// suppression lives in `MainTabView` (`skipPassiveTrialThisSession`).
    private func finishOnboarding() {
        goals.hasCompletedSetup = true
        dismiss()
    }

    /// Fire the HealthKit prompt once, when the user leaves the welcome screen —
    /// never on appear, so the first thing they see is our heads-up rather than
    /// the system permission sheet.
    private func requestHealthAccessIfNeeded() async {
        guard !hasRequestedHealthAccess else { return }
        hasRequestedHealthAccess = true
        do {
            try await HealthKitService.shared.requestAuthorization()
            // Warm the SwiftData cache in the background while the user finishes
            // picking goals, so the dashboard can paint from cache the instant
            // onboarding dismisses instead of waiting on a cold HealthKit read.
            Task { try? await HealthKitService.shared.refreshCache() }
        } catch {
            dashboardLogger.error("Onboarding HealthKit auth failed: \(String(describing: error), privacy: .public)")
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.caloriesGradient)
                Text("Welcome to Total Calories")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Track your calories and steps from Apple Health in one simple view.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 16) {
                WelcomePoint(
                    icon: "heart.fill",
                    color: Theme.caloriesPrimary,
                    title: "Reads from Apple Health",
                    detail: "Next we’ll ask permission to read your active and resting calories and steps. The app only reads; it never writes anything back."
                )
                WelcomePoint(
                    icon: "lock.fill",
                    color: Theme.stepsPrimary,
                    title: "Stays on your device",
                    detail: "Your health data never leaves your iPhone. No account, no cloud sync."
                )
            }
        }
    }

    private var goalsPage: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.caloriesPrimary)
                Text("Set your daily goals")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Or turn both off to use Total Calories as a simple counter.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                GoalRow(
                    icon: "flame.fill",
                    color: Theme.caloriesPrimary,
                    title: "Calorie Goal",
                    enabled: $wantCalGoal,
                    text: $calText,
                    isValid: calValid
                )
                GoalRow(
                    icon: "figure.walk",
                    color: Theme.stepsPrimary,
                    title: "Step Goal",
                    enabled: $wantStepGoal,
                    text: $stepText,
                    isValid: stepValid
                )

                if !wantCalGoal && !wantStepGoal {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.stepsPrimary)
                        Text("Today will show live calorie and step totals without target rings. You can add goals later in Settings.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.cardSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: wantCalGoal || wantStepGoal)
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    /// Unified bottom bar across every onboarding page. The primary button is
    /// pinned from the bottom by a fixed-height legal-footer slot (real
    /// Terms/Privacy/Restore on the trial page, an invisible placeholder of
    /// identical height elsewhere), so the CTA frame is pixel-identical on
    /// Welcome, Goals, and the trial page (Rev A zero-shift requirement).
    /// Page-specific content (trust line, disclosure) sits ABOVE the button,
    /// where variable height is fine because it never moves the bottom-pinned
    /// button. The soft exit sits below it, quieter than the trial CTA.
    private var bottomBar: some View {
        VStack(spacing: 12) {
            aboveButtonSlot

            primaryButton

            // Free exit, below the trial button rather than above it. It stays a
            // plain, labelled, reachable control — it just stops competing with
            // the trial for the eye, which is the whole point of the page.
            // Reserved on every page (invisible off trial) so the button above
            // it keeps its pixel-identical frame.
            softExitSlot
                .opacity(step == .trial ? 1 : 0)
                .allowsHitTesting(step == .trial)
                .accessibilityHidden(step != .trial)

            // Fixed legal-footer slot. Identical view on every page so its height
            // never changes; only visible + interactive on the trial page.
            legalFooter
                .opacity(step == .trial ? 1 : 0)
                .allowsHitTesting(step == .trial)
                .accessibilityHidden(step != .trial)
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Theme.background)
    }

    /// Reserved so the primary button sits at the same y on every page. Each
    /// page puts something different here (a trust line, nothing, the billing
    /// disclosure), and letting the slot size to its content is what walked the
    /// button up and down the screen as the user advanced.
    private var aboveButtonSlot: some View {
        aboveButtonContent
            .frame(minHeight: 46, alignment: .bottom)
    }

    @ViewBuilder
    private var aboveButtonContent: some View {
        switch step {
        case .welcome: welcomeTrustLine
        case .goals: EmptyView()
        case .food: foodPrivacyLine
        case .trial: trialSoftExitAndDisclosure
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button {
                Task { await requestHealthAccessIfNeeded() }
                withAnimation(.easeInOut(duration: 0.25)) { step = .goals }
            } label: {
                primaryLabel("Continue")
            }
            .padding(.horizontal, 24)
        case .goals:
            Button {
                if wantCalGoal, let cal = Double(calText), (500...50000).contains(cal) {
                    goals.calorieGoal = cal
                } else {
                    goals.calorieGoal = nil
                }
                if wantStepGoal, let stepValue = Int(stepText), (100...500000).contains(stepValue) {
                    goals.stepGoal = stepValue
                } else {
                    goals.stepGoal = nil
                }
                // Goals are saved, but onboarding continues. The primary stays
                // in the same coral slot on every page.
                withAnimation(.easeInOut(duration: 0.25)) { step = .food }
            } label: {
                primaryLabel("Continue", enabled: calValid && stepValid)
            }
            .disabled(!calValid || !stepValid)
            .opacity(calValid && stepValid ? 1 : 0.5)
            .padding(.horizontal, 24)
        case .food:
            Button {
                Task { await commitFoodAnswerAndContinue() }
            } label: {
                ZStack {
                    primaryLabel("Continue", enabled: logsFoodChoice != nil && !isRequestingFoodAccess)
                        .opacity(isRequestingFoodAccess ? 0 : 1)
                    if isRequestingFoodAccess {
                        ProgressView().tint(.white)
                    }
                }
            }
            .disabled(logsFoodChoice == nil || isRequestingFoodAccess)
            .opacity(logsFoodChoice == nil ? 0.5 : 1)
            .padding(.horizontal, 24)
        case .trial:
            Button {
                startTrial()
            } label: {
                ZStack {
                    primaryLabel(trialCTALabel, enabled: !isStartingTrial && trialCTAEnabled)
                        .opacity(isStartingTrial || !trialCTAEnabled ? 0 : 1)
                    if isStartingTrial || !trialCTAEnabled {
                        ProgressView().tint(.white)
                    }
                }
            }
            .disabled(isStartingTrial || !trialCTAEnabled)
            .padding(.horizontal, 24)
        }
    }

    // MARK: Food step

    /// Asks the one thing HealthKit will not answer: does this person log food
    /// anywhere that reaches Apple Health?
    ///
    /// Net Deficit and Macros both read dietary data. Pitching them to someone
    /// who logs nothing sells a permanently empty screen, and the app cannot
    /// detect that case on its own: read authorization is unreadable by design,
    /// and an empty dietary query means "denied" and "logs nothing" equally.
    /// A yes also earns the right to ask for the food types, in a separate sheet
    /// from the one that carries calories and steps, so a decline here can never
    /// cost the core app its permissions.
    private var foodPage: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.macrosBrand)
                Text("Do you log your food?")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("In MyFitnessPal, Lose It!, Cronometer, or anything else that saves to Apple Health.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                FoodAnswerCard(
                    title: "Yes, I log my food",
                    detail: "We'll show your net calories and macros",
                    icon: "checkmark.circle.fill",
                    tint: Theme.macrosBrand,
                    isSelected: logsFoodChoice == true
                ) {
                    logsFoodChoice = true
                }
                FoodAnswerCard(
                    title: "No, just track my burn",
                    detail: "Calories and steps only. You can change this later.",
                    icon: "flame.fill",
                    tint: Theme.caloriesPrimary,
                    isSelected: logsFoodChoice == false
                ) {
                    logsFoodChoice = false
                }
            }
        }
    }

    /// Sits in the same slot as the welcome page's trust line, so the primary
    /// button does not move between pages.
    private var foodPrivacyLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.stepsPrimary)
            Text("Read-only, and only if you say yes.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    /// Saves the answer, then asks HealthKit for the food types only on a yes.
    /// The request is deliberately a second, separate sheet: a decline cannot
    /// touch the calories and steps permission the free app depends on.
    private func commitFoodAnswerAndContinue() async {
        guard let choice = logsFoodChoice else { return }
        goals.logsFoodInHealth = choice
        if choice {
            isRequestingFoodAccess = true
            do {
                try await HealthKitService.shared.requestDietaryAuthorization()
            } catch {
                // A failed or dismissed sheet is not a dead end: the user keeps
                // the answer they gave, and every food feature re-asks at the
                // point it is switched on.
                dashboardLogger.error("Onboarding dietary auth failed: \(String(describing: error), privacy: .public)")
            }
            isRequestingFoodAccess = false
        }
        withAnimation(.easeInOut(duration: 0.25)) { step = .trial }
    }

    private var welcomeTrustLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.stepsPrimary)
            Text("Read-only. Stays on your device. No account.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    /// Trial-page content that lives ABOVE the primary button: the billing
    /// disclosure (Apple 3.1.2 wants it adjacent to the purchase) and any
    /// purchase error. Kept above the CTA so neither can shift the button.
    private var trialSoftExitAndDisclosure: some View {
        VStack(spacing: 12) {
            // Render no disclosure until the package loads — never a phantom price.
            // Error replaces disclosure in the same slot (no overlap).
            if let trialError {
                Text(trialError)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.caloriesPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else if let disclosure = store.onboardingTrialDisclosureText {
                Text(disclosure)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
        }
    }

    /// The free way out of onboarding. Quieter than it was and below the trial
    /// button now, but never hidden: same tap target, same plain label, and it
    /// reads as a real choice to anyone looking for one.
    private var softExitSlot: some View {
        Button {
            finishOnboarding()
        } label: {
                Text("Get Started")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    /// Terms / Privacy / Restore beside the purchase point. Rendered on every
    /// onboarding page (invisible off the trial page) so it reserves identical
    /// height and the primary button never shifts between pages.
    private var legalFooter: some View {
        HStack(spacing: 14) {
            Link("Terms", destination: VitalsLinks.standardEULA)
            Link("Privacy", destination: VitalsLinks.privacyPolicy)
            Button(isRestoring ? "Restoring…" : "Restore") {
                // Fire-and-forget before: the task was unobserved, so a
                // returning subscriber with nothing to restore tapped it and
                // watched nothing happen. A success flips `isPro`, which
                // finishes onboarding through the existing onChange.
                isRestoring = true
                Task { @MainActor in
                    defer { isRestoring = false }
                    trialError = nil
                    await store.restorePurchases()
                    guard !store.isPro else { return }
                    trialError = store.lastError
                        ?? "No active Vitals+ purchase was found for this Apple ID."
                }
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(Theme.textTertiary)
    }

    // MARK: Trial step

    /// What the onboarding pitch leads with, decided by the food question.
    ///
    /// Net Deficit and Macros are the two strongest features in the tier and the
    /// two that read as an empty screen to anyone who logs no food. Selling them
    /// to that person is not a weaker pitch, it is a promise the app cannot keep,
    /// so they get the three features that work off burn data alone. `nil`
    /// (installs that predate the question) keeps the old mixed list.
    private var trialSellingPoints: [TrialPoint] {
        let netDeficit = TrialPoint(
            icon: "plus.forwardslash.minus",
            color: Theme.caloriesPrimary,
            title: "Net deficit",
            detail: "Burned minus the food you log"
        )
        let macros = TrialPoint(
            icon: "chart.pie.fill",
            color: Theme.macrosBrand,
            title: "Macros",
            detail: "Protein, carbs, and fat, every day"
        )
        let trends = TrialPoint(
            icon: "chart.line.uptrend.xyaxis",
            color: Theme.stepsPrimary,
            title: "Deeper trends",
            detail: "TDEE, BMR, and period comparisons"
        )
        let streaks = TrialPoint(
            icon: "flame.fill",
            color: Theme.streakPrimary,
            title: "Streaks & projections",
            detail: "Keep the chain and see end-of-day pace"
        )
        let reports = TrialPoint(
            icon: "doc.richtext.fill",
            color: Theme.netDeficitBrand,
            title: "Summary reports",
            detail: "Export a PDF for any date range"
        )

        switch goals.logsFoodInHealth {
        case true: return [macros, netDeficit, trends]
        case false: return [trends, streaks, reports]
        case nil: return [netDeficit, macros, trends]
        }
    }

    private var trialHeadline: String {
        goals.logsFoodInHealth == false ? "Go further with Vitals+" : "Your food, in the picture"
    }

    private var trialSubheadline: String {
        goals.logsFoodInHealth == false
            ? "Deeper numbers on top of your daily calories and steps."
            : "Everything you log already, sitting next to what you burn."
    }

    /// Final onboarding step: compact pitch with icon chips + short lines.
    /// Content is vertically centered in the scroll area so the zero-shift CTA
    /// bar below doesn't leave a dead band under the last selling point.
    private var trialPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.caloriesGradient)

                VStack(spacing: 6) {
                    Text(trialHeadline)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(trialSubheadline)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(trialSellingPoints, id: \.title) { point in
                        TrialSellingPoint(
                            icon: point.icon,
                            color: point.color,
                            title: point.title,
                            detail: point.detail
                        )
                    }
                }
            }

            Spacer(minLength: 8)
        }
    }

    /// One-tap conversion: buy the onboarding plan directly (trial when eligible)
    /// so Apple's confirm sheet is the only interstitial. Falls back to the full
    /// PaywallView only when products failed to load, never a dead button.
    private func startTrial() {
        guard let package = store.onboardingTrialPackage else {
            // No package means products never loaded. The full paywall owns the
            // retry and error UI, so hand the user to it rather than leaving
            // them on a button that cannot do anything.
            showPaywallFallback = true
            return
        }
        trialError = nil
        isStartingTrial = true
        Task { @MainActor in
            defer { isStartingTrial = false }
            await store.refreshIntroEligibility()
            do {
                // StoreKit grants the trial only when this customer is eligible.
                switch try await store.purchase(package) {
                case .purchased:
                    finishOnboarding()
                case .pending:
                    // Not an entitlement. Keep the pitch on screen and say what
                    // is happening; `onChange(of: store.isPro)` finishes
                    // onboarding by itself if the transaction later clears.
                    trialError = store.purchasePendingMessage(for: package)
                case .cancelled:
                    trialError = store.purchaseCancelledMessage(for: package)
                case .unavailable:
                    showPaywallFallback = true
                }
            } catch {
                await store.refreshIntroEligibility()
                trialError = store.lastError ?? store.purchaseFailedMessage(for: package)
            }
        }
    }

    /// How long the trial CTA will show a spinner before it admits that products
    /// are not coming. Long enough to cover an ordinary cold StoreKit fetch,
    /// short enough that a RevenueCat or network failure does not read as a
    /// hung app on the highest-intent screen in onboarding.
    private static let trialCTAWaitLimit = Duration.seconds(6)

    /// The CTA is live once RevenueCat has named the action, and live *anyway*
    /// once the wait limit passes. A disabled spinner with no timeout turns a
    /// transient product-load failure into a dead end: the fallback route in
    /// `startTrial()` is behind this button, so the button has to be pressable
    /// for the user to ever reach it.
    private var trialCTAEnabled: Bool {
        store.conversionCTAReady || trialCTAWaitExpired
    }

    /// Never promises a trial the store has not confirmed. Once the wait expires
    /// without products, the button stops naming a price it does not know.
    private var trialCTALabel: String {
        store.conversionCTAReady ? store.onboardingTrialCTALabel : "See Vitals+ Plans"
    }

    /// Every onboarding primary carries the same halo. It used to be the trial
    /// page only, which made the last button look like a different, louder kind
    /// of thing than the two the user had already pressed. Identical treatment
    /// on every page is what makes the purchase read as the next step in
    /// onboarding rather than a sales interruption.
    private func primaryLabel(_ title: String, enabled: Bool = true) -> some View {
        Text(title)
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.caloriesPrimary, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            // A halo around a button that cannot be pressed reads as a bug.
            .modifier(OptionalCTAGlow(active: enabled))
    }
}

/// One answer on the food question. A card rather than a radio row: there are
/// two of them, they are the only thing to do on the page, and they should read
/// as a choice being offered rather than a form being filled in.
/// One row of the onboarding pitch. A value type so the list can be chosen by
/// the food answer instead of hard-coded into the view.
private struct TrialPoint {
    let icon: String
    let color: Color
    let title: String
    let detail: String
}

private struct FoodAnswerCard: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : Theme.textTertiary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? tint : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "" : "Double tap to choose")
    }
}

private struct WelcomePoint: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// Compact selling point for the onboarding trial step: tinted icon + title +
/// one short supporting line (StatScout density, Vitals icon mix).
private struct TrialSellingPoint: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GoalRow: View {
    let icon: String
    let color: Color
    let title: String
    @Binding var enabled: Bool
    @Binding var text: String
    var isValid: Bool = true

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
            }
            if enabled {
                TextField("Target", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(.body, design: .rounded))
                    .padding(12)
                    .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 10))
                if !isValid {
                    Text(title == "Calorie Goal" ? "Enter 500–50,000 calories." : "Enter 100–500,000 steps.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .background(Theme.cardSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct SettingsSheet: View {
    @ObservedObject var goals: GoalSettings
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    @State private var calEnabled = true
    @State private var calText = ""
    @State private var stepEnabled = true
    @State private var stepText = ""
    @State private var macroGoalText: [MacroKind: String] = [:]
    @State private var appliedGoalDrafts = false
    /// Only one explainer is open at a time; two expanded callouts turn the
    /// section into a wall of prose, which is what this replaced.
    @State private var expandedInfoTopic: SettingsInfoTopic?
    /// The Vitals+ pitch a locked row asked for, presented over this sheet.
    @State private var trialPitch: TrialPitchRequest?
    /// The same request, kept past dismissal: `.sheet(item:)` has already
    /// cleared the binding by the time `onDismiss` runs, and that's exactly when
    /// we need to know which row the user reached for.
    @State private var lastPitch: TrialPitchRequest?
    /// Products never loaded, so the pitch had nothing to sell in one tap.
    @State private var showPlanPicker = false
    /// Chains the plan picker after the pitch is fully gone — a second sheet
    /// raised in the same tick as the first one closes is dropped.
    @State private var wantsPlanPicker = false
    @FocusState private var focusedGoalField: GoalField?

    private enum GoalField: Hashable { case calories, steps, macro(MacroKind) }

    private var calValid: Bool {
        !calEnabled || (Double(calText).map { (500...50000).contains($0) } ?? false)
    }

    private var stepValid: Bool {
        !stepEnabled || (Int(stepText).map { (100...500000).contains($0) } ?? false)
    }

    private func macroVisibleBinding(_ kind: MacroKind) -> Binding<Bool> {
        Binding(
            get: { goals.isMacroVisible(kind) },
            set: { goals.setMacroVisible($0, for: kind) }
        )
    }

    private func macroGoalEnabledBinding(_ kind: MacroKind) -> Binding<Bool> {
        Binding(
            get: { goals.isMacroGoalEnabled(kind) },
            set: { goals.setMacroGoalEnabled($0, for: kind) }
        )
    }

    private func macroGoalBinding(_ kind: MacroKind) -> Binding<String> {
        Binding(
            get: { macroGoalText[kind] ?? String(kind.defaultGoal) },
            set: { macroGoalText[kind] = $0 }
        )
    }

    private func macroGoalValid(_ kind: MacroKind) -> Bool {
        guard goals.isMacroGoalEnabled(kind), goals.isMacroVisible(kind) else { return true }
        return Int(macroGoalText[kind] ?? "").map { kind.goalRange.contains($0) } ?? false
    }

    private var macroGoalsValid: Bool {
        MacroKind.allCases.allSatisfy(macroGoalValid)
    }

    private var showCaloriesBinding: Binding<Bool> {
        Binding(
            get: { goals.showCalories },
            set: { goals.showCalories = $0 }
        )
    }

    private var showStepsBinding: Binding<Bool> {
        Binding(
            get: { goals.showSteps },
            set: { goals.showSteps = $0 }
        )
    }

    private var showNetCaloriesBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.showNetCalories },
            set: { enabled in
                if store.isPro {
                    if enabled {
                        // Don't flip the setting from inside Settings — HealthKit
                        // suppresses the dietary permission sheet while this sheet
                        // is up. DashboardView dismisses first, then enables + asks.
                        NotificationCenter.default.post(
                            name: .vitalsEnableNetDeficitWithDietaryAuth,
                            object: nil
                        )
                    } else {
                        goals.showNetCalories = false
                    }
                } else if enabled {
                    goals.showNetCalories = false
                    requestTrialOffer(.netDeficitToggle)
                }
            }
        )
    }

    /// Peer toggle to Net Deficit — only meaningful when Net Deficit is on.
    /// Off = exclude unlogged-food days from history; on = count them.
    private var netDeficitFastingBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.netDeficitFastingMode },
            set: { enabled in
                guard store.isPro else { return }
                goals.netDeficitFastingMode = enabled
            }
        )
    }

    /// Macros mirrors Net Deficit's enable dance: the toggle can't flip the
    /// setting from inside Settings, because HealthKit suppresses its permission
    /// sheet while this sheet covers the window.
    private var showMacrosBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.showMacros },
            set: { enabled in
                if store.isPro {
                    if enabled {
                        NotificationCenter.default.post(
                            name: .vitalsEnableMacrosWithHealthAuth,
                            object: nil
                        )
                    } else {
                        goals.showMacros = false
                    }
                } else if enabled {
                    goals.showMacros = false
                    requestTrialOffer(.macrosToggle)
                }
            }
        )
    }

    /// Peer toggle to Macros. Only meaningful when Macros is on.
    private var macroSplitBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.macroSplitEnabled },
            set: { enabled in
                guard store.isPro else { return }
                goals.macroSplitEnabled = enabled
            }
        )
    }

    private var macroGoalsBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.macroGoalsEnabled },
            set: { enabled in
                guard store.isPro else { return }
                goals.macroGoalsEnabled = enabled
            }
        )
    }

    private var showActiveRestingBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.showActiveRestingBreakdown },
            set: { enabled in
                if store.isPro {
                    goals.showActiveRestingBreakdown = enabled
                } else if enabled {
                    goals.showActiveRestingBreakdown = false
                    requestTrialOffer(.activeRestingToggle)
                }
            }
        )
    }

    private var showEnergyAveragesBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.showEnergyAverages },
            set: { enabled in
                if store.isPro {
                    goals.showEnergyAverages = enabled
                } else if enabled {
                    goals.showEnergyAverages = false
                    requestTrialOffer(.energyAveragesToggle)
                }
            }
        )
    }

    private var showProjectionsBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.showProjections },
            set: { enabled in
                if store.isPro {
                    goals.showProjections = enabled
                } else if enabled {
                    goals.showProjections = false
                    requestTrialOffer(.projectionsToggle)
                }
            }
        )
    }

    private var showStreaksBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.showStreaks },
            set: { enabled in
                if store.isPro {
                    goals.showStreaks = enabled
                } else if enabled {
                    goals.showStreaks = false
                    requestTrialOffer(.streaksToggle)
                }
            }
        )
    }

    /// Toggle label that appends a lock glyph for non-subscribers, matching the
    /// existing Net Deficit / Active+Resting rows.
    @ViewBuilder
    private func plusToggleLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
            if !store.isPro {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.caloriesPrimary)
            }
        }
    }

    @ViewBuilder
    /// A Vitals+ toggle with an ⓘ beside its label. The switch is built from a
    /// labelless Toggle rather than a plain one so the button can sit between the
    /// title and the switch without the row's tap target swallowing it.
    private func settingsToggleRow(
        _ title: String,
        isOn: Binding<Bool>,
        topic: SettingsInfoTopic,
        toggleDisabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // A real labelled Toggle, not a hand-built row: the Form gives its
            // own controls tighter insets than arbitrary content, which is why
            // the ⓘ rows used to stand ~10pt taller than the plain toggles
            // above them.
            Toggle(isOn: isOn) {
                HStack(spacing: 0) {
                    plusToggleLabel(title)
                    SettingsInfoDot(topic: topic, isOpen: expandedInfoTopic == topic) {
                        withAnimation(.snappy(duration: 0.22)) {
                            expandedInfoTopic = expandedInfoTopic == topic ? nil : topic
                        }
                    }
                    Spacer(minLength: 8)
                }
            }
            .accessibilityLabel(title)
            .disabled(toggleDisabled)
            if expandedInfoTopic == topic {
                SettingsInfoCallout(topic: topic)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var weeklyRecapBinding: Binding<Bool> {
        Binding(
            get: { store.isPro && goals.weeklyRecapEnabled },
            set: { enabled in
                if store.isPro {
                    goals.weeklyRecapEnabled = enabled
                    Task {
                        if enabled {
                            await NotificationService.scheduleWeeklyRecap()
                        } else {
                            NotificationService.cancelWeeklyRecap()
                        }
                    }
                } else if enabled {
                    goals.weeklyRecapEnabled = false
                    requestTrialOffer(.weeklyRecapToggle)
                }
            }
        )
    }

    /// Answer the tap where it happened: the pitch opens over Settings, and
    /// closing it puts the user back on the row they tapped.
    ///
    /// This used to `dismiss()` Settings and hand the intent to MainTabView on a
    /// 350ms delay, which flashed the Today dashboard between the two and threw
    /// the tapped feature away whenever a passive offer had already claimed the
    /// slot — so a tap on Macros could answer with the generic pitch.
    private func requestTrialOffer(_ intent: TrialOfferCoordinator.Intent) {
        let request = TrialPitchRequest(intent: intent, impressionID: "vitals_trial_offer_settings")
        lastPitch = request
        trialPitch = request
    }

    private var showPacingBinding: Binding<Bool> {
        Binding(
            get: { goals.showPacing },
            set: { goals.showPacing = $0 }
        )
    }

    private var pacingComparisonBinding: Binding<PacingComparison> {
        Binding(
            get: { goals.pacingComparison },
            set: { goals.pacingComparison = $0 }
        )
    }

    private var pacingLookbackBinding: Binding<PacingLookback> {
        Binding(
            get: { goals.pacingLookback },
            set: { goals.pacingLookback = $0 }
        )
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { goals.appearance },
            set: { goals.appearance = $0 }
        )
    }

    /// Every switch in this section now explains itself on its own ⓘ, so the
    /// footer says only where the numbers come from.
    private var calorieIntakeFooter: String {
        "Read from the food you log in Apple Health."
    }

    private var pacingFooter: String {
        let window = goals.pacingLookback.label.lowercased()
        let basis = goals.pacingComparison == .dayOfWeek
            ? "Past \(window), same weekday as today."
            : "Past \(window), every day."
        let minSamples = effectiveMinPacingSamples(for: goals.pacingComparison, lookback: goals.pacingLookback)
        let dayWord = minSamples == 1 ? "day" : "days"
        return "Compares your progress so far to your usual at this time (Apple Health). \(basis) Empty days don’t count. Need \(minSamples)+ \(dayWord) with data to show a comparison."
    }

    private func applyGoalDrafts() {
        guard !appliedGoalDrafts else { return }
        appliedGoalDrafts = true
        if calEnabled {
            if let cal = Double(calText), (500...50000).contains(cal) {
                goals.calorieGoal = cal
            }
        } else {
            goals.calorieGoal = nil
        }

        if stepEnabled {
            if let step = Int(stepText), (100...500000).contains(step) {
                goals.stepGoal = step
            }
        } else {
            goals.stepGoal = nil
        }

        for kind in MacroKind.allCases {
            if let grams = Int(macroGoalText[kind] ?? ""), kind.goalRange.contains(grams) {
                goals.setMacroGoal(grams, for: kind)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                vitalsPlusSection

                // Calorie Burn — the ring and everything that shapes the number
                // in it. Split from intake because "2,400" and "1,950" are two
                // different quantities that were previously toggled side by side.
                Section {
                    Toggle("Show Calories", isOn: showCaloriesBinding)
                    Toggle("Calorie Goal", isOn: $calEnabled)
                    if calEnabled {
                        HStack {
                            Text("Daily target")
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            TextField("2500", text: $calText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedGoalField, equals: .calories)
                            Text("cal")
                                .foregroundStyle(Theme.textTertiary)
                        }
                        if !calValid {
                            Text("Enter 500–50,000 calories.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    settingsToggleRow(
                        "Active + Resting Breakdown",
                        isOn: showActiveRestingBinding,
                        topic: .activeResting
                    )
                    settingsToggleRow(
                        "TDEE & BMR",
                        isOn: showEnergyAveragesBinding,
                        topic: .energyAverages
                    )
                } header: {
                    Text("Calorie Burn")
                } footer: {
                    // What each Vitals+ switch does now lives on its own ⓘ, so
                    // the footer is down to the two facts no row can carry.
                    Text("What you burn, from Apple Health. Goal changes save when you close Settings.")
                }

                // Calorie Intake — everything read from logged food, in the order
                // it builds: the burn-minus-food number, its fasting rule, then
                // the macros behind that food. The ⓘ on each row carries the
                // explanation these switches used to spend a footer paragraph on.
                Section {
                    settingsToggleRow(
                        "Net Deficit",
                        isOn: showNetCaloriesBinding,
                        topic: .netDeficit
                    )
                    if store.isPro && goals.showNetCalories {
                        settingsToggleRow(
                            "Fasting Mode",
                            isOn: netDeficitFastingBinding,
                            topic: .fastingMode
                        )
                    }
                    settingsToggleRow(
                        "Show Macros",
                        isOn: showMacrosBinding,
                        topic: .macros
                    )
                    if store.isPro && goals.showMacros {
                        ForEach(MacroKind.allCases) { kind in
                            Toggle(isOn: macroVisibleBinding(kind)) {
                                HStack(spacing: 10) {
                                    // Same dot colour the pills, bars, and chart
                                    // use, so the toggle teaches the mapping.
                                    Circle()
                                        .fill(Theme.macroColor(kind))
                                        .frame(width: 10, height: 10)
                                    Text(kind.label)
                                }
                            }
                            // The last one on can't be switched off; Show Macros
                            // above is the way to hide the card.
                            .disabled(goals.isMacroVisible(kind) && goals.visibleMacroSet.count == 1)
                        }
                        // Sub-options of Show Macros, so they appear under it
                        // rather than sitting greyed out above the fold for
                        // everyone who doesn't track food at all.
                        settingsToggleRow(
                            "Calorie Split",
                            isOn: macroSplitBinding,
                            topic: .calorieSplit
                        )
                        Toggle(isOn: macroGoalsBinding) {
                            plusToggleLabel("Macro Goals")
                        }
                    }
                    if store.isPro && goals.showMacros && goals.macroGoalsEnabled {
                        // Each macro decides for itself whether it has a target:
                        // a protein number to hit while carbs and fat stay a
                        // plain readout is a normal way to eat.
                        ForEach(goals.visibleMacros) { kind in
                            Toggle("\(kind.label) Goal", isOn: macroGoalEnabledBinding(kind))
                                // The last goal on can't be switched off; Macro
                                // Goals above is the way to drop all of them.
                                .disabled(goals.isMacroGoalEnabled(kind) && goals.goaledMacros.count == 1)
                            if goals.isMacroGoalEnabled(kind) {
                                HStack {
                                    // "Daily protein" rather than a second
                                    // "Protein Goal": the toggle right above
                                    // already names the setting, and three rows
                                    // reading "Daily target" would be
                                    // indistinguishable to VoiceOver.
                                    Text("Daily \(kind.label.lowercased())")
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    TextField(String(kind.defaultGoal), text: macroGoalBinding(kind))
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .focused($focusedGoalField, equals: .macro(kind))
                                    Text("g")
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                if !macroGoalValid(kind) {
                                    Text("Enter \(kind.goalRange.lowerBound.formatted(.number))–\(kind.goalRange.upperBound.formatted(.number)) g.")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Calorie Intake")
                } footer: {
                    Text(calorieIntakeFooter)
                }


                // Steps — the step counter and its goal together.
                Section {
                    Toggle("Show Steps", isOn: showStepsBinding)
                    Toggle("Step Goal", isOn: $stepEnabled)
                    if stepEnabled {
                        HStack {
                            Text("Daily target")
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            TextField("10000", text: $stepText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedGoalField, equals: .steps)
                            Text("steps")
                                .foregroundStyle(Theme.textTertiary)
                        }
                        if !stepValid {
                            Text("Enter 100–500,000 steps.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Goal changes save when you close Settings; other settings apply instantly.")
                }

                // Pacing & Projections — the "how am I tracking today" family.
                // Projection is pace-derived and Goal Streak rides on the goals
                // above, so they live next to pacing rather than in a separate lump.
                Section {
                    Toggle("Show Pacing", isOn: showPacingBinding)
                    if goals.showPacing {
                        Picker("Usual day is", selection: pacingComparisonBinding) {
                            ForEach(PacingComparison.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        Picker("Look back", selection: pacingLookbackBinding) {
                            ForEach(PacingLookback.allCases, id: \.self) { span in
                                Text(span.label).tag(span)
                            }
                        }
                    }
                    settingsToggleRow(
                        "End-of-Day Projection",
                        isOn: showProjectionsBinding,
                        topic: .endOfDayProjection
                    )
                    settingsToggleRow(
                        "Goal Streak",
                        isOn: showStreaksBinding,
                        topic: .goalStreak
                    )
                } header: {
                    Text("Pacing & Projections")
                } footer: {
                    // Projection and Streak explain themselves on their own ⓘ;
                    // what's left is how pacing itself is calculated, which no
                    // single row owns.
                    Text(pacingFooter)
                }

                // Notifications — Weekly Recap is the only push the app sends, so
                // it gets its own native section.
                Section {
                    settingsToggleRow(
                        "Weekly Recap",
                        isOn: weeklyRecapBinding,
                        topic: .weeklyRecap
                    )
                } header: {
                    Text("Notifications")
                }

                Section("Appearance") {
                    Picker("Theme", selection: appearanceBinding) {
                        ForEach(AppAppearance.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Body Profile used to sit in an unlabelled section under
                // Appearance, which read as a leftover rather than a feature.
                // It gets a header like every other group, and the same ⓘ, so
                // "what is this and why would I open it" is answerable without
                // opening it.
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            NavigationLink {
                                BodyProfileView()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Body Profile")
                                    Text("BMI, height, and weight")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            SettingsInfoDot(
                                topic: .bodyProfile,
                                isOpen: expandedInfoTopic == .bodyProfile
                            ) {
                                withAnimation(.snappy(duration: 0.22)) {
                                    expandedInfoTopic =
                                        expandedInfoTopic == .bodyProfile ? nil : .bodyProfile
                                }
                            }
                        }
                        if expandedInfoTopic == .bodyProfile {
                            SettingsInfoCallout(topic: .bodyProfile)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                } header: {
                    Text("Body")
                }

                Section {
                    Button {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            ReviewPromptCoordinator.shared.requestEnjoymentPrompt()
                        }
                    } label: {
                        Label("Rate or Send Feedback", systemImage: "star.bubble")
                    }

                    Link(destination: VitalsLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    Link(destination: VitalsLinks.standardEULA) {
                        Label("Terms of Use", systemImage: "doc.text")
                    }

                    Link(destination: VitalsLinks.support) {
                        Label("Support", systemImage: "questionmark.circle")
                    }

                    Link(destination: VitalsLinks.supportEmail) {
                        Label("Contact Support", systemImage: "envelope")
                    }
                } header: {
                    Text("Help")
                } footer: {
                    Text("Total Calories reads Apple Health data in read-only mode and keeps your health data on your device.")
                }

                Section {
                    CoachPromoCard(compact: true)
                        .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Need a Coach")
                } footer: {
                    Text("External links open Elsa's E3 Fitness site in Safari.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .background(InteractivePopGestureEnabler())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyGoalDrafts()
                        dismiss()
                    }
                    .bold()
                    .disabled(!calValid || !stepValid || !macroGoalsValid)
                }
                // The number pad has no return key, so give it an explicit way out.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedGoalField = nil }
                }
            }
            .onDisappear {
                applyGoalDrafts()
            }
            .preferredColorScheme(goals.appearance.colorScheme)
            .sheet(item: $trialPitch, onDismiss: {
                if store.isPro {
                    // Bought it: switch on the row they reached for. Net Deficit
                    // and Macros route through DashboardView, which closes
                    // Settings first so HealthKit's permission sheet can appear.
                    PlusFeatureActivation.apply(lastPitch?.featureToEnable, goals: goals)
                }
                if wantsPlanPicker {
                    wantsPlanPicker = false
                    showPlanPicker = true
                } else {
                    lastPitch = nil
                }
            }) { pitch in
                TrialOfferPitchSheet(
                    request: pitch,
                    onDismiss: { trialPitch = nil },
                    onNeedsPlanPicker: {
                        wantsPlanPicker = true
                        trialPitch = nil
                    }
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showPlanPicker, onDismiss: { lastPitch = nil }) {
                PaywallView(focus: lastPitch?.focus)
                    .environmentObject(store)
                    .task { store.trackPaywallImpression(id: "vitals_trial_sheet_settings") }
            }
            .onAppear {
                appliedGoalDrafts = false
                calEnabled = goals.calorieGoal != nil
                calText = goals.calorieGoal.map { String(Int($0)) } ?? "2500"
                stepEnabled = goals.stepGoal != nil
                stepText = goals.stepGoal.map { String($0) } ?? "10000"
                macroGoalText = Dictionary(
                    uniqueKeysWithValues: MacroKind.allCases.map { ($0, String(goals.storedMacroGoal(for: $0))) }
                )
                Task { await store.updateCustomerProductStatus() }
            }
        }
    }

    /// Rate App and Get Help, on one line, in the same place for subscribers and
    /// free users. They used to ride the section *header*, which put them above
    /// the card they belong to and left the free state without an equivalent.
    /// Living inside the status row means the same two actions sit under the
    /// same block of copy whichever state you're in.
    @ViewBuilder
    private var vitalsPlusActionRow: some View {
        HStack(spacing: 0) {
            Button("Rate App") {
                ReviewPromptTracker.markOpenedWriteReview()
                UIApplication.shared.open(AppStoreReviewLinks.writeReviewURL)
            }
            .buttonStyle(.borderless)
            Text("·")
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
            Button("Get Help") {
                openSupportMail(.getHelp)
            }
            .buttonStyle(.borderless)
            Text("·")
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
            Button("Feature Request") {
                openSupportMail(.featureRequest)
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 0)
        }
        .font(.system(.footnote, design: .rounded, weight: .semibold))
    }

    private func supportSnapshot() -> SupportMail.Snapshot {
        let info = Bundle.main.infoDictionary
        return SupportMail.Snapshot(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "",
            build: info?["CFBundleVersion"] as? String ?? "",
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: SupportMail.deviceModelIdentifier(),
            localeIdentifier: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            isPro: store.isPro,
            appUserID: store.customerInfo?.originalAppUserId,
            healthAuthorized: HealthKitService.shared.isAuthorized
        )
    }

    private func openSupportMail(_ kind: SupportMail.Kind) {
        guard let url = SupportMail.url(kind: kind, snapshot: supportSnapshot()) else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private var vitalsPlusSection: some View {
        Section {
            if store.isPro {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.caloriesPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vitals+ Active")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Thanks for supporting the app.")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Divider()
                    vitalsPlusActionRow
                }
            } else {
                // Same shape as the subscriber card: pitch on top, the same two
                // actions under the same divider. Only the pitch is tappable —
                // wrapping the whole stack in the upgrade Button would make
                // Rate and Get Help open the paywall.
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        requestTrialOffer(.settingsUpgradeRow)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Theme.caloriesGradient)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unlock Vitals+")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Macros, Net Deficit, TDEE & BMR, PDF reports.")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                    vitalsPlusActionRow
                }
            }
        } header: {
            Text("Vitals+")
                .textCase(nil)
                .font(.footnote.weight(.semibold))
        }
    }
}

private enum CoachBrand {
    static let nearBlack = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let coconutCream = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let dustyRose = Color(red: 0.71, green: 0.52, blue: 0.52)
    static let aquamarine = Color(red: 0.50, green: 0.78, blue: 0.77)
}

struct CoachPromoCard: View {
    var compact = false

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [CoachBrand.nearBlack, CoachBrand.nearBlack.opacity(0.88)]
                : [CoachBrand.coconutCream, .white],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var titleColor: Color {
        colorScheme == .dark ? CoachBrand.coconutCream : CoachBrand.nearBlack
    }

    private var secondaryColor: Color {
        colorScheme == .dark ? CoachBrand.coconutCream.opacity(0.72) : CoachBrand.nearBlack.opacity(0.68)
    }

    private var borderColor: Color {
        colorScheme == .dark ? CoachBrand.aquamarine.opacity(0.24) : CoachBrand.dustyRose.opacity(0.18)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 18) {
            HStack(alignment: .center, spacing: 14) {
                Image("ElsaCoach")
                    .resizable()
                    .scaledToFill()
                    .frame(width: compact ? 62 : 88, height: compact ? 78 : 108)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Image("E3Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: compact ? 20 : 24)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            colorScheme == .dark ? CoachBrand.coconutCream : .white,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .accessibilityHidden(true)

                    Text("Need a coach?")
                        .font(.system(compact ? .headline : .title3, design: .rounded, weight: .bold))
                        .foregroundStyle(titleColor)

                    Text("Virtual personal training and nutrition coaching with Elsa.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(secondaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !compact {
                Text("Build strength, confidence, and habits that last, with sessions scheduled directly with your coach.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    CoachTag(title: "Virtual sessions", systemImage: "video.fill", tint: CoachBrand.aquamarine)
                    CoachTag(title: "Custom plans", systemImage: "checklist", tint: CoachBrand.dustyRose)
                    CoachTag(title: "Nutrition support", systemImage: "leaf.fill", tint: CoachBrand.aquamarine)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        CoachTag(title: "Virtual sessions", systemImage: "video.fill", tint: CoachBrand.aquamarine)
                        CoachTag(title: "Custom plans", systemImage: "checklist", tint: CoachBrand.dustyRose)
                    }
                    CoachTag(title: "Nutrition support", systemImage: "leaf.fill", tint: CoachBrand.aquamarine)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    CoachLinkButton(
                        title: compact ? "Contact Elsa" : "Work with Elsa",
                        systemImage: "arrow.up.right",
                        destination: VitalsLinks.coachContact,
                        prominent: true
                    )
                    CoachLinkButton(
                        title: "View services",
                        systemImage: "list.bullet.clipboard",
                        destination: VitalsLinks.coachServices,
                        prominent: false
                    )
                }

                VStack(spacing: 10) {
                    CoachLinkButton(
                        title: compact ? "Contact Elsa" : "Work with Elsa",
                        systemImage: "arrow.up.right",
                        destination: VitalsLinks.coachContact,
                        prominent: true
                    )
                    CoachLinkButton(
                        title: "View services",
                        systemImage: "list.bullet.clipboard",
                        destination: VitalsLinks.coachServices,
                        prominent: false
                    )
                }
            }
        }
        .padding(compact ? 16 : 20)
        .background(backgroundGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .shadow(
            color: colorScheme == .dark ? .clear : CoachBrand.nearBlack.opacity(0.06),
            radius: 18,
            x: 0,
            y: 10
        )
        .accessibilityElement(children: .contain)
    }
}

private struct CoachTag: View {
    let title: String
    let systemImage: String
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(.caption, design: .rounded, weight: .bold))
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .medium))
        }
        .foregroundStyle(colorScheme == .dark ? CoachBrand.coconutCream : CoachBrand.nearBlack)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            tint.opacity(colorScheme == .dark ? 0.18 : 0.12),
            in: Capsule()
        )
    }
}

private struct CoachLinkButton: View {
    let title: String
    let systemImage: String
    let destination: URL
    let prominent: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: systemImage)
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
            }
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        if prominent {
            return CoachBrand.dustyRose
        }
        return colorScheme == .dark ? CoachBrand.nearBlack.opacity(0.24) : .white.opacity(0.7)
    }

    private var foreground: Color {
        if prominent {
            return .white
        }
        return colorScheme == .dark ? CoachBrand.coconutCream : CoachBrand.nearBlack
    }

    private var border: Color {
        colorScheme == .dark ? CoachBrand.aquamarine.opacity(0.22) : CoachBrand.nearBlack.opacity(0.08)
    }
}
