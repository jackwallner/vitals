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

enum GoalSyncKeys {
    static let calorieGoal = "goalSync.calorieGoal"
    static let stepGoal = "goalSync.stepGoal"
    static let calorieGoalEnabled = "goalSync.calorieGoalEnabled"
    static let stepGoalEnabled = "goalSync.stepGoalEnabled"
    static let showNetCalories = "goalSync.showNetCalories"
    static let showCalories = "goalSync.showCalories"
    static let showSteps = "goalSync.showSteps"
}

/// How to aggregate historical days when computing “usual” progress at this time of day.
enum PacingComparison: Int, CaseIterable, Sendable {
    /// Average only past days that match today’s weekday (e.g. compare Mondays to Mondays).
    case dayOfWeek = 0
    /// Average every day in the lookback window (subject to non-empty samples).
    case allDays = 1

    var label: String {
        switch self {
        case .dayOfWeek: "Same weekday"
        case .allDays: "All days"
        }
    }
}

/// How far back to look for pacing samples (completed days before today; empty days excluded per metric).
enum PacingLookback: Int, CaseIterable, Sendable {
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90
    case oneYear = 365

    static let `default` = PacingLookback.thirtyDays

    var label: String {
        switch self {
        case .fourteenDays: "14 days"
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        case .oneYear: "1 year"
        }
    }
}

/// Effective minimum number of sample days required before pacing rendering is allowed.
/// Must match the logic in `DashboardView.refresh()` so the Settings footer reports the
/// same threshold the dashboard actually enforces.
///
/// For `.dayOfWeek`: `lookback / 7` is the maximum number of matching weekdays within
/// the window, capped at 4 so "1 Year × Same Weekday" isn't blocked by a 52-day
/// requirement. For `.allDays`: fixed at 3.
func effectiveMinPacingSamples(for comparison: PacingComparison, lookback: PacingLookback) -> Int {
    switch comparison {
    case .dayOfWeek:
        let raw = max(lookback.rawValue / 7, 1)
        return min(raw, 3)
    case .allDays:
        return 3
    }
}

/// Usual calories/steps by this time of day; sample counts exclude empty days per metric.
struct PacingResult: Sendable {
    let avgCalories: Double?
    let avgSteps: Int?
    let calorieSampleDays: Int
    let stepSampleDays: Int
    /// Usual *full-day* totals over the same sample set (no time-of-day weighting).
    /// Drives the Vitals+ end-of-day projection: expected remaining = full − now.
    /// nil when there aren't enough samples, exactly like the time-weighted averages.
    let avgCaloriesFullDay: Double?
    let avgStepsFullDay: Int?

    init(
        avgCalories: Double?,
        avgSteps: Int?,
        calorieSampleDays: Int,
        stepSampleDays: Int,
        avgCaloriesFullDay: Double? = nil,
        avgStepsFullDay: Int? = nil
    ) {
        self.avgCalories = avgCalories
        self.avgSteps = avgSteps
        self.calorieSampleDays = calorieSampleDays
        self.stepSampleDays = stepSampleDays
        self.avgCaloriesFullDay = avgCaloriesFullDay
        self.avgStepsFullDay = avgStepsFullDay
    }

    /// Resolves optional dashboard values: needs enough non-empty sample days per visible metric.
    func dashboardValues(minSamples: Int = 3, showCalories: Bool, showSteps: Bool) -> (
        calories: Double?,
        caloriesBuilding: Bool,
        steps: Int?,
        stepsBuilding: Bool
    ) {
        let calories: Double?
        let caloriesBuilding: Bool
        if showCalories {
            if let avg = avgCalories, calorieSampleDays >= minSamples, avg > 0 {
                calories = avg
                caloriesBuilding = false
            } else {
                calories = nil
                caloriesBuilding = calorieSampleDays > 0 && calorieSampleDays < minSamples
            }
        } else {
            calories = nil
            caloriesBuilding = false
        }

        let steps: Int?
        let stepsBuilding: Bool
        if showSteps {
            if let avg = avgSteps, stepSampleDays >= minSamples, avg > 0 {
                steps = avg
                stepsBuilding = false
            } else {
                steps = nil
                stepsBuilding = stepSampleDays > 0 && stepSampleDays < minSamples
            }
        } else {
            steps = nil
            stepsBuilding = false
        }

        return (calories, caloriesBuilding, steps, stepsBuilding)
    }
}

@MainActor
final class GoalSettings: ObservableObject {
    static let shared = GoalSettings()

    private let defaults: UserDefaults

