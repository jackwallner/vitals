import SwiftUI
import Charts
import UniformTypeIdentifiers
import os

private let historyLogger = Logger(subsystem: "com.jackwallner.vitals", category: "History")

extension Notification.Name {
    /// Posted when the History tab finishes a successful data load. Drives the
    /// second-touch Vitals+ trial nudge in MainTabView.
    static let vitalsHistoryDidFinishLoading = Notification.Name("vitalsHistoryDidFinishLoading")

    /// Posted when the Today dashboard finishes painting its first real data
    /// (numbers + ring on screen). The passive launch trial nudge waits ~5s from
    /// this so the pitch lands after the user sees their dashboard, not before.
    static let vitalsDashboardDidLoadData = Notification.Name("vitalsDashboardDidLoadData")

    /// Posted by the "What's New" sheet's Open Settings CTA (Pro users) so the
    /// dashboard can present its Settings sheet for the user to opt into extras.
    static let vitalsOpenSettings = Notification.Name("vitalsOpenSettings")
}

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

struct HistoryView: View {
    /// When set, the view renders a single-metric detail screen (pushed from a
    /// Dashboard row or a History chart card) instead of the full History tab.
    var focusMetric: HistoryMetric? = nil

    @Environment(\.scenePhase) var scenePhase
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
    @State private var loadToken: Int = 0
    @State private var inflightLoads: Int = 0
    @State private var isCalculatingTrends = false
    @State private var animateContent = false
    @State private var showExportSheet = false
    @State private var showExportWarning = false
    @State private var showExportError = false
    @State private var csvFile: CSVFile?
    @State private var pdfFile: PDFFile?
    @State private var pdfShareText = SummaryReportShareText.appStoreURL
    @State private var showPDFShareSheet = false
    @State private var isGeneratingPDF = false
    @State private var pdfErrorMessage: String?
    @State private var selectedCalorieDate: Date?
    @State private var selectedStepDate: Date?
    @State private var selectedNetDate: Date?
    @State private var loadErrorMessage: String? = nil
    @State private var generateReportAfterCustomApply = false
    @State private var generatedMonthlySummaryMonth: String? = HistoryPrefs.generatedMonthlySummaryMonth()

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

