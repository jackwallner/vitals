import Foundation

/// Runs `work` against a deadline. Returns true when `work` finished first.
/// `work` keeps running after a timeout; only the wait ends.
enum FirstToFinish {
    static func race(_ work: @escaping @Sendable () async -> Void, timeout seconds: Double) async -> Bool {
        let gate = Gate()
        return await withCheckedContinuation { continuation in
            gate.set(continuation)
            Task {
                await work()
                gate.resume(true)
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                gate.resume(false)
            }
        }
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?

        func set(_ continuation: CheckedContinuation<Bool, Never>) {
            lock.withLock { self.continuation = continuation }
        }

        func resume(_ value: Bool) {
            let pending = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
                defer { continuation = nil }
                return continuation
            }
            pending?.resume(returning: value)
        }
    }
}
