import SwiftUI

struct DashboardView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0
    @State private var isLoading = true
    @State private var animateRing = false
    @State private var animateContent = false

    private var totalCalories: Double { activeCalories + restingCalories }
    private var calorieProgress: Double { totalCalories / Theme.calorieGoal }
    private var stepProgress: Double { Double(steps) / Double(Theme.stepGoal) }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading {
                loadingView
            } else {
                mainContent
            }
        }
        .onChange(of: healthKit.isAuthorized) { _, authorized in
            if authorized { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refresh() }
        }
        .task { await refresh() }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressRing(
                progress: 0.7,
                gradient: Theme.caloriesGradient,
                glowColor: .clear,
                lineWidth: 10,
                size: 60
            )
            .opacity(0.3)
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 10)

            Spacer()

            // Calories ring
            caloriesCard
                .opacity(animateContent ? 1 : 0)
                .scaleEffect(animateContent ? 1 : 0.9)

            Spacer()

            // Steps section
            stepsCard
                .padding(.horizontal, 24)
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 20)

            Spacer()
                .frame(height: 24)
        }
    }

    private var caloriesCard: some View {
        ZStack {
            ProgressRing(
                progress: animateRing ? calorieProgress : 0,
                gradient: Theme.caloriesGradient,
                glowColor: Theme.caloriesGlow,
                lineWidth: 16,
                size: 200
            )

            // Center content
            VStack(spacing: 2) {
                Text(totalCalories, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("calories")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.5)
            }
        }
        .overlay(alignment: .bottom) {
            // Active/resting breakdown
            HStack(spacing: 24) {
                MetricPill(
                    label: "active",
                    value: activeCalories,
                    color: Theme.activePrimary
                )
                MetricPill(
                    label: "resting",
                    value: restingCalories,
                    color: Theme.restingPrimary
                )
            }
            .offset(y: 48)
        }
    }

    private var stepsCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "figure.walk")
                    .font(.title3)
                    .foregroundStyle(Theme.stepsPrimary)
                Text(steps, format: .number)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("steps")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.5)
                Spacer()
                Text("\(Int(stepProgress * 100))%")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.stepsPrimary)
            }

            StepProgressBar(
                progress: animateRing ? stepProgress : 0,
                gradient: Theme.stepsGradient,
                glowColor: Theme.stepsGlow
            )
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func refresh() async {
        do {
            let stats = try await healthKit.fetchTodayStats()
            activeCalories = stats.active
            restingCalories = stats.resting
            steps = stats.steps
            try? await healthKit.refreshCache()
        } catch {
            print("Failed to fetch today stats: \(error)")
        }
        isLoading = false
        withAnimation(.easeOut(duration: 0.5)) {
            animateContent = true
        }
        withAnimation(.spring(duration: 1.0, bounce: 0.15).delay(0.3)) {
            animateRing = true
        }
    }
}

private struct MetricPill: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(value, format: .number.precision(.fractionLength(0)))")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.cardSurface, in: Capsule())
    }
}
