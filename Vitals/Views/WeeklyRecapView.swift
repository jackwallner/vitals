import SwiftUI

/// Vitals+ weekly recap surface. Presented when the user taps the weekly
/// notification or the inline "view recap" affordance. Loads its own data so
/// callers just present `WeeklyRecapView()`.
struct WeeklyRecapView: View {
    @ObservedObject var goals: GoalSettings
    @Environment(\.dismiss) private var dismiss

    @State private var recap: WeeklyRecap?
    @State private var loaded = false

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                content
            }
            .navigationTitle("This Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.bold()
                }
            }
            .preferredColorScheme(goals.appearance.colorScheme)
        }
        .task {
            guard !loaded else { return }
            loaded = true
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            ProgressView().tint(Theme.caloriesPrimary)
        } else if let recap {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headline(recap)
                    metricCards(recap)
                    if let hit = recap.goalDaysHit, let possible = recap.goalDaysPossible {
                        goalCard(hit: hit, possible: possible)
                    }
                    if let best = recap.bestCalorieDay, let value = recap.bestCalorieValue {
                        bestDayCard(day: best, value: value)
                    }
                }
                .padding(20)
            }
        } else {
            emptyState
        }
    }

    private func headline(_ recap: WeeklyRecap) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.caloriesGradient)
            Text("Last 7 days")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(recap.daysWithData) day\(recap.daysWithData == 1 ? "" : "s") with data")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func metricCards(_ recap: WeeklyRecap) -> some View {
        HStack(spacing: 12) {
            statCard(
                title: "Avg calories",
                value: Int(recap.avgCalories.rounded()).formatted(.number),
                changePct: recap.calorieChangePct,
                tint: Theme.caloriesPrimary
            )
            statCard(
                title: "Avg steps",
                value: recap.avgSteps.formatted(.number),
                changePct: recap.stepChangePct,
                tint: Theme.stepsPrimary
            )
        }
    }

    private func statCard(title: String, value: String, changePct: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let pct = changePct {
                let up = pct >= 0
                Label("\(up ? "+" : "")\(Int(pct.rounded()))% vs. last week",
                      systemImage: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .labelStyle(.titleAndIcon)
            } else {
                Text("No prior week")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func goalCard(hit: Int, possible: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.ringTrack, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: possible > 0 ? CGFloat(hit) / CGFloat(possible) : 0)
                    .stroke(Theme.caloriesGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(hit)/\(possible)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Goal days hit")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("You met a goal on \(hit) of \(possible) days with data.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func bestDayCard(day: Date, value: Double) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.caloriesSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Best day")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(Self.dayFmt.string(from: day)) — \(Int(value.rounded()).formatted(.number)) cal")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textTertiary)
            Text("Not enough data yet")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text("Once you've tracked a few days, your weekly recap will appear here.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private func load() async {
        let rows = (try? await HealthKitService.shared.fetchMergedHistory(days: 16)) ?? []
        let records = rows.map { MilestoneDay(date: $0.date, calories: $0.active + $0.resting, steps: $0.steps) }
        recap = WeeklyRecapBuilder.build(
            records: records,
            calorieGoal: goals.calorieGoal,
            stepGoal: goals.stepGoal
        )
    }
}
