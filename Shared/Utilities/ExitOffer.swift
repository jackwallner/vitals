import Foundation
import Security

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
/// where they said no. Once it has been on screen, the half price is a
/// welcome price for 48 hours (`welcomeWindow`): every paywall sells the
/// yearly plan at it, says when it ends, and then goes back to full price for
/// good. Readout: `~/ios/growth/exit-offer-test.md`.
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
        static let welcomeEnded = "conv.exitOffer.welcomeEnded"
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
        return shownAt == nil
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
        #if DEBUG
        if shownThisRun == nil { shownThisRun = now }
        #endif
        guard shownAt == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: Key.shownAt)
        #if !DEBUG
        ShownAtKeychain.write(now)
        #endif
    }

    /// When the offer first came up. Release builds keep it in the Keychain as
    /// well, which survives a reinstall, so deleting the app neither brings the
    /// offer back nor restarts its window. Debug builds skip it so a UI test run
    /// never inherits the last one's.
    static var shownAt: Date? {
        let local = defaults.double(forKey: Key.shownAt)
        if local > 0 { return Date(timeIntervalSince1970: local) }
        #if DEBUG
        return nil
        #else
        return ShownAtKeychain.read()
        #endif
    }

    /// Forgets an earlier showing whose window has closed, so a forced arm (App
    /// Review) gets the offer and its window afresh on a device that saw it in
    /// an earlier review. Never called for a real customer.
    static func resetEndedShowingForReview(now: Date = .now) {
        guard windowStart != nil, welcomeEndsAt(now: now) == nil else { return }
        defaults.removeObject(forKey: Key.shownAt)
        defaults.removeObject(forKey: Key.welcomeEnded)
        #if DEBUG
        shownThisRun = nil
        welcomeEndedThisRun = false
        #else
        ShownAtKeychain.delete()
        #endif
    }

    /// When the welcome window opened. Debug builds count only this run's
    /// showing: the record outlives the app, and one UI test's offer must not
    /// leave the next test at the welcome price.
    static var windowStart: Date? {
        #if DEBUG
        return shownThisRun
        #else
        return shownAt
        #endif
    }

    /// How long the half price stays on every paywall after the offer first
    /// came up. It ends for good: nothing resets it, and it never comes back.
    static var welcomeWindow: TimeInterval {
        #if DEBUG
        if let override = welcomeWindowOverride { return override }
        #endif
        return 48 * 3600
    }

    /// When the welcome price ends, while it still stands. nil before the offer
    /// was shown and after the window closed.
    /// Once seen ended it stays ended, so setting the clock back never reopens
    /// it, and a clock set before the showing reads as ended too.
    static func welcomeEndsAt(now: Date = .now) -> Date? {
        guard let start = windowStart, !welcomeEnded else { return nil }
        let ends = start.addingTimeInterval(welcomeWindow)
        guard now >= start, now < ends else {
            welcomeEnded = true
            return nil
        }
        return ends
    }

    private static var welcomeEnded: Bool {
        get {
            #if DEBUG
            return welcomeEndedThisRun
            #else
            return defaults.bool(forKey: Key.welcomeEnded)
            #endif
        }
        set {
            #if DEBUG
            welcomeEndedThisRun = newValue
            #else
            defaults.set(newValue, forKey: Key.welcomeEnded)
            #endif
        }
    }

    /// "Welcome price, ends in 31 hours." Whole hours down to 90 minutes, then
    /// minutes. nil once it has ended.
    static func welcomeLine(endsAt: Date, now: Date = .now) -> String? {
        let remaining = endsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        if remaining >= 5400 {
            let hours = Int((remaining / 3600).rounded())
            return String(localized: "Welcome price, ends in \(hours) hours.")
        }
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes == 1 { return String(localized: "Welcome price, ends in 1 minute.") }
        return String(localized: "Welcome price, ends in \(minutes) minutes.")
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
        if let shown = shownAt {
            attributes["exit_offer_shown_at"] = iso.string(from: shown)
        }
        if let outcome = d.string(forKey: Key.outcome) {
            attributes["exit_offer_outcome"] = outcome
        }
        return attributes
    }

    #if DEBUG
    /// When this process first showed the offer; the welcome window's start in
    /// debug builds. Tests reset it.
    nonisolated(unsafe) static var shownThisRun: Date?
    nonisolated(unsafe) static var welcomeEndedThisRun = false

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

    /// `-exitOffer.welcomeWindow <seconds>` shortens the welcome price so a UI
    /// test can watch it end.
    static var welcomeWindowOverride: TimeInterval? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-exitOffer.welcomeWindow"), i + 1 < args.count else { return nil }
        return TimeInterval(args[i + 1])
    }
    #endif
}

/// `ExitOffer.shownAt` in the Keychain, as seconds since 1970.
enum ShownAtKeychain {
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.jackwallner.vitals.exitOffer",
        kSecAttrAccount as String: "shownAt",
    ] }

    static func read() -> Date? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let seconds = Double(String(decoding: data, as: UTF8.self)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    @discardableResult
    static func write(_ date: Date) -> Bool {
        let data = Data(String(date.timeIntervalSince1970).utf8)
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess { return true }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
