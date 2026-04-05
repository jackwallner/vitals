import SwiftUI
import Charts
import UniformTypeIdentifiers

struct HistoryView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @State private var selectedPeriod: Period = .week
    @State private var customStart: Date = DateHelpers.daysAgo(7)
    @State private var customEnd: Date = .now
    @State private var showCustomRange = false
    @State private var records: [DayRecord] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var animateContent = false
    @State private var showExportSheet = false
    @State private var showExportWarning = false
    @State private var showExportError = false
    @State private var csvFile: CSVFile?
    @State private var selectedCalorieDate: Date?
    @State private var selectedStepDate: Date?

    enum Period: String, CaseIterable {
        case week = "7D"
        case month = "30D"
        case threeMonths = "90D"
        case year = "1Y"
        case custom = "Custom"

        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .threeMonths: 90
            case .year: 365
            case .custom: nil
            }
        }
    }

    private var avgCalories: Double {
        guard !records.isEmpty else { return 0 }
        return records.map(\.totalCalories).reduce(0, +) / Double(records.count)
    }

    private var avgSteps: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.steps).reduce(0, +) / records.count
    }

    private var calorieTrend: Trend {
        computeTrend(records.map(\.totalCalories))
    }

    private var stepTrend: Trend {
        computeTrend(records.map { Double($0.steps) })
    }

    private var peakCalorieDay: DayRecord? {
        records.max(by: { $0.totalCalories < $1.totalCalories })
    }

    private var peakStepDay: DayRecord? {
        records.max(by: { $0.steps < $1.steps })
    }

    private func recordForDate(_ date: Date?) -> DayRecord? {
        guard let date else { return nil }
        let cal = Calendar.current
        return records.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with export
                HStack {
                    Text("History")
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)
                    if isRefreshing && !isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.textTertiary)
                            .padding(.leading, 4)
                            .transition(.opacity)
                    }
                    Spacer()
                    if !records.isEmpty {
                        Button {
                            showExportWarning = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.caloriesPrimary)
                                .padding(10)
                                .background(Theme.cardSurface, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                // Period selector
                HStack(spacing: 0) {
                    ForEach(Period.allCases, id: \.self) { period in
                        SegmentButton(title: period.rawValue, isSelected: selectedPeriod == period) {
                            if period == .custom {
                                showCustomRange = true
                            } else {
                                selectedPeriod = period
                            }
                        }
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
                    VStack(spacing: 12) {
                        Image(systemName: "figure.walk.motion")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.textTertiary)
                        Text("No Activity Data Yet")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Start moving! Your activity data will appear here once HealthKit records your steps and calories.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Text("Make sure HealthKit permissions are enabled in Settings.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // Summary cards
                            HStack(spacing: 12) {
                                TrendCard(
                                    label: "Avg Calories",
                                    value: avgCalories.formatted(.number.precision(.fractionLength(0))),
                                    trend: calorieTrend,
                                    color: Theme.caloriesPrimary
                                )
                                TrendCard(
                                    label: "Avg Steps",
                                    value: avgSteps.formatted(.number),
                                    trend: stepTrend,
                                    color: Theme.stepsPrimary
                                )
                            }

                            // Peak days
                            if let peakCal = peakCalorieDay, let peakStep = peakStepDay {
                                HStack(spacing: 12) {
                                    PeakCard(
                                        label: "Best Calorie Day",
                                        value: peakCal.totalCalories.formatted(.number.precision(.fractionLength(0))),
                                        date: peakCal.date,
                                        color: Theme.caloriesPrimary
                                    )
                                    PeakCard(
                                        label: "Best Step Day",
                                        value: peakStep.steps.formatted(.number),
                                        date: peakStep.date,
                                        color: Theme.stepsPrimary
                                    )
                                }
                            }

                            // Calories chart
                            ChartCard(title: "Calories", selection: selectedCalorieRecord) {
                                caloriesChart
                            }

                            // Steps chart
                            ChartCard(title: "Steps", selection: selectedStepRecord) {
                                stepsChart
                            }

                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 90)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 15)
                    }
                    .refreshable { await loadHistory() }
                }
            }
        }
        .onChange(of: selectedPeriod) { _, _ in
            if selectedPeriod != .custom {
                Task { await loadHistory() }
            }
        }
        .task {
            if ScreenshotConfig.wantsHistoryTab {
                selectedPeriod = .month
            }
            await loadHistory()
        }
        .sheet(isPresented: $showCustomRange) {
            CustomRangeSheet(start: $customStart, end: $customEnd) {
                selectedPeriod = .custom
                showCustomRange = false
                Task { await loadHistory() }
            }
            .presentationDetents([.medium])
        }
        .alert("Export Health Data", isPresented: $showExportWarning) {
            Button("Export", role: .destructive) {
                exportCSV()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This export contains sensitive health data including your daily calorie and step counts. Only share it with people and services you trust.")
        }
        .sheet(isPresented: $showExportSheet, onDismiss: {
            if let csvFile {
                try? FileManager.default.removeItem(at: csvFile.url)
                self.csvFile = nil
            }
        }) {
            if let csvFile {
                ShareSheet(items: [csvFile.url])
            }
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not save the export file. Please try again.")
        }
    }

    // MARK: - Chart Views

    private var selectedCalorieRecord: ChartSelection? {
        guard let record = recordForDate(selectedCalorieDate) else { return nil }
        return ChartSelection(
            date: record.date,
            primary: ("Calories", record.totalCalories.formatted(.number.precision(.fractionLength(0))))
        )
    }

    private var selectedStepRecord: ChartSelection? {
        guard let record = recordForDate(selectedStepDate) else { return nil }
        return ChartSelection(
            date: record.date,
            primary: ("Steps", record.steps.formatted(.number))
        )
    }

    private var caloriesChart: some View {
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
            .opacity(selectedCalorieDate == nil || Calendar.current.isDate(record.date, inSameDayAs: selectedCalorieDate!) ? 1.0 : 0.3)
            .cornerRadius(4)

            if records.count > 1 {
                RuleMark(y: .value("Average", avgCalories))
                    .foregroundStyle(Theme.caloriesPrimary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
            }
        }
        .chartXSelection(value: $selectedCalorieDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
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
                    .foregroundStyle(Color(.separator).opacity(0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.formatted(.number.notation(.compactName)))
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .frame(minHeight: 180, maxHeight: 240)
    }

    private var stepsChart: some View {
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
            .opacity(selectedStepDate == nil || Calendar.current.isDate(record.date, inSameDayAs: selectedStepDate!) ? 1.0 : 0.3)
            .cornerRadius(4)

            if records.count > 1 {
                RuleMark(y: .value("Average", avgSteps))
                    .foregroundStyle(Theme.stepsPrimary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
            }
        }
        .chartXSelection(value: $selectedStepDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
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
                    .foregroundStyle(Color(.separator).opacity(0.3))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(v.formatted(.number.notation(.compactName)))
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .frame(minHeight: 180, maxHeight: 240)
    }

    // MARK: - Helpers

    private var xAxisStride: Int {
        let count = records.count
        if count <= 10 { return 1 }
        if count <= 31 { return 5 }
        if count <= 91 { return 14 }
        return 30
    }

    private func loadHistory() async {
        let isFirstLoad = records.isEmpty
        if isFirstLoad { isLoading = true }
        isRefreshing = true
        selectedCalorieDate = nil
        selectedStepDate = nil
        do {
            let history: [(date: Date, active: Double, resting: Double, steps: Int)]
            if selectedPeriod == .custom {
                history = try await healthKit.fetchHistory(from: customStart, to: customEnd)
            } else {
                history = try await healthKit.fetchHistory(days: selectedPeriod.days ?? 7)
            }

            withAnimation(.easeOut(duration: 0.3)) {
                records = history.map {
                    DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps)
                }
            }
        } catch {
            print("Failed to fetch history: \(error)")
        }
        isLoading = false
        isRefreshing = false
        if !animateContent {
            withAnimation(.easeOut(duration: 0.4)) {
                animateContent = true
            }
        }
    }

    private func exportCSV() {
        let header = "Date,Active Calories,Resting Calories,Total Calories,Steps\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let rows = records.map { r in
            "\(formatter.string(from: r.date)),\(String(format: "%.0f", r.activeCalories)),\(String(format: "%.0f", r.restingCalories)),\(String(format: "%.0f", r.totalCalories)),\(r.steps)"
        }.joined(separator: "\n")

        let csv = header + rows
        let timestamp = Int(Date.now.timeIntervalSince1970)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vitals_export_\(timestamp).csv")
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            csvFile = CSVFile(url: tempURL)
            showExportSheet = true
        } catch {
            print("CSV export failed: \(error)")
            showExportError = true
        }
    }

    private func computeTrend(_ values: [Double]) -> Trend {
        guard values.count >= 4 else { return .neutral }
        let half = values.count / 2
        let firstHalf = Array(values.prefix(half))
        let secondHalf = Array(values.suffix(half))
        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        guard firstAvg > 1 else { return .neutral }
        let change = (secondAvg - firstAvg) / firstAvg
        if change > 0.05 { return .up(change) }
        if change < -0.05 { return .down(change) }
        return .neutral
    }
}

