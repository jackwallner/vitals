/// A failed refresh is unresolved, so keep the last resolved access decision.
struct EntitlementStatus: Equatable {
    enum Resolution {
        case unresolved
        case active
        case inactive
    }

    private(set) var resolution: Resolution = .unresolved
    private(set) var cachedPro: Bool

    var isPro: Bool { cachedPro }

    mutating func resolve(isPro: Bool) {
        cachedPro = isPro
        resolution = isPro ? .active : .inactive
    }

    mutating func refreshFailed() {
        resolution = .unresolved
    }
}
