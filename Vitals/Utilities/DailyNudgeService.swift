import Foundation
import UIKit
import UserNotifications
import os

/// Posts the daily notifications after each today-cache refresh: "goal
/// reached" (free) and the Vitals+ evening reminder. Installed as
/// `HealthKitService.onTodayCacheSaved`, so it runs on every HealthKit
/// background delivery without the app being opened. Copy and decisions live in
/// `DailyNudgePlanner`; this type only reads state and talks to the system.
@MainActor
enum DailyNudgeService {
    static let goalReachedID = "vitals.goalReached"
    static let eveningReminderID = "vitals.eveningReminder"

    private static let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
    private static let logger = Logger(subsystem: "com.jackwallner.vitals", category: "DailyNudges")

    /// Same-day dedupe. The dashboard's in-app celebration writes its own keys
    /// (`goalCelebration.*`); a goal already celebrated on screen isn't pushed.
    private static func notifiedKey(_ metric: NudgeMetric) -> String { "goalNotified.\(metric.rawValue)" }
    private static func celebratedKey(_ metric: NudgeMetric) -> String {
        metric == .calories ? "goalCelebration.calorieDate" : "goalCelebration.stepDate"
    }

    static func install() {
        HealthKitService.shared.onTodayCacheSaved = { stats in
            await todayDidRefresh(stats: stats)
        }
    }

    static func todayDidRefresh(stats: (active: Double, resting: Double, steps: Int)) async {
        guard await NotificationService.isAuthorized() else { return }
        await postGoalReachedIfNeeded(stats: stats)
        await refreshEveningReminder(stats: stats)
    }

    // MARK: Goal reached

    private static func postGoalReachedIfNeeded(stats: (active: Double, resting: Double, steps: Int)) async {
        let goals = GoalSettings.shared
        guard goals.goalReachedNotificationsEnabled, goals.hasCompletedSetup else { return }
        // On screen, the dashboard's own celebration answers the moment.
        guard UIApplication.shared.applicationState != .active else { return }

        let todayKey = DailyHealthRecord.key(for: .now)
        let announced = Set(NudgeMetric.allCases.filter {
            defaults.string(forKey: notifiedKey($0)) == todayKey
                || defaults.string(forKey: celebratedKey($0)) == todayKey
        })
        let calorieGoal = goals.showCalories ? goals.calorieGoal : nil
        let stepGoal = goals.showSteps ? goals.stepGoal : nil
        let calories = stats.active + stats.resting
        let reached = DailyNudgePlanner.newlyReached(
            calories: calories,
            steps: stats.steps,
            calorieGoal: calorieGoal,
            stepGoal: stepGoal,
            announced: announced
        )
        guard let content = DailyNudgePlanner.goalReached(
            reached,
            calories: calories,
            steps: stats.steps,
            calorieGoal: calorieGoal,
            stepGoal: stepGoal
        ) else { return }

        for metric in reached { defaults.set(todayKey, forKey: notifiedKey(metric)) }
        await post(content, id: "\(goalReachedID).\(todayKey).\(reached.map(\.rawValue).joined())", trigger: nil)
    }

    // MARK: Evening reminder

    /// Schedules (or replaces, or withdraws) today's evening reminder with the
    /// latest numbers. Content is fixed at scheduling time, so each refresh
    /// rewrites it; it's at most one background refresh behind when it fires.
    static func refreshEveningReminder(stats: (active: Double, resting: Double, steps: Int)? = nil) async {
        let center = UNUserNotificationCenter.current()
        let goals = GoalSettings.shared
        let isPro = defaults.bool(forKey: StoreService.cachedProKey)
        guard goals.eveningReminderEnabled, isPro, goals.hasCompletedSetup else {
            center.removePendingNotificationRequests(withIdentifiers: [eveningReminderID])
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let minutes = goals.eveningReminderMinutes
        guard let fireDate = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now),
              fireDate > now
        else {
            // Today's slot has passed (or moved earlier than now): nothing to send today.
            center.removePendingNotificationRequests(withIdentifiers: [eveningReminderID])
            return
        }

        // Before today's first cache write (just after midnight, or a reminder
        // turned on before any refresh), read Health directly rather than skip.
        var latest = stats ?? (try? HealthKitService.shared.fetchCachedTodayStats())
        if latest == nil, let live = try? await HealthKitService.shared.fetchTodayStats(),
           !HealthKitService.isAllZero(live) {
            latest = live
        }
        guard let stats = latest else { return }
        let streaks = goals.showStreaks ? currentStreaks(goals: goals) : (calories: 0, steps: 0)
        guard let content = DailyNudgePlanner.evening(
            active: stats.active,
            resting: stats.resting,
            steps: stats.steps,
            calorieGoal: goals.showCalories ? goals.calorieGoal : nil,
            stepGoal: goals.showSteps ? goals.stepGoal : nil,
            calorieStreak: streaks.calories,
            stepStreak: streaks.steps,
            now: now
        ) else {
            center.removePendingNotificationRequests(withIdentifiers: [eveningReminderID])
            return
        }

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        await post(content, id: eveningReminderID, trigger: trigger)
    }

    static func cancelEveningReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [eveningReminderID])
    }

    /// Per-metric streaks ending yesterday, from the same cache window the
    /// dashboard badges use.
    private static func currentStreaks(goals: GoalSettings) -> (calories: Int, steps: Int) {
        guard let history = try? HealthKitService.shared.fetchCachedHistory(days: MilestoneCalculator.streakHistoryDays) else { return (0, 0) }
        let days = history.map { MilestoneDay(date: $0.date, calories: $0.active + $0.resting, steps: $0.steps) }
        let excluded = goals.excludedDayKeys
        let calories = goals.calorieGoal.map { goal in
            MilestoneCalculator.currentStreak(records: days, excludedKeys: excluded) { $0.calories >= goal }
        } ?? 0
        let steps = goals.stepGoal.map { goal in
            MilestoneCalculator.currentStreak(records: days, excludedKeys: excluded) { $0.steps >= goal }
        } ?? 0
        return (calories, steps)
    }

    // MARK: Posting

    private static func post(_ content: NudgeContent, id: String, trigger: UNNotificationTrigger?) async {
        let body = UNMutableNotificationContent()
        body.title = content.title
        body.body = content.body
        body.sound = .default
        body.threadIdentifier = "vitals.daily"
        body.userInfo = [DeepLink.userInfoKey: content.link.url.absoluteString]
        let request = UNNotificationRequest(identifier: id, content: body, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Scheduled \(id, privacy: .public)")
        } catch {
            logger.error("Scheduling \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }
}
