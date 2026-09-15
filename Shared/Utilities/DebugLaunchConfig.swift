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

    /// Make the offerings fetch fail the way a dead network or a RevenueCat
    /// outage makes it fail. `VITALS_FAIL_PRODUCT_LOAD=1`.
    ///
    /// The dead end this reproduces is not hypothetical: with no packages the
    /// onboarding CTA had no label, no enabled state and no route out, so the
    /// only recovery path in the app sat behind a button nobody could press.
    /// A switch is the only way to assert the recovery in a test.
    static var failProductLoad: Bool {
        ProcessInfo.processInfo.environment["VITALS_FAIL_PRODUCT_LOAD"] == "1"
    }

    /// Launch as a lapsed subscriber: the App Group still says Vitals+ and two
    /// excluded days are stored, while RevenueCat resolves a free customer.
    /// Reproduces the stale-mirror bug from the 1.8.6 audit.
    /// `VITALS_STALE_PRO_CACHE=1`.
    static var staleProCache: Bool {
        ProcessInfo.processInfo.environment["VITALS_STALE_PRO_CACHE"] == "1"
    }

    /// A named Test Store customer instead of the install's anonymous one, so a
    /// UI test that buys cannot leave the next test subscribed.
    /// `VITALS_RC_APP_USER_ID=<id>`.
    static var revenueCatAppUserID: String? {
        ProcessInfo.processInfo.environment["VITALS_RC_APP_USER_ID"]
    }

    /// Start the Pro settings scene with a pause that began this many days ago,
    /// so a long-running pause can be tested without waiting weeks.
    /// `VITALS_PAUSED_DAYS_AGO=<days>`.
    static var pausedDaysAgo: Int? {
        ProcessInfo.processInfo.environment["VITALS_PAUSED_DAYS_AGO"].flatMap(Int.init)
    }
#else
    static var upgradeTabOverride: PaywallUIVariant? { nil }
    static var seedHealth: Bool { false }
    static var forceSetupComplete: Bool { false }
    static var failProductLoad: Bool { false }
    static var staleProCache: Bool { false }
    static var revenueCatAppUserID: String? { nil }
    static var pausedDaysAgo: Int? { nil }
#endif
}
