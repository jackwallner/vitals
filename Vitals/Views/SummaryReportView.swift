import SwiftUI
import Charts
import CoreGraphics
import PDFKit

/// Print-friendly SwiftUI page rendered to PDF via `ImageRenderer`.
/// Designed at US Letter size (612×792 points). Uses light-mode colors only —
/// reports must look right when printed regardless of in-app appearance.
struct SummaryReportView: View {
    let report: SummaryReport

    private let pageWidth: CGFloat = 612
    private let pageHeight: CGFloat = 792
    private let margin: CGFloat = 36

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            keyMetricsGrid
            caloriesChart
            stepsChart
            highlightsRow
            footer
        }
        .padding(margin)
        .frame(width: pageWidth, height: pageHeight, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vitals+")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(reportCalorieColor)
                    Text(report.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(report.calendarLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.gray)
                    Text("\(report.activeDayCount) active days")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.gray)
                }
            }
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
                .padding(.top, 4)
        }
    }

    private var keyMetricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricTile(
                    label: "AVG CALORIES / DAY",
                    value: formatNumber(report.avgCalories),
                    accent: reportCalorieColor,
                    trendPct: report.calorieTrendPct
                )
                MetricTile(
                    label: "TOTAL CALORIES",
                    value: formatNumber(report.totalCalories),
                    accent: reportCalorieColor,
                    trendPct: nil
                )
            }
            HStack(spacing: 10) {
                MetricTile(
                    label: "AVG STEPS / DAY",
                    value: formatNumber(Double(report.avgSteps)),
                    accent: reportStepsColor,
                    trendPct: report.stepTrendPct
                )
                MetricTile(
                    label: "TOTAL STEPS",
                    value: formatNumber(Double(report.totalSteps)),
                    accent: reportStepsColor,
                    trendPct: nil
                )
            }
            if report.calorieGoal != nil || report.stepGoal != nil {
                HStack(spacing: 10) {
                    if let goal = report.calorieGoal {
                        MetricTile(
                            label: "CALORIE GOAL HIT",
                            value: "\(report.calorieGoalHitDays) days",
                            sub: "Goal: \(formatNumber(goal))",
                            accent: reportCalorieColor,
                            trendPct: nil
                        )
                    }
                    if let goal = report.stepGoal {
                        MetricTile(
                            label: "STEP GOAL HIT",
                            value: "\(report.stepGoalHitDays) days",
                            sub: "Goal: \(formatNumber(Double(goal)))",
                            accent: reportStepsColor,
                            trendPct: nil
                        )
                    }
                }
            }
        }
    }

    private var caloriesChart: some View {
        ReportChartCard(title: "Total Calories", color: reportCalorieColor) {
            Chart(report.days) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Calories", day.totalCalories)
                )
                .foregroundStyle(reportCalorieColor)
                .cornerRadius(2)
            }
            .chartXAxis { axisMarks }
            .chartYAxis { yAxisMarks }
            .frame(height: 130)
        }
    }

    private var stepsChart: some View {
        ReportChartCard(title: "Steps", color: reportStepsColor) {
            Chart(report.days) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Steps", day.steps)
                )
                .foregroundStyle(reportStepsColor)
                .cornerRadius(2)
            }
            .chartXAxis { axisMarks }
            .chartYAxis { yAxisMarks }
            .frame(height: 130)
        }
    }

    private var axisMarks: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: max(1, report.days.count / 6))) { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(Self.dateFmt.string(from: date))
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                }
            }
            AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
        }
    }

    private var yAxisMarks: some AxisContent {
        AxisMarks { value in
            AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(v.formatted(.number.notation(.compactName)))
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    private var highlightsRow: some View {
        HStack(spacing: 10) {
            if let peak = report.peakCalorieDay {
                HighlightTile(
                    label: "BIGGEST BURN",
                    value: formatNumber(peak.totalCalories) + " cal",
                    date: peak.date,
                    accent: reportCalorieColor
                )
            }
            if let peak = report.peakStepDay {
                HighlightTile(
                    label: "MOST STEPS",
                    value: formatNumber(Double(peak.steps)),
                    date: peak.date,
                    accent: reportStepsColor
                )
            }
            HighlightTile(
                label: "ACTIVE DAYS",
                value: "\(report.activeDayCount)",
                date: nil,
                sub: "of \(report.days.count) tracked",
                accent: .black
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
            HStack {
                Text("Generated by Vitals on \(generatedAt)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.gray)
                Spacer()
                Text("Data from Apple Health · stays on your device")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.gray)
            }
        }
    }

    private var generatedAt: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: Date.now)
    }

    private func formatNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private var reportCalorieColor: Color { Color(red: 1.0, green: 0.42, blue: 0.42) }
    private var reportStepsColor: Color { Color(red: 0.0, green: 0.69, blue: 0.55) }
}

