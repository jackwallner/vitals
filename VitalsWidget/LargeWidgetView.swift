import SwiftUI
import WidgetKit

/// Today on top, the week underneath. Each metric is its own tap target into
/// that metric's history; a goal-hit day draws its bar in full color so a
/// streak reads at a glance (the StandBy and Home Screen view of the loop).
struct LargeWidgetView: View {
    let entry: VitalsEntry

    var body: some View {
        if entry.dataAvailable {
            VStack(alignment: .leading, spacing: 12) {
                header
                if entry.showCalories {
                    Link(destination: DeepLink.metric(.calories).url) {
                        MetricBlock(
                            title: String(localized: "Calories"),
                            icon: "flame.fill",
                            tint: Theme.caloriesPrimary,
                            value: entry.totalCalories.formatted(.number.precision(.fractionLength(0))),
                            goalText: entry.calGoalEnabled ? entry.calorieGoal.formatted(.number.precision(.fractionLength(0))) : nil,
                            progress: entry.calGoalEnabled ? entry.totalCalories / entry.calorieGoal : nil,
                            bars: entry.week.map(\.calories),
                            goal: entry.calGoalEnabled ? entry.calorieGoal : nil,
                            days: entry.week.map(\.date)
                        )
                    }
                }
                if entry.showSteps {
                    Link(destination: DeepLink.metric(.steps).url) {
                        MetricBlock(
                            title: String(localized: "Steps"),
                            icon: "figure.walk",
                            tint: Theme.stepsPrimary,
                            value: entry.steps.formatted(.number),
                            goalText: entry.stepGoalEnabled ? entry.stepGoal.formatted(.number) : nil,
                            progress: entry.stepGoalEnabled ? Double(entry.steps) / Double(entry.stepGoal) : nil,
                            bars: entry.week.map { Double($0.steps) },
                            goal: entry.stepGoalEnabled ? Double(entry.stepGoal) : nil,
                            days: entry.week.map(\.date)
                        )
                    }
                }
                if entry.showNetCalories {
                    Link(destination: DeepLink.metric(.net).url) {
                        HStack {
                            Label("Net Deficit", systemImage: "fork.knife")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(entry.netDeficit, format: .number.precision(.fractionLength(0)).sign(strategy: .always()))
                                .font(Theme.bigNumber(22))
                                .foregroundStyle(entry.netDeficit >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .widgetURL(DeepLink.today.url)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "heart.text.clipboard")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.textTertiary)
                Text("Open Total Calories to load your health data.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.staleDate == nil ? String(localized: "Today") : String(localized: "Last synced"))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(entry.staleDate ?? entry.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct MetricBlock: View {
    let title: String
    let icon: String
    let tint: Color
    let value: String
    let goalText: String?
    let progress: Double?
    let bars: [Double]
    let goal: Double?
    let days: [Date]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(value)
                    .font(Theme.bigNumber(26))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let goalText {
                    Text("/ \(goalText)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(tint)
            }
            if bars.count == days.count, !bars.isEmpty {
                // The bars take the height the other blocks leave, so two
                // metrics fill the widget instead of leaving its bottom third empty.
                WeekBars(values: bars, goal: goal, days: days, tint: tint)
                    .frame(minHeight: 44, maxHeight: 110)
            }
        }
    }
}

private struct WeekBars: View {
    let values: [Double]
    let goal: Double?
    let days: [Date]
    let tint: Color

    private var ceiling: Double {
        max(values.max() ?? 0, goal ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(barColor(value))
                                .frame(height: max(geo.size.height * value / ceiling, value > 0 ? 3 : 1))
                        }
                    }
                    Text(days[index], format: .dateTime.weekday(.narrow))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Calendar.current.isDateInToday(days[index]) ? Theme.textPrimary : Theme.textTertiary)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func barColor(_ value: Double) -> Color {
        guard let goal else { return tint.opacity(0.7) }
        return value >= goal ? tint : tint.opacity(0.3)
    }
}
