import SwiftUI
import Charts
import UniformTypeIdentifiers

@MainActor
private enum HistoryPrefs {
    private static let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
    private static let periodKey = "history.period"
    private static let customStartKey = "history.customStart"
    private static let customEndKey = "history.customEnd"

    static func savedPeriod() -> HistoryView.Period {
        guard let raw = defaults.string(forKey: periodKey) else { return .week }
        return HistoryView.Period(rawValue: raw) ?? .week
    }

    static func savedCustomStart() -> Date {
        sanitizedRange().start
    }

    static func savedCustomEnd() -> Date {
        sanitizedRange().end
    }

    /// Clamp persisted custom-range dates onto a valid window so a stale saved range
    /// (e.g. "end = old Date.now") can't yield invalid inputs after the clock advances.
    static func sanitizedRange() -> (start: Date, end: Date) {
        let now = Date.now
        let storedStartTi = defaults.double(forKey: customStartKey)
        let storedEndTi = defaults.double(forKey: customEndKey)

        let rawStart = storedStartTi > 0 ? Date(timeIntervalSince1970: storedStartTi) : DateHelpers.daysAgo(6)
        let rawEnd = storedEndTi > 0 ? Date(timeIntervalSince1970: storedEndTi) : now

        let end = min(rawEnd, now)
        var start = min(rawStart, end)
        if start >= end {
            start = DateHelpers.daysAgo(6, from: end)
        }
        // CustomRangeSheet caps at 2 years; enforce the same bound on load.
        let maxWindow: TimeInterval = 730 * 86_400
        if end.timeIntervalSince(start) > maxWindow {
            start = end.addingTimeInterval(-maxWindow)
        }
        // Only persist back if we actually changed something (avoid gratuitous writes).
        let needsWriteback = abs(start.timeIntervalSince(rawStart)) > 1 || abs(end.timeIntervalSince(rawEnd)) > 1
        if needsWriteback && storedStartTi > 0 && storedEndTi > 0 {
            defaults.set(start.timeIntervalSince1970, forKey: customStartKey)
            defaults.set(end.timeIntervalSince1970, forKey: customEndKey)
        }
        return (start, end)
    }

    static func save(period: HistoryView.Period, customStart: Date, customEnd: Date) {
        defaults.set(period.rawValue, forKey: periodKey)
        defaults.set(customStart.timeIntervalSince1970, forKey: customStartKey)
        defaults.set(customEnd.timeIntervalSince1970, forKey: customEndKey)
    }
}

