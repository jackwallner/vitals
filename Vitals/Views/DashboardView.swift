import SwiftUI
import HealthKit
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
            "Open Settings → Privacy → Health → Total Calories and turn on each category to load your data."
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
            "Open Settings"
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
    /// Transient celebration banner shown once per goal per day (paired with the haptic).
    @State private var celebrationMessage: String? = nil

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

    /// Active/resting breakdown is Vitals+ only and gated by the user's setting.
    /// Hidden in minimal mode (no goals + no pacing) to keep that layout uncluttered.
    private var showActiveResting: Bool {
        store.isPro && goals.showActiveRestingBreakdown && !isMinimalMode
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
                Theme.background.ignoresSafeArea()

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
            .navigationDestination(for: HistoryMetric.self) { metric in
                HistoryView(focusMetric: metric)
                    .environmentObject(store)
            }
        .onChange(of: goals.showNetCalories) { _, enabled in
            guard enabled, store.isPro else { return }
            Task {
                let statusBefore = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true)
                dashboardLogger.debug("NetDeficit toggled on — auth status before: \(String(describing: statusBefore?.rawValue), privacy: .public)")

                // Always request dietary auth separately — requesting only the new
                // type avoids HealthKit silently suppressing the sheet when it's
                // bundled with already-authorized types.
                do {
                    try await healthKit.requestDietaryAuthorization()
                    let statusAfter = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true)
                    dashboardLogger.debug("NetDeficit dietary auth requested — auth status after: \(String(describing: statusAfter?.rawValue), privacy: .public)")
                } catch {
                    dietaryEnergyFetchFailed = true
                    dashboardLogger.error("NetDeficit dietary auth request failed: \(String(describing: error), privacy: .public)")
                }

                await refresh()
            }
        }
        .onChange(of: store.isPro) { oldValue, isPro in
            if oldValue && !isPro && goals.showNetCalories {
                goals.showNetCalories = false
            } else if isPro && goals.showNetCalories {
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
        .onReceive(NotificationCenter.default.publisher(for: .vitalsOpenSettings)) { _ in
            showSettings = true
        }
        .task {
            if ScreenshotConfig.wantsOnboarding {
                showOnboarding = true
            } else if !goals.hasCompletedSetup {
                showOnboarding = true
            } else {
                await refresh()
                if ScreenshotConfig.wantsSettingsSheet {
                    showSettings = true
                }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            Task { await refresh() }
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
                .interactiveDismissDisabled()
        }
        }
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
                    .padding(.horizontal, 24)
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

            // Nothing enabled — gentle prompt
            if !goals.showCalories && !goals.showSteps && !isNetDeficitEnabled {
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
                Button("Retry food calories") {
                    Task { await loadDietaryEnergy() }
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
            openAppSettings()
        case .noData, .loadError:
            openHealthApp()
        }
    }

    private func applyStats(_ stats: (active: Double, resting: Double, steps: Int)) {
        activeCalories = stats.active
        restingCalories = stats.resting
        steps = stats.steps

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

    private func loadDietaryEnergy() async {
        guard isNetDeficitEnabled else {
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
            try? healthKit.updateCachedFoodCalories(food)
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
        async let pacingEarly: Void = loadPacing(stats: nil)

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
                // Neither live HK nor cache had any data — surface a recoverable
                // notice so the user can route to Health/Settings.
                let status = await healthKit.authorizationRequestStatus()
                healthNotice = classifyEmptyFetchNotice(requestStatus: status)
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

            // Background history sync for the watch shared cache
            Task(priority: .utility) {
                do {
                    let history = try await healthKit.fetchHistory(days: 90)
                    try healthKit.saveHistoryToCache(history: history)
                    await checkGoalStreakMilestone(history: history)
                } catch {
                    dashboardLogger.error("Background history cache sync failed: \(String(describing: error), privacy: .public)")
                }
            }

            // Wait for the in-flight dietary + pacing reads we kicked off above.
            await dietaryEarly
            await pacingEarly
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
            await pacingEarly
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
        // (hit either goal) — the broadest "on a roll" signal, best for conversion.
        let streak = MilestoneCalculator.currentGoalStreak(
            records: days,
            calorieGoal: goals.calorieGoal,
            stepGoal: goals.stepGoal
        )
        // Milestone celebration sheets are a non-Pro upsell only.
        guard !store.isPro else { return }
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

// MARK: - Onboarding Sheet (first launch only)

private struct OnboardingSheet: View {
    private enum Step {
        case welcome
        case goals
    }

    @ObservedObject var goals: GoalSettings
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .welcome
    @State private var wantCalGoal = true
    @State private var calText = "2500"
    @State private var wantStepGoal = true
    @State private var stepText = "10000"
    @State private var hasRequestedHealthAccess = false

    private var calValid: Bool {
        !wantCalGoal || (Double(calText).map { (500...50000).contains($0) } ?? false)
    }

    private var stepValid: Bool {
        !wantStepGoal || (Int(stepText).map { (100...500000).contains($0) } ?? false)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        switch step {
                        case .welcome: welcomePage
                        case .goals: goalsPage
                        }
                    }
                    .padding(.top, 48)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)
                }

                bottomBar
            }
        }
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
    private var bottomBar: some View {
        switch step {
        case .welcome: welcomeBottomBar
        case .goals: goalsBottomBar
        }
    }

    private var welcomeBottomBar: some View {
        VStack(spacing: 12) {
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

            Button {
                Task { await requestHealthAccessIfNeeded() }
                withAnimation(.easeInOut(duration: 0.25)) { step = .goals }
            } label: {
                primaryLabel("Continue")
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Theme.background)
    }

    private var goalsBottomBar: some View {
        VStack(spacing: 12) {
            Button {
                if wantCalGoal, let cal = Double(calText), (500...50000).contains(cal) {
                    goals.calorieGoal = cal
                } else {
                    goals.calorieGoal = nil
                }
                if wantStepGoal, let step = Int(stepText), (100...500000).contains(step) {
                    goals.stepGoal = step
                } else {
                    goals.stepGoal = nil
                }
                goals.hasCompletedSetup = true
                dismiss()
            } label: {
                primaryLabel("Get Started")
            }
            .disabled(!calValid || !stepValid)
            .opacity(calValid && stepValid ? 1 : 0.5)
            .padding(.horizontal, 24)
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Theme.background)
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.caloriesPrimary, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
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
    @State private var appliedGoalDrafts = false
    @FocusState private var focusedGoalField: GoalField?

    private enum GoalField { case calories, steps }

    private var calValid: Bool {
        !calEnabled || (Double(calText).map { (500...50000).contains($0) } ?? false)
    }

    private var stepValid: Bool {
        !stepEnabled || (Int(stepText).map { (100...500000).contains($0) } ?? false)
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
                    goals.showNetCalories = enabled
                } else if enabled {
                    goals.showNetCalories = false
                    requestTrialOffer(.netDeficitToggle)
                }
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

    /// Dismiss the settings sheet first so the MainTabView-owned trial sheet
    /// presents cleanly — stacking two sheets from sibling-ish hierarchies is
    /// flaky in SwiftUI and the second sometimes drops silently.
    private func requestTrialOffer(_ intent: TrialOfferCoordinator.Intent) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            TrialOfferCoordinator.shared.request(intent)
        }
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
    }

    var body: some View {
        NavigationStack {
            Form {
                vitalsPlusSection

                // Calories — the ring plus everything that shapes that number,
                // including its goal and the Vitals+ calorie extras, all in one
                // place instead of scattered across the sheet.
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
                    Toggle(isOn: showActiveRestingBinding) {
                        plusToggleLabel("Active + Resting Breakdown")
                    }
                    Toggle(isOn: showNetCaloriesBinding) {
                        plusToggleLabel("Net Deficit")
                    }
                    .onChange(of: goals.showNetCalories) { _, enabled in
                        guard enabled, store.isPro else { return }
                        Task {
                            try? await HealthKitService.shared.requestDietaryAuthorization()
                        }
                    }
                } header: {
                    Text("Calories")
                } footer: {
                    Text("Active + Resting and Net Deficit are Vitals+ extras, off until you turn them on. Net Deficit shows calories burned minus food energy from Apple Health — a positive number means a deficit. Connect a food app like MyFitnessPal to populate it. Goal changes save when you tap Done.")
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
                    Text("Goal changes save when you tap Done; other settings apply instantly.")
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
                    Toggle(isOn: showProjectionsBinding) {
                        plusToggleLabel("End-of-Day Projection")
                    }
                    Toggle(isOn: showStreaksBinding) {
                        plusToggleLabel("Goal Streak")
                    }
                } header: {
                    Text("Pacing & Projections")
                } footer: {
                    Text("\(pacingFooter)\n\nEnd-of-Day Projection and Goal Streak are Vitals+ extras, off by default. Projection shows where today's calories and steps will land from your own pace. Goal Streak counts consecutive days you've hit a goal.")
                }

                // Notifications — Weekly Recap is the only push the app sends, so
                // it gets its own native section.
                Section {
                    Toggle(isOn: weeklyRecapBinding) {
                        plusToggleLabel("Weekly Recap")
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Weekly Recap is a Vitals+ extra, off by default. It sends a Sunday-evening notification summarizing your week — turning it on asks permission to notify you.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: appearanceBinding) {
                        ForEach(AppAppearance.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyGoalDrafts()
                        dismiss()
                    }
                    .bold()
                    .disabled(!calValid || !stepValid)
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
            .onAppear {
                appliedGoalDrafts = false
                calEnabled = goals.calorieGoal != nil
                calText = goals.calorieGoal.map { String(Int($0)) } ?? "2500"
                stepEnabled = goals.stepGoal != nil
                stepText = goals.stepGoal.map { String($0) } ?? "10000"
                Task { await store.updateCustomerProductStatus() }
            }
        }
    }

    @ViewBuilder
    private var vitalsPlusSection: some View {
        Section {
            if store.isPro {
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
            } else {
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
                            Text("PDF reports, custom-range exports, deep trends.")
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
            }
        } header: {
            Text("Vitals+")
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
