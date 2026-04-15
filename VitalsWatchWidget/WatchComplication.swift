import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Number Formatting

private enum ComplicationFormat {
    static func shortCalories(_ value: Double, family: WidgetFamily) -> String {
        if family == .accessoryCorner || family == .accessoryInline || family == .accessoryCircular {
            return compact(value)
        }
        if value >= 10_000 {
            return compact(value)
        }
        return plain(value)
    }

    static func shortSteps(_ value: Int, family: WidgetFamily) -> String {
        let asDouble = Double(value)
        if family == .accessoryCorner || family == .accessoryInline || family == .accessoryCircular {
            return compact(asDouble)
        }
        if value >= 10_000 {
            return compact(asDouble)
        }
        return plain(asDouble)
    }

    static func shortNetDeficit(_ value: Double, family: WidgetFamily) -> String {
        let prefix = value >= 0 ? "+" : ""
        let absVal = abs(value)
        if family == .accessoryCorner || family == .accessoryInline || family == .accessoryCircular {
            return prefix + compact(absVal)
        }
        if absVal >= 10_000 {
            return prefix + compact(absVal)
        }
        return prefix + plain(absVal)
    }

    static func goalSuffix(current: Double, goal: Double, family: WidgetFamily) -> String? {
        // Trailing goal text is the first thing that gets clipped on small rectangular slots.
        // Keep rectangular layouts focused on the primary metric for consistency.
        _ = current
        _ = goal
        _ = family
        return nil
    }

    static func goalSuffix(current: Int, goal: Int, family: WidgetFamily) -> String? {
        _ = current
        _ = goal
        _ = family
        return nil
    }

    private static func compact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = value < 10_000 ? 1 : 0
        formatter.minimumFractionDigits = 0

        if value >= 999_500 {
            let compactValue = value / 1_000_000
            let text = formatter.string(from: NSNumber(value: compactValue)) ?? String(format: "%.1f", compactValue)
            return "\(text)M"
        }
        if value >= 1_000 {
            let compactValue = value / 1_000
            let text = formatter.string(from: NSNumber(value: compactValue)) ?? String(format: "%.1f", compactValue)
            return "\(text)K"
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    private static func plain(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }
}

// MARK: - Goal Helper

private func loadGoals() -> (calories: Double, steps: Int, calEnabled: Bool, stepEnabled: Bool, showCalories: Bool, showSteps: Bool, showNetCalories: Bool) {
    let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
    let cal = defaults.double(forKey: "calorieGoal")
    let step = defaults.integer(forKey: "stepGoal")
    let calOn = defaults.object(forKey: "calorieGoalEnabled") as? Bool ?? true
    let stepOn = defaults.object(forKey: "stepGoalEnabled") as? Bool ?? true
    let showCal = defaults.object(forKey: "showCalories") as? Bool ?? true
    let showStep = defaults.object(forKey: "showSteps") as? Bool ?? true
    let showNet = defaults.object(forKey: "showNetCalories") as? Bool ?? false
    return (cal > 0 ? cal : 2500, step > 0 ? step : 10000, calOn, stepOn, showCal, showStep, showNet)
}

// MARK: - Timeline Provider

struct WatchTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchVitalsEntry {
        WatchVitalsEntry(date: .now, totalCalories: 1240, steps: 4520, foodCalories: 480, calorieGoal: 2500, stepGoal: 10000, calGoalEnabled: true, stepGoalEnabled: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchVitalsEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchVitalsEntry>) -> Void) {
        Task { @MainActor in
            let entry = fetchLatestEntry()
            let oneHour = Calendar.current.date(byAdding: .hour, value: 1, to: .now)
                ?? .now.addingTimeInterval(3600)
            let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
            let nextUpdate = min(oneHour, midnight)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    @MainActor
    private func fetchLatestEntry() -> WatchVitalsEntry {
        let todayKey = DailyHealthRecord.key(for: DateHelpers.startOfDay())
        let container = DataService.sharedModelContainer
        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString == todayKey }
        )
        let goals = loadGoals()

        if let record = try? container.mainContext.fetch(descriptor).first {
            return WatchVitalsEntry(
                date: .now,
                totalCalories: record.totalCalories,
                steps: record.steps,
                foodCalories: record.foodCalories,
                calorieGoal: goals.calories,
                stepGoal: goals.steps,
                calGoalEnabled: goals.calEnabled,
                stepGoalEnabled: goals.stepEnabled,
                showCalories: goals.showCalories,
                showSteps: goals.showSteps,
                showNetCalories: goals.showNetCalories
            )
        }
        return WatchVitalsEntry(
            date: .now,
            totalCalories: 0,
            steps: 0,
            foodCalories: 0,
            calorieGoal: goals.calories,
            stepGoal: goals.steps,
            calGoalEnabled: goals.calEnabled,
            stepGoalEnabled: goals.stepEnabled,
            showCalories: goals.showCalories,
            showSteps: goals.showSteps,
            showNetCalories: goals.showNetCalories,
            dataAvailable: false
        )
    }
}

