import SwiftUI

@MainActor
private enum PlusPrefs {
    private static let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
    private static let periodKey = "plus.period"
    private static let customStartKey = "plus.customStart"
    private static let customEndKey = "plus.customEnd"

    static func savedPeriod() -> PlusView.Period {
        guard let raw = defaults.string(forKey: periodKey) else { return .month }
        return PlusView.Period(rawValue: raw) ?? .month
    }

    static func savedCustomStart() -> Date { sanitizedRange().start }
    static func savedCustomEnd() -> Date { sanitizedRange().end }

    static func sanitizedRange() -> (start: Date, end: Date) {
        let now = Date.now
        let storedStart = defaults.double(forKey: customStartKey)
        let storedEnd = defaults.double(forKey: customEndKey)

        let rawStart = storedStart > 0 ? Date(timeIntervalSince1970: storedStart) : DateHelpers.daysAgo(29)
        let rawEnd = storedEnd > 0 ? Date(timeIntervalSince1970: storedEnd) : now

        let end = min(rawEnd, now)
        var start = min(rawStart, end)
        if start >= end {
            start = DateHelpers.daysAgo(29, from: end)
        }
        let maxWindow: TimeInterval = 730 * 86_400
        if end.timeIntervalSince(start) > maxWindow {
            start = end.addingTimeInterval(-maxWindow)
        }
        return (start, end)
    }

    static func save(period: PlusView.Period, customStart: Date, customEnd: Date) {
        defaults.set(period.rawValue, forKey: periodKey)
        defaults.set(customStart.timeIntervalSince1970, forKey: customStartKey)
        defaults.set(customEnd.timeIntervalSince1970, forKey: customEndKey)
    }
}

