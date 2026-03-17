import SwiftUI
import Charts

struct HistoryView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @State private var selectedDays = 7
    @State private var records: [DayRecord] = []
    @State private var isLoading = true
    @State private var animateContent = false

    private var avgCalories: Double {
        guard !records.isEmpty else { return 0 }
        return records.map(\.totalCalories).reduce(0, +) / Double(records.count)
    }

    private var avgSteps: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.steps).reduce(0, +) / records.count
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                Text("History")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                // Segmented control
                HStack(spacing: 0) {
                    SegmentButton(title: "7 Days", isSelected: selectedDays == 7) {
                        selectedDays = 7
                    }
                    SegmentButton(title: "30 Days", isSelected: selectedDays == 30) {
                        selectedDays = 30
                    }
                }
                .padding(3)
                .background(Theme.cardSurface, in: Capsule())
                .padding(.horizontal, 24)
                .padding(.top, 16)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(Theme.textTertiary)
                    Spacer()
                } else if records.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.textTertiary)
                        Text("No data yet")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // Averages row
                            HStack(spacing: 12) {
                                StatCard(
                                    label: "Avg Calories",
                                    value: avgCalories.formatted(.number.precision(.fractionLength(0))),
                                    color: Theme.caloriesPrimary
                                )
                                StatCard(
                                    label: "Avg Steps",
                                    value: avgSteps.formatted(.number),
                                    color: Theme.stepsPrimary
                                )
                            }

                            // Calories chart
                            ChartCard(title: "Calories") {
                                Chart(records) { record in
                                    BarMark(
                                        x: .value("Date", record.date, unit: .day),
                                        y: .value("Calories", record.totalCalories)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Theme.caloriesPrimary, Theme.caloriesSecondary],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .cornerRadius(4)
                                }
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .day, count: selectedDays <= 7 ? 1 : 5)) { value in
                                        AxisValueLabel {
                                            if let date = value.as(Date.self) {
                                                Text(DateHelpers.shortDate(date))
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.textTertiary)
                                            }
                                        }
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks { value in
                                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                            .foregroundStyle(Color.white.opacity(0.06))
                                        AxisValueLabel {
                                            if let v = value.as(Double.self) {
                                                Text(v.formatted(.number.notation(.compactName)))
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.textTertiary)
                                            }
                                        }
                                    }
                                }
                                .frame(height: 180)
                            }

                            // Steps chart
                            ChartCard(title: "Steps") {
                                Chart(records) { record in
                                    BarMark(
                                        x: .value("Date", record.date, unit: .day),
                                        y: .value("Steps", record.steps)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Theme.stepsPrimary, Theme.stepsSecondary],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .cornerRadius(4)
                                }
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .day, count: selectedDays <= 7 ? 1 : 5)) { value in
                                        AxisValueLabel {
                                            if let date = value.as(Date.self) {
                                                Text(DateHelpers.shortDate(date))
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.textTertiary)
                                            }
                                        }
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks { value in
                                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                            .foregroundStyle(Color.white.opacity(0.06))
                                        AxisValueLabel {
                                            if let v = value.as(Int.self) {
                                                Text(v.formatted(.number.notation(.compactName)))
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.textTertiary)
                                            }
                                        }
                                    }
                                }
                                .frame(height: 180)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 15)
                    }
                }
            }
        }
        .onChange(of: selectedDays) { _, _ in
            animateContent = false
            Task { await loadHistory() }
        }
        .task { await loadHistory() }
    }

    private func loadHistory() async {
        isLoading = true
        do {
            let history = try await healthKit.fetchHistory(days: selectedDays)
            records = history.map {
                DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps)
            }
        } catch {
            print("Failed to fetch history: \(error)")
        }
        isLoading = false
        withAnimation(.easeOut(duration: 0.4)) {
            animateContent = true
        }
    }
}

// MARK: - Supporting Views

private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected ? Theme.cardSurfaceLight : .clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            content
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

struct DayRecord: Identifiable {
    let id = UUID()
    let date: Date
    let activeCalories: Double
    let restingCalories: Double
    let steps: Int

    var totalCalories: Double { activeCalories + restingCalories }
}
