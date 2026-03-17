import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline Provider

struct WatchTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchVitalsEntry {
        WatchVitalsEntry(date: .now, totalCalories: 2450, steps: 8234)
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

        if let record = try? container.mainContext.fetch(descriptor).first {
            return WatchVitalsEntry(
                date: .now,
                totalCalories: record.totalCalories,
                steps: record.steps
            )
        }
        return WatchVitalsEntry(date: .now, totalCalories: 0, steps: 0)
    }
}

// MARK: - Entry

struct WatchVitalsEntry: TimelineEntry {
    let date: Date
    let totalCalories: Double
    let steps: Int
}

// MARK: - Complication Views

struct WatchCircularView: View {
    let entry: WatchVitalsEntry

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

struct WatchRectangularView: View {
    let entry: WatchVitalsEntry

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

struct WatchInlineView: View {
    let entry: WatchVitalsEntry

    var body: some View {
        Text("\(entry.totalCalories.formatted(.number.precision(.fractionLength(0)))) cal | \(entry.steps.formatted(.number)) steps")
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Entry View (family-aware)

struct WatchWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchVitalsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            WatchCircularView(entry: entry)
        case .accessoryRectangular:
            WatchRectangularView(entry: entry)
        case .accessoryInline:
            WatchInlineView(entry: entry)
        default:
            WatchCircularView(entry: entry)
        }
    }
}

// MARK: - Widget

@main
struct VitalsWatchWidget: Widget {
    let kind = "VitalsWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchTimelineProvider()) { entry in
            WatchWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Vitals")
        .description("Today's calories and steps.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}
