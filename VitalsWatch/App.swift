import SwiftUI
import SwiftData
import WatchKit
import WidgetKit
import os
#if canImport(WatchConnectivity)
@preconcurrency import WatchConnectivity
#endif

private let logger = Logger(subsystem: "com.jackwallner.vitals.watch", category: "BackgroundRefresh")
private let watchGoalSyncLogger = Logger(subsystem: "com.jackwallner.vitals.watch", category: "GoalSync")

#if canImport(WatchConnectivity)
private final class WatchGoalSyncService: NSObject, WCSessionDelegate {
    nonisolated(unsafe) static let shared = WatchGoalSyncService()

    private let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        applyApplicationContext(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            watchGoalSyncLogger.error("WatchConnectivity activation failed: \(String(describing: error), privacy: .public)")
            return
        }

        watchGoalSyncLogger.info("WatchConnectivity activated with state \(activationState.rawValue, privacy: .public)")
        applyApplicationContext(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        applyApplicationContext(applicationContext)
    }

    private func applyApplicationContext(_ applicationContext: [String: Any]) {
        guard !applicationContext.isEmpty else { return }

        if let calorieGoalEnabled = applicationContext[GoalSyncKeys.calorieGoalEnabled] as? Bool {
            defaults.set(calorieGoalEnabled, forKey: "calorieGoalEnabled")
        }
        if let stepGoalEnabled = applicationContext[GoalSyncKeys.stepGoalEnabled] as? Bool {
            defaults.set(stepGoalEnabled, forKey: "stepGoalEnabled")
        }
        if let calorieGoal = applicationContext[GoalSyncKeys.calorieGoal] as? Double {
            defaults.set(calorieGoal, forKey: "calorieGoal")
        }
        if let stepGoal = applicationContext[GoalSyncKeys.stepGoal] as? Int {
            defaults.set(stepGoal, forKey: "stepGoal")
        }
        if let showNetCalories = applicationContext[GoalSyncKeys.showNetCalories] as? Bool {
            defaults.set(showNetCalories, forKey: "showNetCalories")
            Task { @MainActor in
                GoalSettings.shared.showNetCalories = showNetCalories
            }
        }
        if let fastingMode = applicationContext[GoalSyncKeys.netDeficitFastingMode] as? Bool {
            defaults.set(fastingMode, forKey: "netDeficitFastingMode")
            Task { @MainActor in
                GoalSettings.shared.netDeficitFastingMode = fastingMode
            }
        }
        if let showCalories = applicationContext[GoalSyncKeys.showCalories] as? Bool {
            defaults.set(showCalories, forKey: "showCalories")
            Task { @MainActor in
                GoalSettings.shared.showCalories = showCalories
            }
        }
        if let showSteps = applicationContext[GoalSyncKeys.showSteps] as? Bool {
            defaults.set(showSteps, forKey: "showSteps")
            Task { @MainActor in
                GoalSettings.shared.showSteps = showSteps
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
        watchGoalSyncLogger.info("Applied synced goal settings on watch")
    }
}
#endif

@main
struct VitalsWatchApp: App {
    @StateObject private var healthKit = HealthKitService.shared

    init() {
        // Must run on every launch (including background) so observer queries are active.
        // This is lightweight — just registers HKObserverQuery objects, no blocking I/O.
        HealthKitService.shared.enableBackgroundDelivery()
        #if canImport(WatchConnectivity)
        WatchGoalSyncService.shared.activate()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .task { Self.scheduleBackgroundRefresh() }
        }
        .modelContainer(DataService.sharedModelContainer)
        // Use the unnamed `.appRefresh` variant (BackgroundTask<String?, Void>)
        // which matches refreshes scheduled by `WKApplication.scheduleBackgroundRefresh`
        // (a legacy WatchKit API that carries no identifier). The identifier-parameter
        // form `.appRefresh("…")` only matches `BGAppRefreshTaskRequest` submissions,
        // which this app does not make on watchOS — so the previous wiring never
        // delivered any background refreshes at all.
        .backgroundTask(.appRefresh) { (_: String?) in
            await Self.handleBackgroundRefresh()
        }
    }

    @MainActor
    private static func handleBackgroundRefresh() async {
        let start = ContinuousClock.now
        logger.info("background refresh started")

        // Schedule next refresh first so it's always queued even if we bail early
        scheduleBackgroundRefresh()

        // Keep refresh short so CAROUSEL watchdog doesn't kill us (0xc51bad02).
        // watchOS gives ~15s background budget — bail at 8s to leave margin.
        let work = Task { @MainActor in
            try await HealthKitService.shared.refreshCache()
            let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard
            let showNet = defaults.object(forKey: "showNetCalories") as? Bool ?? false
            if showNet {
                let food = try await HealthKitService.shared.fetchDietaryEnergyToday()
                try HealthKitService.shared.updateCachedFoodCalories(food)
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(8))
            work.cancel()
        }

        let result = await work.result
        let elapsed = ContinuousClock.now - start
        switch result {
        case .success:
            logger.info("background refresh completed in \(elapsed)")
        case .failure(let error):
            logger.error("background refresh failed after \(elapsed): \(error)")
        }
    }

    @MainActor static func scheduleBackgroundRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: 30 * 60),
            userInfo: nil
        ) { error in
            if let error {
                print("Could not schedule watch refresh: \(error)")
            }
        }
    }
}
