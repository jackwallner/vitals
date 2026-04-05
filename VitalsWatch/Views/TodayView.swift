import SwiftUI

private enum VitalsWatchLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let support = URL(string: "https://jackwallner.github.io/vitals/support.html")!
    static let supportEmail = URL(string: "mailto:jackwallner@gmail.com")!
}

struct TodayView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @Environment(\.scenePhase) var scenePhase
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0
    @State private var showBreakdown = false
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var hasLoadedOnce = false
    @State private var loadError = false
    @State private var showHelp = false

    private var totalCalories: Double { activeCalories + restingCalories }
    private var hasNoData: Bool { hasLoadedOnce && totalCalories == 0 && steps == 0 }

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

                    if hasNoData {
                        VStack(spacing: 4) {
                            Text(loadError ? "Could not load data." : "No health data available.")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                            Text("Check Health permissions\nin iPhone Settings.")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .multilineTextAlignment(.center)
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
        .navigationTitle("Vitals")
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

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if !healthKit.isAuthorized {
            try? await healthKit.requestAuthorization()
        }
        do {
            let stats = try await healthKit.fetchTodayStats()
            activeCalories = stats.active
            restingCalories = stats.resting
            steps = stats.steps
            hasLoadedOnce = true
            loadError = false
            if isLoading { isLoading = false }
            try? await healthKit.refreshCache(stats: stats)
        } catch {
            print("Failed to fetch stats: \(error)")
            hasLoadedOnce = true
            loadError = true
            if isLoading { isLoading = false }
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
                    Text("Vitals reads Active Energy, Basal Energy, and Step Count from Apple Health in read-only mode.")
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
