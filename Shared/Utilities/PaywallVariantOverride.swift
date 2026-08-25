import Foundation

#if DEBUG
/// A local override for the Upgrade-tab layout, set by a hidden gesture rather
/// than by RevenueCat.
///
/// **DEBUG only.** This used to ship in Release so an arm could be walked on a
/// real phone from TestFlight, which is a Release build. That is a hidden
/// feature flag in a shipping binary, and App Review is entitled to find it, so
/// it is gone from the store build: a Release binary now draws whatever
/// RevenueCat assigns and nothing else. Walking the arms by hand means a debug
/// build; walking them in a test or a screenshot run means
/// `DebugLaunchConfig.upgradeTabOverride`, which is also DEBUG-only and still
/// wins over this.
enum PaywallVariantOverride {
    private static let key = "debug.upgradeTabOverride"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.jackwallner.vitals") ?? .standard
    }

    /// Nil means "let RevenueCat decide", which is the shipping behaviour and
    /// the state every install starts in.
    static var current: PaywallUIVariant? {
        get {
            guard let raw = defaults.string(forKey: key) else { return nil }
            return PaywallUIVariant(rawValue: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// The cycle the hidden gesture walks: every arm in turn, then back to
    /// RevenueCat control. Ending on nil matters: it is the only way back to
    /// normal without reinstalling.
    static func advance() -> PaywallUIVariant? {
        let cycle = PaywallUIVariant.allCases
        guard let current else {
            let first = cycle.first
            self.current = first
            return first
        }
        guard
            let index = cycle.firstIndex(of: current),
            cycle.index(after: index) < cycle.endIndex
        else {
            self.current = nil
            return nil
        }
        let next = cycle[cycle.index(after: index)]
        self.current = next
        return next
    }

    /// What to show the tester. Nil override reads as the live behaviour rather
    /// than as an empty state.
    static func label(for variant: PaywallUIVariant?) -> String {
        guard let variant else { return "RevenueCat decides (normal)" }
        return variant.rawValue
    }
}
#endif
