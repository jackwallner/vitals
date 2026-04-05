import Foundation
import Combine
import SwiftUI
import WidgetKit

enum AppAppearance: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class GoalSettings: ObservableObject {
    static let shared = GoalSettings()

    private let defaults: UserDefaults

    @Published var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: "hasCompletedSetup") }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }

    @Published var showPacing: Bool {
        didSet { defaults.set(showPacing, forKey: "showPacing") }
    }

    @Published var showCalories: Bool {
        didSet { defaults.set(showCalories, forKey: "showCalories") }
    }

    @Published var showSteps: Bool {
        didSet { defaults.set(showSteps, forKey: "showSteps") }
    }

    // nil means "no goal" — just show the counter
    @Published var calorieGoal: Double? {
        didSet {
            if let val = calorieGoal {
                defaults.set(val, forKey: "calorieGoal")
                defaults.set(true, forKey: "calorieGoalEnabled")
            } else {
                defaults.set(false, forKey: "calorieGoalEnabled")
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @Published var stepGoal: Int? {
        didSet {
            if let val = stepGoal {
                defaults.set(val, forKey: "stepGoal")
                defaults.set(true, forKey: "stepGoalEnabled")
            } else {
                defaults.set(false, forKey: "stepGoalEnabled")
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private init() {
        let defaults = UserDefaults(suiteName: DataService.appGroupID) ?? .standard
        self.defaults = defaults

        self.hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        self.appearance = AppAppearance(rawValue: defaults.integer(forKey: "appearance")) ?? .system
        self.showPacing = defaults.object(forKey: "showPacing") as? Bool ?? true
        self.showCalories = defaults.object(forKey: "showCalories") as? Bool ?? true
        self.showSteps = defaults.object(forKey: "showSteps") as? Bool ?? true

        let calEnabled = defaults.object(forKey: "calorieGoalEnabled") as? Bool ?? true
        if calEnabled {
            let saved = defaults.double(forKey: "calorieGoal")
            self.calorieGoal = saved > 0 ? saved : 2500
        } else {
            self.calorieGoal = nil
        }

        let stepEnabled = defaults.object(forKey: "stepGoalEnabled") as? Bool ?? true
        if stepEnabled {
            let saved = defaults.integer(forKey: "stepGoal")
            self.stepGoal = saved > 0 ? saved : 10000
        } else {
            self.stepGoal = nil
        }

        applyScreenshotOverridesIfNeeded()
    }

    private func applyScreenshotOverridesIfNeeded() {
        guard ScreenshotConfig.isEnabled else { return }

        showCalories = true
        showSteps = true
        appearance = .system

        if ScreenshotConfig.usesMinimalGoals {
            calorieGoal = nil
            stepGoal = nil
            showPacing = false
            hasCompletedSetup = true
            return
        }

        calorieGoal = 2500
        stepGoal = 10000
        showPacing = true
        hasCompletedSetup = !ScreenshotConfig.wantsOnboarding
    }
}
