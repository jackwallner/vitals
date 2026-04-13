import SwiftData
import SwiftUI

@main
struct HeadacheLoggerApp: App {
    @StateObject private var captureCoordinator = CaptureCoordinator()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(captureCoordinator)
        }
        .modelContainer(HeadacheModelStore.sharedModelContainer)
    }
}
