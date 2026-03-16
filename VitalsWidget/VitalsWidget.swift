import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline Provider

struct VitalsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> VitalsEntry {
        VitalsEntry(date: .now, totalCalories: 2450, activeCalories: 650, restingCalories: 1800, steps: 8234)
    }

    func getSnapshot(in context: Context, completion: @escaping (VitalsEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<VitalsEntry>) -> Void) {
        Task { @MainActor in
            let entry = fetchLatestEntry()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    @MainActor
    private func fetchLatestEntry() -> VitalsEntry {
        let today = DateHelpers.startOfDay()
        let container = DataService.sharedModelContainer
        let descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.date == today }
        )

        if let record = try? container.mainContext.fetch(descriptor).first {
            return VitalsEntry(
                date: .now,
                totalCalories: record.totalCalories,
                activeCalories: record.activeCalories,
                restingCalories: record.restingCalories,
                steps: record.steps
            )
        }
        return VitalsEntry(date: .now, totalCalories: 0, activeCalories: 0, restingCalories: 0, steps: 0)
    }
}

// MARK: - Entry

struct VitalsEntry: TimelineEntry {
    let date: Date
    let totalCalories: Double
    let activeCalories: Double
    let restingCalories: Double
    let steps: Int
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: VitalsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Calories", systemImage: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Label("Steps", systemImage: "figure.walk")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.steps, format: .number)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.blue)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MediumWidgetView: View {
    let entry: VitalsEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Calories", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Label("Steps", systemImage: "figure.walk")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.steps, format: .number)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.activeCalories, format: .number.precision(.fractionLength(0)))
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                Text("Resting")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.restingCalories, format: .number.precision(.fractionLength(0)))
                    .font(.caption.bold())
                    .foregroundStyle(.orange.opacity(0.7))
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CircularAccessoryView: View {
    let entry: VitalsEntry

    var body: some View {
        Gauge(value: min(entry.totalCalories, 3000), in: 0...3000) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text(entry.totalCalories / 1000, format: .number.precision(.fractionLength(1)))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct RectangularAccessoryView: View {
    let entry: VitalsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Vitals")
                .font(.headline)
                .widgetAccentable()
            HStack {
                Image(systemName: "flame.fill")
                Text(entry.totalCalories, format: .number.precision(.fractionLength(0)))
            }
            .font(.caption)
            HStack {
                Image(systemName: "figure.walk")
                Text(entry.steps, format: .number)
            }
            .font(.caption)
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
