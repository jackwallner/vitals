import Foundation

enum AppEnvironment {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitesting")
    }

    /// Treat onboarding as complete during UI tests (no interactive Health/Location sheets).
    static var bypassOnboarding: Bool { isUITesting }
}
