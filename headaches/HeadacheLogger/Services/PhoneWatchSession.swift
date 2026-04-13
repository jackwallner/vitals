#if os(iOS)
import Foundation
import WatchConnectivity

/// Receives “log headache” from the Watch companion (works even while iPhone onboarding is unfinished).
final class PhoneWatchSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    nonisolated(unsafe) static let shared = PhoneWatchSession()

    var onWatchRequestedCapture: (() -> Void)?

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("PhoneWatchSession activation error: \(error)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["action"] as? String == "headacheLog" else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleHeadacheLogRequest()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard applicationContext["action"] as? String == "headacheLog" else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleHeadacheLogRequest()
        }
    }

    private func handleHeadacheLogRequest() {
        onWatchRequestedCapture?()
    }
}
#endif