// MARK: - Subcomponents

private struct MetricTile: View {
    let label: String
    let value: String
    var sub: String? = nil
    let accent: Color
    let trendPct: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.gray)
                    .tracking(0.6)
                Spacer()
                if let pct = trendPct {
                    TrendBadge(pct: pct)
                }
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
            if let sub {
                Text(sub)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TrendBadge: View {
    let pct: Double

    var body: some View {
        let isUp = pct >= 0
        let color = isUp ? Color(red: 0.20, green: 0.68, blue: 0.45) : Color(red: 0.85, green: 0.42, blue: 0.40)
        HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 8, weight: .bold))
            Text("\(abs(Int(pct.rounded())))%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct ReportChartCard<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
            }
            content
        }
        .padding(12)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HighlightTile: View {
    let label: String
    let value: String
    let date: Date?
    var sub: String? = nil
    let accent: Color

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.gray)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            if let date {
                Text(Self.dateFmt.string(from: date))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.gray)
            } else if let sub {
                Text(sub)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - PDF Rendering

@MainActor
enum SummaryReportPDF {
    /// Renders a `SummaryReport` to a PDF on disk and returns the file URL.
    /// Caller is responsible for cleaning up the file (typically after the share sheet dismisses).
    static func render(_ report: SummaryReport) throws -> URL {
        let view = SummaryReportView(report: report)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 612, height: 792)
        renderer.scale = 2.0

        let safeTitle = report.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vitals_\(safeTitle)_\(Int(Date.now.timeIntervalSince1970)).pdf")

        var pageBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &pageBox, nil) else {
            throw NSError(domain: "Vitals.PDF", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context."])
        }

        renderer.render { size, renderAction in
            context.beginPDFPage(nil)
            renderAction(context)
            context.endPDFPage()
        }
        context.closePDF()

        return url
    }
}

enum SummaryReportShareText {
    static let appStoreURL = "https://apps.apple.com/us/app/total-calories-daily-tracker/id6761743504"

    static func make(report: SummaryReport) -> String {
        let calorieTrend = emojiLine(label: "calories", percent: report.calorieTrendPct)
        let stepTrend = emojiLine(label: "steps", percent: report.stepTrendPct)
        let goalBlocks = goalBlockLine(report: report)
        return """
        Vitals+ \(report.title) 💪
        \(goalBlocks)
        🔥 Avg calories: \(report.avgCalories.formatted(.number.precision(.fractionLength(0))))
        👟 Avg steps: \(report.avgSteps.formatted(.number))
        \(calorieTrend)
        \(stepTrend)

        Track yours: \(appStoreURL)
        """
    }

    private static func emojiLine(label: String, percent: Double?) -> String {
        guard let percent else { return "⬜️ \(label.capitalized): more data needed" }
        let arrow = percent >= 0 ? "↗️" : "↘️"
        return "\(arrow) \(label.capitalized): \(abs(Int(percent.rounded())))% \(percent >= 0 ? "up" : "down")"
    }

    private static func goalBlockLine(report: SummaryReport) -> String {
        let dayCount = max(report.days.count, 1)
        let calorieRatio = min(Double(report.calorieGoalHitDays) / Double(dayCount), 1)
        let stepRatio = min(Double(report.stepGoalHitDays) / Double(dayCount), 1)
        let filled = Int(((calorieRatio + stepRatio) / 2 * 5).rounded())
        let blocks = (0..<5).map { $0 < filled ? "🟩" : "⬜️" }.joined()
        return "\(blocks) Goals: 🔥 \(report.calorieGoalHitDays)/\(dayCount)  👟 \(report.stepGoalHitDays)/\(dayCount)"
    }
}

struct PDFPreviewSheet: View {
    let title: String
    let url: URL
    let shareText: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitPreview(url: url)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            ShareLink(item: shareText) {
                                Image(systemName: "message.fill")
                            }
                            .accessibilityLabel("Share with friends")
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel("Share PDF")
                        }
                    }
                }
        }
    }
}

private struct PDFKitPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
