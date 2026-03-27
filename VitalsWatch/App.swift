import SwiftUI
import SwiftData
import WatchKit
import os

private let logger = Logger(subsystem: "com.jackwallner.vitals.watch", category: "BackgroundRefresh")

@main
struct VitalsWatchApp: App {
    @StateObject private var healthKit = HealthKitService.shared

    init() {
        // Must run on every launch (including background) so observer queries are active.
        // This is lightweight — just registers HKObserverQuery objects, no blocking I/O.
        HealthKitService.shared.enableBackgroundDelivery()
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .task { await Self.scheduleBackgroundRefresh() }
        }
        .modelContainer(DataService.sharedModelContainer)
        .backgroundTask(.appRefresh("vitals.watch.refresh")) {
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