// MARK: - Entry

struct WatchVitalsEntry: TimelineEntry {
    let date: Date
    let totalCalories: Double
    let steps: Int
    let foodCalories: Double
    let calorieGoal: Double
    let stepGoal: Int
    let calGoalEnabled: Bool
    let stepGoalEnabled: Bool
    var showCalories: Bool = true
    var showSteps: Bool = true
    var showNetCalories: Bool = false
    var dataAvailable: Bool = true

    var netDeficit: Double { totalCalories - foodCalories }
}

private struct NoDataComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "heart.text.clipboard")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("No Health Data")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                Text("Open Total Calories")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryInline:
            Text("Open app")
                .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryCorner:
            Image(systemName: "heart.text.clipboard")
                .font(.title3)
                .foregroundStyle(.secondary)
                .widgetLabel {
                    Text("--")
                }
                .containerBackground(.fill.tertiary, for: .widget)
        default:
            Image(systemName: "heart.text.clipboard")
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Calories Complication Views

struct CaloriesCircularView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.calGoalEnabled {
            Gauge(value: min(entry.totalCalories, entry.calorieGoal), in: 0...entry.calorieGoal) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text(ComplicationFormat.shortCalories(entry.totalCalories, family: family))
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Theme.caloriesPrimary)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.caloriesPrimary)
                Text(ComplicationFormat.shortCalories(entry.totalCalories, family: family))
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .monospacedDigit()
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct CaloriesRectangularView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(Theme.caloriesPrimary)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(ComplicationFormat.shortCalories(entry.totalCalories, family: family))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                Text("calories")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            if entry.calGoalEnabled,
               let goalText = ComplicationFormat.goalSuffix(
                   current: entry.totalCalories,
                   goal: entry.calorieGoal,
                   family: family
               ) {
                Text(goalText)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CaloriesInlineView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Text(ComplicationFormat.shortCalories(entry.totalCalories, family: family))
            .font(.system(.body, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .monospacedDigit()
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CaloriesCornerView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.title3)
            .foregroundStyle(Theme.caloriesPrimary)
            .widgetLabel {
                Text(ComplicationFormat.shortCalories(entry.totalCalories, family: family) + " cal")
            }
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Steps Complication Views

struct StepsCircularView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.stepGoalEnabled {
            Gauge(value: min(Double(entry.steps), Double(entry.stepGoal)), in: 0...Double(entry.stepGoal)) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(ComplicationFormat.shortSteps(entry.steps, family: family))
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Theme.stepsPrimary)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 1) {
                Image(systemName: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(Theme.stepsPrimary)
                Text(ComplicationFormat.shortSteps(entry.steps, family: family))
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .monospacedDigit()
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct StepsRectangularView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.walk")
                .font(.title3)
                .foregroundStyle(Theme.stepsPrimary)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(ComplicationFormat.shortSteps(entry.steps, family: family))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                Text("steps")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            if entry.stepGoalEnabled,
               let goalText = ComplicationFormat.goalSuffix(
                   current: entry.steps,
                   goal: entry.stepGoal,
                   family: family
               ) {
                Text(goalText)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StepsInlineView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Text(ComplicationFormat.shortSteps(entry.steps, family: family))
            .font(.system(.body, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .monospacedDigit()
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StepsCornerView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Image(systemName: "figure.walk")
            .font(.title3)
            .foregroundStyle(Theme.stepsPrimary)
            .widgetLabel {
                Text(ComplicationFormat.shortSteps(entry.steps, family: family) + " steps")
            }
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Entry Views

struct CaloriesEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchVitalsEntry

    var body: some View {
        if !entry.dataAvailable || !entry.showCalories {
            NoDataComplicationView()
        } else {
            switch family {
            case .accessoryCircular: CaloriesCircularView(entry: entry)
            case .accessoryRectangular: CaloriesRectangularView(entry: entry)
            case .accessoryInline: CaloriesInlineView(entry: entry)
            case .accessoryCorner: CaloriesCornerView(entry: entry)
            default: CaloriesCircularView(entry: entry)
            }
        }
    }
}

struct StepsEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchVitalsEntry

    var body: some View {
        if !entry.dataAvailable || !entry.showSteps {
            NoDataComplicationView()
        } else {
            switch family {
            case .accessoryCircular: StepsCircularView(entry: entry)
            case .accessoryRectangular: StepsRectangularView(entry: entry)
            case .accessoryInline: StepsInlineView(entry: entry)
            case .accessoryCorner: StepsCornerView(entry: entry)
            default: StepsCircularView(entry: entry)
            }
        }
    }
}

// MARK: - Net Deficit Complication Views

struct NetDeficitCircularView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    private var color: Color { entry.netDeficit >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative }

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "fork.knife")
                .font(.caption)
                .foregroundStyle(Theme.netDeficitBrand)
            Text(ComplicationFormat.shortNetDeficit(entry.netDeficit, family: family))
                .font(.system(.body, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct NetDeficitRectangularView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    private var color: Color { entry.netDeficit >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.title3)
                .foregroundStyle(Theme.netDeficitBrand)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(ComplicationFormat.shortNetDeficit(entry.netDeficit, family: family))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text("net cal")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct NetDeficitInlineView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Text(ComplicationFormat.shortNetDeficit(entry.netDeficit, family: family))
            .font(.system(.body, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .monospacedDigit()
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct NetDeficitCornerView: View {
    let entry: WatchVitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Image(systemName: "fork.knife")
            .font(.title3)
            .foregroundStyle(Theme.netDeficitBrand)
            .widgetLabel {
                Text(ComplicationFormat.shortNetDeficit(entry.netDeficit, family: family) + " net")
            }
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Net Deficit Entry View

struct NetDeficitEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchVitalsEntry

    var body: some View {
        if !entry.dataAvailable {
            NoDataComplicationView()
        } else {
            switch family {
            case .accessoryCircular: NetDeficitCircularView(entry: entry)
            case .accessoryRectangular: NetDeficitRectangularView(entry: entry)
            case .accessoryInline: NetDeficitInlineView(entry: entry)
            case .accessoryCorner: NetDeficitCornerView(entry: entry)
            default: NetDeficitCircularView(entry: entry)
            }
        }
    }
}

// MARK: - Widgets

struct CaloriesWidget: Widget {
    let kind = "VitalsCalories"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchTimelineProvider()) { entry in
            CaloriesEntryView(entry: entry)
        }
        .configurationDisplayName("Calories")
        .description("Today's total calories burned.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct StepsWidget: Widget {
    let kind = "VitalsSteps"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchTimelineProvider()) { entry in
            StepsEntryView(entry: entry)
        }
        .configurationDisplayName("Steps")
        .description("Today's step count.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct NetDeficitWidget: Widget {
    let kind = "VitalsNetDeficit"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchTimelineProvider()) { entry in
            NetDeficitEntryView(entry: entry)
        }
        .configurationDisplayName("Net Calories")
        .description("Today's calories burned minus food eaten.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

// MARK: - Widget Bundle

@main
struct VitalsWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        StepsWidget()
        NetDeficitWidget()
    }
}
