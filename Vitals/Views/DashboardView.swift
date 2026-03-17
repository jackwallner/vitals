import SwiftUI

struct DashboardView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared
    @State private var activeCalories: Double = 0
    @State private var restingCalories: Double = 0
    @State private var steps: Int = 0
    @State private var pacingCalories: Double? = nil
    @State private var pacingSteps: Int? = nil
    @State private var isLoading = true
    @State private var animateRing = false
    @State private var animateContent = false
    @State private var showSettings = false
    @State private var showBreakdown = false
    @State private var showOnboarding = false
    @State private var showHealthKitDenied = false

    private var totalCalories: Double { activeCalories + restingCalories }

    private var calorieProgress: Double? {
        guard let goal = goals.calorieGoal, goal > 0 else { return nil }
        return totalCalories / goal
    }

    private var stepProgress: Double? {
        guard let goal = goals.stepGoal, goal > 0 else { return nil }
        return Double(steps) / Double(goal)
    }

    private var isMinimalMode: Bool {
        goals.calorieGoal == nil && goals.stepGoal == nil && !goals.showPacing
    }

    // Only one metric visible
    private var isSingleMetric: Bool {
        goals.showCalories != goals.showSteps
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if !healthKit.isAuthorized && !isLoading {
                healthKitDeniedView
            } else if isLoading {
                loadingView
            } else {
                GeometryReader { geo in
                    mainContent(availableHeight: geo.size.height)
                }
            }
        }
        .onChange(of: healthKit.isAuthorized) { _, authorized in
            if authorized { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refresh() }
        }
        .task {
            if !goals.hasCompletedSetup {
                showOnboarding = true
            }
            await refresh()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(goals: goals)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet(goals: goals)
                .interactiveDismissDisabled()
        }
    }

    private var healthKitDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)
            Text("Health Access Required")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Vitals needs access to HealthKit to display your calories and steps. Please enable access in Settings.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.system(.headline, design: .rounded))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.caloriesPrimary, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
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

    private func mainContent(availableHeight: CGFloat) -> some View {
        // Scale fonts based on mode
        let calNumberSize: CGFloat = {
            if isSingleMetric && !goals.showSteps { return min(availableHeight * 0.12, 100) }
            if isMinimalMode { return min(availableHeight * 0.10, 88) }
            return min(availableHeight * 0.06, 52)
        }()
        let stepsNumberSize: CGFloat = {
            if isSingleMetric && !goals.showCalories { return min(availableHeight * 0.12, 100) }
            if isMinimalMode { return min(availableHeight * 0.08, 68) }
            return min(availableHeight * 0.048, 42)
        }()
        let ringSize: CGFloat = min(availableHeight * 0.32, 260)
        let ringLineWidth: CGFloat = min(availableHeight * 0.022, 18)

        return VStack(spacing: 0) {
            // Header
            HStack {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(10)
                        .background(Theme.cardSurface, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 10)

            Spacer(minLength: 16)

            // Calories section
            if goals.showCalories {
                if let progress = calorieProgress {
                    ZStack {
                        ProgressRing(
                            progress: animateRing ? progress : 0,
                            gradient: Theme.caloriesGradient,
                            glowColor: Theme.caloriesGlow,
                            lineWidth: ringLineWidth,
                            size: ringSize
                        )
                        calorieLabel(numberSize: calNumberSize)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Calorie progress")
                    .accessibilityValue("\(Int(totalCalories)) of \(Int(goals.calorieGoal ?? 0)) calories")
                } else {
                    calorieLabel(numberSize: calNumberSize)
                }

                // Tap to show/hide breakdown
                if !isMinimalMode {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showBreakdown.toggle()
                        }
                    } label: {
                        if showBreakdown {
                            HStack(spacing: 16) {
                                MetricPill(label: "active", value: activeCalories, color: Theme.activePrimary)
                                MetricPill(label: "resting", value: restingCalories, color: Theme.restingPrimary)
                            }
                        } else {
                            Text("Tap for breakdown")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, showBreakdown ? 16 : 8)
                    .opacity(animateContent ? 1 : 0)
                }

                // Calorie pacing
                if goals.showPacing, let pacingCal = pacingCalories {
                    PacingPill(
                        current: totalCalories,
                        typical: pacingCal,
                        label: "cal",
                        color: Theme.caloriesPrimary
                    )
                    .padding(.top, 10)
                    .opacity(animateContent ? 1 : 0)
                }
            }

            if goals.showCalories && goals.showSteps {
                Spacer(minLength: 16)
            }

            // Steps section
            if goals.showSteps {
                if isMinimalMode || (isSingleMetric && !goals.showCalories) {
                    // Clean centered layout
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "figure.walk")
                                .font(isSingleMetric ? .largeTitle : .title)
                                .foregroundStyle(Theme.stepsPrimary)
                            Text(steps, format: .number)
                                .font(Theme.bigNumber(stepsNumberSize))
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(.numericText())
                        }
                        Text("steps")
                            .font(.system(isSingleMetric ? .title3 : .subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(1.5)

                        if goals.showPacing, let pacingStep = pacingSteps {
                            PacingPill(
                                current: Double(steps),
                                typical: Double(pacingStep),
                                label: "steps",
                                color: Theme.stepsPrimary
                            )
                            .padding(.top, 8)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Steps")
                    .accessibilityValue("\(steps) steps")
                    .opacity(animateContent ? 1 : 0)
                    .scaleEffect(animateContent ? 1 : 0.9)
                } else {
                    // Card layout with goals/pacing
                    VStack(spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "figure.walk")
                                .font(.title2)
                                .foregroundStyle(Theme.stepsPrimary)
                            Text(steps, format: .number)
                                .font(Theme.bigNumber(stepsNumberSize))
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(.numericText())
                            if let goal = goals.stepGoal {
                                Text("/ \(goal.formatted(.number))")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                Text("steps")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                    .textCase(.uppercase)
                                    .tracking(1.5)
                            }
                            Spacer()
                            if let progress = stepProgress {
                                Text("\(Int(progress * 100))%")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(Theme.stepsPrimary)
                            }
                        }

                        if let progress = stepProgress {
                            StepProgressBar(
                                progress: animateRing ? progress : 0,
                                gradient: Theme.stepsGradient,
                                glowColor: Theme.stepsGlow
                            )
                        }

                        if goals.showPacing, let pacingStep = pacingSteps {
                            PacingPill(
                                current: Double(steps),
                                typical: Double(pacingStep),
                                label: "steps",
                                color: Theme.stepsPrimary
                            )
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Steps")
                    .accessibilityValue("\(steps) steps")
                    .padding(Theme.cardPadding)
                    .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .padding(.horizontal, 24)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                }
            }

            // Nothing enabled — gentle prompt
            if !goals.showCalories && !goals.showSteps {
                VStack(spacing: 12) {
                    Image(systemName: "heart.text.clipboard")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No metrics selected")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Open Settings") { showSettings = true }
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Theme.caloriesPrimary)
                }
                .opacity(animateContent ? 1 : 0)
            }

            Spacer(minLength: 16)
        }
        .padding(.bottom, 90)
    }

    private func calorieLabel(numberSize: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(totalCalories, format: .number.precision(.fractionLength(0)))
                .font(Theme.bigNumber(numberSize))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            if let goal = goals.calorieGoal {
                Text("/ \(goal, format: .number.precision(.fractionLength(0))) cal")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("calories")
                    .font(.system(isSingleMetric ? .title3 : .subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calories")
        .accessibilityValue("\(Int(totalCalories)) calories")
        .opacity(animateContent ? 1 : 0)
        .scaleEffect(animateContent ? 1 : 0.9)
    }

    private func refresh() async {
        do {
            let stats = try await healthKit.fetchTodayStats()
            activeCalories = stats.active
            restingCalories = stats.resting
            steps = stats.steps

            // Show UI immediately, don't wait for pacing/cache
            if isLoading {
                isLoading = false
                withAnimation(.easeOut(duration: 0.5)) {
                    animateContent = true
                }
                withAnimation(.spring(duration: 1.0, bounce: 0.15).delay(0.3)) {
                    animateRing = true
                }
            }

            // Load pacing and cache in background
            try? await healthKit.refreshCache()
            if goals.showPacing {
                if let pacing = try? await healthKit.fetchPacing() {
                    if pacing.avgCalories > 0 { pacingCalories = pacing.avgCalories }
                    if pacing.avgSteps > 0 { pacingSteps = pacing.avgSteps }
                }
            } else {
                pacingCalories = nil
                pacingSteps = nil
            }
        } catch {
            print("Failed to fetch today stats: \(error)")
            if isLoading {
                isLoading = false
                withAnimation(.easeOut(duration: 0.5)) { animateContent = true }
            }
        }
    }
}

// MARK: - Pacing Pill

private struct PacingPill: View {
    let current: Double
    let typical: Double
    let label: String
    let color: Color

    private var diff: Double { current - typical }
    private var isAhead: Bool { diff >= 0 }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isAhead ? "arrow.up.right" : "arrow.down.right")
                .font(.system(.caption2, design: .rounded, weight: .bold))
            Text("\(abs(Int(diff)).formatted(.number)) \(label) \(isAhead ? "ahead" : "behind") usual pace")
                .font(.system(.caption2, design: .rounded))
        }
        .foregroundStyle(isAhead ? .green : Color(red: 1.0, green: 0.42, blue: 0.42))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (isAhead ? Color.green : Color(red: 1.0, green: 0.42, blue: 0.42)).opacity(0.1),
            in: Capsule()
        )
        .accessibilityLabel("\(abs(Int(diff))) \(label) \(isAhead ? "ahead of" : "behind") usual pace")
    }
}

