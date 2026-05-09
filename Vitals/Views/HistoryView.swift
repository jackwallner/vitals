import SwiftUI
import Charts
import UniformTypeIdentifiers

@MainActor
private enum HistoryPrefs {
    private static let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
    private static let periodKey = "history.period"
    private static let customStartKey = "history.customStart"
    private static let customEndKey = "history.customEnd"
    private static let monthlySummaryGeneratedMonthKey = "history.monthlySummaryGeneratedMonth"

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

    static func generatedMonthlySummaryMonth() -> String? {
        defaults.string(forKey: monthlySummaryGeneratedMonthKey)
    }

    static func saveGeneratedMonthlySummaryMonth(_ date: Date = Date.now) {
        defaults.set(monthKey(for: date), forKey: monthlySummaryGeneratedMonthKey)
    }

    static func monthKey(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }
}

enum HistoryFocus: Equatable {
    case reports
    case customReports
    case deepTrends
}

struct HistoryView: View {
    let focus: HistoryFocus?

    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared
    @EnvironmentObject private var store: StoreService
    @State private var selectedPeriod: Period = HistoryPrefs.savedPeriod()
    @State private var customStart: Date = HistoryPrefs.savedCustomStart()
    @State private var customEnd: Date = HistoryPrefs.savedCustomEnd()
    @State private var showCustomRange = false
    @State private var records: [DayRecord] = []
    @State private var foodByDay: [Date: Double] = [:]
    @State private var previousRecords: [DayRecord] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var animateContent = false
    @State private var showExportSheet = false
    @State private var showExportWarning = false
    @State private var showExportError = false
    @State private var csvFile: CSVFile?
    @State private var pdfFile: PDFFile?
    @State private var pdfShareText = SummaryReportShareText.appStoreURL
    @State private var showPDFShareSheet = false
    @State private var showPaywall = false
    @State private var isGeneratingPDF = false
    @State private var pdfErrorMessage: String?
    @State private var selectedCalorieDate: Date?
    @State private var selectedStepDate: Date?
    @State private var selectedNetDate: Date?
    @State private var loadErrorMessage: String? = nil
    @State private var generateReportAfterCustomApply = false
    @State private var generatedMonthlySummaryMonth: String? = HistoryPrefs.generatedMonthlySummaryMonth()

    init(focus: HistoryFocus? = nil) {
        self.focus = focus
    }

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

    private var focusNotice: String? {
        switch focus {
        case .reports:
            return "Vitals+ reports are available in the tools section below."
        case .customReports:
            return "Custom reports are a Vitals+ feature. Choose a range from the tools section below."
        case .deepTrends:
            return "Deep Trends are highlighted below the charts for this history range."
        case nil:
            return nil
        }
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
        return Int((Double(totalSteps) / Double(records.count)).rounded())
    }

    private var currentMonthKey: String {
        HistoryPrefs.monthKey(for: Date.now)
    }

    private var shouldOfferMonthlySummary: Bool {
        store.isPro && generatedMonthlySummaryMonth != currentMonthKey && records.count >= 7
    }

    // MARK: - Chart Data (aggregated for longer periods)

    private var shouldAggregateByWeek: Bool {
        selectedPeriod == .threeMonths
    }

    private var shouldAggregateByMonth: Bool {
        selectedPeriod == .year
    }

    private var calorieChartData: [(date: Date, value: Double, id: UUID)] {
        if shouldAggregateByMonth {
            return aggregateByMonth(records: records).map { ($0.monthStart, $0.avgCalories, $0.id) }
        } else if shouldAggregateByWeek {
            return aggregateByWeek(records: records).map { ($0.weekStart, $0.avgCalories, $0.id) }
        } else {
            return records.map { ($0.date, $0.totalCalories, $0.id) }
        }
    }

    private var stepsChartData: [(date: Date, value: Double, id: UUID)] {
        if shouldAggregateByMonth {
            return aggregateByMonth(records: records).map { ($0.monthStart, Double($0.avgSteps), $0.id) }
        } else if shouldAggregateByWeek {
            return aggregateByWeek(records: records).map { ($0.weekStart, Double($0.avgSteps), $0.id) }
        } else {
            return records.map { ($0.date, Double($0.steps), $0.id) }
        }
    }

