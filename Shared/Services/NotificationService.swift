import Foundation
import UserNotifications
import os

/// Schedules the Vitals+ weekly recap nudge — a repeating local notification that
/// reminds the user to open their week in review. The notification itself carries
/// no live data (local notifications can't compute content at fire time); it's a
/// re-engagement nudge, and the real numbers are rendered on open by
/// `WeeklyRecapView`. This is the deliberate "weekly heartbeat" retention loop.
///
/// Not actor-isolated: every call goes through the thread-safe
/// `UNUserNotificationCenter`, and the routing constants need to be readable
/// from the (nonisolated) notification-center delegate.
enum NotificationService {
    /// Identifier for the repeating weekly recap request. Stable so re-scheduling
    /// replaces rather than stacks, and cancel can target it precisely.
    static let weeklyRecapID = "vitals.weeklyRecap"

    /// userInfo key set on the recap notification so the app can route a tap
    /// straight to the recap surface.
    static let recapRouteKey = "route"
    static let recapRouteValue = "weeklyRecap"

    /// Fire the recap Sunday evening — late enough that the week is "done", early
    /// enough to still be seen. Weekday 1 = Sunday in `Calendar.current`.
    static let recapWeekday = 1
    static let recapHour = 18

    private static let logger = Logger(subsystem: "com.jackwallner.vitals", category: "Notifications")

    /// Requests notification permission. Returns true if authorized (or already
    /// authorized / provisional). Safe to call repeatedly — the system only
    /// prompts once.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization granted=\(granted, privacy: .public)")
            return granted
        } catch {
            logger.error("Notification authorization failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// True when the user has authorized (or provisionally authorized) notifications.
    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Schedules (or re-schedules) the repeating weekly recap notification.
    /// Requests authorization first; if denied, schedules nothing and returns false.
    @discardableResult
    static func scheduleWeeklyRecap() async -> Bool {
        guard await requestAuthorization() else {
            logger.info("Weekly recap not scheduled — notifications not authorized")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Your week in review"
        content.body = "See how your calories and steps stacked up this week."
        content.sound = .default
        content.userInfo = [recapRouteKey: recapRouteValue]

        var components = DateComponents()
        components.weekday = recapWeekday
        components.hour = recapHour
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: weeklyRecapID, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyRecapID])
        do {
            try await center.add(request)
            logger.info("Weekly recap scheduled for weekday=\(recapWeekday, privacy: .public) hour=\(recapHour, privacy: .public)")
            return true
        } catch {
            logger.error("Weekly recap scheduling failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Cancels the pending weekly recap notification (toggle turned off, or
    /// subscription lapsed).
    static func cancelWeeklyRecap() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weeklyRecapID])
        logger.info("Weekly recap cancelled")
    }
}