    @Published var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: "hasCompletedSetup") }
    }

    /// Last time the launch-surface Vitals+ trial offer was shown. nil = never.
    /// Passive triggers respect [[trialOfferCooldownDays]]; intent-driven taps
    /// (locked feature, Vitals+ tab) bypass the cooldown.
    @Published var lastTrialOfferShownDate: Date? {
        didSet {
            if let date = lastTrialOfferShownDate {
                defaults.set(date, forKey: "lastTrialOfferShownDate")
            } else {
                defaults.removeObject(forKey: "lastTrialOfferShownDate")
            }
        }
    }

    /// Last time the History-load second-touch trial offer was shown. nil = never.
    @Published var lastHistoryTrialOfferShownDate: Date? {
        didSet {
            if let date = lastHistoryTrialOfferShownDate {
                defaults.set(date, forKey: "lastHistoryTrialOfferShownDate")
            } else {
                defaults.removeObject(forKey: "lastHistoryTrialOfferShownDate")
            }
        }
    }

    /// Cooldown for passive trial surfaces. Re-encounter the pitch after this
    /// window; intent-driven taps ignore the cooldown.
    static let trialOfferCooldownDays = 14

    /// Set of milestone ids ("streak_7", "month_2025-04") that have already
    /// fired a celebration sheet. Each id is one-shot per user — once fired
    /// it stays fired so we don't celebrate the same achievement twice.
    @Published var firedMilestoneIds: Set<String> {
        didSet {
            defaults.set(Array(firedMilestoneIds), forKey: "firedMilestoneIds")
        }
    }

    /// True when a passive trial surface (launch, history-load) is allowed to
    /// fire — i.e. it has never shown, or the last show is older than the cooldown.
    func passiveTrialOfferAllowed(now: Date = .now) -> Bool {
        guard let last = lastTrialOfferShownDate else { return true }
        let cooldown = TimeInterval(Self.trialOfferCooldownDays) * 86_400
        return now.timeIntervalSince(last) >= cooldown
    }

    func passiveHistoryTrialOfferAllowed(now: Date = .now) -> Bool {
        guard let last = lastHistoryTrialOfferShownDate else { return true }
        let cooldown = TimeInterval(Self.trialOfferCooldownDays) * 86_400
        return now.timeIntervalSince(last) >= cooldown
    }

    /// Content version of the last "What's New" announcement the user has seen.
    /// nil = never shown. Compared against [[WhatsNew]].currentVersion so the
    /// upgrade announcement fires once per content release. Fresh installs are
    /// seeded to the current version in `init` so they get onboarding instead.
    @Published var lastWhatsNewVersionShown: String? {
        didSet {
            if let version = lastWhatsNewVersionShown {
                defaults.set(version, forKey: "lastWhatsNewVersionShown")
            } else {
                defaults.removeObject(forKey: "lastWhatsNewVersionShown")
            }
        }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }

    @Published var showPacing: Bool {
        didSet { defaults.set(showPacing, forKey: "showPacing") }
    }

    @Published var pacingComparison: PacingComparison {
        didSet { defaults.set(pacingComparison.rawValue, forKey: "pacingComparison") }
    }

    @Published var pacingLookback: PacingLookback {
        didSet { defaults.set(pacingLookback.rawValue, forKey: "pacingLookbackDays") }
    }

    @Published var showCalories: Bool {
        didSet {
            defaults.set(showCalories, forKey: "showCalories")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @Published var showSteps: Bool {
        didSet {
            defaults.set(showSteps, forKey: "showSteps")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// iOS dashboard: net deficit (burned − dietary energy from Health), e.g. food from MyFitnessPal via Health.
    @Published var showNetCalories: Bool {
        didSet {
            defaults.set(showNetCalories, forKey: "showNetCalories")
            // Watch complications read this setting to gate the NetDeficit widget;
            // iOS widget doesn't surface net deficit today but reload anyway for
            // consistency with `showCalories` / `showSteps` and future-proofing.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Vitals+ feature: show the active vs. resting calorie split below the ring on the dashboard.
    @Published var showActiveRestingBreakdown: Bool {
        didSet { defaults.set(showActiveRestingBreakdown, forKey: "showActiveRestingBreakdown") }
    }

    /// Vitals+ feature: show maintenance (TDEE) and resting (BMR) averages below the
    /// ring — a stable 30-day reference figure derived from Apple Health, distinct
    /// from today's live total. Default off so the core Today view is unchanged.
    @Published var showEnergyAverages: Bool {
        didSet { defaults.set(showEnergyAverages, forKey: "showEnergyAverages") }
    }

    /// Vitals+ feature: show the "on pace for…" end-of-day projection under the ring.
    /// Default off — opt-in so the core Today view is unchanged for everyone else.
    @Published var showProjections: Bool {
        didSet { defaults.set(showProjections, forKey: "showProjections") }
    }

    /// Vitals+ feature: show the current goal streak ("12-day streak") under the ring.
    @Published var showStreaks: Bool {
        didSet { defaults.set(showStreaks, forKey: "showStreaks") }
    }

    /// Vitals+ feature: schedule a weekly local notification nudging the user to
    /// open their recap. Default off; flipping it on requests notification
    /// permission and schedules the weekly trigger (see [[NotificationService]]).
    @Published var weeklyRecapEnabled: Bool {
        didSet { defaults.set(weeklyRecapEnabled, forKey: "weeklyRecapEnabled") }
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

        // Migration: prior versions used Bool flags (hasSeenTrialOffer /
        // hasSeenHistoryTrialOffer). Treat legacy `true` as "shown a long time
        // ago" so the cooldown allows the user to re-encounter the pitch on
        // their next session. New users (no key set) stay nil.
        let cooldownInterval = TimeInterval(Self.trialOfferCooldownDays) * 86_400
        let legacyShownDate = Date(timeIntervalSinceNow: -cooldownInterval)
        // Property observers don't fire during the first assignment in init,
        // so persist migrated values explicitly. Then clear the legacy bool.
        if let stored = defaults.object(forKey: "lastTrialOfferShownDate") as? Date {
            self.lastTrialOfferShownDate = stored
        } else if defaults.bool(forKey: "hasSeenTrialOffer") {
            self.lastTrialOfferShownDate = legacyShownDate
            defaults.set(legacyShownDate, forKey: "lastTrialOfferShownDate")
            defaults.removeObject(forKey: "hasSeenTrialOffer")
        } else {
            self.lastTrialOfferShownDate = nil
        }
        if let stored = defaults.object(forKey: "lastHistoryTrialOfferShownDate") as? Date {
            self.lastHistoryTrialOfferShownDate = stored
        } else if defaults.bool(forKey: "hasSeenHistoryTrialOffer") {
            self.lastHistoryTrialOfferShownDate = legacyShownDate
            defaults.set(legacyShownDate, forKey: "lastHistoryTrialOfferShownDate")
            defaults.removeObject(forKey: "hasSeenHistoryTrialOffer")
        } else {
            self.lastHistoryTrialOfferShownDate = nil
        }

        if let stored = defaults.array(forKey: "firedMilestoneIds") as? [String] {
            self.firedMilestoneIds = Set(stored)
        } else {
            self.firedMilestoneIds = []
        }
        self.lastWhatsNewVersionShown = defaults.string(forKey: "lastWhatsNewVersionShown")
        self.appearance = AppAppearance(rawValue: defaults.integer(forKey: "appearance")) ?? .system
        self.showPacing = defaults.object(forKey: "showPacing") as? Bool ?? true
        if let raw = defaults.object(forKey: "pacingComparison") as? Int,
           let mode = PacingComparison(rawValue: raw) {
            self.pacingComparison = mode
        } else {
            self.pacingComparison = .dayOfWeek
        }
        if let raw = defaults.object(forKey: "pacingLookbackDays") as? Int,
           let span = PacingLookback(rawValue: raw) {
            self.pacingLookback = span
        } else {
            self.pacingLookback = .default
        }
        self.showCalories = defaults.object(forKey: "showCalories") as? Bool ?? true
        self.showSteps = defaults.object(forKey: "showSteps") as? Bool ?? true
        self.showNetCalories = defaults.object(forKey: "showNetCalories") as? Bool ?? false
        self.showActiveRestingBreakdown = defaults.object(forKey: "showActiveRestingBreakdown") as? Bool ?? false
        self.showEnergyAverages = defaults.object(forKey: "showEnergyAverages") as? Bool ?? false
        self.showProjections = defaults.object(forKey: "showProjections") as? Bool ?? false
        self.showStreaks = defaults.object(forKey: "showStreaks") as? Bool ?? false
        self.weeklyRecapEnabled = defaults.object(forKey: "weeklyRecapEnabled") as? Bool ?? false

        let calEnabled = defaults.object(forKey: "calorieGoalEnabled") as? Bool ?? true
        if calEnabled {
            let saved = defaults.double(forKey: "calorieGoal")
            self.calorieGoal = saved.isFinite && (500...50000).contains(saved) ? saved : 2500
        } else {
            self.calorieGoal = nil
        }

        let stepEnabled = defaults.object(forKey: "stepGoalEnabled") as? Bool ?? true
        if stepEnabled {
            let saved = defaults.integer(forKey: "stepGoal")
            self.stepGoal = (100...500000).contains(saved) ? saved : 10000
        } else {
            self.stepGoal = nil
        }

        // Fresh installs (no record yet, onboarding not completed) shouldn't see
        // the "What's New" upgrade announcement — they get onboarding instead.
        // Seed the current version so the sheet only ever fires for users coming
        // from an older build. didSet doesn't run during init, so persist by hand.
        if self.lastWhatsNewVersionShown == nil && !self.hasCompletedSetup {
            self.lastWhatsNewVersionShown = WhatsNew.currentVersion
            defaults.set(WhatsNew.currentVersion, forKey: "lastWhatsNewVersionShown")
        }

        applyScreenshotOverridesIfNeeded()
    }

    private func applyScreenshotOverridesIfNeeded() {
        guard ScreenshotConfig.isEnabled else { return }

        showCalories = true
        showSteps = true
        showNetCalories = false
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
        // Surface the TDEE/BMR readout in the premium-active marketing scene so
        // the store screenshot shows the feature; off elsewhere.
        showEnergyAverages = ScreenshotConfig.wantsPremiumActive
        hasCompletedSetup = !ScreenshotConfig.wantsOnboarding
    }
}
