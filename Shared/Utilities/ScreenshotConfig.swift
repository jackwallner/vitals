import Foundation

enum ScreenshotScene: String {
    case dashboard
    case minimal
    case history
    case premium
    case premiumActive
    case premiumDashboard
    case netDeficit
    /// Every calorie number the app can show, on one screen: Net Deficit plus
    /// the macro card, with steps hidden so intake reads as one block.
    case calorieIntake
    case macroDashboard
    case macroGoals
    case macroHistory
    case darkDashboard
    case settings
    /// Settings sheet with Vitals+ unlocked and the intake toggles on, so the
    /// nested Fasting Mode / macro sub-options can be reviewed in capture runs.
    case settingsPro
    case onboarding
    case watchToday
    case watchBreakdown
    case watchHelp
}

enum ScreenshotConfig {
#if DEBUG
    static let isEnabled = ProcessInfo.processInfo.environment["VITALS_SCREENSHOT_MODE"] == "1"
    static let scene = isEnabled
        ? ScreenshotScene(rawValue: ProcessInfo.processInfo.environment["VITALS_SCREENSHOT_SCENE"] ?? "")
        : nil
    /// Force intro-offer ineligible so we can verify used-trial / paid yearly
    /// copy across onboarding, trial sheet, milestone, paywall, and What's New.
    static let forceIntroIneligible =
        ProcessInfo.processInfo.environment["VITALS_FORCE_INTRO_INELIGIBLE"] == "1"
#else
    static let isEnabled = false
    static let scene: ScreenshotScene? = nil
    static let forceIntroIneligible = false
#endif

    static var wantsHistoryTab: Bool { scene == .history || scene == .macroHistory }
    static var wantsPremiumTab: Bool { scene == .premium || scene == .premiumActive }
    // "Premium unlocked" (isPro true + Vitals+ readouts on). Covers the paywall-
    // while-subscribed scene and the premium Today-tab hero showing TDEE/BMR.
    static var wantsPremiumActive: Bool {
        scene == .premiumActive
            || scene == .premiumDashboard
            || scene == .netDeficit
            || scene == .calorieIntake
            || scene == .macroDashboard
            || scene == .macroGoals
            || scene == .macroHistory
            || scene == .settingsPro
    }
    static var wantsSettingsSheet: Bool { scene == .settings || scene == .settingsPro }
    static var wantsOnboarding: Bool { scene == .onboarding }
    static var wantsWatchHelp: Bool { scene == .watchHelp }
    static var wantsWatchBreakdown: Bool { scene == .watchBreakdown }
    static var usesMinimalGoals: Bool { scene == .minimal }
    static var wantsMacroScene: Bool {
        scene == .macroDashboard || scene == .macroGoals || scene == .macroHistory
    }
    static var wantsMacroHistory: Bool { scene == .macroHistory }
    static var wantsNetDeficit: Bool { scene == .netDeficit }
    static var wantsCalorieIntake: Bool { scene == .calorieIntake }
    static var wantsDarkDashboard: Bool { scene == .darkDashboard }
}

#if DEBUG
enum ScreenshotFixtures {
    static func todayStats() -> (active: Double, resting: Double, steps: Int) {
        switch ScreenshotConfig.scene {
        case .minimal:
            return (active: 540, resting: 1695, steps: 8248)
        case .watchToday, .watchBreakdown, .watchHelp:
            return (active: 710, resting: 1610, steps: 11284)
        default:
            return (active: 685, resting: 1715, steps: 10342)
        }
    }

    static func dietaryEnergyToday() -> Double {
        switch ScreenshotConfig.scene {
        case .minimal:
            return 1400
        default:
            return 1950
        }
    }

    static func macrosToday() -> MacroTotals {
        switch ScreenshotConfig.scene {
        case .minimal:
            return MacroTotals(protein: 118, carbs: 156, fat: 52)
        default:
            return MacroTotals(protein: 142, carbs: 186, fat: 61)
        }
    }

    static func energyAverages() -> EnergyAveragesResult {
        EnergyAveragesResult(tdee: 2380, bmr: 1715, sampleDays: 30)
    }

    /// Plausible macro history for capture runs. Deterministic per day offset so
    /// repeated captures produce identical charts.
    static func macroHistory(days: Int, end: Date = .now) -> [(date: Date, macros: MacroTotals)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: end)
        return (0..<max(days, 0)).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
            let wobble = Double((offset * 37) % 11) - 5
            return (
                date: date,
                macros: MacroTotals(
                    protein: 140 + wobble * 3,
                    carbs: 185 + wobble * 6,
                    fat: 60 + wobble * 2
                )
            )
        }
    }

    static func pacing() -> PacingResult {
        switch ScreenshotConfig.scene {
        case .minimal:
            return PacingResult(avgCalories: 2050, avgSteps: 7600, calorieSampleDays: 14, stepSampleDays: 14)
        default:
            return PacingResult(avgCalories: 1980, avgSteps: 9150, calorieSampleDays: 14, stepSampleDays: 14)
        }
    }

    static func history(days: Int, end: Date = .now) -> [(date: Date, active: Double, resting: Double, steps: Int)] {
        let totalDays = max(days, 30)
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: end)

        return (0..<totalDays).compactMap { index in
            let reverseIndex = totalDays - index - 1
            guard let date = calendar.date(byAdding: .day, value: -reverseIndex, to: endDate) else {
                return nil
            }

            let dayOffset = Double(index)
            let active = 480 + sin(dayOffset / 3.4) * 140 + Double(index % 5) * 18
            let resting = 1585 + cos(dayOffset / 7.0) * 55
            let steps = Int(7600 + sin(dayOffset / 2.7) * 1650 + Double(index % 4) * 380)

            return (
                date: date,
                active: max(active, 250),
                resting: max(resting, 1400),
                steps: max(steps, 3200)
            )
        }
    }
}
#endif