struct HistoryView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared
    @State private var selectedPeriod: Period = HistoryPrefs.savedPeriod()
    @State private var customStart: Date = HistoryPrefs.savedCustomStart()
    @State private var customEnd: Date = HistoryPrefs.savedCustomEnd()
    @State private var showCustomRange = false
    @State private var records: [DayRecord] = []
    @State private var foodByDay: [Date: Double] = [:]
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var animateContent = false
    @State private var showExportSheet = false
    @State private var showExportWarning = false
    @State private var showExportError = false
    @State private var csvFile: CSVFile?
    @State private var selectedCalorieDate: Date?
    @State private var selectedStepDate: Date?
    @State private var selectedNetDate: Date?
    @State private var loadErrorMessage: String? = nil

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

    private var hasNoData: Bool {
        records.isEmpty || records.allSatisfy { $0.totalCalories == 0 && $0.steps == 0 }
    }

    private var totalCalories: Double {
        records.map(\.totalCalories).reduce(0, +)
    }

    private var avgCalories: Double {
        guard !records.isEmpty else { return 0 }
        return totalCalories / Double(records.count)
    }

    private var totalSteps: Int {
        records.map(\.steps).reduce(0, +)
    }

    private var avgSteps: Int {
        guard !records.isEmpty else { return 0 }
        return totalSteps / records.count
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

    // MARK: - Net Deficit Helpers

    private func food(for date: Date) -> Double {
        let key = Calendar.current.startOfDay(for: date)
        return foodByDay[key] ?? 0
    }

    private func netDeficit(for record: DayRecord) -> Double {
        record.totalCalories - food(for: record.date)
    }

    /// Days that have any food logged — the only days where Net Deficit is meaningful.
    private var netRecords: [DayRecord] {
        records.filter { food(for: $0.date) > 0 }
    }

    private var hasNetData: Bool {
        !netRecords.isEmpty
    }

    private var totalNetDeficit: Double {
        netRecords.map { netDeficit(for: $0) }.reduce(0, +)
    }

    private var avgNetDeficit: Double {
        guard !netRecords.isEmpty else { return 0 }
        return totalNetDeficit / Double(netRecords.count)
    }

    private var bestNetDay: DayRecord? {
        netRecords.max(by: { netDeficit(for: $0) < netDeficit(for: $1) })
    }

    private func formatSignedNet(_ value: Double) -> String {
        let r = Int(value.rounded())
        return r > 0 ? "+\(r.formatted(.number))" : r.formatted(.number)
    }

    private func netColor(for value: Double) -> Color {
        value >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative
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

                if selectedPeriod == .custom {
                    Text("\(customStart, format: .dateTime.month(.abbreviated).day()) – \(customEnd, format: .dateTime.month(.abbreviated).day().year())")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                }

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(Theme.textTertiary)
                    Spacer()
                } else if let loadErrorMessage, records.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.textTertiary)
                        Text("Couldn't Load History")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        Text(loadErrorMessage)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Try Again") {
                            Task { await loadHistory() }
                        }
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Theme.caloriesPrimary)
                    }
                    Spacer()
                } else if hasNoData {
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
                            if let loadErrorMessage {
                                historyNoticeBanner(loadErrorMessage)
                            }

                            // Summary cards grouped by metric: Calories, Steps, Net Deficit
                            // Calories row
                            HStack(spacing: 12) {
                                AverageCard(
                                    label: "Total Calories",
                                    value: totalCalories.formatted(.number.precision(.fractionLength(0))),
                                    color: Theme.caloriesPrimary
                                )
                                AverageCard(
                                    label: "Avg Calories",
                                    value: avgCalories.formatted(.number.precision(.fractionLength(0))),
                                    color: Theme.caloriesPrimary
                                )
                            }

                            // Steps row
                            HStack(spacing: 12) {
                                AverageCard(
                                    label: "Total Steps",
                                    value: totalSteps.formatted(.number),
                                    color: Theme.stepsPrimary
                                )
                                AverageCard(
                                    label: "Avg Steps",
                                    value: avgSteps.formatted(.number),
                                    color: Theme.stepsPrimary
                                )
                            }

                            // Net Deficit row (if enabled)
                            if goals.showNetCalories && hasNetData {
                                HStack(spacing: 12) {
                                    AverageCard(
                                        label: "Total Deficit",
                                        value: formatSignedNet(totalNetDeficit),
                                        color: netColor(for: totalNetDeficit)
                                    )
                                    AverageCard(
                                        label: "Avg Deficit",
                                        value: formatSignedNet(avgNetDeficit),
                                        color: netColor(for: avgNetDeficit)
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

                            // Net Deficit chart
                            if goals.showNetCalories && hasNetData {
                                ChartCard(title: "Net Deficit", selection: selectedNetRecord) {
                                    netDeficitChart
                                }
                            }

                            CoachPromoCard()

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
                HistoryPrefs.save(period: selectedPeriod, customStart: customStart, customEnd: customEnd)
                Task { await loadHistory() }
            }
        }
        .onChange(of: goals.showNetCalories) { _, _ in
            Task { await loadHistory() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await loadHistory() }
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
                HistoryPrefs.save(period: .custom, customStart: customStart, customEnd: customEnd)
                Task { await loadHistory() }
            }
            .presentationDetents([.medium])
        }
        .alert("Export Health Data", isPresented: $showExportWarning) {
            Button("Export") {
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

    private var selectedNetRecord: ChartSelection? {
        guard let record = recordForDate(selectedNetDate), food(for: record.date) > 0 else { return nil }
        return ChartSelection(
            date: record.date,
            primary: ("Net", formatSignedNet(netDeficit(for: record)))
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

    private var netDeficitChart: some View {
        Chart(netRecords) { record in
            let value = netDeficit(for: record)
            BarMark(
                x: .value("Date", record.date, unit: .day),
                y: .value("Net", value)
            )
            .foregroundStyle(value >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative)
            .opacity(selectedNetDate == nil || Calendar.current.isDate(record.date, inSameDayAs: selectedNetDate!) ? 1.0 : 0.3)
            .cornerRadius(4)

            if netRecords.count > 1 {
                RuleMark(y: .value("Average", avgNetDeficit))
                    .foregroundStyle(Theme.netDeficitBrand.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
            }
        }
        .chartXSelection(value: $selectedNetDate)
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

    // MARK: - Helpers

    private var xAxisStride: Int {
        let count = records.count
        if count <= 10 { return 1 }
        if count <= 31 { return 5 }
        if count <= 91 { return 14 }
        return 30
    }

    private func historyNoticeBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caloriesPrimary)
                .padding(.top, 2)
            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func loadHistory() async {
        // Single-flight guard: the History view can be triggered by .task, pull-to-refresh,
        // foreground notifications, and period changes at the same time. Without a guard
        // these race into `records` and cause flicker / double HealthKit quota usage.
        guard !isRefreshing else { return }
        let isFirstLoad = records.isEmpty
        if isFirstLoad { isLoading = true }
        isRefreshing = true
        defer { isRefreshing = false }
        selectedCalorieDate = nil
        selectedStepDate = nil
        selectedNetDate = nil
        loadErrorMessage = nil

        // Dashboard is always the first screen users see and owns the auth-request
        // flow — here we just sync the cached state so `isAuthorized` is accurate
        // before we attempt the fetch. Calling `requestAuthorization` again could
        // trigger a duplicate permission sheet on fresh installs.
        await healthKit.synchronizeAuthorizationStateForFetching()

        do {
            let history: [(date: Date, active: Double, resting: Double, steps: Int)]
            if selectedPeriod == .custom {
                history = try await healthKit.fetchHistory(from: customStart, to: customEnd)
            } else {
                history = try await healthKit.fetchHistory(days: selectedPeriod.days ?? 7)
            }

            // Only fetch dietary history when Net Deficit is enabled; failure here is
            // non-fatal — calorie/step charts still render without it.
            var foodMap: [Date: Double] = [:]
            if goals.showNetCalories {
                do {
                    let dietary: [(date: Date, foodCalories: Double)]
                    if selectedPeriod == .custom {
                        dietary = try await healthKit.fetchDietaryHistory(from: customStart, to: customEnd)
                    } else {
                        dietary = try await healthKit.fetchDietaryHistory(days: selectedPeriod.days ?? 7)
                    }
                    let cal = Calendar.current
                    for day in dietary {
                        foodMap[cal.startOfDay(for: day.date)] = day.foodCalories
                    }
                } catch {
                    print("Failed to fetch dietary history: \(error)")
                }
            }

            withAnimation(.easeOut(duration: 0.3)) {
                records = history.map {
                    DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps)
                }
                foodByDay = foodMap
            }
            // Persist the fetched history to the shared cache so the watch can read it.
            try? healthKit.saveHistoryToCache(history: history)
        } catch {
            print("Failed to fetch history: \(error)")
            loadErrorMessage = records.isEmpty
                ? "Try again in a moment or check Apple Health access."
                : "Showing the last available data because refresh failed."
        }
        isLoading = false
        if !animateContent {
            withAnimation(.easeOut(duration: 0.4)) {
                animateContent = true
            }
        }
    }

    private func exportCSV() {
        // Force POSIX locale so that devices using non-Latin digit systems
        // (Arabic, Persian, Thai, etc.) still emit ASCII dates that CSV parsers expect.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        let columns = ["Date", "Active Calories", "Resting Calories", "Total Calories", "Steps"]
        let header = columns.map(Self.csvEscape).joined(separator: ",") + "\n"

        let rows = records.map { r -> String in
            let fields = [
                formatter.string(from: r.date),
                String(format: "%.0f", r.activeCalories),
                String(format: "%.0f", r.restingCalories),
                String(format: "%.0f", r.totalCalories),
                String(r.steps),
            ]
            return fields.map(Self.csvEscape).joined(separator: ",")
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

    /// RFC 4180 CSV escaping: double-quote any field that contains `,`, `"`, CR, or LF,
    /// and double internal quotes. Numeric/date fields pass through unchanged today,
    /// but routing every column through this helper prevents drift when we add text columns later.
    private static func csvEscape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuoting else { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
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

private struct AverageCard: View {
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
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
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
