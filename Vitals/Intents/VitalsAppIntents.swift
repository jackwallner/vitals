import AppIntents
import Foundation

/// Today's totals for Siri, Spotlight, Shortcuts and the Action Button. Reads
/// Apple Health live when the phone is unlocked and falls back to the cache the
/// widgets read (HealthKit data is unreadable while the device is locked).
@MainActor
private enum TodaySnapshot {
    static func load() async -> (active: Double, resting: Double, steps: Int) {
        if let live = try? await HealthKitService.shared.fetchTodayStats(),
           !HealthKitService.isAllZero(live) {
            return live
        }
        if let cached = try? HealthKitService.shared.fetchCachedTodayStats() {
            return cached
        }
        return (0, 0, 0)
    }
}

struct TodayCaloriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories Burned Today"
    static let description = IntentDescription("Your total calories burned today, active plus resting, from Apple Health.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let stats = await TodaySnapshot.load()
        let total = Int((stats.active + stats.resting).rounded())
        let goal = GoalSettings.shared.calorieGoal.map { Int($0.rounded()) }
        return .result(value: total, dialog: IntentDialog(stringLiteral: Self.sentence(total: total, goal: goal)))
    }

    static func sentence(total: Int, goal: Int?) -> String {
        let burned = "You've burned \(total.formatted(.number)) calories today"
        guard let goal, goal > 0 else { return burned + "." }
        if total >= goal { return burned + ". Calorie goal reached." }
        let percent = Int((Double(total) / Double(goal) * 100).rounded(.down))
        return burned + ", \(percent)% of your \(goal.formatted(.number)) goal."
    }
}

struct TodayStepsIntent: AppIntent {
    static let title: LocalizedStringResource = "Steps Today"
    static let description = IntentDescription("Your step count so far today, from Apple Health.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let stats = await TodaySnapshot.load()
        let goal = GoalSettings.shared.stepGoal
        return .result(value: stats.steps, dialog: IntentDialog(stringLiteral: Self.sentence(steps: stats.steps, goal: goal)))
    }

    static func sentence(steps: Int, goal: Int?) -> String {
        let walked = "You've taken \(steps.formatted(.number)) steps today"
        guard let goal, goal > 0 else { return walked + "." }
        if steps >= goal { return walked + ". Step goal reached." }
        return walked + ", \((goal - steps).formatted(.number)) to go."
    }
}

struct VitalsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayCaloriesIntent(),
            phrases: [
                "How many calories have I burned in \(.applicationName)",
                "Calories burned today in \(.applicationName)",
                "Check my calories in \(.applicationName)",
            ],
            shortTitle: "Calories Today",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: TodayStepsIntent(),
            phrases: [
                "How many steps have I taken in \(.applicationName)",
                "Steps today in \(.applicationName)",
                "Check my steps in \(.applicationName)",
            ],
            shortTitle: "Steps Today",
            systemImageName: "figure.walk"
        )
    }
}
