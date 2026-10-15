import Foundation

/// Paywall CTA wording test, October 2026: "Start my free trial" against
/// "Start your free trial", judged on trial starts per exposed customer.
///
/// Each install is assigned once, 50/50, and keeps its arm for life, so nobody
/// sees the button change under them. The arm rides to RevenueCat as the
/// `cta_wording` subscriber attribute together with the funnel attributes,
/// which are only sent once a pitch has been shown: a customer carrying the
/// attribute saw a trial CTA in that arm. Readout and decision rule:
/// `~/ios/growth/cta-wording-test.md`.
///
/// Only the possessive changes. Each surface keeps its own casing, and
/// non-trial labels ("Subscribe", lifetime) are untouched.
enum CTAExperiment {
    enum Arm: String, CaseIterable, Sendable {
        case my, your
    }

    static let attributeKey = "cta_wording"
    private static let storageKey = "experiment.ctaWording.2026-10"

    /// Overridable so tests get their own suite.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    static var arm: Arm {
        #if DEBUG
        if let pinned = launchOverride { return pinned }
        #endif
        if let stored = defaults.string(forKey: storageKey).flatMap(Arm.init(rawValue:)) {
            return stored
        }
        let assigned: Arm = Bool.random() ? .my : .your
        defaults.set(assigned.rawValue, forKey: storageKey)
        return assigned
    }

    /// Sentence case: "Start my free trial".
    static func trialCTA(_ arm: Arm = CTAExperiment.arm) -> String {
        "Start \(arm.rawValue) free trial"
    }

    /// Title case: "Start My Free Trial".
    static func trialCTATitleCase(_ arm: Arm = CTAExperiment.arm) -> String {
        "Start \(arm.rawValue.capitalized) Free Trial"
    }

    #if DEBUG
    /// `-cta.arm my` or `-cta.arm your` pins the arm for captures.
    private static var launchOverride: Arm? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-cta.arm"), index + 1 < args.count else { return nil }
        return Arm(rawValue: args[index + 1])
    }

    /// Test seam: forget the assignment.
    static func reset() {
        defaults.removeObject(forKey: storageKey)
    }
    #endif
}
