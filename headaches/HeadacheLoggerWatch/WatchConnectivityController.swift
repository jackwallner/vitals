import Foundation
import WatchConnectivity

/// Sends log requests to the paired iPhone (which runs capture with Health + location there).
@MainActor
final class WatchConnectivityController: NSObject, ObservableObject {
    @Published var statusMessage: String?

    func activate() {
        guard WCSession.isSupported() else {
            statusMessage = "Watch Connectivity unavailable."
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func requestLogFromPhone() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            statusMessage = "Connecting to iPhone…"
            return
        }
        let payload = ["action": "headacheLog"]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Sent — check your iPhone."
                }
            }, errorHandler: { error in
                Task { @MainActor [weak self] in
                    self?.statusMessage = error.localizedDescription
                }
            })
        } else {
            do {
                try session.updateApplicationContext(payload)
                statusMessage = "Queued — open Headache Logger on iPhone."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

extension WatchConnectivityController: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            self?.statusMessage = error.localizedDescription
        }
    }
}
