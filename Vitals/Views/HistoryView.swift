import SwiftUI
import Charts

struct HistoryView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @State private var selectedDays = 7
    @State private var records: [DayRecord] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Time Range", selection: $selectedDays) {
                    Text("7 Days").tag(7)
                    Text("30 Days").tag(30)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if records.isEmpty {
                    Spacer()
                    Text("No data yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Calories Chart
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Calories")
                                    .font(.headline)
                                Chart(records) { record in
                                    BarMark(
                                        x: .value("Date", record.date, unit: .day),
                                        y: .value("Active", record.activeCalories)
                                    )
                                    .foregroundStyle(.red)
                                    BarMark(
                                        x: .value("Date", record.date, unit: .day),
                                        y: .value("Resting", record.restingCalories)
                                    )
                                    .foregroundStyle(.orange.opacity(0.7))
                                }
                                .chartYAxisLabel("kcal")
                                .frame(height: 200)
                            }
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                            // Steps Chart
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Steps")
                                    .font(.headline)
                                Chart(records) { record in
                                    BarMark(
                                        x: .value("Date", record.date, unit: .day),
                                        y: .value("Steps", record.steps)
                                    )
                                    .foregroundStyle(.blue)
                                }
                                .frame(height: 200)
                            }
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("History")
            .onChange(of: selectedDays) { _, _ in
                Task { await loadHistory() }
            }
            .task { await loadHistory() }
        }
    }

    private func loadHistory() async {
        isLoading = true
        do {
            let history = try await healthKit.fetchHistory(days: selectedDays)
            records = history.map { DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps) }
        } catch {
            print("Failed to fetch history: \(error)")
        }
        isLoading = false
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
