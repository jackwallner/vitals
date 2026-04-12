import SwiftUI

private enum VitalsWatchLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let support = URL(string: "https://jackwallner.github.io/vitals/support.html")!
    static let supportEmail = URL(string: "mailto:jackwallner@gmail.com")!
}

private enum WatchHealthNotice: Equatable {
    case sampleData
    case noData
    case cachedData
    case loadError

    var message: String {
        switch self {
        case .sampleData:
            "Sample data preview.\nEnable Health access to see yours."
        case .noData:
            "No Health data yet.\nCheck Apple Health access on iPhone."
        case .cachedData:
            "Showing last saved data."
        case .loadError:
            "Couldn't load Health data."
        }
    }
}

struct TodayView: View {
    private static let reviewerSampleStats = (active: 420.0, resting: 1380.0, steps: 6240)

    @StateObject private var healthKit = HealthKitService.shared
    @Environment(\.scenePhase) var scenePhase
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0
    @State private var showBreakdown = false
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var showHelp = false
    @State private var healthNotice: WatchHealthNotice? = nil

    private var totalCalories: Double { activeCalories + restingCalories }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Theme.textTertiary)
            } else {
                VStack(spacing: 12) {
                    Spacer(minLength: 4)

                    // Calories
                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.caloriesPrimary)
                        Text(totalCalories, format: .number.precision(.fractionLength(0)))
                            .font(Theme.bigNumber(38))
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

                    // Divider
                    Rectangle()
                        .fill(Theme.cardSurface)
                        .frame(height: 1)
                        .padding(.horizontal, 20)

                    // Steps
                    VStack(spacing: 2) {
                        Image(systemName: "figure.walk")
                            .font(.caption)
                            .foregroundStyle(Theme.stepsPrimary)
                        Text(steps, format: .number)
                            .font(Theme.bigNumber(38))
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

                    if let healthNotice {
                        VStack(spacing: 6) {
                            Text(healthNotice.message)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                                .multilineTextAlignment(.center)

                            if healthNotice == .sampleData {
                                Button("Enable Health") {
                                    handleHealthNoticeAction(healthNotice)
                                }
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.caloriesPrimary)
                            }
                        }
                    }

                    Spacer(minLength: 4)
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

    private func applyStats(_ stats: (active: Double, resting: Double, steps: Int)) {
        activeCalories = stats.active
        restingCalories = stats.resting
        steps = stats.steps
    }

    private func handleHealthNoticeAction(_ notice: WatchHealthNotice) {
        guard notice == .sampleData else { return }

        Task {
            do {
                try await healthKit.requestAuthorization()
            } catch {
                print("Failed to request watch HealthKit authorization: \(error)")
                healthNotice = .loadError
            }
        }
    }

    private func applyReviewerSampleStats() {
        applyStats(Self.reviewerSampleStats)
    }

    private func isAllZero(_ stats: (active: Double, resting: Double, steps: Int)) -> Bool {
        stats.active == 0 && stats.resting == 0 && stats.steps == 0
    }

    private func showLoadedStateIfNeeded() {
        if isLoading { isLoading = false }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if !healthKit.isAuthorized {
            let requestStatus = await healthKit.authorizationRequestStatus()
            if requestStatus != .unnecessary {
                try? healthKit.clearTodayCache()
                applyReviewerSampleStats()
                healthNotice = .sampleData
                showLoadedStateIfNeeded()
                try? await healthKit.requestAuthorization()
                if !healthKit.isAuthorized { return }
            } else {
                try? await healthKit.requestAuthorization()
            }
        }
        do {
            let stats = try await healthKit.fetchTodayStatsWithRetry()
            applyStats(stats)
            healthNotice = isAllZero(stats) ? .noData : nil
            showLoadedStateIfNeeded()
            do {
                try await healthKit.refreshCache(stats: stats)
            } catch {
                print("Failed to refresh watch cache: \(error)")
            }
        } catch {
            print("Failed to fetch stats: \(error)")
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
