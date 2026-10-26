import Foundation

/// The paywall exit offer: Vitals+ Yearly at half price, shown once, the first
/// time someone closes a paywall on purpose without buying.
///
/// Lives in its own RevenueCat offering, `exit_offer`, which is never current:
/// it holds the `exit_annual` package and, in its metadata, the split
/// (`{"offer_pct": 50, "salt": "exit1", "force": null}`). Older binaries only
/// read the current offering, so they never see the half-price plan, and the
/// test runs beside any RevenueCat Experiment instead of competing with it for
/// customers. The arm is a stable hash of the RevenueCat app user id against
/// the salt, so the holdout is a real randomized control. `force` pins
/// everyone to one arm (review builds); `offer_pct` 0 switches it off.
///
/// The close is the denominator, recorded for both arms the same way: the
/// first deliberate close (a close button, "Not now", or onboarding's "Get
/// Started"). A swipe-down is not counted in either arm. The close itself
/// goes through as normal in both arms; the offer arm then gets the offer as
/// its own sheet when the customer comes back to the app at least an hour
/// later (`isPending`, `isReady`, shown by `MainTabView`), never in the visit
/// where they said no. Readout: `~/ios/growth/exit-offer-test.md`.
enum ExitOffer {
    enum Arm: String, Sendable {
        case offer
        case holdout
    }

    enum Outcome: String, Sendable {
        case purchased
        case declined
    }

    static let offeringID = "exit_offer"
    static let packageID = "exit_annual"
    /// Impression id for the offer itself; its surface reads `exit_offer`.
    static let impressionID = "vitals_exit_offer"

    /// nil when the offering carries no split: not in the test.
    static func arm(from metadata: [String: Any]?, appUserID: String) -> Arm? {
        guard let metadata else { return nil }
        if let forced = (metadata["force"] as? String).flatMap(Arm.init(rawValue:)) {
            return forced
        }
        guard let pct = (metadata["offer_pct"] as? NSNumber)?.intValue,
              let salt = metadata["salt"] as? String else { return nil }
        return bucket(salt: salt, appUserID: appUserID) < pct ? .offer : .holdout
    }

    /// 0..<100, stable across launches and builds. FNV-1a, because Swift's own
    /// `Hasher` is seeded per process.
    static func bucket(salt: String, appUserID: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(salt):\(appUserID)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % 100)
    }

    private enum Key {
        static let arm = "conv.exitOffer.arm"
        static let closedAt = "conv.exitOffer.closedAt"
        static let surface = "conv.exitOffer.surface"
        static let shownAt = "conv.exitOffer.shownAt"
        static let outcome = "conv.exitOffer.outcome"
        static let pending = "conv.exitOffer.pending"
    }

    /// Same suite as `ConversionDiagnostics`, so its test reset clears this too.
    private static var defaults: UserDefaults {
        ConversionDiagnostics.defaultsOverride
            ?? UserDefaults(suiteName: ConversionDiagnostics.suiteName)
            ?? .standard
    }

    /// A paywall was closed on purpose. Records the first close for either arm,
    /// then answers whether to show the offer now: offer arm, never shown
    /// before, not already Vitals+, and the discounted plan actually loaded.
    static func shouldOffer(
        onCloseOf surface: String,
        arm: Arm?,
        offerLoaded: Bool,
        isPro: Bool,
        now: Date = .now
    ) -> Bool {
        guard let arm, !isPro else { return false }
        let d = defaults
        if d.object(forKey: Key.closedAt) == nil {
            d.set(now.timeIntervalSince1970, forKey: Key.closedAt)
            d.set(surface, forKey: Key.surface)
            d.set(arm.rawValue, forKey: Key.arm)
        }
        guard arm == .offer, offerLoaded else { return false }
        return d.object(forKey: Key.shownAt) == nil
    }

    /// Owed but not yet on screen. Persisted, so an app closed before the sheet
    /// came up still gets it on the next launch.
    static var isPending: Bool {
        get { defaults.bool(forKey: Key.pending) }
        set { defaults.set(newValue, forKey: Key.pending) }
    }

    /// How long after the first close the offer waits. It then comes up on the
    /// next return to the app, never in the middle of a visit.
    static var returnDelay: TimeInterval {
        #if DEBUG
        if let override = returnDelayOverride { return override }
        #endif
        return 3600
    }

    /// The app came back (a launch, or a return from the background) at
    /// `activatedAt`, at least `returnDelay` after the first close. A forced arm
    /// (App Review) skips the wait so the offer follows the close.
    static func isReady(activatedAt: Date, skipsWait: Bool) -> Bool {
        guard !skipsWait else { return true }
        let closed = defaults.double(forKey: Key.closedAt)
        guard closed > 0 else { return true }
        return activatedAt.timeIntervalSince1970 - closed >= returnDelay
    }

    static func recordShown(now: Date = .now) {
        let d = defaults
        guard d.object(forKey: Key.shownAt) == nil else { return }
        d.set(now.timeIntervalSince1970, forKey: Key.shownAt)
    }

    /// First answer only: a decline followed by a later full-price purchase is
    /// still a decline here, and the purchase shows in the conversion record.
    static func recordOutcome(_ outcome: Outcome) {
        let d = defaults
        guard d.string(forKey: Key.outcome) == nil else { return }
        d.set(outcome.rawValue, forKey: Key.outcome)
    }

    static var hasClosed: Bool { defaults.object(forKey: Key.closedAt) != nil }

    /// Rides with the funnel attributes in `StoreService.syncConversionAttributes`.
    static var subscriberAttributes: [String: String] {
        let d = defaults
        guard let arm = d.string(forKey: Key.arm) else { return [:] }
        let iso = ISO8601DateFormatter()
        var attributes = ["exit_offer_arm": arm]
        let closed = d.double(forKey: Key.closedAt)
        if closed > 0 {
            attributes["exit_offer_closed_at"] = iso.string(from: Date(timeIntervalSince1970: closed))
        }
        if let surface = d.string(forKey: Key.surface) {
            attributes["exit_offer_surface"] = surface
        }
        let shown = d.double(forKey: Key.shownAt)
        if shown > 0 {
            attributes["exit_offer_shown_at"] = iso.string(from: Date(timeIntervalSince1970: shown))
        }
        if let outcome = d.string(forKey: Key.outcome) {
            attributes["exit_offer_outcome"] = outcome
        }
        return attributes
    }

    #if DEBUG
    /// `-exitOffer.force` puts this run in the offer arm and ignores "shown
    /// before", for captures and review of the screen.
    static var isForced: Bool {
        ProcessInfo.processInfo.arguments.contains("-exitOffer.force")
    }

    /// `-exitOffer.returnDelay <seconds>` shortens the wait for a return and
    /// keeps it even under `-exitOffer.force`, so a UI test can walk it.
    static var returnDelayOverride: TimeInterval? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-exitOffer.returnDelay"), i + 1 < args.count else { return nil }
        return TimeInterval(args[i + 1])
    }
    #endif
}
