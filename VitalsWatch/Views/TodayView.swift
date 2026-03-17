import SwiftUI
import WatchKit

struct TodayView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0

    private var totalCalories: Double { activeCalories + restingCalories }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Calories")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(totalCalories, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                HStack(spacing: 12) {
                    Label(activeCalories.formatted(.number.precision(.fractionLength(0))), systemImage: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Label(restingCalories.formatted(.number.precision(.fractionLength(0))), systemImage: "bed.double.fill")
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.7))
                }
            }

            Divider()

            VStack(spacing: 4) {
                Text("Steps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(steps, format: .number)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .navigationTitle("Vitals")
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.willEnterForegroundNotification)) { _ in
            Task { await refresh() }
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
