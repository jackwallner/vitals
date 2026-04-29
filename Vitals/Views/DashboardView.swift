import SwiftUI
import HealthKit

private enum VitalsLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let support = URL(string: "https://jackwallner.github.io/vitals/support.html")!
    static let supportEmail = URL(string: "mailto:jackwallner@gmail.com")!
    static let coachServices = URL(string: "https://www.e3fit.me/#services")!
    static let coachContact = URL(string: "https://www.e3fit.me/#contact")!
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
    case cachedData
    case loadError

    var iconName: String {
        switch self {
        case .accessNeeded: "heart.text.square.fill"
        case .accessBlocked: "lock.shield"
        case .noData: "heart.text.clipboard"
        case .cachedData: "clock.arrow.circlepath"
        case .loadError: "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch self {
        case .accessNeeded: "Health access needed"
        case .accessBlocked: "Health access is off"
        case .noData: "No Health data yet"
        case .cachedData: "Showing last saved data"
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
        case .cachedData:
            "Showing the last good values because the latest Health read looked incomplete."
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
        case .cachedData:
            nil
        }
    }
}

struct DashboardView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0
    @State private var pacingCalories: Double? = nil
    @State private var pacingSteps: Int? = nil
    @State private var isLoading = true
    @State private var animateRing = false
    @State private var animateContent = false
    @State private var showSettings = false
    @State private var showBreakdown = false
    @State private var showOnboarding = false
    @State private var pacingCaloriesInsufficient = false
    @State private var pacingStepsInsufficient = false
    @State private var isRefreshing = false
    @State private var healthNotice: HealthNotice? = nil
    @State private var lastRefreshDate: Date? = nil
    @State private var foodCalories: Double = 0
    /// True after we’ve successfully read dietary energy at least once this session (while net is on).
    @State private var dietaryEnergyReady = false
    /// True when the last dietary fetch failed (don’t treat as “0 kcal logged”).
    @State private var dietaryEnergyFetchFailed = false
    /// True when HealthKit reports read access denied for dietary energy (queries return 0 without error).
    @State private var dietaryEnergyAccessDenied = false

    private var totalCalories: Double { activeCalories + restingCalories }

    /// Positive = burned more than logged food (deficit); negative = surplus.
    private var netDeficit: Double { totalCalories - foodCalories }

    /// Whether we can show a numeric net (not loading, not failed, not denied).
    private var netDeficitNumericReady: Bool {
        goals.showNetCalories && dietaryEnergyReady && !dietaryEnergyFetchFailed && !dietaryEnergyAccessDenied
    }

    private var visibleMetricCount: Int {
        (goals.showCalories ? 1 : 0) + (goals.showSteps ? 1 : 0) + (goals.showNetCalories ? 1 : 0)
    }

    /// Only the net-deficit row is visible (no calorie ring / steps).
    private var onlyNetMetric: Bool {
        goals.showNetCalories && !goals.showCalories && !goals.showSteps
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

    /// Exactly one of calories / steps / net is enabled.
    private var isSingleMetric: Bool {
        visibleMetricCount == 1
    }

    var body: some View {
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
        .onChange(of: healthKit.isAuthorized) { _, authorized in
            if authorized { Task { await refresh() } }
        }
        .onChange(of: goals.showNetCalories) { _, enabled in
            guard enabled else { return }
            Task {
                let statusBefore = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true)
                print("[NetDeficit] Toggled ON — auth status before request: \(String(describing: statusBefore?.rawValue)) (0=unknown, 1=shouldRequest, 2=unnecessary)")

                // Always request dietary auth separately — requesting only the new
                // type avoids HealthKit silently suppressing the sheet when it's
                // bundled with already-authorized types.
                do {
                    try await healthKit.requestDietaryAuthorization()
                    let statusAfter = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true)
                    print("[NetDeficit] requestDietaryAuthorization completed — auth status after: \(String(describing: statusAfter?.rawValue))")
                } catch {
                    dietaryEnergyFetchFailed = true
                    print("[NetDeficit] requestDietaryAuthorization failed: \(error)")
                }

                await refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refresh() }
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
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            Task { await refresh() }
        }) {
            OnboardingSheet(goals: goals)
                .interactiveDismissDisabled()
        }
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
            if isSingleMetric && goals.showCalories && !goals.showSteps && !goals.showNetCalories {
                return min(availableHeight * 0.12, 100)
            }
            if isMinimalMode { return min(availableHeight * 0.10, 88) }
            return min(availableHeight * 0.06, 52)
        }()
        let stepsNumberSize: CGFloat = {
            if isSingleMetric && goals.showSteps && !goals.showCalories && !goals.showNetCalories {
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
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView()
                            .tint(Theme.textTertiary)
                        Text("Refreshing...")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    } else if healthNotice == .accessNeeded || healthNotice == .accessBlocked {
                        Text("Waiting for Health access")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    } else if let date = lastRefreshDate {
                        Text("Updated \(date, format: .dateTime.hour().minute())")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
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
                // Ring (or bare number if no goal) — tapping toggles the Active/Resting
                // breakdown. Intentionally a hidden affordance: discoverable via
                // VoiceOver hint / a11y action, but no always-on chip cluttering the UI.
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
                .onTapGesture {
                    guard !isMinimalMode else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBreakdown.toggle()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Calorie progress")
                .accessibilityValue(calorieProgress != nil
                    ? "\(Int(totalCalories)) of \(Int(goals.calorieGoal ?? 0)) calories"
                    : "\(Int(totalCalories)) calories")
                .accessibilityHint(isMinimalMode ? "" : "Double tap to show active and resting breakdown.")
                .accessibilityAction(named: showBreakdown ? "Hide breakdown" : "Show breakdown") {
                    guard !isMinimalMode else { return }
                    showBreakdown.toggle()
                }

                // Active/Resting pills revealed when the ring is tapped.
                if !isMinimalMode && showBreakdown {
                    HStack(spacing: 16) {
                        MetricPill(label: "active", value: activeCalories, color: Theme.activePrimary)
                        MetricPill(label: "resting", value: restingCalories, color: Theme.restingPrimary)
                    }
                    .padding(.top, 16)
                    .opacity(animateContent ? 1 : 0)
                    .transition(.opacity)
                }

                // Calorie pacing
                if goals.showPacing {
                    if let pacingCal = pacingCalories {
                        PacingPill(
                            current: totalCalories,
                            typical: pacingCal,
                            label: "cal",
                            color: Theme.caloriesPrimary
                        )
                        .padding(.top, 16)
                        .opacity(animateContent ? 1 : 0)
                    } else if pacingCaloriesInsufficient {
                        Text("Building pace data...")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 16)
                            .opacity(animateContent ? 1 : 0)
                    }
                }
            }

            if goals.showCalories && goals.showSteps {
                Spacer(minLength: 16)
            }

            // Steps section
            if goals.showSteps {
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
                        Text("steps")
                            .font(.system(isSingleMetric ? .title3 : .subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(1.5)

                        if goals.showPacing {
                            if let pacingStep = pacingSteps {
                                PacingPill(
                                    current: Double(steps),
                                    typical: Double(pacingStep),
                                    label: "steps",
                                    color: Theme.stepsPrimary
                                )
                                .padding(.top, 8)
                            } else if pacingStepsInsufficient {
                                Text("Building pace data...")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Steps")
                    .accessibilityValue("\(steps) steps")
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
                            if let progress = stepProgress {
                                Text("\(Int(progress * 100))%")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(Theme.stepsPrimary)
                            }
                        }

                        if let progress = stepProgress {
                            StepProgressBar(
                                progress: animateRing ? progress : 0,
                                gradient: Theme.stepsGradient,
                                glowColor: Theme.stepsGlow
                            )
                        }

                        if goals.showPacing {
                            if let pacingStep = pacingSteps {
                                PacingPill(
                                    current: Double(steps),
                                    typical: Double(pacingStep),
                                    label: "steps",
                                    color: Theme.stepsPrimary
                                )
                            } else if pacingStepsInsufficient {
                                Text("Building pace data...")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Steps")
                    .accessibilityValue("\(steps) steps")
                    .padding(Theme.cardPadding)
                    .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .padding(.horizontal, 24)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                }
            }

            if goals.showNetCalories && (goals.showCalories || goals.showSteps) {
                Spacer(minLength: 16)
            }

            if goals.showNetCalories {
                netDeficitSection(netNumberSize: netNumberSize)
            }

            // Nothing enabled — gentle prompt
            if !goals.showCalories && !goals.showSteps && !goals.showNetCalories {
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
                    } else {
                        Text("—")
                            .font(Theme.bigNumber(netNumberSize))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    netDeficitBreakdownRow(centered: true)
                    Text("net calories")
                        .font(.system(isSingleMetric ? .title3 : .subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.5)
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
                        Text("net")
                            .font(.system(.callout, design: .rounded, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer(minLength: 8)
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
            Text("Couldn't read food calories. Check Health permissions.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(align)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, centered ? 12 : 0)
        } else if dietaryEnergyAccessDenied {
            Text("Health isn't sharing food calories. Open Health → Sharing → Total Calories and enable Dietary Energy.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(align)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, centered ? 12 : 0)
        } else if !dietaryEnergyReady {
            Text("Loading food calories…")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(align)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, centered ? 12 : 0)
        } else if foodCalories <= 0 {
            Text("No food logged today — sync a food-tracking app to Apple Health.")
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
        if dietaryEnergyAccessDenied {
            return "Food sharing denied in Health"
        }
        if !dietaryEnergyReady {
            return "Waiting for Health permission or loading food data"
        }
        let n = Int(deficit.rounded())
        return "\(n) calories, \(deficit < 0 ? "surplus" : "deficit"), burned minus food from Health"
    }

    private func calorieLabel(numberSize: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(totalCalories, format: .number.precision(.fractionLength(0)))
                .font(Theme.bigNumber(numberSize))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            if let goal = goals.calorieGoal {
                Text("/ \(goal, format: .number.precision(.fractionLength(0))) cal")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("calories")
                    .font(.system(isSingleMetric ? .title3 : .subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.5)
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
                    print("Failed to request HealthKit authorization: \(error)")
                    healthNotice = .loadError
                }
            }
        case .accessBlocked:
            openAppSettings()
        case .noData, .loadError:
            openHealthApp()
        case .cachedData:
            break
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

        var shouldBuzz = false

        if let calGoal = goals.calorieGoal,
           calGoal > 0,
           newTotal >= calGoal,
           GoalCelebration.shouldCelebrateCalories(for: todayKey) {
            GoalCelebration.markCaloriesCelebrated(for: todayKey)
            shouldBuzz = true
        }

        if let stepGoal = goals.stepGoal,
           stepGoal > 0,
           steps >= stepGoal,
           GoalCelebration.shouldCelebrateSteps(for: todayKey) {
            GoalCelebration.markStepsCelebrated(for: todayKey)
            shouldBuzz = true
        }

        if shouldBuzz {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
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
        }
    }

    private func clearPacing() {
        pacingCalories = nil
        pacingSteps = nil
        pacingCaloriesInsufficient = false
        pacingStepsInsufficient = false
    }

    private func loadDietaryEnergy() async {
        guard goals.showNetCalories else {
            foodCalories = 0
            dietaryEnergyReady = false
            dietaryEnergyFetchFailed = false
            dietaryEnergyAccessDenied = false
            return
        }
        do {
            let food = try await healthKit.fetchDietaryEnergyToday()
            foodCalories = food
            // HealthKit does not expose read-auth directly: a denied read returns
            // 0 kcal without throwing, indistinguishable from "authorized, but no
            // food logged today". When today is 0 kcal we probe for ANY historical
            // sample — if none exist and the system has already shown the auth
            // sheet, we infer denial and surface the recovery footer.
            if food > 0 {
                dietaryEnergyAccessDenied = false
            } else {
                let status = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true)
                if status == .unnecessary {
                    let hasAny = (try? await healthKit.hasAnyDietarySample()) ?? true
                    dietaryEnergyAccessDenied = !hasAny
                } else {
                    dietaryEnergyAccessDenied = false
                }
            }
            // Set ready last so UI reflects the final state (post-denial check)
            // and doesn't briefly show a stale numeric deficit.
            dietaryEnergyFetchFailed = false
            dietaryEnergyReady = !dietaryEnergyAccessDenied
            try? healthKit.updateCachedFoodCalories(food)
        } catch {
            dietaryEnergyFetchFailed = true
            dietaryEnergyAccessDenied = false
            print("Failed to fetch dietary energy: \(error)")
        }
    }

    private func loadPacing(stats: (active: Double, resting: Double, steps: Int)) async {
        guard goals.showPacing, !isAllZero(stats) else {
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
        let v = pacing.dashboardValues(minSamples: minSamples, showCalories: goals.showCalories, showSteps: goals.showSteps)
        pacingCalories = v.calories
        pacingCaloriesInsufficient = v.caloriesBuilding
        pacingSteps = v.steps
        pacingStepsInsufficient = v.stepsBuilding
    }

    private func isAllZero(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        HealthKitService.isAllZero(stats)
    }

    /// Classify the dashboard's recovery notice based on the most recent fetch result and
    /// HealthKit authorization request status. Runs only when the fetch returned all-zero
    /// and no same-day cache is present — otherwise the happy path / `.cachedData` paths
    /// already handled it upstream.
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
        let cachedHasData = cachedStats.map { healthKit.hasRecordedData($0) } ?? false

        if isLoading, let cachedStats, cachedHasData {
            applyStats(cachedStats)
            healthNotice = .cachedData
            showLoadedStateIfNeeded()
        }

        defer { isRefreshing = false }

        // Skip the HK auth-status IPC roundtrip when already authorized —
        // status doesn't change between refreshes, and the only branch that
        // does anything new is `.shouldRequest`, which can't fire post-auth.
        if !healthKit.isAuthorized {
            await healthKit.synchronizeAuthorizationStateForFetching()
        }
        do {
            let stats = try await healthKit.fetchTodayStatsWithRetry()
            if isAllZero(stats), let cachedStats, cachedHasData {
                applyStats(cachedStats)
                healthNotice = .cachedData
            } else {
                applyStats(stats)
                if isAllZero(stats) {
                    // All-zero fetch with no cached backup: ask HealthKit whether the user
                    // was already prompted so we can route them to Settings (blocked) instead
                    // of a generic "no data yet" banner they can't recover from.
                    let status = await healthKit.authorizationRequestStatus()
                    healthNotice = classifyEmptyFetchNotice(requestStatus: status)
                } else {
                    healthNotice = nil
                }
            }
            // Only advance the "Updated HH:mm" header after a successful read
            // so users aren't misled into thinking cached-after-failure data is fresh.
            lastRefreshDate = .now

            // Show UI immediately, don't wait for pacing/cache
            showLoadedStateIfNeeded()

            // Fire-and-forget: stats are already applied; the SwiftData write
            // and widget reload don't need to gate dietary/pacing fetches.
            Task {
                do {
                    try await healthKit.refreshCache(stats: stats)
                } catch {
                    print("Failed to refresh today cache: \(error)")
                }
            }

            // Background history sync for the watch shared cache
            Task(priority: .utility) {
                do {
                    let history = try await healthKit.fetchHistory(days: 90)
                    try healthKit.saveHistoryToCache(history: history)
                } catch {
                    print("Background history cache sync failed: \(error)")
                }
            }

            // Dietary and pacing are independent HK reads — run them concurrently
            // so the slower of the two dominates instead of summing.
            async let dietary: Void = loadDietaryEnergy()
            async let pacing: Void = loadPacing(stats: stats)
            _ = await (dietary, pacing)
        } catch {
            let ns = error as NSError
            print("Failed to fetch today stats: \(error) domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            if let cachedStats = try? healthKit.fetchCachedTodayStats() {
                applyStats(cachedStats)
                healthNotice = .cachedData
            } else {
                applyStats((active: 0, resting: 0, steps: 0))
                healthNotice = .loadError
            }
            clearPacing()
            foodCalories = 0
            dietaryEnergyReady = false
            dietaryEnergyFetchFailed = false
            dietaryEnergyAccessDenied = false
            showLoadedStateIfNeeded()
        }
    }
}

// MARK: - Pacing Pill

private struct PacingPill: View {
    let current: Double
    let typical: Double
    let label: String
    let color: Color

    private var diff: Double { current - typical }
    private var isAhead: Bool { diff >= 0 }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isAhead ? "arrow.up.right" : "arrow.down.right")
                .font(.system(.caption2, design: .rounded, weight: .bold))
            Text("\(abs(Int(diff)).formatted(.number)) \(label) \(isAhead ? "ahead" : "behind") usual pace")
                .font(.system(.caption2, design: .rounded))
        }
        .foregroundStyle(isAhead ? .green : Color(red: 1.0, green: 0.42, blue: 0.42))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (isAhead ? Color.green : Color(red: 1.0, green: 0.42, blue: 0.42)).opacity(0.1),
            in: Capsule()
        )
        .accessibilityLabel("\(abs(Int(diff))) \(label) \(isAhead ? "ahead of" : "behind") usual pace")
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
    @ObservedObject var goals: GoalSettings
    @Environment(\.dismiss) private var dismiss

    @State private var wantCalGoal = true
    @State private var calText = "2500"
    @State private var wantStepGoal = true
    @State private var stepText = "10000"

    private var calValid: Bool {
        !wantCalGoal || (Double(calText) ?? 0) > 0
    }

    private var stepValid: Bool {
        !wantStepGoal || (Int(stepText) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.caloriesPrimary)
                    Text("Welcome to Total Calories")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Set up your daily goals, or skip to use as a simple counter.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
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
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    if wantCalGoal, let cal = Double(calText), cal > 0 {
                        goals.calorieGoal = min(max(cal, 500), 50000)
                    } else {
                        goals.calorieGoal = nil
                    }
                    if wantStepGoal, let step = Int(stepText), step > 0 {
                        goals.stepGoal = min(max(step, 100), 500000)
                    } else {
                        goals.stepGoal = nil
                    }
                    goals.hasCompletedSetup = true
                    // Request HealthKit access now so the system sheet appears
                    // while the user is still in the onboarding flow, instead of
                    // surprising them after the dashboard has already rendered.
                    Task {
                        do {
                            try await HealthKitService.shared.requestAuthorization()
                        } catch {
                            print("Onboarding HealthKit auth failed: \(error)")
                        }
                        dismiss()
                    }
                } label: {
                    Text("Get Started")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.caloriesPrimary, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .disabled(!calValid || !stepValid)
                .opacity(calValid && stepValid ? 1 : 0.5)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.top, 48)
        }
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
                    Text("Enter a valid number.")
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
    @Environment(\.dismiss) private var dismiss

    @State private var calEnabled = true
    @State private var calText = ""
    @State private var stepEnabled = true
    @State private var stepText = ""

    private var calValid: Bool {
        !calEnabled || (Double(calText) ?? 0) > 0
    }

    private var stepValid: Bool {
        !stepEnabled || (Int(stepText) ?? 0) > 0
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
            get: { goals.showNetCalories },
            set: { goals.showNetCalories = $0 }
        )
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
        if calEnabled {
            if let cal = Double(calText), cal > 0 {
                goals.calorieGoal = min(max(cal, 500), 50000)
            }
        } else {
            goals.calorieGoal = nil
        }

        if stepEnabled {
            if let step = Int(stepText), step > 0 {
                goals.stepGoal = min(max(step, 100), 500000)
            }
        } else {
            goals.stepGoal = nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show Calories", isOn: showCaloriesBinding)
                    Toggle("Show Steps", isOn: showStepsBinding)
                    Toggle("Show Net Deficit", isOn: showNetCaloriesBinding)
                        .onChange(of: goals.showNetCalories) { _, enabled in
                            guard enabled else { return }
                            Task {
                                try? await HealthKitService.shared.requestDietaryAuthorization()
                            }
                        }
                } header: {
                    Text("Dashboard")
                } footer: {
                    Text("Net deficit is total calories burned (active + resting) minus food calories from Apple Health. Connect a food app like MyFitnessPal to Health to populate dietary energy.")
                }

                Section {
                    Toggle("Calorie Goal", isOn: $calEnabled)
                    if calEnabled {
                        TextField("Daily calories", text: $calText)
                            .keyboardType(.numberPad)
                        if !calValid {
                            Text("Enter a valid number.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Toggle("Step Goal", isOn: $stepEnabled)
                    if stepEnabled {
                        TextField("Daily steps", text: $stepText)
                            .keyboardType(.numberPad)
                        if !stepValid {
                            Text("Enter a valid number.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Goals")
                } footer: {
                    Text("Goal changes are saved when you tap Done. Everything else applies instantly.")
                }

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
                } header: {
                    Text("Pacing")
                } footer: {
                    Text(pacingFooter)
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
                    Link(destination: VitalsLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
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
            }
            .onDisappear {
                applyGoalDrafts()
            }
            .onAppear {
                calEnabled = goals.calorieGoal != nil
                calText = goals.calorieGoal.map { String(Int($0)) } ?? "2500"
                stepEnabled = goals.stepGoal != nil
                stepText = goals.stepGoal.map { String($0) } ?? "10000"
            }
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