    private var chartAvgCalories: Double {
        let data = calorieChartData
        guard !data.isEmpty else { return 0 }
        return data.map(\.value).reduce(0, +) / Double(data.count)
    }

    private var chartAvgSteps: Double {
        let data = stepsChartData
        guard !data.isEmpty else { return 0 }
        return data.map(\.value).reduce(0, +) / Double(data.count)
    }

    private var netDeficitChartData: [(date: Date, value: Double, id: UUID)] {
        if shouldAggregateByMonth {
            let months = aggregateByMonth(records: netRecords)
            return months.map { month -> (Date, Double, UUID) in
                let netVals = netRecords.filter {
                    Calendar.current.isDate($0.date, equalTo: month.monthStart, toGranularity: .month)
                }.map { netDeficit(for: $0) }
                let avg = netVals.isEmpty ? 0.0 : netVals.reduce(0, +) / Double(netVals.count)
                return (month.monthStart, avg, month.id)
            }
        } else if shouldAggregateByWeek {
            let weeks = aggregateByWeek(records: netRecords)
            return weeks.map { week -> (Date, Double, UUID) in
                let netVals = netRecords.filter {
                    let weekStart = DateHelpers.startOfWeek($0.date)
                    return Calendar.current.isDate(weekStart, equalTo: week.weekStart, toGranularity: .day)
                }.map { netDeficit(for: $0) }
                let avg = netVals.isEmpty ? 0.0 : netVals.reduce(0, +) / Double(netVals.count)
                return (week.weekStart, avg, week.id)
            }
        } else {
            return netRecords.map { ($0.date, netDeficit(for: $0), $0.id) }
        }
    }

