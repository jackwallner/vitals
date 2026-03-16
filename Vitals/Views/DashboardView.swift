import SwiftUI

struct DashboardView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0
    @State private var isLoading = true

    private var totalCalories: Double { activeCalories + restingCalories }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        ProgressView("Loading health data...")
                            .padding(.top, 60)
                    } else {
                        // Total Calories Card
                        VStack(spacing: 8) {
                            Text("Total Calories")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(totalCalories, format: .number.precision(.fractionLength(0)))
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            HStack(spacing: 24) {
                                LabeledMetric(
                                    title: "Active",
                                    value: activeCalories,
                                    color: .red
                                )
                                LabeledMetric(
                                    title: "Resting",
                                    value: restingCalories,
                                    color: .orange.opacity(0.7)
                                )
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                        // Steps Card
                        VStack(spacing: 8) {
                            Text("Steps")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(steps, format: .number)
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .navigationTitle("Vitals")
            .refreshable { await refresh() }
            .task { await refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
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
            print("Failed to fetch today stats: \(error)")
        }
        isLoading = false
    }
}

private struct LabeledMetric: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.title2.bold())
                .foregroundStyle(color)
        }
    }
}
