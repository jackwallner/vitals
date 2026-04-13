import SwiftData
import SwiftUI

@main
struct HeadacheLoggerApp: App {
    @StateObject private var captureCoordinator = CaptureCoordinator()
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if AppEnvironment.bypassOnboarding || hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(captureCoordinator)
        }
        .modelContainer(HeadacheModelStore.sharedModelContainer)
    }
}
