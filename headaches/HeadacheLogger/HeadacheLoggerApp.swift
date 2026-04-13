import SwiftData
import SwiftUI

@main
struct HeadacheLoggerApp: App {
    @StateObject private var captureCoordinator = CaptureCoordinator()

    var body: some Scene {
        WindowGroup {
            HeadacheLoggerRootContent()
                .environmentObject(captureCoordinator)
        }
        .modelContainer(HeadacheModelStore.sharedModelContainer)
    }
}

/// Hosts onboarding vs main UI and always wires Watch → phone capture so the watch can log before iPhone onboarding finishes.
private struct HeadacheLoggerRootContent: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if AppEnvironment.bypassOnboarding || hasCompletedOnboarding {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            #if os(iOS)
            PhoneWatchSession.shared.onWatchRequestedCapture = { [captureCoordinator] in
                captureCoordinator.captureHeadache(in: modelContext, fromWatch: true)
            }
            PhoneWatchSession.shared.start()
            #endif
        }
    }
}
