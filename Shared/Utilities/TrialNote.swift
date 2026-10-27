import Foundation

/// A short note from the studio under the onboarding trial pitch, picked by
/// the current offering's `trial_note` metadata, the `CTAExperiment` pattern:
/// a RevenueCat Experiment whose treatment offering sets `trial_note: indie`
/// against the default offering as control. Missing or unknown is `none`, so
/// the binary alone changes nothing.
///
/// The note promises "tell us what to fix", so a customer who saw it and then
/// switches the trial's renewal off is asked exactly that, once, through the
/// feedback sheet. The arm rides to RevenueCat as the `trial_note` attribute
/// with the funnel attributes. Readout: `~/ios/growth/indie-note-test.md`.
enum TrialNote {
    enum Arm: String, CaseIterable, Sendable {
        /// Control: the pitch as live.
        case none
        case indie
    }

    static let attributeKey = "trial_note"
    static let metadataKey = "trial_note"

    /// Set by `StoreService` whenever the current offering changes.
    nonisolated(unsafe) static var offeringArm: Arm = .none

    static var arm: Arm {
        #if DEBUG
        if let pinned = launchOverride { return pinned }
        #endif
        return offeringArm
    }

    static func from(metadata: [String: Any]?) -> Arm {
        guard let raw = metadata?[metadataKey] as? String else { return .none }
        return Arm(rawValue: raw) ?? .none
    }

    private enum Key {
        static let seen = "trialNote.seen"
        static let asked = "trialNote.whatToFixAsked"
    }

    /// The note was on screen for this install.
    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Key.seen)
    }

    /// True once: the note was seen and the customer's free trial (running or
    /// ended) will not renew. A billing retry is not a choice to leave, so the caller
    /// passes `willRenew` true for it.
    static func whatToFixDue(inTrial: Bool, willRenew: Bool, _ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Key.seen) && !defaults.bool(forKey: Key.asked) && inTrial && !willRenew
    }

    /// Spent only when the sheet is actually shown.
    static func markAsked(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Key.asked)
    }

    #if DEBUG
    /// `-trialNote.arm none|indie` pins the arm for captures.
    private static var launchOverride: Arm? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-trialNote.arm"), index + 1 < args.count else { return nil }
        return Arm(rawValue: args[index + 1])
    }
    #endif
}
