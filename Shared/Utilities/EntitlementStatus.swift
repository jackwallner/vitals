/// A failed refresh is unresolved, so keep the last resolved access decision.
struct EntitlementStatus: Equatable {
    enum Resolution {
        case unresolved
        case active
        case inactive
    }

    private(set) var resolution: Resolution = .unresolved
    private(set) var cachedPro: Bool
    private(set) var serverAnswered = false

    var isPro: Bool { cachedPro }
    /// RevenueCat replays its on-device customer info at launch, so "no access"
    /// counts as a lapse only once its servers have replied.
    var lapseConfirmed: Bool { serverAnswered && resolution == .inactive }

    mutating func markServerAnswered() {
        serverAnswered = true
    }

    mutating func resolve(isPro: Bool) {
        cachedPro = isPro
        resolution = isPro ? .active : .inactive
    }

    mutating func refreshFailed() {
        resolution = .unresolved
        serverAnswered = false
    }
}
