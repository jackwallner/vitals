import SwiftUI
import SwiftData

@main
struct VitalsWatchApp: App {
    @StateObject private var healthKit = HealthKitService.shared

    var body: some Scene {
        WindowGroup {
            TodayView()
                .task {
                    try? await healthKit.requestAuthorization()
                    healthKit.enableBackgroundDelivery()
                }
        }
        .modelContainer(DataService.sharedModelContainer)
    }
}
