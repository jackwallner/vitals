import SwiftUI

private enum VitalsLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let support = URL(string: "https://jackwallner.github.io/vitals/support.html")!
    static let supportEmail = URL(string: "mailto:jackwallner@gmail.com")!
    static let coachServices = URL(string: "https://www.e3fit.me/#services")!
    static let coachContact = URL(string: "https://www.e3fit.me/#contact")!
}

private enum HealthNotice: Equatable {
    case accessNeeded
    case noData
    case cachedData
    case loadError

    var iconName: String {
        switch self {
        case .accessNeeded: "heart.text.square.fill"
        case .noData: "heart.text.clipboard"
        case .cachedData: "clock.arrow.circlepath"
        case .loadError: "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch self {
        case .accessNeeded: "Health access needed"
        case .noData: "No Health data yet"
        case .cachedData: "Showing last saved data"
        case .loadError: "Couldn't refresh Health data"
        }
    }

    var message: String {
        switch self {
        case .accessNeeded:
            "Grant Apple Health access so Vitals can load your active calories, resting calories, and steps."
        case .noData:
            "If you just granted access, Apple Health may still be catching up. If this seems wrong, check Health access."
        case .cachedData:
            "Vitals kept the last good saved values on screen because the latest Health read looked incomplete."
        case .loadError:
            "Try reopening the app in a moment, or check Apple Health access."
        }
    }

