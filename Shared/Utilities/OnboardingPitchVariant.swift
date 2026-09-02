import Foundation

/// Onboarding trial-pitch layouts the binary knows how to draw.
///
/// Unlike `PaywallUIVariant`, RevenueCat cannot name one of these directly. It
/// hands out the offering at the `welcome` step, and the answer this test splits
/// on (`logsFoodInHealth`) is not committed until the `food` step two screens
/// later. So the offering carries a *routing table* instead of an arm, and the
/// app applies it once the answer exists. See `OnboardingPitchRouting`.
enum OnboardingPitchVariant: String, Equatable, CaseIterable, Sendable {
    /// What shipped through 1.8.3: glyph, headline, five feature rows. Control.
    case current = "a"
    /// Their own macro split as the hero, general rows kept underneath.
    /// Draws nothing useful without food in Health, so it is logger-only.
    case macroFood = "b"
    /// The real maintenance/BMR card, rendered and blurred behind a lock.
    /// Needs no food data, so it is the one arm identical in both segments.
    case lockedNumbers = "c"
    /// Fourteen days of burn history: the page as it looks once it has data.
    case twoWeeks = "d"
    /// Arm `d` with the net-deficit strip added. Logger-only, and deliberately
    /// the same screen as `d` otherwise, so the pair isolates the food layer.
    case twoWeeksFood = "e"

    /// Whether this arm can draw anything meaningful for the given answer.
    /// Belt to the routing table's braces: a dashboard edit that puts `b` in the
    /// non-logger segment would otherwise ship a blank card.
    func canDraw(logsFood: Bool?) -> Bool {
        switch self {
        case .macroFood, .twoWeeksFood: return logsFood == true
        case .current, .lockedNumbers, .twoWeeks: return true
        }
    }
}

/// The allocation rules, as carried on offering metadata under
/// `onboarding_pitch`. Everything here is editable in the RevenueCat dashboard
/// without a build: which arms are live per segment, how traffic splits between
/// them, whether anyone is enrolled at all, and whether the whole thing is
/// pinned to one arm.
///
/// The one thing that always needs a build is a *layout*: this only ever picks
/// among cases of `OnboardingPitchVariant` that the running binary already
/// contains. An unknown arm name degrades to `fallback` rather than to a blank
/// screen, which is what makes it safe to add an arm to the table before the
/// build that can draw it has cleared review.
struct OnboardingPitchRouting: Equatable, Sendable {
    static let metadataKey = "onboarding_pitch"

    /// Segment keys, as spelled in the metadata.
    enum Segment: String, Sendable {
        case logsFood = "logs_food"
        case noFoodLog = "no_food_log"

        /// `nil` (never asked, every install before the food question shipped)
        /// is routed with the non-loggers: there is no food data either way, so
        /// the food-dependent arms would draw blank.
        init(logsFood: Bool?) { self = logsFood == true ? .logsFood : .noFoodLog }
    }

    /// Changing this reshuffles every assignment. Useful for a clean second read
    /// after an arm's copy changes.
    var salt: String
    /// Share of customers who get randomised at all, 0...100. The remainder get
    /// `fallback`, which makes this a ramp control rather than an on/off switch.
    var enrollPercent: Int
    /// Pins everyone to one arm, ignoring the weights. This is the kill switch
    /// and the ship-the-winner switch, and it takes effect on the next fetch.
    var force: OnboardingPitchVariant?
    /// Relative weights per segment. They need not total 100, and an arm is
    /// retired by giving it weight `0`.
    var weights: [Segment: [OnboardingPitchVariant: Int]]
    /// Where anything unrecognised or unenrolled lands.
    var fallback: OnboardingPitchVariant

    /// What the app does when the offering carries no table: the shipping pitch
    /// for everyone. A build that cannot reach RevenueCat behaves exactly like
    /// 1.8.3 rather than silently entering a test.
    static let disabled = OnboardingPitchRouting(
        salt: "",
        enrollPercent: 0,
        force: nil,
        weights: [:],
        fallback: .current
    )

    // MARK: - Parsing

    /// Reads the table off offering metadata. Every field is optional and every
    /// bad value is dropped rather than defaulted to something surprising: a
    /// table that fails to parse in full still yields a usable one, and a table
    /// that yields no weights at all behaves like `.disabled`.
    static func from(metadata: [String: Any]?) -> OnboardingPitchRouting {
        guard let raw = metadata?[metadataKey] as? [String: Any] else { return .disabled }

        let fallback = (raw["fallback"] as? String)
            .flatMap(OnboardingPitchVariant.init(rawValue:)) ?? .current

        var weights: [Segment: [OnboardingPitchVariant: Int]] = [:]
        if let segments = raw["segments"] as? [String: Any] {
            for (key, value) in segments {
                guard let segment = Segment(rawValue: key),
                      let armWeights = value as? [String: Any] else { continue }
                var parsed: [OnboardingPitchVariant: Int] = [:]
                for (armKey, weight) in armWeights {
                    guard let arm = OnboardingPitchVariant(rawValue: armKey),
                          let n = (weight as? NSNumber)?.intValue, n > 0 else { continue }
                    parsed[arm] = n
                }
                if !parsed.isEmpty { weights[segment] = parsed }
            }
        }

        // An explicit 0 has to survive, so this cannot use `?? 100`: a dashboard
        // that pauses enrollment by setting 0 must not read as "unset".
        let enroll = (raw["enroll_pct"] as? NSNumber)?.intValue ?? (weights.isEmpty ? 0 : 100)

        return OnboardingPitchRouting(
            salt: raw["salt"] as? String ?? "",
            enrollPercent: min(max(enroll, 0), 100),
            force: (raw["force"] as? String).flatMap(OnboardingPitchVariant.init(rawValue:)),
            weights: weights,
            fallback: fallback
        )
    }

    // MARK: - Resolution

    /// Which arm this customer gets. Deterministic: the same id and salt always
    /// land on the same arm, so the pitch does not change if onboarding is
    /// restarted, and the assignment survives a reinstall that restores the same
    /// RevenueCat id.
    func variant(forID id: String, logsFood: Bool?) -> OnboardingPitchVariant {
        let safeFallback = fallback.canDraw(logsFood: logsFood) ? fallback : .current

        if let force { return force.canDraw(logsFood: logsFood) ? force : safeFallback }
        guard enrollPercent > 0 else { return safeFallback }

        // Two independent draws off one id: one decides enrollment, one picks
        // the arm. Salting them differently keeps the enrolled slice from
        // correlating with which arm it lands on when `enroll_pct` is ramped.
        let enrollRoll = Self.bucket(id + "|enroll|" + salt, modulo: 100)
        guard enrollRoll < enrollPercent else { return safeFallback }

        let segment = Segment(logsFood: logsFood)
        // Sorted so the mapping from roll to arm is stable across launches;
        // dictionary order is not.
        let candidates = (weights[segment] ?? [:])
            .filter { $0.key.canDraw(logsFood: logsFood) && $0.value > 0 }
            .sorted { $0.key.rawValue < $1.key.rawValue }
        let total = candidates.reduce(0) { $0 + $1.value }
        guard total > 0 else { return safeFallback }

        var roll = Self.bucket(id + "|arm|" + salt, modulo: total)
        for (arm, weight) in candidates {
            if roll < weight { return arm }
            roll -= weight
        }
        return safeFallback
    }

    /// FNV-1a over the UTF-8 bytes. Swift's own `hashValue` is seeded per
    /// process and would hand the same customer a different arm on every launch.
    static func bucket(_ string: String, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(modulo))
    }
}
