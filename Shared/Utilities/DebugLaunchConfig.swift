import Foundation

/// DEBUG-only launch switches for simulator verification. Production ignores
/// every key. Screenshot mode stays separate: that path fakes HealthKit, this
/// one is for walking the real app against seeded samples.
enum DebugLaunchConfig {
#if DEBUG
    /// Force the Upgrade-tab layout regardless of offering metadata.
    /// `VITALS_UPGRADE_TAB=catalog` or `feature_led`.
    static var upgradeTabOverride: PaywallUIVariant? {
        PaywallUIVariant(rawValue: ProcessInfo.processInfo.environment["VITALS_UPGRADE_TAB"] ?? "")
    }

    /// Write a realistic HealthKit history, then let the normal read path
    /// consume it. `VITALS_SEED_HEALTH=1`.
    static var seedHealth: Bool {
        ProcessInfo.processInfo.environment["VITALS_SEED_HEALTH"] == "1"
    }

    /// Skip onboarding so Today/History/Settings are reachable on a fresh
    /// install. `VITALS_FORCE_SETUP_COMPLETE=1`.
    static var forceSetupComplete: Bool {
        ProcessInfo.processInfo.environment["VITALS_FORCE_SETUP_COMPLETE"] == "1"
    }
#else
    static var upgradeTabOverride: PaywallUIVariant? { nil }
    static var seedHealth: Bool { false }
    static var forceSetupComplete: Bool { false }
#endif
}
