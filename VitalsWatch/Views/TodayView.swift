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

                            if let calorieTrends {
                                WatchTrendSection(trends: calorieTrends)
                                    .padding(.top, compactLayout ? 2 : 4)
                            } else if trendLoadFailed {
                                Text("Trends unavailable")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
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
        .overlay(alignment: .topTrailing) {
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(6)
                    .background(Theme.cardSurface.opacity(0.8), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .padding(.trailing, 2)
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
                // Reset so toggling Net back on later will re-check status.
                dietaryAuthResolved = false
            }
            await loadCalorieTrendsIfNeeded()
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
            let history = try await healthKit.fetchHistory(days: 60)
            calorieTrends = CalorieTrendSummary.make(history: history)
            trendLoadFailed = calorieTrends == nil
        } catch {
            print("Failed to fetch watch calorie trends: \(error)")
            trendLoadFailed = calorieTrends == nil
        }
    }
}

private struct WatchTrendSection: View {
    let trends: CalorieTrendSummary

    var body: some View {
        VStack(spacing: 6) {
            WatchTrendBars(points: trends.points)
                .frame(height: 34)
                .padding(.horizontal, 4)

            HStack(spacing: 6) {
                WatchTrendCard(metric: trends.weekly)
                WatchTrendCard(metric: trends.monthly)
            }
        }
        .padding(8)
        .background(Theme.cardSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calorie trends")
        .accessibilityValue("\(trends.weekly.accessibilityText), \(trends.monthly.accessibilityText)")
    }
}

private struct WatchTrendCard: View {
    let metric: CalorieTrendMetric

    var body: some View {
        VStack(spacing: 2) {
            Text(metric.title)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .tracking(0.8)
            Text(metric.averageText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.7)
            Text(metric.changeText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(metric.changeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
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
                    RoundedRectangle(cornerRadius: 2)
                        .fill(point.totalCalories > 0 ? Theme.caloriesGradient : LinearGradient(colors: [Theme.ringTrack], startPoint: .bottom, endPoint: .top))
                        .frame(height: max(3, proxy.size.height * point.totalCalories / maxCalories))
                        .opacity(point.totalCalories > 0 ? 1 : 0.35)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private extension CalorieTrendMetric {
    var changeColor: Color {
        guard let percentChange else { return Theme.textTertiary }
        if percentChange > 0 { return Theme.netDeficitPositive }
        if percentChange < 0 { return Theme.netDeficitNegative }
        return Theme.textTertiary
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
