import SwiftUI

/// Vitals+ screen for picking the days that shouldn't count (see [[ExcludedDays]]).
///
/// A calendar, because the question the user is answering is "which days" and a
/// calendar is the only control that answers it in one gesture. A flu week is
/// five taps here and five separate list additions anywhere else. The excluded
/// days are listed underneath with the numbers they carry, so the user can
/// confirm they excluded the day they meant to before leaving the screen.
///
/// Without Vitals+ the screen still opens, so a free user sees exactly what
/// they would get, and every control answers with the trial pitch instead of
/// changing anything. The pitch names one of their own days (see
/// `ExcludedDaysPitch`), and buying from it carries out the tap that raised it.
struct ExcludedDaysView: View {
    @ObservedObject var goals: GoalSettings
    @EnvironmentObject private var store: StoreService

    /// What a locked tap asked for, carried out if the pitch converts.
    private enum LockedAction: Equatable {
        case exclude(Date)
        case pause
    }

    @State private var pitch: TrialPitchRequest?
    @State private var pendingAction: LockedAction?
    @State private var wantsPlanPicker = false
    @State private var showPlanPicker = false
    /// Recent daily burn, loaded only while locked, to name a day in the pitch.
    @State private var recentCalories: [(date: Date, calories: Double)] = []
    /// MultiDatePicker keeps its own selection and ignores a binding that
    /// refuses a tap, so a locked tap stays drawn selected. Rebuilding the
    /// picker when the pitch closes is the only way to clear it.
    @State private var pickerID = UUID()

    private var isLocked: Bool { !store.isPro }

