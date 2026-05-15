import WidgetKit
import SwiftUI
import SwiftData

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
                stepGoalEnabled: goals.stepEnabled,
                showCalories: goals.showCalories,
                showSteps: goals.showSteps,
                showNetCalories: goals.showNetCalories,
                foodCalories: record.foodCalories
            )
        }

        // Fall back to the most recent prior day so the widget doesn't show
        // a hard-zero "Open app" empty state every morning before the host app
        // (or HKObserverQuery) writes a new same-day cache row.
        var fetchPrior = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString < todayKey }
        )
        fetchPrior.sortBy = [SortDescriptor(\DailyHealthRecord.dateString, order: .reverse)]
        fetchPrior.fetchLimit = 1
        if let prior = try? container.mainContext.fetch(fetchPrior).first {
            return VitalsEntry(
                date: .now,
                totalCalories: prior.totalCalories,
                activeCalories: prior.activeCalories,
                restingCalories: prior.restingCalories,
                steps: prior.steps,
                calorieGoal: goals.calories,
                stepGoal: goals.steps,
                calGoalEnabled: goals.calEnabled,
                stepGoalEnabled: goals.stepEnabled,
                showCalories: goals.showCalories,
                showSteps: goals.showSteps,
                showNetCalories: goals.showNetCalories,
                foodCalories: prior.foodCalories,
                staleDate: prior.date
            )
        }

        // No record at all — first launch or HealthKit unavailable
        return VitalsEntry(date: .now, totalCalories: 0, activeCalories: 0, restingCalories: 0, steps: 0, calorieGoal: goals.calories, stepGoal: goals.steps, calGoalEnabled: goals.calEnabled, stepGoalEnabled: goals.stepEnabled, showCalories: goals.showCalories, showSteps: goals.showSteps, showNetCalories: goals.showNetCalories, dataAvailable: false)
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
    var showCalories: Bool = true
    var showSteps: Bool = true
    var showNetCalories: Bool = false
    var foodCalories: Double = 0
    var netDeficit: Double { totalCalories - foodCalories }
    var dataAvailable: Bool = true
    /// When set, the values are from a prior day (today's cache hasn't been written yet).
    var staleDate: Date? = nil
}

// MARK: - Widget Views

private func staleLabel(for date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInYesterday(date) { return "Yesterday" }
    let daysOld = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: .now)).day ?? 0
    let formatter = DateFormatter()
    formatter.dateFormat = daysOld >= 7 ? "MMM d" : "EEE d"
    return formatter.string(from: date)
}

struct SmallWidgetView: View {
    let entry: VitalsEntry

    private var metricCount: Int {
        (entry.showCalories ? 1 : 0) + (entry.showSteps ? 1 : 0) + (entry.showNetCalories ? 1 : 0)
    }

    private var bigNumberSize: CGFloat {
        switch metricCount {
        case 3: return 20
        case 2: return 28
        default: return 36
        }
    }

    private var blockSpacing: CGFloat { metricCount == 3 ? 4 : 8 }
    private var innerSpacing: CGFloat { metricCount == 3 ? 0 : 2 }
    private var showGoalSubtext: Bool { metricCount < 3 }

