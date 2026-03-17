import SwiftUI
import WatchKit

struct TodayView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @Environment(\.scenePhase) var scenePhase
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0
    @State private var showBreakdown = false

    private var totalCalories: Double { activeCalories + restingCalories }

    var body: some View {
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

            Spacer(minLength: 4)
        }
        .background(Theme.background)
        .navigationTitle("Vitals")
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.willEnterForegroundNotification)) { _ in
            Task { await refresh() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refresh() }
            }
        }
    }

    private func refresh() async {
        do {
            let stats = try await healthKit.fetchTodayStats()
            activeCalories = stats.active
            restingCalories = stats.resting
            steps = stats.steps
            try? await healthKit.refreshCache()
        } catch {
            print("Failed to fetch stats: \(error)")
        }
    }
}
