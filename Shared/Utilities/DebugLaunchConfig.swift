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

    /// Force the onboarding pitch arm regardless of the routing table.
    /// `VITALS_ONBOARDING_PITCH=a`..`e`. This is how the five arms are walked
    /// on a TestFlight-equivalent debug build without editing the dashboard.
    static var onboardingPitchOverride: OnboardingPitchVariant? {
        OnboardingPitchVariant(rawValue: ProcessInfo.processInfo.environment["VITALS_ONBOARDING_PITCH"] ?? "")
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
#else
    static var upgradeTabOverride: PaywallUIVariant? { nil }
    static var onboardingPitchOverride: OnboardingPitchVariant? { nil }
    static var seedHealth: Bool { false }
    static var forceSetupComplete: Bool { false }
    static var failProductLoad: Bool { false }
#endif
}