    /// The lowest recent day, shown before any tap so the locked screen says
    /// what the feature would do for this user rather than for anyone.
    private var suggestion: ExcludedDaysPitch? {
        ExcludedDaysPitch.make(history: recentCalories)
    }

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
        // The pause only caps the picker while it is actually running. Locked,
        // it is dormant, and letting it shorten the range would leave a lapsed
        // subscriber unable to tap the recent days the upsell is there to sell.
        let pauseCap = isLocked ? nil : goals.averagesPausedSince
        let end = pauseCap.map { calendar.startOfDay(for: $0) } ?? defaultEnd
        return start..<max(end, calendar.date(byAdding: .day, value: 1, to: start) ?? end)
    }

    private var selection: Binding<Set<DateComponents>> {
        Binding(
            get: {
                // Locked, nothing is excluded, so nothing is drawn selected: a
                // tapped day snaps back as the pitch rises.
                guard !isLocked else { return [] }
                return Set(goals.excludedDates.map {
                    calendar.dateComponents([.calendar, .era, .year, .month, .day], from: $0)
                })
            },
            set: { components in
                let dates = components.compactMap { calendar.date(from: $0) }
                guard !isLocked else {
                    if let tapped = dates.first { presentPitch(for: .exclude(tapped)) }
                    return
                }
                goals.setExcludedDays(dates)
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
            if isLocked {
                Section {
                    lockedCard
                }
            }

            Section {
                pauseRow
            } footer: {
                Text(pauseFooter)
            }

            Section {
                MultiDatePicker(selection: selection, in: selectableRange) {
                    Text("Excluded days")
                }
                .id(pickerID)
                .frame(minHeight: 320)
            } header: {
                HStack(spacing: 6) {
                    Text("Pick Days")
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.caloriesPrimary)
                            .accessibilityLabel("Vitals+")
                    }
                }
            } footer: {
                Text(
                    isLocked
                        ? "Tap a day to take it out of your averages with Vitals+."
                        : goals.isAveragesPaused
                            ? "Tap a day before the pause to take it out too. Tap it again to put it back."
                            : "Tap a day to take it out of your averages. Tap it again to put it back."
                )
            }

            if isLocked {
                Section {
                } footer: {
                    Text(effectFooter)
                }
            } else if excludedDates.isEmpty {
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
        // Every appearance, not once: a first open before HealthKit has answered
        // (fresh install, permission still pending) would otherwise keep the
        // generic card for good.
        .task { await loadRecentCaloriesIfLocked() }
        .sheet(item: $pitch, onDismiss: finishPitch) { request in
            TrialOfferPitchSheet(
                request: request,
                onDismiss: { pitch = nil },
                onNeedsPlanPicker: {
                    wantsPlanPicker = true
                    pitch = nil
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showPlanPicker, onDismiss: finishPitch) {
            PaywallView(focus: .excludedDays)
                .environmentObject(store)
                .task { store.trackPaywallImpression(id: "vitals_trial_sheet_excluded_days") }
        }
    }

    // MARK: - Locked

    private var lockedCard: some View {
        let suggestion = self.suggestion
        return VStack(alignment: .leading, spacing: 10) {
            Text("Vitals+")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.caloriesPrimary)
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion?.headline ?? "Keep odd days out of your averages")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(suggestion?.subheadline ?? "Pick the days that shouldn't count, like a sick day or a day the watch stayed on the charger.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                presentPitch(for: suggestion.map { .exclude($0.day) }, copy: suggestion)
            } label: {
                Text(suggestion.map { "Exclude \(Self.shortDayFormatter.string(from: $0.day))" } ?? "Try Excluded Days")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Theme.caloriesPrimary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("excluded-days-unlock")
        }
        .padding(.vertical, 6)
    }

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    /// `copy` is passed when the caller already has the pitch it is showing
    /// (the lowest-day card), so the sheet repeats the card word for word.
    private func presentPitch(for action: LockedAction?, copy: ExcludedDaysPitch? = nil) {
        pendingAction = action
        var copy = copy
        if copy == nil, case .exclude(let day) = action {
            copy = ExcludedDaysPitch.make(history: recentCalories, tapped: day)
        }
        pitch = TrialPitchRequest(excludedDays: copy, impressionID: "vitals_trial_offer_excluded_days")
    }

    /// Runs when either sheet closes. Bought: do what the tap asked. The plan
    /// picker hand-off closes the pitch first, so hold the action for it.
    private func finishPitch() {
        pickerID = UUID()
        if wantsPlanPicker {
            wantsPlanPicker = false
            showPlanPicker = true
            return
        }
        defer { pendingAction = nil }
        guard store.isPro, let pendingAction else { return }
        switch pendingAction {
        case .exclude(let day): goals.setDay(day, excluded: true)
        case .pause: goals.pauseAverages()
        }
    }

    private func loadRecentCaloriesIfLocked() async {
        guard isLocked, recentCalories.isEmpty else { return }
        guard let history = try? await HealthKitService.shared.fetchHistory(days: ExcludedDaysPitch.windowDays + 1) else { return }
        recentCalories = history.map { ($0.date, $0.active + $0.resting) }
    }

    /// Pause is the first row because it is the decision with a clock on it: a
    /// user who opened this screen mid-flu wants the switch, not the calendar.
    @ViewBuilder
    private var pauseRow: some View {
        Toggle(isOn: pauseBinding) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Pause Averages")
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.caloriesPrimary)
                    }
                }
                Text(pauseSubtitle)
                    .font(.caption)
                    .foregroundStyle(pauseSubtitleIsActive ? Theme.caloriesPrimary : Theme.textSecondary)
            }
        }
        // The subtitle carries the only statement of whether a pause exists and
        // since when. A bare "Pause averages" label replaces the whole subtree,
        // so VoiceOver announced the switch without ever mentioning the pause.
        .accessibilityLabel("Pause averages. \(pauseSubtitle)")
    }

    /// Reads the row's second line. Locked, a stored pause is dormant:
    /// `GoalSettings.excludedDayKeys` returns an empty set while Vitals+ is
    /// inactive, so counting its days here would describe a state the numbers
    /// don't agree with.
    private var pauseSubtitle: String {
        guard let since = goals.averagesPausedSince else {
            return "Stop counting new days until you resume"
        }
        let date = Self.pauseDateFormatter.string(from: since)
        if isLocked {
            return "Paused since \(date) · on hold without Vitals+"
        }
        let count = goals.pausedDates.count
        return "Paused since \(date) · \(count) \(count == 1 ? "day" : "days")"
    }

    /// Only a pause that is actually filtering gets the accent colour.
    private var pauseSubtitleIsActive: Bool {
        !isLocked && goals.isAveragesPaused
    }

    private var pauseBinding: Binding<Bool> {
        Binding(
            get: { !isLocked && goals.isAveragesPaused },
            set: { paused in
                guard !isLocked else {
                    if paused { presentPitch(for: .pause) }
                    return
                }
                if paused {
                    goals.pauseAverages()
                } else {
                    goals.resumeAverages()
                }
            }
        )
    }

    private var pauseFooter: String {
        if isLocked {
            // Nothing is being excluded while Vitals+ is inactive, so neither
            // active-pause line is true. Say what is actually kept instead —
            // and with nothing kept, fall through to the plain description of
            // what the feature does.
            if goals.isAveragesPaused {
                return "Your pause and excluded days are saved. Every day is counting toward your averages again until Vitals+ is back."
            }
            if !goals.excludedDates.isEmpty {
                return "Your excluded days are saved. Every day is counting toward your averages until Vitals+ is back."
            }
        }
        return goals.isAveragesPaused
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
