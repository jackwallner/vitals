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

struct VitalsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> VitalsEntry {
        VitalsEntry(date: .now, totalCalories: 1240, activeCalories: 340, restingCalories: 900, steps: 4520, calorieGoal: 2500, stepGoal: 10000, calGoalEnabled: true, stepGoalEnabled: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (VitalsEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<VitalsEntry>) -> Void) {
        Task { @MainActor in
            let entry = fetchLatestEntry()
            // Schedule next update in 1 hour, or at midnight if that's sooner
            let oneHour = Calendar.current.date(byAdding: .hour, value: 1, to: .now)
                ?? .now.addingTimeInterval(3600)
            let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
            let nextUpdate = min(oneHour, midnight)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    @MainActor
    private func fetchLatestEntry() -> VitalsEntry {
        let todayKey = DailyHealthRecord.key(for: DateHelpers.startOfDay())
        let container = DataService.sharedModelContainer
        let goals = loadGoals()

        // Try today's record first
        let todayDescriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString == todayKey }
        )
        if let record = try? container.mainContext.fetch(todayDescriptor).first {
            return VitalsEntry(
                date: .now,
                totalCalories: record.totalCalories,
                activeCalories: record.activeCalories,
                restingCalories: record.restingCalories,
                steps: record.steps,
                calorieGoal: goals.calories,
                stepGoal: goals.steps,
                calGoalEnabled: goals.calEnabled,
                stepGoalEnabled: goals.stepEnabled
            )
        }

        // No record for today — could be new day or HealthKit unavailable
        return VitalsEntry(date: .now, totalCalories: 0, activeCalories: 0, restingCalories: 0, steps: 0, calorieGoal: goals.calories, stepGoal: goals.steps, calGoalEnabled: goals.calEnabled, stepGoalEnabled: goals.stepEnabled, dataAvailable: false)
    }
}

// MARK: - Entry

struct VitalsEntry: TimelineEntry {
    let date: Date
    let totalCalories: Double
    let activeCalories: Double
    let restingCalories: Double
    let steps: Int
    let calorieGoal: Double
    let stepGoal: Int
    let calGoalEnabled: Bool
    let stepGoalEnabled: Bool
    var dataAvailable: Bool = true
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: VitalsEntry

    var body: some View {
        if entry.dataAvailable {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Calories", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                        .font(Theme.bigNumber(28))
                        .foregroundStyle(Theme.caloriesPrimary)
                    if entry.calGoalEnabled {
                        Text("/ \(entry.calorieGoal.formatted(.number.precision(.fractionLength(0))))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Label("Steps", systemImage: "figure.walk")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(entry.steps, format: .number)
                        .font(Theme.bigNumber(28))
                        .foregroundStyle(Theme.stepsPrimary)
                    if entry.stepGoalEnabled {
                        Text("/ \(entry.stepGoal.formatted(.number))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "heart.text.clipboard")
                    .font(.title2)
                    .foregroundStyle(Theme.textTertiary)
                Text("Open Vitals to load health data.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct MediumWidgetView: View {
    let entry: VitalsEntry

    var body: some View {
        if entry.dataAvailable {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Calories", systemImage: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                                .font(Theme.bigNumber(28))
                                .foregroundStyle(Theme.caloriesPrimary)
                            if entry.calGoalEnabled {
                                Text("/ \(entry.calorieGoal.formatted(.number.precision(.fractionLength(0))))")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Steps", systemImage: "figure.walk")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(entry.steps, format: .number)
                                .font(Theme.bigNumber(28))
                                .foregroundStyle(Theme.stepsPrimary)
                            if entry.stepGoalEnabled {
                                Text("/ \(entry.stepGoal.formatted(.number))")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Active")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                        Text(entry.activeCalories, format: .number.precision(.fractionLength(0)))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(Theme.activePrimary)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Resting")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                        Text(entry.restingCalories, format: .number.precision(.fractionLength(0)))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(Theme.restingPrimary)
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.clipboard")
                    .font(.title2)
                    .foregroundStyle(Theme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Health Data")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Open Vitals to load your health data.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct CircularAccessoryView: View {
    let entry: VitalsEntry

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
                Text(entry.totalCalories / 1000, format: .number.precision(.fractionLength(1)))
                    .font(.system(.body, design: .rounded, weight: .bold))
                Text("k cal")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct RectangularAccessoryView: View {
    let entry: VitalsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Vitals")
                .font(.system(.headline, design: .rounded))
                .widgetAccentable()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                if entry.calGoalEnabled {
                    Text("/ \(entry.calorieGoal.formatted(.number.precision(.fractionLength(0))))")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                Text(entry.steps, format: .number)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                if entry.stepGoalEnabled {
                    Text("/ \(entry.stepGoal.formatted(.number))")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Entry View (family-aware)

struct VitalsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: VitalsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .accessoryCircular:
            CircularAccessoryView(entry: entry)
        case .accessoryRectangular:
            RectangularAccessoryView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget

@main
struct VitalsWidget: Widget {
    let kind = "VitalsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VitalsTimelineProvider()) { entry in
            VitalsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Vitals")
        .description("Today's calories and steps.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}
