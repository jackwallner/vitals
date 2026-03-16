import SwiftUI
import SwiftData

@main
struct VitalsApp: App {
    @StateObject private var healthKit = HealthKitService.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                DashboardView()
                    .tabItem {
                        Label("Today", systemImage: "heart.fill")
                    }
                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "chart.bar.fill")
                    }
            }
            .task {
                try? await healthKit.requestAuthorization()
                healthKit.enableBackgroundDelivery()
            }
        }
        .modelContainer(DataService.sharedModelContainer)
    }
}