struct PlusView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared
    @EnvironmentObject private var store: StoreService

    @State private var selectedPeriod: Period = PlusPrefs.savedPeriod()
    @State private var customStart: Date = PlusPrefs.savedCustomStart()
    @State private var customEnd: Date = PlusPrefs.savedCustomEnd()
    @State private var showCustomRange = false

    @State private var records: [DayRecord] = []
    @State private var previousRecords: [DayRecord] = []
    @State private var yearAgoRecords: [DayRecord] = []

    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var loadErrorMessage: String?

    @State private var showPaywall = false
    @State private var isGeneratingReport = false
    @State private var previewReport: PreviewWrapper?
    @State private var reportError: String?

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

    private struct PreviewWrapper: Identifiable {
        let id = UUID()
        let report: SummaryReport
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                periodSelector
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                if selectedPeriod == .custom {
                    Text(
                        "\(customStart, format: .dateTime.month(.abbreviated).day()) – \(customEnd, format: .dateTime.month(.abbreviated).day().year())"
                    )
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        if let loadErrorMessage {
                            noticeBanner(loadErrorMessage)
                        }

                        if store.isPro {
                            reportCard
                            deepTrendsCard
                        } else {
                            upsellHero
                            reportCardLocked
                            deepTrendsCardLocked
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 90)
                }
                .refreshable { await loadData() }
            }
        }
        .onChange(of: selectedPeriod) { _, _ in
            if selectedPeriod != .custom {
                PlusPrefs.save(period: selectedPeriod, customStart: customStart, customEnd: customEnd)
                Task { await loadData() }
            }
        }
        .onChange(of: healthKit.isAuthorized) { _, newValue in
            if newValue { Task { await loadData() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await loadData() }
        }
        .task { await loadData() }
        .sheet(isPresented: $showCustomRange) {
            PlusCustomRangeSheet(start: $customStart, end: $customEnd) {
                selectedPeriod = .custom
                showCustomRange = false
                PlusPrefs.save(period: .custom, customStart: customStart, customEnd: customEnd)
                Task { await loadData() }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
        .sheet(item: $previewReport) { wrapper in
            SummaryReportPreviewView(report: wrapper.report)
        }
        .alert(
            "Report Failed",
            isPresented: Binding(
                get: { reportError != nil },
                set: { if !$0 { reportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportError ?? "")
        }
        .overlay(alignment: .center) {
            if isGeneratingReport {
                VStack(spacing: 12) {
                    ProgressView().tint(Theme.caloriesPrimary)
                    Text("Preparing report…")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(20)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Vitals+")
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)
                    if store.isPro {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.caloriesPrimary.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.caloriesPrimary)
                    }
                }
                Text(store.isPro ? "Reports & Deep Trends" : "Reports & Deep Trends — locked")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            if isRefreshing && !isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.textTertiary)
                    .padding(.leading, 4)
                    .transition(.opacity)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var periodSelector: some View {
        HStack(spacing: 0) {
            ForEach(Period.allCases, id: \.self) { period in
                PlusSegmentButton(title: period.rawValue, isSelected: selectedPeriod == period) {
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
    }

    // MARK: - Pro: Report Card

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.caloriesPrimary)
                Text("Summary Report")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text(reportSubtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: generatePreview) {
                HStack(spacing: 8) {
                    if isGeneratingReport {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "eye")
                    }
                    Text(isGeneratingReport ? "Preparing…" : "Generate Preview")
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.caloriesGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingReport || records.isEmpty)
            .opacity(records.isEmpty ? 0.5 : 1)
            if records.isEmpty && !isLoading {
                Text("No activity for this range yet.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var reportSubtitle: String {
        let label = reportTitle
        return "\(label) · charts, trends, and a daily breakdown for ranges over 31 days."
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

    // MARK: - Pro: Deep Trends Card

    private var deepTrendsCard: some View {
        DeepTrendsCard(
            isPro: true,
            calorieTrend: deepCalorieTrend,
            stepTrend: deepStepTrend,
            yoyCalorieTrend: yoyCalorieTrend,
            yoyStepTrend: yoyStepTrend,
            periodLabel: deepTrendsPeriodLabel,
            onUpgrade: {}
        )
    }

    // MARK: - Free: Upsell Hero

    private var upsellHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.caloriesGradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock Vitals+")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Shareable PDF reports & deep trend insights.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            Button {
                showPaywall = true
            } label: {
                Text("See Plans")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.caloriesGradient, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var reportCardLocked: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.caloriesPrimary)
                Text("Summary Report")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Vitals+")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.caloriesPrimary.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.caloriesPrimary)
            }
            Text("Print-ready PDF with charts, period-over-period trends, and a daily breakdown table. Pick any range — 7 days through 2 years.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showPaywall = true
            } label: {
                Text("Unlock with Vitals+")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.caloriesGradient, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var deepTrendsCardLocked: some View {
        DeepTrendsCard(
            isPro: false,
            calorieTrend: nil,
            stepTrend: nil,
            yoyCalorieTrend: nil,
            yoyStepTrend: nil,
            periodLabel: deepTrendsPeriodLabel,
            onUpgrade: { showPaywall = true }
        )
    }

    // MARK: - Trend computations

    private var deepTrendsPeriodLabel: String {
        switch selectedPeriod {
        case .week: return "vs. previous week"
        case .month: return "vs. previous 30 days"
        case .threeMonths: return "vs. previous 90 days"
        case .year: return "vs. previous year"
        case .custom: return "vs. previous range"
        }
    }

    private var avgCalories: Double {
        let nz = records.filter { $0.totalCalories > 0 }
        guard !nz.isEmpty else { return 0 }
        return nz.map(\.totalCalories).reduce(0, +) / Double(nz.count)
    }

    private var avgSteps: Int {
        let nz = records.filter { $0.steps > 0 }
        guard !nz.isEmpty else { return 0 }
        return nz.map(\.steps).reduce(0, +) / nz.count
    }

    private var deepCalorieTrend: Double? {
        let curr = avgCalories
        let nz = previousRecords.filter { $0.totalCalories > 0 }
        guard !nz.isEmpty else { return nil }
        let prev = nz.map(\.totalCalories).reduce(0, +) / Double(nz.count)
        guard prev > 0, curr > 0 else { return nil }
        return ((curr - prev) / prev) * 100
    }

    private var deepStepTrend: Double? {
        let curr = Double(avgSteps)
        let nz = previousRecords.filter { $0.steps > 0 }
        guard !nz.isEmpty else { return nil }
        let prev = Double(nz.map(\.steps).reduce(0, +)) / Double(nz.count)
        guard prev > 0, curr > 0 else { return nil }
        return ((curr - prev) / prev) * 100
    }

    private var yoyCalorieTrend: Double? {
        let curr = avgCalories
        let nz = yearAgoRecords.filter { $0.totalCalories > 0 }
        guard !nz.isEmpty else { return nil }
        let prev = nz.map(\.totalCalories).reduce(0, +) / Double(nz.count)
        guard prev > 0, curr > 0 else { return nil }
        return ((curr - prev) / prev) * 100
    }

    private var yoyStepTrend: Double? {
        let curr = Double(avgSteps)
        let nz = yearAgoRecords.filter { $0.steps > 0 }
        guard !nz.isEmpty else { return nil }
        let prev = Double(nz.map(\.steps).reduce(0, +)) / Double(nz.count)
        guard prev > 0, curr > 0 else { return nil }
        return ((curr - prev) / prev) * 100
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        loadErrorMessage = nil

        let isFirstLoad = records.isEmpty
        if isFirstLoad { isLoading = true }

        do {
            let history: [(date: Date, active: Double, resting: Double, steps: Int)]
            if selectedPeriod == .custom {
                history = try await healthKit.fetchHistory(from: customStart, to: customEnd)
            } else {
                history = try await healthKit.fetchHistory(days: selectedPeriod.days ?? 30)
            }
            records = history.map {
                DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps)
            }
            await loadPreviousWindow(history: history)
            await loadYearAgoWindow(history: history)
        } catch {
            print("PlusView load failed: \(error)")
            loadErrorMessage = "Couldn't load activity. Try again."
        }
        isLoading = false
    }

    private func loadPreviousWindow(history: [(date: Date, active: Double, resting: Double, steps: Int)]) async {
        guard let earliest = history.map(\.date).min() else {
            previousRecords = []
            return
        }
        let cal = Calendar.current
        let priorEnd = cal.date(byAdding: .day, value: -1, to: earliest) ?? earliest
        let lengthDays: Int
        switch selectedPeriod {
        case .week, .month, .threeMonths, .year:
            lengthDays = selectedPeriod.days ?? 0
        case .custom:
            lengthDays = max(1, (cal.dateComponents([.day], from: customStart, to: customEnd).day ?? 0) + 1)
        }
        guard lengthDays > 0 else {
            previousRecords = []
            return
        }
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

    private func loadYearAgoWindow(history: [(date: Date, active: Double, resting: Double, steps: Int)]) async {
        guard let earliest = history.map(\.date).min(),
              let latest = history.map(\.date).max() else {
            yearAgoRecords = []
            return
        }
        let cal = Calendar.current
        guard let yaStart = cal.date(byAdding: .year, value: -1, to: earliest),
              let yaEnd = cal.date(byAdding: .year, value: -1, to: latest) else {
            yearAgoRecords = []
            return
        }
        do {
            let ya = try await healthKit.fetchHistory(from: yaStart, to: yaEnd)
            yearAgoRecords = ya.map {
                DayRecord(date: $0.date, activeCalories: $0.active, restingCalories: $0.resting, steps: $0.steps)
            }
        } catch {
            yearAgoRecords = []
        }
    }

    // MARK: - Report generation

    private func generatePreview() {
        guard !isGeneratingReport else { return }
        isGeneratingReport = true
        Task {
            defer { isGeneratingReport = false }
            let reportDays = records.map { rec in
                ReportDay(
                    date: rec.date,
                    activeCalories: rec.activeCalories,
                    restingCalories: rec.restingCalories,
                    steps: rec.steps,
                    foodCalories: nil
                )
            }
            let prevDays = previousRecords.map { rec in
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
                stepGoal: goals.stepGoal
            )
            previewReport = PreviewWrapper(report: report)
        }
    }

    private func noticeBanner(_ message: String) -> some View {
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
}

// MARK: - Deep Trends Card (shared layout used inside PlusView)

struct DeepTrendsCard: View {
    let isPro: Bool
    let calorieTrend: Double?
    let stepTrend: Double?
    let yoyCalorieTrend: Double?
    let yoyStepTrend: Double?
    let periodLabel: String
    let onUpgrade: () -> Void

    private var hasYoyData: Bool { yoyCalorieTrend != nil || yoyStepTrend != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: isPro ? "chart.line.uptrend.xyaxis" : "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.caloriesPrimary)
                Text("Deep Trends")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !isPro {
                    Text("Vitals+")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.caloriesPrimary.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.caloriesPrimary)
                }
            }

            if isPro {
                VStack(alignment: .leading, spacing: 14) {
                    Text(periodLabel)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 12) {
                        TrendStat(label: "Calories", trend: calorieTrend, color: Theme.caloriesPrimary)
                        TrendStat(label: "Steps", trend: stepTrend, color: Theme.stepsPrimary)
                    }

                    if hasYoyData {
                        Divider().background(Theme.textTertiary.opacity(0.2))
                        Text("vs. same period last year")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                        HStack(spacing: 12) {
                            TrendStat(label: "Calories", trend: yoyCalorieTrend, color: Theme.caloriesPrimary)
                            TrendStat(label: "Steps", trend: yoyStepTrend, color: Theme.stepsPrimary)
                        }
                    }
                }
            } else {
                Text(periodLabel)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                VStack(alignment: .leading, spacing: 10) {
                    Text("See whether you’re trending up or down on calories and steps — vs. the previous period and the same period last year.")
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

private struct TrendStat: View {
    let label: String
    let trend: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
            if let trend {
                let isUp = trend >= 0
                let signColor = isUp ? Theme.netDeficitPositive : Theme.netDeficitNegative
                HStack(spacing: 4) {
                    Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(abs(Int(trend.rounded())))%")
                        .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(signColor)
            } else {
                Text("—")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                Text("Need more data")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Period Segment Button

private struct PlusSegmentButton: View {
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

// MARK: - Custom Range Sheet

private struct PlusCustomRangeSheet: View {
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