    var buttonTitle: String? {
        switch self {
        case .accessNeeded:
            "Enable Health"
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
        VStack(spacing: 16) {
            ProgressRing(
                progress: 0.7,
                gradient: Theme.caloriesGradient,
                glowColor: .clear,
                lineWidth: 10,
                size: 60
            )
            .opacity(0.3)
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
        }
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
                HStack(spacing: 4) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.textTertiary)
                        Text("Refreshing...")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    } else if healthNotice == .accessNeeded {
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

            Spacer(minLength: 16)

            // Calories section
            if goals.showCalories {
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Calorie progress")
                    .accessibilityValue("\(Int(totalCalories)) of \(Int(goals.calorieGoal ?? 0)) calories")
                } else {
                    calorieLabel(numberSize: calNumberSize)
                }

                // Tap to show/hide breakdown
                if !isMinimalMode {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showBreakdown.toggle()
                        }
                    } label: {
                        if showBreakdown {
                            HStack(spacing: 16) {
                                MetricPill(label: "active", value: activeCalories, color: Theme.activePrimary)
                                MetricPill(label: "resting", value: restingCalories, color: Theme.restingPrimary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, showBreakdown ? 16 : 8)
                    .opacity(animateContent ? 1 : 0)
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
                        .padding(.top, 10)
                        .opacity(animateContent ? 1 : 0)
                    } else if pacingCaloriesInsufficient {
                        Text("Building pace data...")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 10)
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

            if let healthNotice {
                healthNoticeBanner(healthNotice)
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

    private func netDeficitStatusPill(deficit: Double) -> some View {
        let surplus = deficit < 0
        let label = surplus ? "Surplus" : "Deficit"
        let color = surplus ? Theme.netDeficitNegative : Theme.netDeficitPositive
        return Text(label)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func netDeficitBreakdownRow(centered: Bool) -> some View {
        if netDeficitNumericReady {
            let burned = Int(totalCalories.rounded())
            let eaten = Int(foodCalories.rounded())
            let result = Int(netDeficit.rounded())
            let align: HorizontalAlignment = centered ? .center : .leading

            VStack(alignment: align, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(burned)")
                        .foregroundStyle(Theme.caloriesPrimary)
                    Text("burned")
                        .foregroundStyle(Theme.textTertiary)
                    Text("−")
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(eaten)")
                        .foregroundStyle(Theme.netDeficitBrand)
                    Text("eaten")
                        .foregroundStyle(Theme.textTertiary)
                    Text("=")
                        .foregroundStyle(Theme.textTertiary)
                    Text(netDeficitDisplayText(Double(result)))
                        .foregroundStyle(netDeficitColor)
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
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
                    if netDeficitNumericReady {
                        netDeficitStatusPill(deficit: deficit)
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
                VStack(alignment: .leading, spacing: 10) {
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
                        if netDeficitNumericReady {
                            netDeficitStatusPill(deficit: deficit)
                        }
                    }
                    netDeficitBreakdownRow(centered: false)
                    netDeficitFootnote(centered: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("Couldn’t read food calories from Health. Check Total Calories → Health permissions.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(align)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, centered ? 12 : 0)
        } else if dietaryEnergyAccessDenied {
            Text("Health isn’t sharing food calories. Open the Health app → Sharing → Total Calories and allow Dietary Energy.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(align)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, centered ? 12 : 0)
        } else if !dietaryEnergyReady {
            Text("Waiting for Health permission to read food calories, or loading…")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(align)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, centered ? 12 : 0)
        } else if foodCalories <= 0 {
            Text("No food in Health yet — sync a food app to Apple Health.")
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

    private func handleHealthNoticeAction(_ notice: HealthNotice) {
        switch notice {
        case .accessNeeded:
            Task {
                do {
                    try await healthKit.requestAuthorization()
                } catch {
                    print("Failed to request HealthKit authorization: \(error)")
                    healthNotice = .loadError
                }
            }
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

    private func isAllZero(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        stats.active == 0 && stats.resting == 0 && stats.steps == 0
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

        defer {
            isRefreshing = false
            lastRefreshDate = .now
        }

        await healthKit.synchronizeAuthorizationStateForFetching()
        do {
            let stats = try await healthKit.fetchTodayStatsWithRetry()
            if isAllZero(stats), let cachedStats, cachedHasData {
                applyStats(cachedStats)
                healthNotice = .cachedData
            } else {
                applyStats(stats)
                healthNotice = isAllZero(stats) ? .noData : nil
            }

            // Show UI immediately, don't wait for pacing/cache
            showLoadedStateIfNeeded()

            // Load pacing and cache in background (reuse stats, don't re-fetch)
            do {
                try await healthKit.refreshCache(stats: stats)
            } catch {
                print("Failed to refresh today cache: \(error)")
            }

            if goals.showNetCalories {
                do {
                    foodCalories = try await healthKit.fetchDietaryEnergyToday()
                    // Apple provides no API to check read authorization — a successful
                    // fetch is the only reliable signal.  authorizationStatus(for:) only
                    // reports write/sharing status, which is always .notDetermined here.
                    dietaryEnergyReady = true
                    dietaryEnergyFetchFailed = false
                    dietaryEnergyAccessDenied = false
                } catch {
                    dietaryEnergyFetchFailed = true
                    dietaryEnergyAccessDenied = false
                    print("Failed to fetch dietary energy: \(error)")
                }
            } else {
                foodCalories = 0
                dietaryEnergyReady = false
                dietaryEnergyFetchFailed = false
                dietaryEnergyAccessDenied = false
            }

            if goals.showPacing && !isAllZero(stats) {
                if let pacing = try? await healthKit.fetchPacing(
                    comparison: goals.pacingComparison,
                    lookback: goals.pacingLookback
                ) {
                    let v = pacing.dashboardValues(showCalories: goals.showCalories, showSteps: goals.showSteps)
                    pacingCalories = v.calories
                    pacingCaloriesInsufficient = v.caloriesBuilding
                    pacingSteps = v.steps
                    pacingStepsInsufficient = v.stepsBuilding
                } else {
                    clearPacing()
                }
            } else {
                clearPacing()
            }
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
                    dismiss()
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

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @ObservedObject var goals: GoalSettings
    @Environment(\.dismiss) private var dismiss

    @State private var calEnabled = true
    @State private var calText = ""
    @State private var stepEnabled = true
    @State private var stepText = ""
    @State private var pacingEnabled = true
    @State private var pacingComparison: PacingComparison = .dayOfWeek
    @State private var pacingLookback: PacingLookback = .default
    @State private var showCalories = true
    @State private var showSteps = true
    @State private var showNetCalories = false
    @State private var appearance: AppAppearance = .system
    @State private var dietaryAuthRequested = false

    private var calValid: Bool {
        !calEnabled || (Double(calText) ?? 0) > 0
    }

    private var stepValid: Bool {
        !stepEnabled || (Int(stepText) ?? 0) > 0
    }

    private var pacingFooter: String {
        let window = pacingLookback.label.lowercased()
        let basis = pacingComparison == .dayOfWeek
            ? "Past \(window), same weekday as today."
            : "Past \(window), every day."
        return "Compares your progress so far to your usual at this time (Apple Health). \(basis) Empty days don’t count. Need 3+ days with data to show a comparison."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show Calories", isOn: $showCalories)
                    Toggle("Show Steps", isOn: $showSteps)
                    Toggle("Show Net Deficit", isOn: $showNetCalories)
                        .onChange(of: showNetCalories) { _, enabled in
                            guard enabled, !dietaryAuthRequested else { return }
                            dietaryAuthRequested = true
                            Task {
                                do {
                                    try await HealthKitService.shared.requestDietaryAuthorization()
                                } catch {
                                    print("[Settings] Dietary auth request failed: \(error)")
                                }
                            }
                        }
                } header: {
                    Text("Display")
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
                }

                Section {
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
                }

                Section {
                    Toggle("Show Pacing", isOn: $pacingEnabled)
                    if pacingEnabled {
                        Picker("Usual day is", selection: $pacingComparison) {
                            ForEach(PacingComparison.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        Picker("Look back", selection: $pacingLookback) {
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
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if calEnabled, let cal = Double(calText), cal > 0 {
                            goals.calorieGoal = min(max(cal, 500), 50000)
                        } else if !calEnabled {
                            goals.calorieGoal = nil
                        }
                        if stepEnabled, let step = Int(stepText), step > 0 {
                            goals.stepGoal = min(max(step, 100), 500000)
                        } else if !stepEnabled {
                            goals.stepGoal = nil
                        }
                        goals.showPacing = pacingEnabled
                        goals.pacingComparison = pacingComparison
                        goals.pacingLookback = pacingLookback
                        goals.showCalories = showCalories
                        goals.showSteps = showSteps
                        goals.showNetCalories = showNetCalories
                        goals.appearance = appearance
                        dismiss()
                    }
                    .bold()
                    .disabled(!calValid || !stepValid)
                }
            }
            .onAppear {
                calEnabled = goals.calorieGoal != nil
                calText = goals.calorieGoal.map { String(Int($0)) } ?? "2500"
                stepEnabled = goals.stepGoal != nil
                stepText = goals.stepGoal.map { String($0) } ?? "10000"
                pacingEnabled = goals.showPacing
                pacingComparison = goals.pacingComparison
                pacingLookback = goals.pacingLookback
                showCalories = goals.showCalories
                showSteps = goals.showSteps
                showNetCalories = goals.showNetCalories
                appearance = goals.appearance
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