    /// Symmetric around zero so 0 always sits at the vertical center of the chart —
    /// otherwise Swift Charts fits the domain to the data's min/max, which (for
    /// all-positive deficits) pushes 0 to the bottom edge and makes the average look
    /// like the "center" of the chart instead.
    private var netDeficitChartYDomain: ClosedRange<Double> {
        let maxAbs = netDeficitChartData.map { abs($0.value) }.max() ?? 0
        let padded = max(maxAbs, abs(chartAvgNetDeficit)) * 1.15
        guard padded > 0 else { return -100...100 }
        return -padded...padded
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

    /// Returns logged food calories for `date`, or `nil` when no dietary entry exists.
    /// A zero entry counts as logged-zero, distinct from "not logged."
    private func food(for date: Date) -> Double? {
        let key = Calendar.current.startOfDay(for: date)
        return foodByDay[key]
    }

    private func hasFoodLogged(_ record: DayRecord) -> Bool {
        // `fetchDietaryHistory` zero-fills every day, so `food(for:)` is 0 (not nil)
        // on unlogged days — a positive value is the only reliable "food was logged"
        // signal. Testing nil-vs-0 silently let unlogged days through.
        (food(for: record.date) ?? 0) > 0
    }

    private func netDeficit(for record: DayRecord) -> Double {
        record.totalCalories - (food(for: record.date) ?? 0)
    }

    /// Net Deficit excludes days with no food logged (an unlogged day would read as a
    /// full-burn "deficit" and skew the chart and averages) — unless the user turns on
    /// Net Deficit Fasting Mode, which counts those unlogged days as real deficits.
    private var netRecords: [DayRecord] {
        records.filter { $0.totalCalories > 0 && (goals.netDeficitFastingMode || hasFoodLogged($0)) }
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

    @ViewBuilder
    var body: some View {
        if let focusMetric {
            focusedBody(focusMetric)
        } else {
            NavigationStack {
                fullBody
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: HistoryMetric.self) { metric in
                        HistoryView(focusMetric: metric)
                            .environmentObject(store)
                    }
            }
        }
    }

    private var fullBody: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with export
                HStack {
                    Text("History")
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)
                    if inflightLoads > 0 && !isLoading {
                        LoadingBar(color: Theme.caloriesPrimary)
                            .frame(width: 80)
                            .padding(.leading, 8)
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
                        SegmentButton(
                            title: period.rawValue,
                            isSelected: selectedPeriod == period,
                            locked: period == .custom && !store.isPro
                        ) {
                            if period == .custom {
                                if store.isPro {
                                    showCustomRange = true
                                } else {
                                    TrialOfferCoordinator.shared.request(.lockedCustomRange)
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
                            ChartCard(title: "Calories", selection: selectedCalorieRecord, metricLink: .calories) {
                                caloriesChart
                            }

                            // Steps chart
                            ChartCard(title: "Steps", selection: selectedStepRecord, metricLink: .steps) {
                                stepsChart
                            }

                            // Net Deficit chart — when enabled, always present so the
                            // section is discoverable: skeleton while food data loads,
                            // empty state when no days have food logged, else the chart.
                            if store.isPro && goals.showNetCalories {
                                ChartCard(title: "Net Deficit", selection: hasNetData ? selectedNetRecord : nil, metricLink: .net) {
                                    netDeficitCardContent
                                }
                            }

                            DeepTrendsCard(
                                isPro: store.isPro,
                                isCalculating: isCalculatingTrends && previousRecords.isEmpty,
                                insights: store.isPro ? deepTrendInsights : DeepTrendsBuilder.teaserInsights(currentRecords: records),
                                highlights: store.isPro ? deepTrendHighlights : DeepTrendsBuilder.teaserHighlights(records: records),
                                periodLabel: deepTrendsPeriodLabel,
                                onUpgrade: { TrialOfferCoordinator.shared.request(.deepTrendsUpgrade) }
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
                resetForReload()
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
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
            await checkMonthReviewMilestone()
        }
        .sheet(isPresented: $showCustomRange) {
            CustomRangeSheet(start: $customStart, end: $customEnd) {
                selectedPeriod = .custom
                showCustomRange = false
                HistoryPrefs.save(period: .custom, customStart: customStart, customEnd: customEnd)
                let shouldGenerate = generateReportAfterCustomApply
                generateReportAfterCustomApply = false
                resetForReload()
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
                Task { await generateMonthlySummaryPDF() }
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
            TrialOfferCoordinator.shared.request(.lockedSummaryReport)
            return
        }
        Task { await generateSummaryPDF() }
    }

    private func generateSummaryPDF() async {
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
            title: reportTitle,
            periodStart: start,
            periodEnd: end,
            days: reportDays,
            previousDays: prevDays,
            calorieGoal: goals.calorieGoal,
            stepGoal: goals.stepGoal,
            netDeficitFastingMode: goals.netDeficitFastingMode
        )

        do {
            let url = try SummaryReportPDF.render(report)
            pdfFile = PDFFile(url: url)
            pdfShareText = SummaryReportShareText.make(report: report)
            showPDFShareSheet = true
        } catch {
            pdfErrorMessage = "Could not generate the PDF report. Please try again."
        }
    }

    /// Always pulls a fresh 30-day window so the "Monthly Summary" PDF matches the
    /// title even when the user is currently viewing 7D/90D/1Y/Custom.
    private func generateMonthlySummaryPDF() async {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        try? await Task.sleep(nanoseconds: 100_000_000)

        do {
            let history = try await healthKit.fetchHistory(days: 30)
            let calendar = Calendar.current
            let priorEnd = calendar.date(byAdding: .day, value: -1, to: history.first?.date ?? DateHelpers.daysAgo(29)) ?? Date.now
            let priorStart = calendar.date(byAdding: .day, value: -29, to: priorEnd) ?? priorEnd
            let previous = (try? await healthKit.fetchHistory(from: priorStart, to: priorEnd)) ?? []

            var foodMap: [Date: Double] = [:]
            if goals.showNetCalories {
                if let dietary = try? await healthKit.fetchDietaryHistory(days: 30) {
                    for day in dietary {
                        foodMap[calendar.startOfDay(for: day.date)] = day.foodCalories
                    }
                }
            }

            let reportDays = history.map { rec in
                ReportDay(
                    date: rec.date,
                    activeCalories: rec.active,
                    restingCalories: rec.resting,
                    steps: rec.steps,
                    foodCalories: foodMap[calendar.startOfDay(for: rec.date)]
                )
            }
            let previousDays = previous.map { rec in
                ReportDay(
                    date: rec.date,
                    activeCalories: rec.active,
                    restingCalories: rec.resting,
                    steps: rec.steps,
                    foodCalories: nil
                )
            }
            let start = history.map(\.date).min() ?? DateHelpers.daysAgo(29)
            let end = history.map(\.date).max() ?? Date.now

            let report = SummaryReportGenerator.make(
                title: "Monthly Summary",
                periodStart: start,
                periodEnd: end,
                days: reportDays,
                previousDays: previousDays,
                calorieGoal: goals.calorieGoal,
                stepGoal: goals.stepGoal,
                netDeficitFastingMode: goals.netDeficitFastingMode
            )
            let url = try SummaryReportPDF.render(report)
            pdfFile = PDFFile(url: url)
            pdfShareText = SummaryReportShareText.make(report: report)
            HistoryPrefs.saveGeneratedMonthlySummaryMonth()
            generatedMonthlySummaryMonth = currentMonthKey
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
        DeepTrendsBuilder.insights(currentRecords: records, previousRecords: previousRecords)
    }

    private var deepTrendHighlights: [String] {
        DeepTrendsBuilder.highlights(records: records)
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

            // Solid zero baseline so deficit (up) vs surplus (down) reads off a
            // fixed reference — distinct from the dashed "avg" line below.
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Theme.textTertiary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1))

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
        .chartYScale(domain: netDeficitChartYDomain)
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

    @ViewBuilder
    private var netDeficitCardContent: some View {
        if hasNetData {
            netDeficitChart
        } else if inflightLoads > 0 {
            SkeletonBlock()
                .frame(minHeight: 180, maxHeight: 240)
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.textTertiary)
                Text("No food logged this period")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("Log meals in Apple Health to see your net deficit (calories burned minus eaten).")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Focused single-metric detail

    private var periodSelectorBar: some View {
        HStack(spacing: 0) {
            ForEach(Period.allCases, id: \.self) { period in
                SegmentButton(
                    title: period.rawValue,
                    isSelected: selectedPeriod == period,
                    locked: period == .custom && !store.isPro
                ) {
                    if period == .custom {
                        if store.isPro {
                            showCustomRange = true
                        } else {
                            TrialOfferCoordinator.shared.request(.lockedCustomRange)
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
    }

    private func focusedBody(_ metric: HistoryMetric) -> some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                periodSelectorBar
                    .padding(.top, 12)

                if selectedPeriod == .custom {
                    Text("\(customStart, format: .dateTime.month(.abbreviated).day()) – \(customEnd, format: .dateTime.month(.abbreviated).day().year())")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                }

                if inflightLoads > 0 && !isLoading {
                    LoadingBar(color: metric.tint)
                        .frame(width: 120)
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                if isLoading {
                    Spacer()
                    VStack(spacing: 14) {
                        LoadingBar(color: metric.tint)
                            .frame(width: 180)
                        Text("Loading…")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            focusedSummaryCards(metric)
                            focusedChartCard(metric)
                            RecentDaysList(metric: metric, rows: recentDayRows(metric))
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
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHistory() }
        .onChange(of: selectedPeriod) { _, _ in
            if selectedPeriod != .custom {
                HistoryPrefs.save(period: selectedPeriod, customStart: customStart, customEnd: customEnd)
                resetForReload()
                Task { await loadHistory() }
            }
        }
        .onChange(of: goals.showNetCalories) { _, _ in
            Task { await loadHistory() }
        }
        .onChange(of: healthKit.isAuthorized) { _, newValue in
            if newValue { Task { await loadHistory() } }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await loadHistory() } }
        }
        .sheet(isPresented: $showCustomRange) {
            CustomRangeSheet(start: $customStart, end: $customEnd) {
                selectedPeriod = .custom
                showCustomRange = false
                HistoryPrefs.save(period: .custom, customStart: customStart, customEnd: customEnd)
                resetForReload()
                Task { await loadHistory() }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func focusedSummaryCards(_ metric: HistoryMetric) -> some View {
        switch metric {
        case .calories:
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    AverageCard(label: "Avg Calories", value: avgCalories.formatted(.number.precision(.fractionLength(0))), color: Theme.caloriesPrimary)
                    if let peak = peakCalorieDay {
                        PeakCard(label: "Best Day", value: peak.totalCalories.formatted(.number.precision(.fractionLength(0))), date: peak.date, color: Theme.caloriesPrimary)
                    }
                }
                WideTotalCard(label: "Total Calories", value: totalCalories.formatted(.number.precision(.fractionLength(0))), color: Theme.caloriesPrimary)
            }
        case .steps:
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    AverageCard(label: "Avg Steps", value: avgSteps.formatted(.number), color: Theme.stepsPrimary)
                    if let peak = peakStepDay {
                        PeakCard(label: "Best Day", value: peak.steps.formatted(.number), date: peak.date, color: Theme.stepsPrimary)
                    }
                }
                WideTotalCard(label: "Total Steps", value: totalSteps.formatted(.number), color: Theme.stepsPrimary)
            }
        case .net:
            if hasNetData {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        AverageCard(label: "Avg Deficit", value: formatSignedNet(avgNetDeficit), color: netColor(for: avgNetDeficit))
                        if let best = bestNetDay {
                            PeakCard(label: "Best Day", value: formatSignedNet(netDeficit(for: best)), date: best.date, color: netColor(for: netDeficit(for: best)))
                        }
                    }
                    WideTotalCard(label: "Total Deficit", value: formatSignedNet(totalNetDeficit), color: netColor(for: totalNetDeficit))
                }
            }
        }
    }

    @ViewBuilder
    private func focusedChartCard(_ metric: HistoryMetric) -> some View {
        switch metric {
        case .calories:
            ChartCard(title: "Calories", selection: selectedCalorieRecord) { caloriesChart }
        case .steps:
            ChartCard(title: "Steps", selection: selectedStepRecord) { stepsChart }
        case .net:
            ChartCard(title: "Net Deficit", selection: hasNetData ? selectedNetRecord : nil) { netDeficitCardContent }
        }
    }

    /// Most-recent-first rows for the detail view's recent-days list. Net uses
    /// only days with food logged; calories/steps use every non-zero day.
    private func recentDayRows(_ metric: HistoryMetric, limit: Int = 14) -> [RecentDayRow] {
        let source: [DayRecord]
        switch metric {
        case .calories, .steps:
            source = records.filter { $0.totalCalories > 0 || $0.steps > 0 }
        case .net:
            source = netRecords
        }
        let sorted = source.sorted { $0.date > $1.date }
        let value: (DayRecord) -> Double = { rec in
            switch metric {
            case .calories: return rec.totalCalories
            case .steps: return Double(rec.steps)
            case .net: return netDeficit(for: rec)
            }
        }
        return sorted.prefix(limit).enumerated().map { index, rec in
            let v = value(rec)
            // Delta compares against the next-older day in the list.
            let olderIndex = index + 1
            let delta: Double? = olderIndex < sorted.count ? v - value(sorted[olderIndex]) : nil
            let valueText: String
            switch metric {
            case .calories: valueText = v.formatted(.number.precision(.fractionLength(0)))
            case .steps: valueText = Int(v.rounded()).formatted(.number)
            case .net: valueText = formatSignedNet(v)
            }
            return RecentDayRow(date: rec.date, valueText: valueText, delta: delta, tint: metric.tint)
        }
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

    /// Wipes view state so a period/range change shows a clean loading bar
    /// instead of flashing the previous period's charts and trends until the
    /// new fetch lands.
    private func resetForReload() {
        records = []
        previousRecords = []
        foodByDay = [:]
        selectedCalorieDate = nil
        selectedStepDate = nil
        selectedNetDate = nil
        animateContent = false
        isLoading = true
    }

    private func loadHistory() async {
        // Each call bumps the token; in-flight loads compare against it before
        // writing back, so a stale fetch (e.g. the previous period's request) can't
        // overwrite `records` after the user has switched to a new range.
        loadToken &+= 1
        let token = loadToken
        let period = selectedPeriod
        let rangeStart = customStart
        let rangeEnd = customEnd
        inflightLoads += 1
        defer { inflightLoads = max(0, inflightLoads - 1) }
        selectedCalorieDate = nil
        selectedStepDate = nil
        selectedNetDate = nil
        loadErrorMessage = nil

        // Cache prime: paint instantly from SwiftData when we have any cached
        // data for this period. HealthKit refresh below overwrites with fresh
        // values when they arrive, so the user never stares at a blank spinner
        // on returning visits. Only applies to fixed periods — custom ranges
        // skip the cache (uncommon path, not worth a from/to overload).
        if records.isEmpty, let days = period.days,
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
            if period == .custom {
                history = try await healthKit.fetchHistory(from: rangeStart, to: rangeEnd)
            } else {
                history = try await healthKit.fetchHistory(days: period.days ?? 7)
            }
            guard token == loadToken else { return }

            // Only fetch dietary history when Net Deficit is enabled; failure here is
            // non-fatal — calorie/step charts still render without it.
            var foodMap: [Date: Double] = [:]
            if store.isPro && goals.showNetCalories {
                do {
                    let dietary: [(date: Date, foodCalories: Double)]
                    if period == .custom {
                        dietary = try await healthKit.fetchDietaryHistory(from: rangeStart, to: rangeEnd)
                    } else {
                        dietary = try await healthKit.fetchDietaryHistory(days: period.days ?? 7)
                    }
                    guard token == loadToken else { return }
                    let cal = Calendar.current
                    for day in dietary {
                        foodMap[cal.startOfDay(for: day.date)] = day.foodCalories
                    }
                } catch {
                    historyLogger.error("Dietary history fetch failed: \(String(describing: error), privacy: .public)")
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
            guard token == loadToken else { return }

            // History has fully loaded. This drives the second-touch Vitals+
            // trial nudge in MainTabView — posting on every successful load is
            // fine because the one-shot / not-Pro / second-touch gating all
            // lives in the observer.
            NotificationCenter.default.post(name: .vitalsHistoryDidFinishLoading, object: nil)
        } catch {
            guard token == loadToken else { return }
            historyLogger.error("History fetch failed: \(String(describing: error), privacy: .public)")
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

    /// On the first 1-3 days of a month, checks whether last month is worth a
    /// recap and, if so, asks the milestone coordinator to celebrate it (which
    /// chains into a Vitals+ pitch). Cheap early-exit on non-Pro + day-of-month
    /// before doing any fetch, so the common case costs nothing.
    private func checkMonthReviewMilestone() async {
        guard !store.isPro,
              Calendar.current.component(.day, from: Date.now) <= 3
        else { return }
        guard let history = try? await healthKit.fetchHistory(days: 62) else { return }
        let days = history.map {
            MilestoneDay(date: $0.date, calories: $0.active + $0.resting, steps: $0.steps)
        }
        guard let milestone = MilestoneCalculator.reviewableLastMonth(records: days) else { return }
        MilestoneCoordinator.shared.request(milestone)
    }

    /// Load the window of equal length preceding the current selection, used for
    /// period-over-period trend calculations on the Deep Trends card and PDF report.
    private func loadPreviousWindow(history: [(date: Date, active: Double, resting: Double, steps: Int)]) async {
        isCalculatingTrends = true
        defer { isCalculatingTrends = false }
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

        // Paint instantly from the SwiftData cache when we have prior data on disk
        // — the HealthKit fetch below overwrites with fresh values when they arrive.
        // Without this, Deep Trends sits on a "Calculating…" spinner on every revisit
        // even when the only thing changing is bytes we already have locally.
        if let cached = try? healthKit.fetchCachedHistory(from: priorStart, to: priorEnd),
           cached.contains(where: { $0.active > 0 || $0.resting > 0 || $0.steps > 0 }) {
            previousRecords = cached.map {
                DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps)
            }
        }

        do {
            let prev = try await healthKit.fetchHistory(from: priorStart, to: priorEnd)
            previousRecords = prev.map {
                DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps)
            }
            try? healthKit.saveHistoryToCache(history: prev)
        } catch {
            if previousRecords.isEmpty {
                previousRecords = []
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
                if let foodCalories = food(for: r.date) {
                    fields.append(String(format: "%.0f", foodCalories))
                    fields.append(String(format: "%.0f", r.totalCalories - foodCalories))
                } else {
                    fields.append("")
                    fields.append("")
                }
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
            historyLogger.error("CSV export failed: \(String(describing: error), privacy: .public)")
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

struct DeepTrendInsight: Identifiable {
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

@MainActor
enum DeepTrendsBuilder {
    static func insights(
        currentRecords: [DayRecord],
        previousRecords: [DayRecord]
    ) -> [DeepTrendInsight] {
        var insights: [DeepTrendInsight] = []

        let currentCalAvg = average(of: currentRecords.map(\.totalCalories))
        let prevCalAvg = average(of: previousRecords.filter { $0.totalCalories > 0 }.map(\.totalCalories))
        if let prev = prevCalAvg, prev > 0, let current = currentCalAvg {
            let delta = current - prev
            let percent = (delta / prev) * 100
            insights.append(
                DeepTrendInsight(
                    title: "Calories",
                    icon: "flame.fill",
                    current: current.formatted(.number.precision(.fractionLength(0))),
                    previous: prev.formatted(.number.precision(.fractionLength(0))),
                    change: signedValue(Int(delta.rounded()).formatted(.number)),
                    percent: signedPercent(percent),
                    narrative: abs(delta) < 1 ? "Calories held steady day-to-day." : "You averaged \(abs(Int(delta.rounded())).formatted(.number)) \(delta >= 0 ? "more" : "fewer") calories per day.",
                    color: Theme.caloriesPrimary,
                    isUp: delta >= 0
                )
            )
        }

        let currentStepAvg = average(of: currentRecords.map { Double($0.steps) })
        let prevStepAvg = average(of: previousRecords.filter { $0.steps > 0 }.map { Double($0.steps) })
        if let prev = prevStepAvg, prev > 0, let current = currentStepAvg {
            let delta = current - prev
            let percent = (delta / prev) * 100
            insights.append(
                DeepTrendInsight(
                    title: "Steps",
                    icon: "figure.walk",
                    current: Int(current.rounded()).formatted(.number),
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

    static func highlights(records: [DayRecord]) -> [String] {
        var highlights: [String] = []
        let activeDays = records.filter { $0.totalCalories > 0 || $0.steps > 0 }.count
        if !records.isEmpty {
            highlights.append("\(activeDays) of \(records.count) days had calories or steps logged.")
        }
        if let peak = records.max(by: { $0.totalCalories < $1.totalCalories }), peak.totalCalories > 0 {
            highlights.append("Peak calories: \(peak.totalCalories.formatted(.number.precision(.fractionLength(0)))) on \(DateHelpers.shortDate(peak.date)).")
        }
        if let peak = records.max(by: { $0.steps < $1.steps }), peak.steps > 0 {
            highlights.append("Peak steps: \(peak.steps.formatted(.number)) on \(DateHelpers.shortDate(peak.date)).")
        }
        return highlights
    }

    private static func average(of values: [Double]) -> Double? {
        let nonZero = values.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return nil }
        return nonZero.reduce(0, +) / Double(nonZero.count)
    }

    private static func signedValue(_ value: String) -> String {
        value.hasPrefix("-") ? value : "+\(value)"
    }

    private static func signedPercent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded >= 0 ? "+\(rounded)%" : "\(rounded)%"
    }

    /// Locked-state insights for the paywall tease. Shows the user's own current-window
    /// average as the only real number; the comparison columns use neutral placeholders
    /// ("—") instead of fabricated deltas so the preview never implies a false trend the
    /// user would then see "change" once they actually subscribe.
    static func teaserInsights(currentRecords: [DayRecord]) -> [DeepTrendInsight] {
        var insights: [DeepTrendInsight] = []
        if let cal = average(of: currentRecords.map(\.totalCalories)) {
            insights.append(
                DeepTrendInsight(
                    title: "Calories",
                    icon: "flame.fill",
                    current: cal.formatted(.number.precision(.fractionLength(0))),
                    previous: "—",
                    change: "—",
                    percent: "vs last",
                    narrative: "Compare your current pace against the prior matching window.",
                    color: Theme.caloriesPrimary,
                    isUp: true
                )
            )
        }
        if let steps = average(of: currentRecords.map { Double($0.steps) }) {
            insights.append(
                DeepTrendInsight(
                    title: "Steps",
                    icon: "figure.walk",
                    current: Int(steps.rounded()).formatted(.number),
                    previous: "—",
                    change: "—",
                    percent: "vs last",
                    narrative: "See momentum on steps across periods.",
                    color: Theme.stepsPrimary,
                    isUp: true
                )
            )
        }
        return insights
    }

    static func teaserHighlights(records: [DayRecord]) -> [String] {
        [
            "Period-over-period averages, deltas, and percent movement.",
            "Peak-day highlights with dates for every metric.",
            "Refresh trends instantly when you switch windows."
        ]
    }
}

struct DeepTrendsCard: View {
    let isPro: Bool
    var isCalculating: Bool = false
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
                if isCalculating {
                    VStack(alignment: .leading, spacing: 10) {
                        LoadingBar(color: Theme.caloriesPrimary)
                            .frame(maxWidth: 200)
                        Text("Calculating trends…")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else if insights.isEmpty {
                    Text("Deep Trends need a previous matching range with calories or steps before they can compare your momentum.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    insightsContent
                }
            } else {
                lockedTeaser
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var insightsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
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
    }

    /// Non-pro view: render the actual insight rows so the user sees the shape of what
    /// they'd get, then crush them with a heavy blur and stamp an Unlock CTA on top.
    /// The blurred content stays interactive-free (`allowsHitTesting(false)`) so taps
    /// only ever land on the upgrade button.
    private var lockedTeaser: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                if insights.isEmpty {
                    placeholderTeaserRows
                } else {
                    VStack(spacing: 12) {
                        ForEach(insights) { insight in
                            DeepTrendInsightRow(insight: insight)
                        }
                    }
                }
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
            .blur(radius: 14)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay(
                LinearGradient(
                    colors: [
                        Theme.cardSurface.opacity(0.35),
                        Theme.cardSurface.opacity(0.55),
                        Theme.cardSurface.opacity(0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.caloriesPrimary)
                Text("Unlock Deep Trends")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Compare this period against the matching previous range: averages, deltas, percent movement, and peak days.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onUpgrade) {
                    Text("Try Vitals+ Free")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.caloriesGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(14)
        }
    }

    /// Synthetic rows used only when the user has no records yet — keeps the locked card
    /// looking like the unlocked card instead of collapsing to a tiny block above the CTA.
    private var placeholderTeaserRows: some View {
        VStack(spacing: 12) {
            DeepTrendInsightRow(insight: DeepTrendInsight(
                title: "Calories",
                icon: "flame.fill",
                current: "2,480",
                previous: "2,310",
                change: "+170",
                percent: "+7%",
                narrative: "Compare current vs prior averages.",
                color: Theme.caloriesPrimary,
                isUp: true
            ))
            DeepTrendInsightRow(insight: DeepTrendInsight(
                title: "Steps",
                icon: "figure.walk",
                current: "9,420",
                previous: "8,860",
                change: "+560",
                percent: "+6%",
                narrative: "Track momentum across periods.",
                color: Theme.stepsPrimary,
                isUp: true
            ))
        }
    }
}

struct DeepTrendInsightRow: View {
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

struct DeepTrendMiniStat: View {
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
    var locked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(.caption.bold())
            }
            .foregroundStyle(locked ? Theme.textTertiary : (isSelected ? Theme.textPrimary : Theme.textSecondary))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Theme.cardSurfaceLight : .clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityHint(locked ? "Vitals+: pick any date range" : "")
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
            .clipShape(Capsule())
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// Full-width total row: label on the left, value on the right. Sits under the
/// Avg + Best Day pair in the focused metric views for a consistent layout.
private struct WideTotalCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    /// When set (and no point is selected), the header becomes a NavigationLink
    /// into the single-metric detail screen, with a chevron affordance.
    var metricLink: HistoryMetric? = nil
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
            } else if let metricLink {
                NavigationLink(value: metricLink) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(title) history")
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

struct RecentDayRow: Identifiable {
    let id = UUID()
    let date: Date
    let valueText: String
    /// Change vs the next-older day in the list; nil when there's no prior day.
    let delta: Double?
    let tint: Color
}

/// Recent-days list shown on the single-metric detail screen so "what was
/// yesterday" is a glance rather than a chart scrub.
private struct RecentDaysList: View {
    let metric: HistoryMetric
    let rows: [RecentDayRow]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Days")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if rows.isEmpty {
                Text(metric == .net ? "No days with food logged yet." : "No recent activity to show.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(Self.dateFormatter.string(from: row.date))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(row.valueText)
                            .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                            .foregroundStyle(row.tint)
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(Self.dateFormatter.string(from: row.date)): \(row.valueText)")
                    if index < rows.count - 1 {
                        Divider().overlay(Theme.textTertiary.opacity(0.15))
                    }
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
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
