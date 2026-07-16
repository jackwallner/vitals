import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Entry

/// Running 30-day maintenance (TDEE) and resting (BMR) averages, mirroring the
/// Vitals+ readout on the Today tab. Computed from the shared SwiftData cache the
/// app keeps populated (widgets can't query HealthKit directly).
struct EnergyAveragesEntry: TimelineEntry {
    let date: Date
    let tdee: Double?
    let bmr: Double?
    let sampleDays: Int
    /// Mirrors the live Vitals+ entitlement so the paid figure stays behind the
    /// paywall even if the widget is added from the gallery by a free user.
    var isPro: Bool = true
    /// False when the cache holds no history at all (fresh install / no access).
    var hasCache: Bool = true

    static let minSamples = 7

    /// A number to show, or nil while building / locked / empty.
    var showsFigures: Bool { isPro && tdee != nil && bmr != nil }
}

// MARK: - Timeline Provider

struct EnergyAveragesProvider: TimelineProvider {
    func placeholder(in context: Context) -> EnergyAveragesEntry {
        EnergyAveragesEntry(date: .now, tdee: 2450, bmr: 1780, sampleDays: 30)
    }

    func getSnapshot(in context: Context, completion: @escaping (EnergyAveragesEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<EnergyAveragesEntry>) -> Void) {
        Task { @MainActor in
            let entry = fetchLatestEntry()
            // TDEE is a slow-moving 30-day average — a couple refreshes a day is
            // plenty. Refresh in ~3h, or at the next midnight when the completed-day
            // window rolls forward, whichever comes first.
            let threeHours = Calendar.current.date(byAdding: .hour, value: 3, to: .now)
                ?? .now.addingTimeInterval(3 * 3600)
            let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
            let nextUpdate = min(threeHours, midnight)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    @MainActor
    private func fetchLatestEntry() -> EnergyAveragesEntry {
        let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
        let isPro = defaults.bool(forKey: StoreService.cachedProKey)

        let todayKey = DailyHealthRecord.key(for: DateHelpers.startOfDay())
        let container = DataService.sharedModelContainer

        // Pull the most recent completed days (today is excluded via predicate).
        // 34 rows comfortably covers the 30-day window even with a few gaps.
        var descriptor = FetchDescriptor<DailyHealthRecord>(
            predicate: #Predicate { $0.dateString < todayKey }
        )
        descriptor.sortBy = [SortDescriptor(\DailyHealthRecord.dateString, order: .reverse)]
        descriptor.fetchLimit = 34

        guard let rows = try? container.mainContext.fetch(descriptor), !rows.isEmpty else {
            return EnergyAveragesEntry(date: .now, tdee: nil, bmr: nil, sampleDays: 0, isPro: isPro, hasCache: false)
        }

        let result = EnergyAveragesCalculator.compute(
            records: rows.map { (date: $0.date, active: $0.activeCalories, resting: $0.restingCalories) },
            referenceDate: .now,
            minSamples: EnergyAveragesEntry.minSamples
        )
        return EnergyAveragesEntry(
            date: .now,
            tdee: result.tdee,
            bmr: result.bmr,
            sampleDays: result.sampleDays,
            isPro: isPro,
            hasCache: true
        )
    }
}

// MARK: - Shared pieces

private struct EnergyLockedView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Theme.caloriesPrimary)
            Text("TDEE average")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("A Vitals+ feature. Open Total Calories to unlock.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct EnergyBuildingView: View {
    let sampleDays: Int
    let hasCache: Bool
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.title3)
                .foregroundStyle(Theme.textTertiary)
            Text("TDEE average")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(hasCache
                ? "Building: \(sampleDays)/\(EnergyAveragesEntry.minSamples) days"
                : "Open Total Calories to load health data.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Routes an entry to locked / building / value content so each family view only
/// has to lay out the numbers.
@ViewBuilder
private func energyContent(_ entry: EnergyAveragesEntry, @ViewBuilder figures: () -> some View) -> some View {
    if !entry.isPro {
        EnergyLockedView()
    } else if entry.showsFigures {
        figures()
    } else {
        EnergyBuildingView(sampleDays: entry.sampleDays, hasCache: entry.hasCache)
    }
}

// MARK: - Home Screen families

struct EnergySmallView: View {
    let entry: EnergyAveragesEntry

    var body: some View {
        energyContent(entry) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Maintenance", systemImage: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .labelStyle(.titleAndIcon)
                Text(entry.tdee ?? 0, format: .number.precision(.fractionLength(0)))
                    .font(Theme.bigNumber(36))
                    .foregroundStyle(Theme.caloriesPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("cal · TDEE")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle().fill(Theme.restingPrimary).frame(width: 6, height: 6)
                    Text("\(entry.bmr ?? 0, format: .number.precision(.fractionLength(0))) BMR")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("30-day avg")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct EnergyMediumView: View {
    let entry: EnergyAveragesEntry

    var body: some View {
        energyContent(entry) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Maintenance · 30-day avg")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 16) {
                    energyColumn(label: "TDEE", value: entry.tdee ?? 0, color: Theme.caloriesPrimary)
                    energyColumn(label: "BMR", value: entry.bmr ?? 0, color: Theme.restingPrimary)
                    Spacer(minLength: 0)
                }
                Text("From Apple Health")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func energyColumn(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(Theme.bigNumber(30))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Lock Screen accessories

struct EnergyCircularView: View {
    let entry: EnergyAveragesEntry

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "flame.fill")
                .font(.caption)
                .foregroundStyle(Theme.caloriesPrimary)
            if entry.showsFigures {
                Text((entry.tdee ?? 0) / 1000, format: .number.precision(.fractionLength(1)))
                    .font(.system(.body, design: .rounded, weight: .bold))
                Text("TDEE")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.system(.body, design: .rounded, weight: .bold))
                Text("TDEE")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct EnergyRectangularView: View {
    let entry: EnergyAveragesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Maintenance")
                    .font(.system(.headline, design: .rounded))
                    .widgetAccentable()
            }
            if entry.showsFigures {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text(entry.tdee ?? 0, format: .number.precision(.fractionLength(0)))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                    Text("TDEE")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Image(systemName: "bed.double.fill")
                    Text(entry.bmr ?? 0, format: .number.precision(.fractionLength(0)))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                    Text("BMR")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text(entry.isPro ? "Building 30-day average" : "Vitals+ feature")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Entry View (family-aware)

struct EnergyAveragesEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: EnergyAveragesEntry

    var body: some View {
        switch family {
        case .systemSmall:
            EnergySmallView(entry: entry)
        case .systemMedium:
            EnergyMediumView(entry: entry)
        case .accessoryCircular:
            EnergyCircularView(entry: entry)
        case .accessoryRectangular:
            EnergyRectangularView(entry: entry)
        default:
            EnergySmallView(entry: entry)
        }
    }
}

// MARK: - Widget

struct EnergyAveragesWidget: Widget {
    let kind = "VitalsEnergyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EnergyAveragesProvider()) { entry in
            EnergyAveragesEntryView(entry: entry)
        }
        .configurationDisplayName("Maintenance (TDEE)")
        .description("Your running 30-day TDEE and BMR average from Apple Health.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}
