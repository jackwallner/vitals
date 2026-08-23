import Foundation

/// A local override for the Upgrade-tab layout, set by a hidden gesture rather
/// than by RevenueCat.
///
/// This is deliberately **not** `#if DEBUG`. The whole point is to walk the
/// arms on a real phone from a TestFlight build, which is a Release build, and
/// a debug-only switch cannot do that. The launch-environment override in
/// `DebugLaunchConfig` still exists and still wins; it is how the test suite
/// and the screenshot runs pick an arm, and it never survives a relaunch.
///
/// Shipping a hidden switch in a Release binary is only acceptable because of
/// what it can and cannot do. It picks between layouts that are already in the
/// binary and that every user can already be served by RevenueCat. It cannot
/// change a price, a product, an entitlement, or what a purchase does. A
/// customer who somehow discovers it sees a different arrangement of the same
/// paywall, which is a thing RevenueCat could have shown them anyway.
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
    /// RevenueCat control. Ending on nil matters — it is the only way back to
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
