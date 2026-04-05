import Foundation

enum ScreenshotScene: String {
    case dashboard
    case minimal
    case history
    case settings
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
#else
    static let isEnabled = false
    static let scene: ScreenshotScene? = nil
#endif

    static var wantsHistoryTab: Bool { scene == .history }
    static var wantsSettingsSheet: Bool { scene == .settings }
    static var wantsOnboarding: Bool { scene == .onboarding }
    static var wantsWatchHelp: Bool { scene == .watchHelp }
    static var wantsWatchBreakdown: Bool { scene == .watchBreakdown }
    static var usesMinimalGoals: Bool { scene == .minimal }
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

    static func pacing() -> (avgCalories: Double, avgSteps: Int, daysWithData: Int) {
        switch ScreenshotConfig.scene {
        case .minimal:
            return (avgCalories: 2050, avgSteps: 7600, daysWithData: 14)
        default:
            return (avgCalories: 1980, avgSteps: 9150, daysWithData: 14)
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
