import SwiftData
import SwiftUI

@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published var bannerMessage: String?
    @Published var isCapturing = false
    @Published var lastCapturedEventID: UUID?

    /// - Parameter fromWatch: Watch requests bypass the iPhone onboarding gate so logging works from the watch immediately.
    func captureHeadache(in context: ModelContext, fromWatch: Bool = false) {
        if !fromWatch {
            guard HeadacheOnboardingStore.hasCompletedOnboarding || AppEnvironment.bypassOnboarding else {
                bannerMessage = "Finish setup on your iPhone first."
                return
            }
        }

        let event = HeadacheEvent()
        context.insert(event)
        lastCapturedEventID = event.id

        do {
            try context.save()
        } catch {
            consoleError("CaptureCoordinator: initial save failed", error: error, trace: [:])
            bannerMessage = "Could not save event. Try again."
            return
        }

        isCapturing = true
        bannerMessage = nil

        let eventID = event.id
        let timestamp = event.timestamp

        Task { @MainActor in
            // Serialize Health then environment so two permission / heavy queries never race on first launch.
            let health = await HealthKitService.shared.captureSnapshot(at: timestamp)
            let environment = await EnvironmentService.shared.captureSnapshot(at: timestamp)

            var descriptor = FetchDescriptor<HeadacheEvent>(
                predicate: #Predicate { $0.id == eventID }
            )
            descriptor.fetchLimit = 1

            guard let found = try? context.fetch(descriptor).first else {
                isCapturing = false
                bannerMessage = "Could not update event."
                consoleError("CaptureCoordinator: fetch after capture failed", error: nil, trace: ["eventID": "\(eventID)"])
                return
            }

            found.apply(health)
            found.apply(environment)
            found.finalizeCapture()

            do {
                try context.save()
            } catch {
                consoleError("CaptureCoordinator: finalize save failed", error: error, trace: ["eventID": "\(eventID)"])
            }

            isCapturing = false

            switch found.captureStatus {
            case .complete:
                bannerMessage = "Context saved."
            case .partial:
                bannerMessage = "Saved with partial context."
            case .failed:
                bannerMessage = "Saved; some context unavailable."
            case .pending:
                bannerMessage = nil
            }
        }
    }

    func undoLastCapture(in context: ModelContext) {
        guard let eventID = lastCapturedEventID else { return }

        var descriptor = FetchDescriptor<HeadacheEvent>(predicate: #Predicate { $0.id == eventID })
        descriptor.fetchLimit = 1

        if let event = try? context.fetch(descriptor).first {
            context.delete(event)
            do {
                try context.save()
            } catch {
                consoleError("CaptureCoordinator: undo save failed", error: error, trace: ["eventID": "\(eventID)"])
            }
        }

        lastCapturedEventID = nil
        bannerMessage = nil
    }

    private func consoleError(_ message: String, error: Error?, trace: [String: String]) {
        var parts = [message]
        if let error {
            parts.append(String(describing: error))
        }
        if !trace.isEmpty {
            parts.append(trace.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        }
        print(parts.joined(separator: " | "))
    }
}