// MARK: - Metric Pill

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
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.cardSurface, in: Capsule())
    }
}

// MARK: - Onboarding Sheet (first launch only)

private struct OnboardingSheet: View {
    @ObservedObject var goals: GoalSettings
    @Environment(\.dismiss) private var dismiss

    @State private var wantCalGoal = true
    @State private var calText = "2500"
    @State private var wantStepGoal = true
    @State private var stepText = "10000"

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.caloriesPrimary)
                    Text("Welcome to Vitals")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Set up your daily goals, or skip to use as a simple counter.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 16) {
                    GoalRow(
                        icon: "flame.fill",
                        color: Theme.caloriesPrimary,
                        title: "Calorie Goal",
                        enabled: $wantCalGoal,
                        text: $calText
                    )
                    GoalRow(
                        icon: "figure.walk",
                        color: Theme.stepsPrimary,
                        title: "Step Goal",
                        enabled: $wantStepGoal,
                        text: $stepText
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    if wantCalGoal, let cal = Double(calText), cal > 0 {
                        goals.calorieGoal = min(max(cal, 500), 50000)
                    } else {
                        goals.calorieGoal = nil
                    }
                    if wantStepGoal, let step = Int(stepText), step > 0 {
                        goals.stepGoal = min(max(step, 100), 500000)
                    } else {
                        goals.stepGoal = nil
                    }
                    goals.hasCompletedSetup = true
                    dismiss()
                } label: {
                    Text("Get Started")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.caloriesPrimary, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.top, 48)
        }
    }
}

