import SwiftUI

/// Vitals+ screen for picking the days that shouldn't count (see [[ExcludedDays]]).
///
/// A calendar, because the question the user is answering is "which days" and a
/// calendar is the only control that answers it in one gesture. A flu week is
/// five taps here and five separate list additions anywhere else. The excluded
/// days are listed underneath with the numbers they carry, so the user can
/// confirm they excluded the day they meant to before leaving the screen.
struct ExcludedDaysView: View {
    @ObservedObject var goals: GoalSettings

    /// Calories and steps for the excluded days, so a row reads as the day the
    /// user remembers rather than a bare date. Best-effort: a HealthKit failure
    /// leaves the numbers off and changes nothing else on the screen.
    @State private var statsByKey: [String: (calories: Double, steps: Int)] = [:]

    private let calendar = Calendar.current

    /// Three years back is past any window the app charts, and the picker has to
    /// stop somewhere or it scrolls forever. The upper bound is tomorrow's start,
    /// which makes today selectable and nothing after it: a day that hasn't
    /// happened has nothing to exclude.
    ///
    /// While a pause is running, the range stops at the pause instead. The paused
    /// days are already excluded and the pause owns them until it ends, so
    /// offering them as tappable calendar days would only invite a tap that
    /// appears to do nothing.
    private var selectableRange: Range<Date> {
        let today = DateHelpers.startOfDay()
        let start = calendar.date(byAdding: .year, value: -3, to: today) ?? today
        let defaultEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let end = goals.averagesPausedSince.map { calendar.startOfDay(for: $0) } ?? defaultEnd
        return start..<max(end, calendar.date(byAdding: .day, value: 1, to: start) ?? end)
    }

    private var selection: Binding<Set<DateComponents>> {
        Binding(
            get: {
                Set(goals.excludedDates.map {
                    calendar.dateComponents([.calendar, .era, .year, .month, .day], from: $0)
                })
            },
            set: { components in
                goals.setExcludedDays(components.compactMap { calendar.date(from: $0) })
            }
        )
    }

    private var excludedDates: [Date] { goals.excludedDates }

    private static let rowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f
    }()

    var body: some View {
        Form {
            Section {
                pauseRow
            } footer: {
                Text(pauseFooter)
            }

            Section {
                MultiDatePicker(selection: selection, in: selectableRange) {
                    Text("Excluded days")
                }
                .frame(minHeight: 320)
            } header: {
                Text("Pick Days")
            } footer: {
                Text(
                    goals.isAveragesPaused
                        ? "Tap a day before the pause to take it out too. Tap it again to put it back."
                        : "Tap a day to take it out of your averages. Tap it again to put it back."
                )
            }

            if excludedDates.isEmpty {
                Section {
                    emptyState
                } footer: {
                    Text(effectFooter)
                }
            } else {
                Section {
                    ForEach(excludedDates, id: \.self) { date in
                        row(for: date)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            goals.setDay(excludedDates[index], excluded: false)
                        }
                    }
                } header: {
                    HStack {
                        Text(excludedDates.count == 1 ? "1 Excluded Day" : "\(excludedDates.count) Excluded Days")
                        Spacer()
                        Button("Clear All", role: .destructive) {
                            goals.clearExcludedDays()
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                } footer: {
                    Text(effectFooter)
                }
            }
        }
        .navigationTitle("Excluded Days")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: goals.excludedDayKeys) { await loadStats() }
    }

    /// Pause is the first row because it is the decision with a clock on it: a
    /// user who opened this screen mid-flu wants the switch, not the calendar.
    @ViewBuilder
    private var pauseRow: some View {
        Toggle(isOn: pauseBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pause Averages")
                if let since = goals.averagesPausedSince {
                    Text("Paused since \(Self.pauseDateFormatter.string(from: since)) · \(goals.pausedDates.count) \(goals.pausedDates.count == 1 ? "day" : "days")")
                        .font(.caption)
                        .foregroundStyle(Theme.caloriesPrimary)
                } else {
                    Text("Stop counting new days until you resume")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityLabel("Pause averages")
    }

    private var pauseBinding: Binding<Bool> {
        Binding(
            get: { goals.isAveragesPaused },
            set: { paused in
                if paused {
                    goals.pauseAverages()
                } else {
                    goals.resumeAverages()
                }
            }
        )
    }

    private var pauseFooter: String {
        goals.isAveragesPaused
            ? "Today and every day until you resume is excluded. Resuming starts counting again and keeps the paused days excluded, and you can drop them from the list below afterwards."
            : "For a stretch you can't put an end date on yet: an injury, a trip, a spell off the wrist. Each new day is excluded automatically until you resume."
    }

    private static let pauseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var effectFooter: String {
        "Excluded days count toward no average, total, best day, pacing figure, or weekly recap, and they neither extend nor break a goal streak. Nothing is deleted: they stay in your charts and CSV export, drawn dimmed."
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No days excluded")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("A week with the flu, a long flight, a day the watch stayed on the charger. Pick those days above and your averages stop counting them.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func row(for date: Date) -> some View {
        HStack {
            Text(Self.rowDateFormatter.string(from: date))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let stats = statsByKey[ExcludedDays.key(for: date)] {
                HStack(spacing: 6) {
                    Text(stats.calories.formatted(.number.precision(.fractionLength(0))))
                        .foregroundStyle(Theme.caloriesPrimary)
                    Text("·")
                        .foregroundStyle(Theme.textTertiary)
                    Text(stats.steps.formatted(.number))
                        .foregroundStyle(Theme.stepsPrimary)
                }
                .font(.system(.caption, design: .rounded, weight: .semibold).monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: date))
    }

    private func accessibilityLabel(for date: Date) -> String {
        let base = Self.rowDateFormatter.string(from: date) + ", excluded"
        guard let stats = statsByKey[ExcludedDays.key(for: date)] else { return base }
        return "\(base), \(Int(stats.calories)) calories, \(stats.steps) steps"
    }

    /// One query covering the oldest excluded day through today. Cheaper and
    /// simpler than a fetch per row, and the set is small by nature.
    private func loadStats() async {
        let allExcluded = goals.excludedDayKeys.compactMap(GoalSettings.date(fromDayKey:))
        guard let earliest = allExcluded.min() else {
            statsByKey = [:]
            return
        }
        guard let history = try? await HealthKitService.shared.fetchHistory(from: earliest, to: .now) else { return }
        var map: [String: (calories: Double, steps: Int)] = [:]
        for day in history {
            map[ExcludedDays.key(for: day.date)] = (day.active + day.resting, day.steps)
        }
        statsByKey = map
    }
}
