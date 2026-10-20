#if DEBUG
import Foundation
import HealthKit
import UIKit
import UserNotifications
import os

/// Audit-only launch hooks for verifying the background notification paths in
/// the simulator. Every switch is an environment variable; nothing runs without one.
///
/// - `VITALS_AUDIT_DUMP=<path>`: once a second, write pending and delivered
///   notification requests (id, title, body, userInfo, trigger) to `<path>`.
/// - `VITALS_AUDIT_BG_STEPS=<n>[,<delay seconds>]`: when the app enters the
///   background, hold a background task, wait the delay (default 5), save `n`
///   extra step samples to Health, and, if the HealthKit observer has not
///   already refreshed the cache, call `refreshCache()` itself. Logs which one
///   ran to `<dump path>.log`.
enum AuditHooks {
    private static let logger = Logger(subsystem: "com.jackwallner.vitals", category: "AuditHooks")

    @MainActor private static var started = false

    @MainActor
    static func start() {
        guard !started else { return }
        started = true
        let env = ProcessInfo.processInfo.environment
        if let path = env["VITALS_AUDIT_DUMP"] {
            Task { @MainActor in
                while true {
                    await dump(to: path)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        if let spec = env["VITALS_AUDIT_BG_STEPS"], let path = env["VITALS_AUDIT_DUMP"] {
            let parts = spec.split(separator: ",").map(String.init)
            let steps = Double(parts.first ?? "") ?? 0
            let delay = parts.count > 1 ? Double(parts[1]) ?? 5 : 5
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in await bump(steps: steps, delay: delay, logPath: path + ".log") }
            }
        }
    }

    @MainActor
    private static func bump(steps: Double, delay: Double, logPath: String) async {
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(task) }
        log("bg task began, state=\(UIApplication.shared.applicationState.rawValue)", to: logPath)
        try? await Task.sleep(for: .seconds(delay))
        let store = HealthKitService.shared.debugStore
        let now = Date()
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: steps),
            start: now.addingTimeInterval(-60), end: now,
            metadata: ["VitalsSeededHealthSample": true]
        )
        do { try await store.save([sample]) } catch { log("save failed \(error)", to: logPath) }
        log("saved \(Int(steps)) steps, state=\(UIApplication.shared.applicationState.rawValue)", to: logPath)
        // Give the observer query a chance to run the real path first.
        try? await Task.sleep(for: .seconds(6))
        let stamp = (try? HealthKitService.shared.fetchCachedTodayStats())?.steps ?? -1
        log("cache steps after wait: \(stamp)", to: logPath)
        try? await HealthKitService.shared.refreshCache()
        log("explicit refreshCache done", to: logPath)
        try? await Task.sleep(for: .seconds(2))
        UIApplication.shared.endBackgroundTask(task)
    }

    private static func log(_ line: String, to path: String) {
        let text = "\(Date().formatted(.iso8601)) \(line)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    @MainActor private static func dump(to path: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        func entry(_ request: UNNotificationRequest) -> [String: Any] {
            var item: [String: Any] = [
                "id": request.identifier,
                "title": request.content.title,
                "body": request.content.body,
                "userInfo": request.content.userInfo.compactMapValues { $0 as? String },
            ]
            if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                item["trigger"] = "\(trigger.dateComponents)"
                item["next"] = trigger.nextTriggerDate()?.formatted(.iso8601) ?? "nil"
            }
            return item
        }
        let payload: [String: Any] = [
            "pending": pending.map(entry),
            "delivered": delivered.map { entry($0.request) },
            "authorization": "\(await center.notificationSettings().authorizationStatus.rawValue)",
            "calorieGoal": GoalSettings.shared.calorieGoal ?? -1,
            "stepGoal": GoalSettings.shared.stepGoal ?? -1,
            "defaults": (UserDefaults(suiteName: vitalsAppGroupID) ?? .standard).dictionaryRepresentation()
                .filter { $0.key.hasPrefix("goalNotified") || $0.key.hasPrefix("goalCelebration") }
                .compactMapValues { $0 as? String },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