private struct GoalRow: View {
    let icon: String
    let color: Color
    let title: String
    @Binding var enabled: Bool
    @Binding var text: String

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
            }
            if enabled {
                TextField("Target", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(.body, design: .rounded))
                    .padding(12)
                    .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Theme.cardSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @ObservedObject var goals: GoalSettings
    @Environment(\.dismiss) private var dismiss

    @State private var calEnabled = true
    @State private var calText = ""
    @State private var stepEnabled = true
    @State private var stepText = ""
    @State private var pacingEnabled = true
    @State private var showCalories = true
    @State private var showSteps = true
    @State private var appearance: AppAppearance = .system

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Show Calories", isOn: $showCalories)
                    Toggle("Show Steps", isOn: $showSteps)
                }

                Section {
                    Toggle("Calorie Goal", isOn: $calEnabled)
                    if calEnabled {
                        TextField("Daily calories", text: $calText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Toggle("Step Goal", isOn: $stepEnabled)
                    if stepEnabled {
                        TextField("Daily steps", text: $stepText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Toggle("Show Pacing", isOn: $pacingEnabled)
                } footer: {
                    Text("Compare your current progress against your 14-day average at this time of day.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if calEnabled, let cal = Double(calText), cal > 0 {
                            goals.calorieGoal = min(max(cal, 500), 50000)
                        } else if !calEnabled {
                            goals.calorieGoal = nil
                        }
                        if stepEnabled, let step = Int(stepText), step > 0 {
                            goals.stepGoal = min(max(step, 100), 500000)
                        } else if !stepEnabled {
                            goals.stepGoal = nil
                        }
                        goals.showPacing = pacingEnabled
                        goals.showCalories = showCalories
                        goals.showSteps = showSteps
                        goals.appearance = appearance
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                calEnabled = goals.calorieGoal != nil
                calText = goals.calorieGoal.map { String(Int($0)) } ?? "2500"
                stepEnabled = goals.stepGoal != nil
                stepText = goals.stepGoal.map { String($0) } ?? "10000"
                pacingEnabled = goals.showPacing
                showCalories = goals.showCalories
                showSteps = goals.showSteps
                appearance = goals.appearance
            }
        }
    }
}
