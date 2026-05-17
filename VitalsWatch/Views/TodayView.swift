import SwiftUI
import HealthKit

private enum VitalsWatchLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let support = URL(string: "https://jackwallner.github.io/vitals/support.html")!
    static let supportEmail = URL(string: "mailto:jackwallner@gmail.com")!
}

private enum WatchHealthNotice: Equatable {
    case accessNeeded
    case accessBlocked
    case noData
    case cachedData
    case loadError

    var message: String {
        switch self {
        case .accessNeeded:
            "Enable Apple Health access\nto load your real data."
        case .accessBlocked:
            "Health access is off. On your iPhone: Settings → Privacy → Health → Total Calories."
        case .noData:
            "No Health data yet.\nCheck Apple Health access on iPhone."
        case .cachedData:
            "Showing last good saved data."
        case .loadError:
            "Couldn't load Health data."
        }
    }
}

struct TodayView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var goals = GoalSettings.shared
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0
    @State private var foodCalories: Double = 0
    @State private var showBreakdown = false
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var showHelp = false
    @State private var healthNotice: WatchHealthNotice? = nil
    @State private var calorieTrends: CalorieTrendSummary?
    @State private var trendLoadFailed = false
    @State private var stepTrends: StepTrendSummary?
    @State private var stepTrendLoadFailed = false
    @State private var netDeficitTrends: NetDeficitTrendSummary?
    @State private var netDeficitTrendLoadFailed = false
    /// Once we've resolved dietary auth (granted or denied), don't re-request on every refresh.
    @State private var dietaryAuthResolved = false

    private var totalCalories: Double { activeCalories + restingCalories }
    private var netDeficit: Double { totalCalories - foodCalories }
    private var compactLayout: Bool {
        // When more than one metric is visible, compact the layout so they all fit on small watches.
        let visibleCount = (goals.showCalories ? 1 : 0)
            + (goals.showSteps ? 1 : 0)
            + (goals.showNetCalories ? 1 : 0)
        return visibleCount >= 2
    }
    private var allMetricsHidden: Bool {
        !goals.showCalories && !goals.showSteps && !goals.showNetCalories
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Theme.textTertiary)
            } else {
                ScrollView {
                    VStack(spacing: compactLayout ? 6 : 12) {
                        Spacer(minLength: compactLayout ? 2 : 4)

                        if allMetricsHidden {
                            VStack(spacing: 6) {
                                Image(systemName: "heart.text.clipboard")
                                    .font(.title3)
                                    .foregroundStyle(Theme.textTertiary)
                                Text("No metrics enabled")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                Text("Open Total Calories on your iPhone to turn one on.")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 6)
                        }

                        // Calories
                        if goals.showCalories {
                            VStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.caloriesPrimary)
                                Text(totalCalories, format: .number.precision(.fractionLength(0)))
                                    .font(Theme.bigNumber(compactLayout ? 28 : 38))
                                    .foregroundStyle(Theme.textPrimary)
                                    .contentTransition(.numericText())
                                Text("CALORIES")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                    .tracking(1.2)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Calories")
                            .accessibilityValue("\(Int(totalCalories)) calories")
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showBreakdown.toggle()
                                }
                            }

                            if showBreakdown {
                                HStack(spacing: 8) {
                                    Label(activeCalories.formatted(.number.precision(.fractionLength(0))), systemImage: "flame.fill")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(Theme.activePrimary)
                                    Label(restingCalories.formatted(.number.precision(.fractionLength(0))), systemImage: "bed.double.fill")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(Theme.restingPrimary)
                                }
                            }

                        }

                        // Divider between Calories and Steps (only when both visible)
                        if goals.showCalories && goals.showSteps {
                            Rectangle()
                                .fill(Theme.cardSurface)
                                .frame(height: 1)
                                .padding(.horizontal, 20)
                        }

                        // Steps
                        if goals.showSteps {
                            VStack(spacing: 2) {
                                Image(systemName: "figure.walk")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.stepsPrimary)
                                Text(steps, format: .number)
                                    .font(Theme.bigNumber(compactLayout ? 28 : 38))
                                    .foregroundStyle(Theme.textPrimary)
                                    .contentTransition(.numericText())
                                Text("STEPS")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                    .tracking(1.2)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Steps")
                            .accessibilityValue("\(steps) steps")
                        }

                        if goals.showNetCalories {
                            // Divider above Net (only when an earlier metric is visible)
                            if goals.showCalories || goals.showSteps {
                                Rectangle()
                                    .fill(Theme.cardSurface)
                                    .frame(height: 1)
                                    .padding(.horizontal, 20)
                            }

                            VStack(spacing: 2) {
                                Image(systemName: "fork.knife")
                                    .font(.caption)
                                    .foregroundStyle(Theme.netDeficitBrand)
                                Text(netDeficitDisplayText(netDeficit))
                                    .font(Theme.bigNumber(24))
                                    .foregroundStyle(netDeficit >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative)
                                    .contentTransition(.numericText())
                                Text("NET CAL")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                    .tracking(1.2)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Net calories")
                            .accessibilityValue("\(Int(netDeficit)) net calories")
                        }

                        if goals.showCalories {
                            if let calorieTrends {
                                WatchTrendSection(trends: calorieTrends)
                                    .padding(.top, compactLayout ? 2 : 4)
                            } else if trendLoadFailed {
                                Text("Trends unavailable")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }

                        if goals.showSteps {
                            if let stepTrends {
                                WatchStepTrendSection(trends: stepTrends)
                                    .padding(.top, compactLayout ? 2 : 4)
                            } else if stepTrendLoadFailed {
                                Text("Step trends unavailable")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }

                        if goals.showNetCalories, let netDeficitTrends {
                            WatchNetDeficitTrendSection(trends: netDeficitTrends)
                                .padding(.top, compactLayout ? 2 : 4)
                        }

                        if let healthNotice {
                            VStack(spacing: 6) {
                                Text(healthNotice.message)
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
                                    .multilineTextAlignment(.center)

                                if healthNotice == .accessNeeded {
                                    Button("Enable Health") {
                                        handleHealthNoticeAction(healthNotice)
                                    }
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.caloriesPrimary)
                                }
                                if healthNotice == .accessBlocked {
                                    Text("Enable Active Energy, Basal Energy,\nand Step Count for Total Calories.")
                                        .font(.system(size: 9, design: .rounded))
                                        .foregroundStyle(Theme.textTertiary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }

                        Button {
                            showHelp = true
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.caloriesPrimary)

                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .overlay(alignment: .top) {
            if isRefreshing && !isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.textTertiary)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .background(Theme.background)
        .navigationTitle("Total Calories")
        .onChange(of: healthKit.isAuthorized) { _, authorized in
            if authorized {
                Task { await refresh() }
            }
        }
        .task {
            await refresh()
            if ScreenshotConfig.wantsWatchBreakdown {
                showBreakdown = true
            }
            if ScreenshotConfig.wantsWatchHelp {
                showHelp = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refresh() }
            }
        }
        .sheet(isPresented: $showHelp) {
            WatchHelpView()
        }
    }

    private func netDeficitDisplayText(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return prefix + Int(value).formatted(.number)
    }

    private func applyStats(_ stats: (active: Double, resting: Double, steps: Int)) {
        activeCalories = stats.active
        restingCalories = stats.resting
        steps = stats.steps
    }

    private func handleHealthNoticeAction(_ notice: WatchHealthNotice) {
        guard notice == .accessNeeded else { return }

        Task {
            // If iOS already prompted (status == .unnecessary),
            // requestAuthorization is a silent no-op for previously-denied
            // categories. Surface a clearer notice instead.
            let status = await healthKit.authorizationRequestStatus()
            if status == .unnecessary {
                healthNotice = .accessBlocked
                return
            }
            do {
                try await healthKit.requestAuthorization()
                await refresh()
            } catch {
                print("Failed to request watch HealthKit authorization: \(error)")
                healthNotice = .loadError
            }
        }
    }

    private func isAllZero(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        HealthKitService.isAllZero(stats)
    }

    /// Same classification as Dashboard: on all-zero fetch with no cache, read HealthKit's
    /// request-status to decide between `.accessNeeded` (never prompted) and `.accessBlocked`
    /// (prompted, denied) so the watch can surface the right copy.
    private func classifyEmptyFetchNotice(
        requestStatus: HKAuthorizationRequestStatus?
    ) -> WatchHealthNotice {
        switch requestStatus {
        case .shouldRequest:
            return .accessNeeded
        case .unnecessary:
            return .accessBlocked
        default:
            return .noData
        }
    }

    private func showLoadedStateIfNeeded() {
        if isLoading { isLoading = false }
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

        await healthKit.synchronizeAuthorizationStateForFetching()
        do {
            let stats = try await healthKit.fetchTodayStatsWithRetry()
            if isAllZero(stats), let cachedStats, cachedHasData {
                applyStats(cachedStats)
                healthNotice = .cachedData
            } else {
                applyStats(stats)
                if isAllZero(stats) {
                    let status = await healthKit.authorizationRequestStatus()
                    healthNotice = classifyEmptyFetchNotice(requestStatus: status)
                } else {
                    healthNotice = nil
                }
            }
            showLoadedStateIfNeeded()
            do {
                try await healthKit.refreshCache(stats: stats)
            } catch {
                print("Failed to refresh watch cache: \(error)")
            }
            if goals.showNetCalories {
                do {
                    if !dietaryAuthResolved {
                        // Only call requestAuthorization once per session. After
                        // the first call (granted or denied) the system caches the
                        // answer; calling again is a silent no-op but generates
                        // noisy logs every scenePhase active.
                        let status = await healthKit.authorizationRequestStatus(includeDietaryEnergy: true)
                        if status == .shouldRequest {
                            try await healthKit.requestDietaryAuthorization()
                        }
                        dietaryAuthResolved = true
                    }
                    let food = try await healthKit.fetchDietaryEnergyToday()
                    foodCalories = food
                    try healthKit.updateCachedFoodCalories(food)
                } catch {
                    print("Failed to fetch dietary energy: \(error)")
                }
            } else {
                foodCalories = 0
            }
            await loadCalorieTrendsIfNeeded()
            await loadStepTrendsIfNeeded()
            await loadNetDeficitTrendsIfNeeded()
        } catch {
            let ns = error as NSError
            print("Failed to fetch stats: \(error) domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            if let cachedStats = try? healthKit.fetchCachedTodayStats() {
                applyStats(cachedStats)
                healthNotice = .cachedData
            } else {
                applyStats((active: 0, resting: 0, steps: 0))
                healthNotice = .loadError
            }
            showLoadedStateIfNeeded()
        }
    }

    private func loadCalorieTrendsIfNeeded() async {
        guard goals.showCalories else {
            calorieTrends = nil
            trendLoadFailed = false
            return
        }

        do {
            let history = try await healthKit.fetchMergedHistory(days: 30)
            calorieTrends = CalorieTrendSummary.make(history: history)
            trendLoadFailed = calorieTrends == nil
        } catch {
            print("Failed to fetch watch calorie trends: \(error)")
            trendLoadFailed = calorieTrends == nil
        }
    }

    private func loadStepTrendsIfNeeded() async {
        guard goals.showSteps else {
            stepTrends = nil
            stepTrendLoadFailed = false
            return
        }

        do {
            let history = try await healthKit.fetchMergedHistory(days: 30)
            stepTrends = StepTrendSummary.make(history: history)
            stepTrendLoadFailed = stepTrends == nil
        } catch {
            print("Failed to fetch watch step trends: \(error)")
            stepTrendLoadFailed = stepTrends == nil
        }
    }

    private func loadNetDeficitTrendsIfNeeded() async {
        guard goals.showNetCalories else {
            netDeficitTrends = nil
            netDeficitTrendLoadFailed = false
            return
        }

        do {
            let history = try await healthKit.fetchMergedHistory(days: 30)
            let dietary = try await healthKit.fetchDietaryHistory(days: 30)
            let calendar = Calendar.current
            let foodMap = Dictionary(uniqueKeysWithValues: dietary.map {
                (calendar.startOfDay(for: $0.date), $0.foodCalories)
            })
            let summary = NetDeficitTrendSummary.make(history: history, foodByDate: foodMap)
            // Only surface the section once at least one day in the window has food
            // logged — otherwise it would just be a flat 0 chart.
            netDeficitTrends = summary
            netDeficitTrendLoadFailed = summary == nil
        } catch {
            print("Failed to fetch watch net deficit trends: \(error)")
            netDeficitTrends = nil
            netDeficitTrendLoadFailed = true
        }
    }
}

private struct WatchTrendSection: View {
    let trends: CalorieTrendSummary

    var body: some View {
        WatchTrendPeriodSection(
            title: "Calories, Last 7 Days",
            points: Array(trends.points.suffix(7)),
            metric: trends.weekly
        )
        .padding(10)
        .background(Theme.cardSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calorie history")
        .accessibilityValue(trends.weekly.accessibilityText)
    }
}

private struct WatchTrendPeriodSection: View {
    let title: String
    let points: [CalorieTrendPoint]
    let metric: CalorieTrendMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.averageText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("avg")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            WatchTrendBars(points: points)
                .frame(height: 28)
        }
    }
}

private struct WatchTrendBars: View {
    let points: [CalorieTrendPoint]

    private var maxCalories: Double {
        max(points.map(\.totalCalories).max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(points) { point in
                    let isToday = Calendar.current.isDateInToday(point.date)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barFill(for: point, isToday: isToday))
                        .frame(height: max(3, proxy.size.height * point.totalCalories / maxCalories))
                        .opacity(barOpacity(for: point, isToday: isToday))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private func barFill(for point: CalorieTrendPoint, isToday: Bool) -> LinearGradient {
    if isToday {
        return Theme.caloriesGradient
    }
    return point.totalCalories > 0 ? Theme.caloriesGradient : LinearGradient(colors: [Theme.ringTrack], startPoint: .bottom, endPoint: .top)
}

private func barOpacity(for point: CalorieTrendPoint, isToday: Bool) -> Double {
    if isToday { return 1.0 }
    return point.totalCalories > 0 ? 0.86 : 0.3
}

private struct WatchStepTrendSection: View {
    let trends: StepTrendSummary

    var body: some View {
        WatchStepTrendPeriodSection(
            title: "Steps, Last 7 Days",
            points: Array(trends.points.suffix(7)),
            metric: trends.weekly
        )
        .padding(10)
        .background(Theme.cardSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step history")
        .accessibilityValue(trends.weekly.accessibilityText)
    }
}

private struct WatchStepTrendPeriodSection: View {
    let title: String
    let points: [StepTrendPoint]
    let metric: StepTrendMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.averageText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("avg")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            WatchStepTrendBars(points: points)
                .frame(height: 28)
        }
    }
}

private struct WatchStepTrendBars: View {
    let points: [StepTrendPoint]

    private var maxSteps: Double {
        max(Double(points.map(\.steps).max() ?? 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(points) { point in
                    let isToday = Calendar.current.isDateInToday(point.date)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(stepBarFill(for: point, isToday: isToday))
                        .frame(height: max(3, proxy.size.height * Double(point.steps) / maxSteps))
                        .opacity(stepBarOpacity(for: point, isToday: isToday))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private func stepBarFill(for point: StepTrendPoint, isToday: Bool) -> LinearGradient {
    if isToday {
        return Theme.stepsGradient
    }
    return point.steps > 0 ? Theme.stepsGradient : LinearGradient(colors: [Theme.ringTrack], startPoint: .bottom, endPoint: .top)
}

private func stepBarOpacity(for point: StepTrendPoint, isToday: Bool) -> Double {
    if isToday { return 1.0 }
    return point.steps > 0 ? 0.86 : 0.3
}

private struct WatchNetDeficitTrendSection: View {
    let trends: NetDeficitTrendSummary

    var body: some View {
        WatchNetDeficitPeriodSection(
            title: "Net Deficit, Last 7 Days",
            points: Array(trends.points.suffix(7)),
            metric: trends.weekly
        )
        .padding(10)
        .background(Theme.cardSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Net deficit history")
        .accessibilityValue(trends.weekly.accessibilityText)
    }
}

private struct WatchNetDeficitPeriodSection: View {
    let title: String
    let points: [NetDeficitTrendPoint]
    let metric: NetDeficitTrendMetric

    private var avgColor: Color {
        guard let avg = metric.average else { return Theme.textPrimary }
        return avg >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.averageText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(avgColor)
                Text("avg")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            WatchNetDeficitBars(points: points)
                .frame(height: 28)
        }
    }
}

/// Center-baseline bar chart: positive deficits grow up (green), negative grow down (red).
/// Days without food logged render as a faint placeholder so the 7-day pattern stays visible.
private struct WatchNetDeficitBars: View {
    let points: [NetDeficitTrendPoint]

    private var maxAbs: Double {
        max(points.map { abs($0.netDeficit) }.max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let halfHeight = proxy.size.height / 2
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(points) { point in
                    let isToday = Calendar.current.isDateInToday(point.date)
                    let hasFood = point.burned > 0
                    let isPositive = point.netDeficit >= 0
                    let magnitude = max(3, halfHeight * abs(point.netDeficit) / maxAbs)
                    VStack(spacing: 0) {
                        // Top half (positive deficits)
                        if hasFood && isPositive {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.netDeficitPositive)
                                .frame(height: magnitude)
                                .opacity(isToday ? 1.0 : 0.86)
                        } else {
                            Spacer(minLength: 0)
                        }
                        // Bottom half (negative deficits / no food placeholder)
                        if hasFood && !isPositive {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.netDeficitNegative)
                                .frame(height: magnitude)
                                .opacity(isToday ? 1.0 : 0.86)
                            Spacer(minLength: 0)
                        } else if !hasFood {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.ringTrack)
                                .frame(height: 3)
                                .opacity(0.3)
                            Spacer(minLength: 0)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WatchHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Help") {
                    Link(destination: VitalsWatchLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    Link(destination: VitalsWatchLinks.support) {
                        Label("Support", systemImage: "questionmark.circle")
                    }

                    Link(destination: VitalsWatchLinks.supportEmail) {
                        Label("Contact Support", systemImage: "envelope")
                    }
                }

                Section("Health Data") {
                    Text("Total Calories reads Active Energy, Basal Energy, and Step Count from Apple Health in read-only mode.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Help")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
