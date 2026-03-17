import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Goal Helper

private func loadGoals() -> (calories: Double, steps: Int, calEnabled: Bool, stepEnabled: Bool) {
    let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
    let cal = defaults.double(forKey: "calorieGoal")
    let step = defaults.integer(forKey: "stepGoal")
    let calOn = defaults.object(forKey: "calorieGoalEnabled") as? Bool ?? true
    let stepOn = defaults.object(forKey: "stepGoalEnabled") as? Bool ?? true
    return (cal > 0 ? cal : 2500, step > 0 ? step : 10000, calOn, stepOn)
}

// MARK: - Timeline Provider

struct WatchTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchVitalsEntry {
        WatchVitalsEntry(date: .now, totalCalories: 1240, steps: 4520, calorieGoal: 2500, stepGoal: 10000, calGoalEnabled: true, stepGoalEnabled: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchVitalsEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchVitalsEntry>) -> Void) {
        Task { @MainActor in
            let entry = fetchLatestEntry()
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now)
                ?? .now.addingTimeInterval(3600)
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
                calorieGoal: goals.calories,
                stepGoal: goals.steps,
                calGoalEnabled: goals.calEnabled,
                stepGoalEnabled: goals.stepEnabled
            )
        }
        return WatchVitalsEntry(date: .now, totalCalories: 0, steps: 0, calorieGoal: goals.calories, stepGoal: goals.steps, calGoalEnabled: goals.calEnabled, stepGoalEnabled: goals.stepEnabled)
    }
}

// MARK: - Entry

struct WatchVitalsEntry: TimelineEntry {
    let date: Date
    let totalCalories: Double
    let steps: Int
    let calorieGoal: Double
    let stepGoal: Int
    let calGoalEnabled: Bool
    let stepGoalEnabled: Bool
}

// MARK: - Calories Complication Views

struct CaloriesCircularView: View {
    let entry: WatchVitalsEntry

    var body: some View {
        if entry.calGoalEnabled {
            Gauge(value: min(entry.totalCalories, entry.calorieGoal), in: 0...entry.calorieGoal) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text(entry.totalCalories / 1000, format: .number.precision(.fractionLength(1)))
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Theme.caloriesPrimary)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.caloriesPrimary)
                Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct CaloriesRectangularView: View {
    let entry: WatchVitalsEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(Theme.caloriesPrimary)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("calories")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.calGoalEnabled {
                Text("\(Int(min(entry.totalCalories / entry.calorieGoal, 1.0) * 100))%")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.caloriesPrimary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CaloriesInlineView: View {
    let entry: WatchVitalsEntry

    var body: some View {
        Text("\(entry.totalCalories.formatted(.number.precision(.fractionLength(0)))) cal")
            .font(.system(.body, design: .rounded))
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CaloriesCornerView: View {
    let entry: WatchVitalsEntry

    var body: some View {
        Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(Theme.caloriesPrimary)
            .widgetLabel {
                if entry.calGoalEnabled {
                    Gauge(value: min(entry.totalCalories, entry.calorieGoal), in: 0...entry.calorieGoal) {
                        Text("cal")
                    }
                    .tint(Theme.caloriesPrimary)
                    .gaugeStyle(.accessoryLinear)
                } else {
                    Text("cal")
                        .font(.system(.caption, design: .rounded))
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Steps Complication Views

struct StepsCircularView: View {
    let entry: WatchVitalsEntry

    var body: some View {
        if entry.stepGoalEnabled {
            Gauge(value: min(Double(entry.steps), Double(entry.stepGoal)), in: 0...Double(entry.stepGoal)) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(Double(entry.steps) / 1000, format: .number.precision(.fractionLength(1)))
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Theme.stepsPrimary)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 1) {
                Image(systemName: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(Theme.stepsPrimary)
                Text(entry.steps, format: .number)
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct StepsRectangularView: View {
    let entry: WatchVitalsEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.walk")
                .font(.title3)
                .foregroundStyle(Theme.stepsPrimary)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.steps, format: .number)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("steps")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.stepGoalEnabled {
                Text("\(Int(min(Double(entry.steps) / Double(entry.stepGoal), 1.0) * 100))%")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.stepsPrimary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StepsInlineView: View {
    let entry: WatchVitalsEntry

    var body: some View {
        Text("\(entry.steps.formatted(.number)) steps")
            .font(.system(.body, design: .rounded))
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StepsCornerView: View {
    let entry: WatchVitalsEntry

    var body: some View {
        Text(entry.steps.formatted(.number))
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(Theme.stepsPrimary)
            .widgetLabel {
                if entry.stepGoalEnabled {
                    Gauge(value: min(Double(entry.steps), Double(entry.stepGoal)), in: 0...Double(entry.stepGoal)) {
                        Text("steps")
                    }
                    .tint(Theme.stepsPrimary)
                    .gaugeStyle(.accessoryLinear)
                } else {
                    Text("steps")
                        .font(.system(.caption, design: .rounded))
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Entry Views

struct CaloriesEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchVitalsEntry

    var body: some View {
        switch family {
        case .accessoryCircular: CaloriesCircularView(entry: entry)
        case .accessoryRectangular: CaloriesRectangularView(entry: entry)
        case .accessoryInline: CaloriesInlineView(entry: entry)
        case .accessoryCorner: CaloriesCornerView(entry: entry)
        default: CaloriesCircularView(entry: entry)
        }
    }
}

struct StepsEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchVitalsEntry

    var body: some View {
        switch family {
        case .accessoryCircular: StepsCircularView(entry: entry)
        case .accessoryRectangular: StepsRectangularView(entry: entry)
        case .accessoryInline: StepsInlineView(entry: entry)
        case .accessoryCorner: StepsCornerView(entry: entry)
        default: StepsCircularView(entry: entry)
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

// MARK: - Widget Bundle

@main
struct VitalsWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        StepsWidget()
    }
}
