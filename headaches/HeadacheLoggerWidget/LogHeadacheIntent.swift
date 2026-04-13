import AppIntents
import SwiftData
import WidgetKit

/// One-tap log from the Home Screen widget. Runs in the widget extension: no HealthKit or location here;
/// the event is stored immediately and shows as **partial** until the user opens the app (future: could enrich then).
struct LogHeadacheIntent: AppIntent {
    static let title: LocalizedStringResource = "Log headache"
    static let description: IntentDescription = "Records a headache in Headache Logger."

    /// Keep the user on the Home Screen after tapping.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard HeadacheOnboardingStore.hasCompletedOnboarding else {
            return .result(dialog: IntentDialog("Finish setup in Headache Logger first."))
        }

        do {
            try await MainActor.run {
                try Self.insertQuickLog()
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            print("LogHeadacheIntent: save failed | error=\(String(describing: error))")
            throw error
        }

        return .result(dialog: IntentDialog("Headache logged."))
    }

    @MainActor
    private static func insertQuickLog() throws {
        let container = HeadacheModelStore.sharedModelContainer
        let context = ModelContext(container)
        let event = HeadacheEvent()
        context.insert(event)
        event.apply(
            HealthCaptureResult(
                status: .unavailable,
                message: "Open the app to capture Health context.",
                snapshot: nil
            )
        )
        event.apply(
            EnvironmentCaptureResult(
                status: .unavailable,
                message: "Open the app to capture weather.",
                snapshot: nil
            )
        )
        event.finalizeCapture()
        try context.save()
    }
}
