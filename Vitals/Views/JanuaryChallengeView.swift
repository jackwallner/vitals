import SwiftUI

/// Loads January's daily totals and marks the goal days.
@MainActor
private func loadJanuaryChallenge(goals: GoalSettings, now: Date) async -> JanuaryChallenge.Snapshot {
    let days = JanuaryChallenge.days()
    var records: [MilestoneDay] = []
    if let first = days.first, let last = days.last, now >= first {
        let end = min(DateHelpers.startOfDay(now), last)
        var history = (try? await HealthKitService.shared.fetchHistory(from: first, to: end)) ?? []
        #if DEBUG
        if ScreenshotConfig.isEnabled { history = ScreenshotFixtures.challengeHistory(through: end) }
        #endif
        records = history.map { MilestoneDay(date: $0.date, calories: $0.active + $0.resting, steps: $0.steps) }
    }
    return JanuaryChallenge.snapshot(
        now: now, records: records, calorieGoal: goals.calorieGoal, stepGoal: goals.stepGoal
    )
}

private func progressLine(_ snapshot: JanuaryChallenge.Snapshot) -> Text {
    guard snapshot.hasStarted else {
        return Text((snapshot.days.first?.date ?? .now).formatted(.dateTime.month(.wide).day()))
    }
    let count = String(snapshot.goalDays) + " "
    return Text(verbatim: count) + Text("of 31 goal days")
}

/// The challenge's door on Today.
struct JanuaryChallengeRow: View {
    @ObservedObject var goals: GoalSettings
    /// Changes when today's goal state or the day does, so the count reloads.
    let refreshID: String
    @State private var snapshot: JanuaryChallenge.Snapshot?

    var body: some View {
        Button {
            DeepLinkRouter.shared.open(.challenge)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.caloriesText)
                    .frame(width: 32, height: 32)
                    .background(Theme.caloriesText.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("New Year Goal Challenge")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let snapshot {
                        progressLine(snapshot)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("januaryChallengeRow")
        .task(id: refreshID) {
            snapshot = await loadJanuaryChallenge(goals: goals, now: JanuaryChallenge.clock())
        }
    }
}

/// The challenge itself: the count, the month, and the rule.
struct JanuaryChallengeSheet: View {
    @ObservedObject var goals: GoalSettings
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: JanuaryChallenge.Snapshot?

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let snapshot {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            hero(snapshot)
                            month(snapshot)
                            rule(complete: snapshot.isComplete)
                        }
                        .padding(20)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ProgressView().tint(Theme.caloriesPrimary)
                }
            }
            .navigationTitle("New Year Goal Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.bold()
                }
            }
            .preferredColorScheme(goals.appearance.colorScheme)
        }
        .task {
            snapshot = await loadJanuaryChallenge(goals: goals, now: JanuaryChallenge.clock())
        }
    }

    @ViewBuilder
    private func hero(_ snapshot: JanuaryChallenge.Snapshot) -> some View {
        VStack(spacing: 4) {
            if snapshot.hasStarted {
                Text(verbatim: String(snapshot.goalDays))
                    .font(Theme.bigNumber(88))
                    .foregroundStyle(Theme.caloriesText)
                Text("of 31 goal days")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                progressLine(snapshot)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.caloriesText)
            }
        }
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
    }

    private func month(_ snapshot: JanuaryChallenge.Snapshot) -> some View {
        let calendar = Calendar.current
        let firstWeekday = calendar.component(.weekday, from: snapshot.days.first?.date ?? .now)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: Self.columns, spacing: 6) {
                // Negative ids: a day's id is its number, and blanks must not share one.
                ForEach((0..<leadingBlanks).map { -1 - $0 }, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(snapshot.days) { dayCell($0) }
            }
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var weekdaySymbols: [String] {
        let raw = DateFormatter().veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = Calendar.current.firstWeekday - 1
        return Array(raw[first...] + raw[..<first])
    }

    private func dayCell(_ day: JanuaryChallenge.Day) -> some View {
        let isHit = day.mark == .hit
        return Text(verbatim: String(day.number))
            .font(.system(.caption, design: .rounded, weight: .bold))
            // The page color on the dark-in-light, light-in-dark green: 4.5:1 both ways.
            .foregroundStyle(isHit ? Theme.background : (day.mark == .ahead ? Theme.textTertiary : Theme.textPrimary))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isHit ? Theme.positiveText : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(day.isToday ? Theme.caloriesText : .clear, lineWidth: 2)
            )
            .accessibilityLabel(Text(day.date.formatted(.dateTime.month(.wide).day())))
            .accessibilityAddTraits(isHit ? .isSelected : [])
    }

    private func rule(complete: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: complete ? "checkmark.seal.fill" : "seal")
                .font(.title3)
                .foregroundStyle(complete ? Theme.positiveText : Theme.textTertiary)
                .frame(width: 32)
                .accessibilityHidden(true)
            Text("Hit your daily goal on all 31 days of January.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