    private var chartAvgNetDeficit: Double {
        let data = netDeficitChartData
        guard !data.isEmpty else { return 0 }
        return data.map(\.value).reduce(0, +) / Double(data.count)
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

    private var netRecords: [DayRecord] {
        records.filter { $0.totalCalories > 0 }
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
                            handleSummaryReportTap()
                        } label: {
                            Image(systemName: store.isPro ? "doc.richtext" : "lock.doc.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.caloriesPrimary)
                                .frame(width: 22, height: 22)
                                .padding(10)
                                .background(Theme.cardSurface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.isPro ? "Generate summary report" : "Vitals Plus summary report (locked)")
                        .disabled(isGeneratingPDF)

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
                                if store.isPro {
                                    showCustomRange = true
                                } else {
                                    showPaywall = true
                                }
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
                    VStack(spacing: 14) {
                        LoadingBar(color: Theme.caloriesPrimary)
                            .frame(width: 180)
                        Text("Loading history…")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
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

                            if let focusNotice {
                                historyNoticeBanner(focusNotice, systemImage: "sparkles")
                            }

                            if shouldOfferMonthlySummary {
                                monthlySummaryPrompt
                            }

                            // Summary cards grouped by metric: Calories, Steps, Net Deficit
                            // Calories row
                            HStack(spacing: 12) {
                                AverageCard(
                                    label: "Avg Calories",
                                    value: avgCalories.formatted(.number.precision(.fractionLength(0))),
                                    color: Theme.caloriesPrimary
                                )
                                AverageCard(
                                    label: "Total Calories",
                                    value: totalCalories.formatted(.number.precision(.fractionLength(0))),
                                    color: Theme.caloriesPrimary
                                )
                            }

                            // Steps row
                            HStack(spacing: 12) {
                                AverageCard(
                                    label: "Avg Steps",
                                    value: avgSteps.formatted(.number),
                                    color: Theme.stepsPrimary
                                )
                                AverageCard(
                                    label: "Total Steps",
                                    value: totalSteps.formatted(.number),
                                    color: Theme.stepsPrimary
                                )
                            }

                            // Net Deficit row (if enabled)
                            if store.isPro && goals.showNetCalories && hasNetData {
                                HStack(spacing: 12) {
                                    AverageCard(
                                        label: "Avg Deficit",
                                        value: formatSignedNet(avgNetDeficit),
                                        color: netColor(for: avgNetDeficit)
                                    )
                                    AverageCard(
                                        label: "Total Deficit",
                                        value: formatSignedNet(totalNetDeficit),
                                        color: netColor(for: totalNetDeficit)
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
                            if store.isPro && goals.showNetCalories && hasNetData {
                                ChartCard(title: "Net Deficit", selection: selectedNetRecord) {
                                    netDeficitChart
                                }
                            }

                            historyVitalsPlusSection

                            DeepTrendsCard(
                                isPro: store.isPro,
                                insights: deepTrendInsights,
                                highlights: deepTrendHighlights,
                                periodLabel: deepTrendsPeriodLabel,
                                onUpgrade: { showPaywall = true }
                            )

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
        .onChange(of: healthKit.isAuthorized) { _, newValue in
            // Dashboard owns the auth grant flow; when it completes we may have
            // been sitting on an empty/zero state, so refresh as soon as auth
            // flips to true.
            if newValue {
                Task { await loadHistory() }
            }
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
                let shouldGenerate = generateReportAfterCustomApply
                generateReportAfterCustomApply = false
                Task {
                    await loadHistory()
                    if shouldGenerate {
                        await generateSummaryPDF()
                    }
                }
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showPDFShareSheet, onDismiss: {
            if let pdfFile {
                try? FileManager.default.removeItem(at: pdfFile.url)
                self.pdfFile = nil
            }
        }) {
            if let pdfFile {
                PDFPreviewSheet(title: reportTitle, url: pdfFile.url, shareText: pdfShareText)
            }
        }
        .alert("Report Failed", isPresented: Binding(get: { pdfErrorMessage != nil }, set: { if !$0 { pdfErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pdfErrorMessage ?? "")
        }
        .overlay(alignment: .center) {
            if isGeneratingPDF {
                VStack(spacing: 12) {
                    LoadingBar(color: Theme.caloriesPrimary)
                        .frame(width: 180)
                    Text("Generating report…")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(20)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
    }

    private var historyVitalsPlusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.caloriesPrimary)
                Text("Vitals+ Tools")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(store.isPro ? "Active" : "Premium")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.caloriesPrimary.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.caloriesPrimary)
            }

            VitalsPlusHistoryRow(
                icon: "doc.richtext.fill",
                title: "Monthly Summary PDF",
                detail: "Generate a 30-day report and preview it before sharing.",
                buttonTitle: store.isPro ? "Generate Report" : "Unlock Reports",
                locked: !store.isPro
            ) {
                handleSummaryReportTap()
            }

            VitalsPlusHistoryRow(
                icon: "calendar.badge.clock",
                title: "Custom Reports",
                detail: "The standard date selector is free. Custom paid ranges unlock with Vitals+.",
                buttonTitle: store.isPro ? "Choose & Generate" : "Unlock Custom",
                locked: !store.isPro
            ) {
                if store.isPro {
                    generateReportAfterCustomApply = true
                    showCustomRange = true
                } else {
                    showPaywall = true
                }
            }

            VitalsPlusHistoryRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Deep Trends",
                detail: "Compare this range against the previous period below.",
                buttonTitle: store.isPro ? "Visible Below" : "Unlock Trends",
                locked: !store.isPro
            ) {
                if !store.isPro {
                    showPaywall = true
                }
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var monthlySummaryPrompt: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.caloriesPrimary)
                .frame(width: 30, height: 30)
                .background(Theme.caloriesPrimary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text("Your monthly summary is ready")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Generate a fresh 30-day PDF once a month, then preview or share it.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Generate") {
                Task { await generateSummaryPDF(markMonthlyGenerated: true, forcedTitle: "Monthly Summary") }
            }
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.caloriesGradient, in: Capsule())
            .disabled(isGeneratingPDF)
        }
        .padding(14)
        .background(Theme.caloriesPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.caloriesPrimary.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Vitals+ Summary Report

    private func handleSummaryReportTap() {
        if !store.isPro {
            showPaywall = true
            return
        }
        Task { await generateSummaryPDF() }
    }

    private func generateSummaryPDF(markMonthlyGenerated: Bool = false, forcedTitle: String? = nil) async {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        try? await Task.sleep(nanoseconds: 100_000_000)

        let reportDays: [ReportDay] = records.map { rec in
            ReportDay(
                date: rec.date,
                activeCalories: rec.activeCalories,
                restingCalories: rec.restingCalories,
                steps: rec.steps,
                foodCalories: foodByDay[Calendar.current.startOfDay(for: rec.date)]
            )
        }
        let prevDays: [ReportDay] = previousRecords.map { rec in
            ReportDay(
                date: rec.date,
                activeCalories: rec.activeCalories,
                restingCalories: rec.restingCalories,
                steps: rec.steps,
                foodCalories: nil
            )
        }
        let start = records.map(\.date).min() ?? Date.now
        let end = records.map(\.date).max() ?? Date.now

        let report = SummaryReportGenerator.make(
            title: forcedTitle ?? reportTitle,
            periodStart: start,
            periodEnd: end,
            days: reportDays,
            previousDays: prevDays,
            calorieGoal: goals.calorieGoal,
            stepGoal: goals.stepGoal
        )

        do {
            let url = try SummaryReportPDF.render(report)
            pdfFile = PDFFile(url: url)
            pdfShareText = SummaryReportShareText.make(report: report)
            if markMonthlyGenerated {
                HistoryPrefs.saveGeneratedMonthlySummaryMonth()
                generatedMonthlySummaryMonth = currentMonthKey
            }
            showPDFShareSheet = true
        } catch {
            pdfErrorMessage = "Could not generate the PDF report. Please try again."
        }
    }

    private var reportTitle: String {
        switch selectedPeriod {
        case .week: return "7-Day Summary"
        case .month: return "30-Day Summary"
        case .threeMonths: return "90-Day Summary"
        case .year: return "Annual Summary"
        case .custom: return "Vitals Summary"
        }
    }

    // MARK: - Deep Trends (Vitals+)

    private var deepTrendsPeriodLabel: String {
        switch selectedPeriod {
        case .week: return "vs. previous week"
        case .month: return "vs. previous 30 days"
        case .threeMonths: return "vs. previous 90 days"
        case .year: return "vs. previous year"
        case .custom: return "vs. previous range"
        }
    }

    private var previousAverageCalories: Double? {
        let prevNonZero = previousRecords.filter { $0.totalCalories > 0 }
        guard !prevNonZero.isEmpty else { return nil }
        return prevNonZero.map(\.totalCalories).reduce(0, +) / Double(prevNonZero.count)
    }

    private var previousAverageSteps: Double? {
        let prevNonZero = previousRecords.filter { $0.steps > 0 }
        guard !prevNonZero.isEmpty else { return nil }
        return Double(prevNonZero.map(\.steps).reduce(0, +)) / Double(prevNonZero.count)
    }

    private var deepTrendInsights: [DeepTrendInsight] {
        var insights: [DeepTrendInsight] = []
        if let prev = previousAverageCalories, prev > 0 {
            let delta = avgCalories - prev
            let percent = (delta / prev) * 100
            insights.append(
                DeepTrendInsight(
                    title: "Calories",
                    icon: "flame.fill",
                    current: avgCalories.formatted(.number.precision(.fractionLength(0))),
                    previous: prev.formatted(.number.precision(.fractionLength(0))),
                    change: signedValue(delta.formatted(.number.precision(.fractionLength(0)))),
                    percent: signedPercent(percent),
                    narrative: abs(delta) < 1 ? "Calories held steady day-to-day." : "You averaged \(abs(Int(delta.rounded())).formatted(.number)) \(delta >= 0 ? "more" : "fewer") calories per day.",
                    color: Theme.caloriesPrimary,
                    isUp: delta >= 0
                )
            )
        }
        if let prev = previousAverageSteps, prev > 0 {
            let current = Double(avgSteps)
            let delta = current - prev
            let percent = (delta / prev) * 100
            insights.append(
                DeepTrendInsight(
                    title: "Steps",
                    icon: "figure.walk",
                    current: avgSteps.formatted(.number),
                    previous: Int(prev.rounded()).formatted(.number),
                    change: signedValue(Int(delta.rounded()).formatted(.number)),
                    percent: signedPercent(percent),
                    narrative: abs(delta) < 1 ? "Steps held steady day-to-day." : "You averaged \(abs(Int(delta.rounded())).formatted(.number)) \(delta >= 0 ? "more" : "fewer") steps per day.",
                    color: Theme.stepsPrimary,
                    isUp: delta >= 0
                )
            )
        }
        return insights
    }

    private var deepTrendHighlights: [String] {
        var highlights: [String] = []
        let activeDays = records.filter { $0.totalCalories > 0 || $0.steps > 0 }.count
        if !records.isEmpty {
            highlights.append("\(activeDays) of \(records.count) days had calories or steps logged.")
        }
        if let peakCalorieDay {
            highlights.append("Peak calories: \(peakCalorieDay.totalCalories.formatted(.number.precision(.fractionLength(0)))) on \(DateHelpers.shortDate(peakCalorieDay.date)).")
        }
        if let peakStepDay {
            highlights.append("Peak steps: \(peakStepDay.steps.formatted(.number)) on \(DateHelpers.shortDate(peakStepDay.date)).")
        }
        return highlights
    }

    private func signedValue(_ value: String) -> String {
        value.hasPrefix("-") ? value : "+\(value)"
    }

    private func signedPercent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded >= 0 ? "+\(rounded)%" : "\(rounded)%"
    }

    private var deepCalorieTrend: Double? {
        let curr = avgCalories
        guard let prev = previousAverageCalories else { return nil }
        guard prev > 0 else { return nil }
        return ((curr - prev) / prev) * 100
    }

    private var deepStepTrend: Double? {
        let curr = Double(avgSteps)
        guard let prev = previousAverageSteps else { return nil }
        guard prev > 0 else { return nil }
        return ((curr - prev) / prev) * 100
    }

    // MARK: - Chart Views

    private var selectedCalorieRecord: ChartSelection? {
        guard let item = selectedChartItem(for: selectedCalorieDate, in: calorieChartData) else { return nil }
        return ChartSelection(
            date: item.date,
            primary: ("Calories", selectedChartValue(item.value.formatted(.number.precision(.fractionLength(0))))),
            dateLabel: selectedChartDateLabel(for: item.date)
        )
    }

    private var selectedStepRecord: ChartSelection? {
        guard let item = selectedChartItem(for: selectedStepDate, in: stepsChartData) else { return nil }
        return ChartSelection(
            date: item.date,
            primary: ("Steps", selectedChartValue(Int(item.value.rounded()).formatted(.number))),
            dateLabel: selectedChartDateLabel(for: item.date)
        )
    }

    private var selectedNetRecord: ChartSelection? {
        guard let item = selectedChartItem(for: selectedNetDate, in: netDeficitChartData) else { return nil }
        return ChartSelection(
            date: item.date,
            primary: ("Net", selectedChartValue(formatSignedNet(item.value))),
            dateLabel: selectedChartDateLabel(for: item.date)
        )
    }

    private var caloriesChart: some View {
        Chart(calorieChartData, id: \.id) { item in
            BarMark(
                x: .value("Date", item.date, unit: chartDateUnit),
                y: .value("Calories", item.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.caloriesPrimary, Theme.caloriesSecondary],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .opacity(selectedCalorieDate == nil || Calendar.current.isDate(item.date, equalTo: selectedCalorieDate!, toGranularity: chartDateGranularity) ? 1.0 : 0.3)
            .cornerRadius(4)

            if calorieChartData.count > 1 {
                RuleMark(y: .value("Average", chartAvgCalories))
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
            AxisMarks(values: .stride(by: chartXAxisStrideBy, count: chartXAxisStrideCount)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(chartDateLabel(date))
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
        Chart(stepsChartData, id: \.id) { item in
            BarMark(
                x: .value("Date", item.date, unit: chartDateUnit),
                y: .value("Steps", item.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.stepsPrimary, Theme.stepsSecondary],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .opacity(selectedStepDate == nil || Calendar.current.isDate(item.date, equalTo: selectedStepDate!, toGranularity: chartDateGranularity) ? 1.0 : 0.3)
            .cornerRadius(4)

            if stepsChartData.count > 1 {
                RuleMark(y: .value("Average", chartAvgSteps))
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
            AxisMarks(values: .stride(by: chartXAxisStrideBy, count: chartXAxisStrideCount)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(chartDateLabel(date))
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

    private var netDeficitChart: some View {
        Chart(netDeficitChartData, id: \.id) { item in
            let value = item.value
            BarMark(
                x: .value("Date", item.date, unit: chartDateUnit),
                y: .value("Net", value)
            )
            .foregroundStyle(value >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative)
            .opacity(selectedNetDate == nil || Calendar.current.isDate(item.date, equalTo: selectedNetDate!, toGranularity: chartDateGranularity) ? 1.0 : 0.3)
            .cornerRadius(4)

            if netDeficitChartData.count > 1 {
                RuleMark(y: .value("Average", chartAvgNetDeficit))
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
            AxisMarks(values: .stride(by: chartXAxisStrideBy, count: chartXAxisStrideCount)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(chartDateLabel(date))
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

    private var chartDateUnit: Calendar.Component {
        if shouldAggregateByMonth { return .month }
        if shouldAggregateByWeek { return .weekOfYear }
        return .day
    }

    private var chartDateGranularity: Calendar.Component {
        if shouldAggregateByMonth { return .month }
        if shouldAggregateByWeek { return .weekOfYear }
        return .day
    }

    private func selectedChartItem(for selectedDate: Date?, in data: [(date: Date, value: Double, id: UUID)]) -> (date: Date, value: Double, id: UUID)? {
        guard let selectedDate else { return nil }
        let calendar = Calendar.current
        if let exactBucket = data.first(where: { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: chartDateGranularity) }) {
            return exactBucket
        }
        return data.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func selectedChartDateLabel(for date: Date) -> String? {
        if shouldAggregateByMonth {
            return DateHelpers.monthYear(date)
        }
        if shouldAggregateByWeek {
            return "Week of \(DateHelpers.mediumDate(date))"
        }
        return nil
    }

    private func selectedChartValue(_ value: String) -> String {
        if shouldAggregateByMonth || shouldAggregateByWeek {
            return "Avg \(value)"
        }
        return value
    }

    private var chartXAxisStrideBy: Calendar.Component {
        if shouldAggregateByMonth { return .month }
        if shouldAggregateByWeek { return .weekOfYear }
        return .day
    }

    private var chartXAxisStrideCount: Int {
        if shouldAggregateByMonth {
            return 1  // Every month
        }
        if shouldAggregateByWeek {
            return 2  // Every 2 weeks for 90-day view
        }
        let count = records.count
        if count <= 10 { return 1 }
        if count <= 31 { return 5 }
        if count <= 91 { return 14 }
        return 30
    }

    private func chartDateLabel(_ date: Date) -> String {
        if shouldAggregateByMonth {
            return DateHelpers.shortMonth(date)
        }
        if shouldAggregateByWeek {
            return DateHelpers.mediumDate(date)
        }
        return DateHelpers.shortDate(date)
    }

    private func historyNoticeBanner(_ message: String, systemImage: String = "exclamationmark.triangle.fill") -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
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
        isRefreshing = true
        defer { isRefreshing = false }
        selectedCalorieDate = nil
        selectedStepDate = nil
        selectedNetDate = nil
        loadErrorMessage = nil

        // Cache prime: paint instantly from SwiftData when we have any cached
        // data for this period. HealthKit refresh below overwrites with fresh
        // values when they arrive, so the user never stares at a blank spinner
        // on returning visits. Only applies to fixed periods — custom ranges
        // skip the cache (uncommon path, not worth a from/to overload).
        if records.isEmpty, let days = selectedPeriod.days,
           let cached = try? healthKit.fetchCachedHistory(days: days),
           cached.contains(where: { $0.active > 0 || $0.resting > 0 || $0.steps > 0 }) {
            records = cached.map {
                DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps)
            }
            isLoading = false
            if !animateContent {
                withAnimation(.easeOut(duration: 0.4)) { animateContent = true }
            }
        }

        let isFirstLoad = records.isEmpty
        if isFirstLoad { isLoading = true }

        // Dashboard exclusively owns the HealthKit auth-request flow. Calling
        // synchronizeAuthorizationStateForFetching here previously raced the
        // dashboard's permission sheet on fresh installs and left this load
        // pending forever. We rely on the `.onChange(of: healthKit.isAuthorized)`
        // observer below to reload once Dashboard finishes its grant.

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
            if store.isPro && goals.showNetCalories {
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

            // Fire-and-forget: load the immediately preceding window for trend
            // calculations. Failure here is silent — the deep trends card just
            // shows an empty state and the report skips trend pills.
            await loadPreviousWindow(history: history)
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

    /// Load the window of equal length preceding the current selection, used for
    /// period-over-period trend calculations on the Deep Trends card and PDF report.
    private func loadPreviousWindow(history: [(date: Date, active: Double, resting: Double, steps: Int)]) async {
        let cal = Calendar.current
        let currentStart: Date
        let lengthDays: Int
        switch selectedPeriod {
        case .week, .month, .threeMonths, .year:
            lengthDays = selectedPeriod.days ?? 0
            currentStart = DateHelpers.daysAgo(max(lengthDays - 1, 0))
        case .custom:
            lengthDays = max(1, cal.dateComponents([.day], from: customStart, to: customEnd).day ?? 0) + 1
            currentStart = cal.startOfDay(for: customStart)
        }
        guard lengthDays > 0 else {
            previousRecords = []
            return
        }
        let priorEnd = cal.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
        let priorStart = cal.date(byAdding: .day, value: -(lengthDays - 1), to: priorEnd) ?? priorEnd
        do {
            let prev = try await healthKit.fetchHistory(from: priorStart, to: priorEnd)
            previousRecords = prev.map {
                DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps)
            }
        } catch {
            previousRecords = []
        }
    }

    private func exportCSV() {
        // Force POSIX locale so that devices using non-Latin digit systems
        // (Arabic, Persian, Thai, etc.) still emit ASCII dates that CSV parsers expect.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        let includeNet = store.isPro && goals.showNetCalories
        let columns = includeNet
            ? ["Date", "Active Calories", "Resting Calories", "Total Calories", "Steps", "Food Calories", "Net Deficit"]
            : ["Date", "Active Calories", "Resting Calories", "Total Calories", "Steps"]
        let header = columns.map(Self.csvEscape).joined(separator: ",") + "\n"

        let rows = records.map { r -> String in
            var fields = [
                formatter.string(from: r.date),
                String(format: "%.0f", r.activeCalories),
                String(format: "%.0f", r.restingCalories),
                String(format: "%.0f", r.totalCalories),
                String(r.steps),
            ]
            if includeNet {
                let foodCalories = food(for: r.date)
                fields.append(String(format: "%.0f", foodCalories))
                fields.append(String(format: "%.0f", r.totalCalories - foodCalories))
            }
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
    private let dateLabelOverride: String?

    init(date: Date, primary: (label: String, value: String), dateLabel: String? = nil) {
        self.date = date
        self.primary = primary
        self.dateLabelOverride = dateLabel
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var dateLabel: String {
        dateLabelOverride ?? Self.dateFormatter.string(from: date)
    }
}


// MARK: - CSV File

struct CSVFile {
    let url: URL
}

struct PDFFile {
    let url: URL
}

// MARK: - Deep Trends Card (Vitals+)

private struct VitalsPlusHistoryRow: View {
    let icon: String
    let title: String
    let detail: String
    let buttonTitle: String
    let locked: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: locked ? "lock.fill" : icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.caloriesPrimary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.caloriesGradient, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.cardSurfaceLight, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DeepTrendInsight: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let current: String
    let previous: String
    let change: String
    let percent: String
    let narrative: String
    let color: Color
    let isUp: Bool
}

private struct DeepTrendsCard: View {
    let isPro: Bool
    let insights: [DeepTrendInsight]
    let highlights: [String]
    let periodLabel: String
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: isPro ? "chart.line.uptrend.xyaxis" : "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.caloriesPrimary)
                Text("Deep Trends")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(isPro ? "Active" : "Vitals+")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.caloriesPrimary.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.caloriesPrimary)
            }

            Text(periodLabel)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)

            if isPro {
                if insights.isEmpty {
                    Text("Deep Trends need a previous matching range with calories or steps before they can compare your momentum.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 12) {
                        ForEach(insights) { insight in
                            DeepTrendInsightRow(insight: insight)
                        }
                    }
                    if !highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(highlights, id: \.self) { highlight in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.caloriesPrimary)
                                        .padding(.top, 2)
                                    Text(highlight)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Compare this period against the matching previous range with current averages, prior averages, absolute deltas, percent movement, and peak-day highlights.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onUpgrade) {
                        Text("Unlock with Vitals+")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.caloriesGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

private struct DeepTrendInsightRow: View {
    let insight: DeepTrendInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: insight.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(insight.color)
                    .frame(width: 28, height: 28)
                    .background(insight.color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.title)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(insight.narrative)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: insight.isUp ? "arrow.up.right" : "arrow.down.right")
                    Text(insight.percent)
                }
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(insight.isUp ? Theme.netDeficitPositive : Theme.netDeficitNegative)
            }

            HStack(spacing: 8) {
                DeepTrendMiniStat(label: "Current", value: insight.current)
                DeepTrendMiniStat(label: "Previous", value: insight.previous)
                DeepTrendMiniStat(label: "Change", value: insight.change)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(insight.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DeepTrendMiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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

/// Indeterminate animated linear bar — used in place of the system spinner
/// so users see something *moving* during initial loads. A spinner reads as
/// frozen on slow HealthKit fetches; a sweeping bar reads as live.
struct LoadingBar: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let segmentWidth = max(width * 0.35, 60)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(
                        colors: [color.opacity(0), color, color.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: segmentWidth)
                    .offset(x: animating ? width : -segmentWidth)
            }
        }
        .frame(height: 4)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
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

// MARK: - Aggregated Data for Charts

struct WeekRecord: Identifiable {
    let id = UUID()
    let weekStart: Date
    let totalCalories: Double
    let avgCalories: Double
    let totalSteps: Int
    let avgSteps: Int
    let dayCount: Int
}

struct MonthRecord: Identifiable {
    let id = UUID()
    let monthStart: Date
    let totalCalories: Double
    let avgCalories: Double
    let totalSteps: Int
    let avgSteps: Int
    let dayCount: Int
}

// MARK: - Aggregation Helpers

private func aggregateByWeek(records: [DayRecord], calendar: Calendar = .current) -> [WeekRecord] {
    let grouped = Dictionary(grouping: records) { DateHelpers.startOfWeek($0.date, calendar: calendar) }
    return grouped.sorted { $0.key < $1.key }.map { weekStart, days in
        let totalCal = days.map(\.totalCalories).reduce(0, +)
        let totalStp = days.map(\.steps).reduce(0, +)
        let nonZeroCal = days.filter { $0.totalCalories > 0 }
        let nonZeroStp = days.filter { $0.steps > 0 }
        return WeekRecord(
            weekStart: weekStart,
            totalCalories: totalCal,
            avgCalories: nonZeroCal.isEmpty ? 0 : nonZeroCal.map(\.totalCalories).reduce(0, +) / Double(nonZeroCal.count),
            totalSteps: totalStp,
            avgSteps: nonZeroStp.isEmpty ? 0 : nonZeroStp.map(\.steps).reduce(0, +) / nonZeroStp.count,
            dayCount: days.count
        )
    }
}

private func aggregateByMonth(records: [DayRecord], calendar: Calendar = .current) -> [MonthRecord] {
    let grouped = Dictionary(grouping: records) { DateHelpers.startOfMonth($0.date, calendar: calendar) }
    return grouped.sorted { $0.key < $1.key }.map { monthStart, days in
        let totalCal = days.map(\.totalCalories).reduce(0, +)
        let totalStp = days.map(\.steps).reduce(0, +)
        let nonZeroCal = days.filter { $0.totalCalories > 0 }
        let nonZeroStp = days.filter { $0.steps > 0 }
        return MonthRecord(
            monthStart: monthStart,
            totalCalories: totalCal,
            avgCalories: nonZeroCal.isEmpty ? 0 : nonZeroCal.map(\.totalCalories).reduce(0, +) / Double(nonZeroCal.count),
            totalSteps: totalStp,
            avgSteps: nonZeroStp.isEmpty ? 0 : nonZeroStp.map(\.steps).reduce(0, +) / nonZeroStp.count,
            dayCount: days.count
        )
    }
}