    var body: some View {
        if entry.dataAvailable {
            VStack(alignment: .leading, spacing: blockSpacing) {
                if let stale = entry.staleDate {
                    Text(staleLabel(for: stale))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                }
                if entry.showCalories {
                    VStack(alignment: .leading, spacing: innerSpacing) {
                        Label("Calories", systemImage: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                            .font(Theme.bigNumber(bigNumberSize))
                            .foregroundStyle(Theme.caloriesPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if entry.calGoalEnabled && showGoalSubtext {
                            Text("/ \(entry.calorieGoal.formatted(.number.precision(.fractionLength(0))))")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                if entry.showSteps {
                    VStack(alignment: .leading, spacing: innerSpacing) {
                        Label("Steps", systemImage: "figure.walk")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(entry.steps, format: .number)
                            .font(Theme.bigNumber(bigNumberSize))
                            .foregroundStyle(Theme.stepsPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if entry.stepGoalEnabled && showGoalSubtext {
                            Text("/ \(entry.stepGoal.formatted(.number))")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                if entry.showNetCalories {
                    VStack(alignment: .leading, spacing: innerSpacing) {
                        Label("Net Deficit", systemImage: "fork.knife")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(entry.netDeficit, format: .number.precision(.fractionLength(0)).sign(strategy: .always()))
                            .font(Theme.bigNumber(bigNumberSize))
                            .foregroundStyle(entry.netDeficit >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                if metricCount == 0 {
                    Text("No metrics enabled")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "heart.text.clipboard")
                    .font(.title2)
                    .foregroundStyle(Theme.textTertiary)
                Text("Open Total Calories to load health data.")
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

    private var metricCount: Int {
        (entry.showCalories ? 1 : 0) + (entry.showSteps ? 1 : 0) + (entry.showNetCalories ? 1 : 0)
    }

    private var bigNumberSize: CGFloat {
        switch metricCount {
        case 3: return 22
        case 2: return 28
        default: return 36
        }
    }

    private var columnSpacing: CGFloat { metricCount == 3 ? 6 : 12 }
    private var innerSpacing: CGFloat { metricCount == 3 ? 0 : 2 }
    private var showGoalSubtext: Bool { metricCount < 3 }

    var body: some View {
        if entry.dataAvailable {
            VStack(alignment: .leading, spacing: 6) {
                if let stale = entry.staleDate {
                    Text(staleLabel(for: stale))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                }
                HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: columnSpacing) {
                    if entry.showCalories {
                        VStack(alignment: .leading, spacing: innerSpacing) {
                            Label("Calories", systemImage: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                                    .font(Theme.bigNumber(bigNumberSize))
                                    .foregroundStyle(Theme.caloriesPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                if entry.calGoalEnabled && showGoalSubtext {
                                    Text("/ \(entry.calorieGoal.formatted(.number.precision(.fractionLength(0))))")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                    }
                    if entry.showSteps {
                        VStack(alignment: .leading, spacing: innerSpacing) {
                            Label("Steps", systemImage: "figure.walk")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(entry.steps, format: .number)
                                    .font(Theme.bigNumber(bigNumberSize))
                                    .foregroundStyle(Theme.stepsPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                if entry.stepGoalEnabled && showGoalSubtext {
                                    Text("/ \(entry.stepGoal.formatted(.number))")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                    }
                    if entry.showNetCalories {
                        VStack(alignment: .leading, spacing: innerSpacing) {
                            Label("Net Deficit", systemImage: "fork.knife")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            Text(entry.netDeficit, format: .number.precision(.fractionLength(0)).sign(strategy: .always()))
                                .font(Theme.bigNumber(bigNumberSize))
                                .foregroundStyle(entry.netDeficit >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    if metricCount == 0 {
                        Text("No metrics enabled")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                if entry.showCalories {
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
                } // close inner HStack
            } // close outer VStack
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
                    Text("Open Total Calories to load your health data.")
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

    /// Circular accessory has no room for a "Yesterday" pill, so use dimmer styling
    /// to signal stale data instead of silently rendering old numbers as if fresh.
    private var staleOpacity: Double { entry.staleDate == nil ? 1.0 : 0.55 }

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
            .opacity(staleOpacity)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.caloriesPrimary)
                Text(entry.totalCalories / 1000, format: .number.precision(.fractionLength(1)))
                    .font(.system(.body, design: .rounded, weight: .bold))
                Text("kcal")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .opacity(staleOpacity)
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct RectangularAccessoryView: View {
    let entry: VitalsEntry

    private var metricCount: Int {
        (entry.showCalories ? 1 : 0) + (entry.showSteps ? 1 : 0) + (entry.showNetCalories ? 1 : 0)
    }

    /// The rectangular accessory only fits ~3 lines. When all 3 metrics are
    /// enabled, drop the header so every metric stays visible. Stale-date
    /// indicator falls back to dimming the rows (matches CircularAccessoryView).
    private var showHeader: Bool { metricCount < 3 }
    private var rowSpacing: CGFloat { metricCount == 3 ? 1 : 2 }
    private var rowFont: Font {
        metricCount == 3
            ? .system(.caption2, design: .rounded, weight: .semibold)
            : .system(.caption, design: .rounded, weight: .semibold)
    }
    private var showGoalSubtext: Bool { metricCount < 3 }
    private var staleOpacity: Double {
        (entry.staleDate != nil && !showHeader) ? 0.6 : 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            if showHeader {
                HStack(spacing: 6) {
                    Text("Total Calories")
                        .font(.system(.headline, design: .rounded))
                        .widgetAccentable()
                    if let stale = entry.staleDate {
                        Text(staleLabel(for: stale))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                }
            }
            if entry.showCalories {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                        .font(rowFont)
                    if entry.calGoalEnabled && showGoalSubtext {
                        Text("/ \(entry.calorieGoal.formatted(.number.precision(.fractionLength(0))))")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            if entry.showSteps {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                    Text(entry.steps, format: .number)
                        .font(rowFont)
                    if entry.stepGoalEnabled && showGoalSubtext {
                        Text("/ \(entry.stepGoal.formatted(.number))")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            if entry.showNetCalories {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                    Text(entry.netDeficit, format: .number.precision(.fractionLength(0)).sign(strategy: .always()))
                        .font(rowFont)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(entry.netDeficit >= 0 ? Theme.netDeficitPositive : Theme.netDeficitNegative)
            }
        }
        .opacity(staleOpacity)
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
        .configurationDisplayName("Total Calories")
        .description("Today's calories and steps.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}