// MARK: - Chart Selection

struct ChartSelection {
    let date: Date
    let primary: (label: String, value: String)

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var dateLabel: String {
        Self.dateFormatter.string(from: date)
    }
}

// MARK: - Trend

enum Trend {
    case up(Double)
    case down(Double)
    case neutral

    var icon: String {
        switch self {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .neutral: "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .up: .green
        case .down: Color(red: 1.0, green: 0.42, blue: 0.42)
        case .neutral: Theme.textTertiary
        }
    }

    var label: String {
        switch self {
        case .up(let pct): "+\(Int(pct * 100))%"
        case .down(let pct): "\(Int(pct * 100))%"
        case .neutral: "Flat"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .up(let pct): "up \(Int(pct * 100)) percent"
        case .down(let pct): "down \(Int(abs(pct) * 100)) percent"
        case .neutral: "flat"
        }
    }
}

// MARK: - CSV File

struct CSVFile {
    let url: URL
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Custom Range Sheet

private struct CustomRangeSheet: View {
    @Binding var start: Date
    @Binding var end: Date
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        start < end && (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) <= 730
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $start, in: ...Date.now, displayedComponents: .date)
                DatePicker("End", selection: $end, in: ...Date.now, displayedComponents: .date)
                if !isValid {
                    Section {
                        if start >= end {
                            Text("Start date must be before end date.")
                                .foregroundStyle(.red)
                                .font(.caption)
                        } else {
                            Text("Maximum range is 2 years.")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply() }
                        .bold()
                        .disabled(!isValid)
                }
            }
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
                .font(.caption.bold())
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

private struct TrendCard: View {
    let label: String
    let value: String
    let trend: Trend
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            HStack(spacing: 4) {
                Image(systemName: trend.icon)
                    .font(.caption2.bold())
                Text(trend.label)
                    .font(.caption2.bold())
            }
            .foregroundStyle(trend.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(value), trending \(trend.accessibilityDescription)")
    }
}

private struct PeakCard: View {
    let label: String
    let value: String
    let date: Date
    let color: Color

    private static let peakDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            Text(Self.peakDateFormatter.string(from: date))
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) on \(Self.peakDateFormatter.string(from: date))")
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    var selection: ChartSelection? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sel = selection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sel.dateLabel)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Text(sel.primary.value)
                        .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                .transition(.opacity)
            } else {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            content
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .animation(.easeInOut(duration: 0.15), value: selection?.dateLabel)
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
