import Foundation

/// The trial button's wording, picked by the current offering's `trial_cta`
/// metadata so a wording test is a RevenueCat Experiment against a real
/// control, the Mahj pattern. Every wording ships in the binary; a missing or
/// unknown value is `standard`, the copy 1.8.8 shipped, so nobody's button
/// changes until an Experiment arm sets the key.
///
/// The arm rides to RevenueCat as the `cta_wording` subscriber attribute with
/// the funnel attributes, which are only sent once a pitch has been shown.
/// Readout and decision rule: `~/ios/growth/cta-wording-test.md`.
///
/// Each surface keeps its own casing, and non-trial labels ("Subscribe",
/// lifetime) are untouched.
enum CTAExperiment {
    enum Arm: String, CaseIterable, Sendable {
        /// Control: "Start 7-day free trial" / "Start Free Trial", as live.
        case standard
        case my
        case your
    }

    static let attributeKey = "cta_wording"
    static let metadataKey = "trial_cta"

    /// Set by `StoreService` whenever the current offering changes.
    nonisolated(unsafe) static var offeringArm: Arm = .standard

    static var arm: Arm {
        #if DEBUG
        if let pinned = launchOverride { return pinned }
        #endif
        return offeringArm
    }

    static func from(metadata: [String: Any]?) -> Arm {
        guard let raw = metadata?[metadataKey] as? String else { return .standard }
        return Arm(rawValue: raw) ?? .standard
    }

    /// Sentence case: "Start 7-day free trial", "Start my free trial".
    static func trialCTA(_ arm: Arm = CTAExperiment.arm, trialLabel: String) -> String {
        switch arm {
        case .standard: String(localized: "Start \(trialLabel)")
        case .my: String(localized: "Start my free trial")
        case .your: String(localized: "Start your free trial")
        }
    }

    /// Title case: "Start Free Trial", "Start My Free Trial".
    static func trialCTATitleCase(_ arm: Arm = CTAExperiment.arm) -> String {
        switch arm {
        case .standard: String(localized: "Start Free Trial")
        case .my: String(localized: "Start My Free Trial")
        case .your: String(localized: "Start Your Free Trial")
        }
    }

    #if DEBUG
    /// `-cta.arm standard|my|your` pins the arm for captures.
    private static var launchOverride: Arm? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-cta.arm"), index + 1 < args.count else { return nil }
        return Arm(rawValue: args[index + 1])
    }
    #endif
}
