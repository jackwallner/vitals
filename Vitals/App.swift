import SwiftUI
import SwiftData
import BackgroundTasks
import os
#if canImport(WatchConnectivity)
@preconcurrency import WatchConnectivity
#endif

private let goalSyncLogger = Logger(subsystem: "com.jackwallner.vitals", category: "GoalSync")

#if canImport(WatchConnectivity)
private final class PhoneGoalSyncService: NSObject, WCSessionDelegate {
    nonisolated(unsafe) static let shared = PhoneGoalSyncService()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    @MainActor
    func pushCurrentGoals(from goals: GoalSettings) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            goalSyncLogger.info("Skipping goal sync because WatchConnectivity is not activated yet")
            return
        }

        let payload: [String: Any] = [
            GoalSyncKeys.calorieGoalEnabled: goals.calorieGoal != nil,
            GoalSyncKeys.stepGoalEnabled: goals.stepGoal != nil,
            GoalSyncKeys.calorieGoal: goals.calorieGoal ?? 2500,
            GoalSyncKeys.stepGoal: goals.stepGoal ?? 10000,
        ]

        do {
            try session.updateApplicationContext(payload)
            goalSyncLogger.info("Pushed goal settings to watch")
        } catch {
            goalSyncLogger.error("Failed to push goal settings: \(String(describing: error), privacy: .public)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            goalSyncLogger.error("WatchConnectivity activation failed: \(String(describing: error), privacy: .public)")
            return
        }

        goalSyncLogger.info("WatchConnectivity activated with state \(activationState.rawValue, privacy: .public)")
        Task { @MainActor in
            PhoneGoalSyncService.shared.pushCurrentGoals(from: GoalSettings.shared)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif

@main
struct VitalsApp: App {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var goals = GoalSettings.shared

    private static let refreshTaskID = "com.jackwallner.vitals.refresh"

    init() {
        // Run the launch handler on the main queue. With `using: nil` the system uses a
        // background queue; referencing MainActor-isolated `Self` / `handleAppRefresh`
        // from there trips Swift 6 executor checks (see _dispatch_assert_queue_fail).
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: DispatchQueue.main) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Self.handleAppRefresh(task)
        }
        // Must run on every launch (including background) so observer queries are active
        HealthKitService.shared.enableBackgroundDelivery()
        Self.scheduleAppRefresh()
        #if canImport(WatchConnectivity)
        PhoneGoalSyncService.shared.activate()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(goals.appearance.colorScheme)
                .task {
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
                .onChange(of: goals.calorieGoal) { _, _ in
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
                .onChange(of: goals.stepGoal) { _, _ in
                    #if canImport(WatchConnectivity)
                    PhoneGoalSyncService.shared.pushCurrentGoals(from: goals)
                    #endif
                }
        }
        .modelContainer(DataService.sharedModelContainer)
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }

    private static func handleAppRefresh(_ task: BGAppRefreshTask) {
        // Schedule the next one immediately
        scheduleAppRefresh()

        let refreshTask = Task { @MainActor in
            do {
                try await HealthKitService.shared.refreshCache()
                return true
            } catch {
                print("Background app refresh failed: \(error)")
                return false
            }
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        Task {
            let success = await refreshTask.value
            task.setTaskCompleted(success: success)
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var historyHasAppeared = false

    init() {
        if ScreenshotConfig.wantsHistoryTab {
            _selectedTab = State(initialValue: 1)
            _historyHasAppeared = State(initialValue: true)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keep both views alive, toggle visibility
            DashboardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)
            if historyHasAppeared {
                HistoryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
            }

            // Custom tab bar
            HStack(spacing: 0) {
                TabButton(
                    icon: "heart.fill",
                    label: "Today",
                    isSelected: selectedTab == 0
                ) { selectedTab = 0 }

                TabButton(
                    icon: "chart.bar.fill",
                    label: "History",
                    isSelected: selectedTab == 1
                ) {
                    if !historyHasAppeared { historyHasAppeared = true }
                    selectedTab = 1
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            .padding(.bottom, 12)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct TabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Theme.caloriesPrimary : Theme.textTertiary)
            .frame(width: 72, height: 44)
            .background(
                isSelected ? Theme.caloriesPrimary.opacity(0.12) : .clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
