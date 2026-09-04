import Foundation
import os

/// On-device record of how someone met Vitals+ before they bought it — which
/// surfaces they saw, how many times, and how long it took.
///
/// RevenueCat can say a trial started; it cannot say what was on screen when it
/// did, or how many pitches came before it. These counters live in the App Group
/// so every process shares one tally, and `StoreService` mirrors them onto the
/// RevenueCat customer as subscriber attributes, where they are readable per
/// customer without a device in hand.
///
/// Deliberately NOT sent as extra custom paywall impressions: RevenueCat counts
/// every impression id as a paywall encounter, so pushing funnel steps through
/// that channel would inflate the encounter rate and ruin the one server-side
/// number that already works.
enum ConversionDiagnostics {
    private static let logger = Logger(subsystem: "com.jackwallner.vitals", category: "Conversion")

    /// The App Group id is spelled out rather than taken from `DataService`, so
    /// this file can join the standalone unit-test bundle without dragging
    /// HealthKit and SwiftData in behind it.
    static let suiteName = "group.com.jackwallner.vitals"

    /// Overridable so tests get their own suite instead of stamping on the real
    /// counters in the shared container.
    nonisolated(unsafe) static var defaultsOverride: UserDefaults?

    private static var defaults: UserDefaults {
        defaultsOverride ?? UserDefaults(suiteName: suiteName) ?? .standard
    }

    private enum Key {
        static let totalViews = "conv.pitchViews.total"
        static let firstSeen = "conv.pitchFirstSeen"
        static let lastSurface = "conv.pitchLastSurface"
        static func views(_ surface: String) -> String { "conv.pitchViews.\(surface)" }

        static let installedAt = "conv.installedAt"
        static let appOpens = "conv.appOpens"
        static let opensBeforeFirstPitch = "conv.opensBeforeFirstPitch"
        static let daysSinceInstallAtFirstPitch = "conv.daysToFirstPitch"

        static let convertedOn = "conv.convertedOn"
        static let viewsAtConvert = "conv.viewsAtConvert"
        static let daysToConvert = "conv.daysToConvert"
        static let convertedPlan = "conv.convertedPlan"
        static let convertedWithTrial = "conv.convertedWithTrial"
        static let convertedVariant = "conv.convertedVariant"
        static let convertedOffering = "conv.convertedOffering"
        static let convertedAt = "conv.convertedAt"
        static let onboardingVariant = "conv.onboardingVariant"

        /// Owned by `GoalSettings`, not by this file, but it lives in the same
        /// App Group suite and it is the single strongest way to segment this
        /// funnel: Net Deficit and Macros are half the tier and both render
        /// blank for someone who logs nothing.
        static let logsFood = "logsFoodInHealth"
    }

    /// Impression ids all carry an app prefix that says nothing once they are
    /// grouped under this app's customer record.
    static func surface(fromImpressionID id: String) -> String {
        id.hasPrefix("vitals_") ? String(id.dropFirst("vitals_".count)) : id
    }

    // MARK: - Recording

    /// The onboarding arm this binary actually drew. Not the same fact as the
    /// arm the routing table nominated: an arm the table names but this build
    /// does not contain, or cannot draw for this user's food answer, degrades to
    /// the fallback, and the test has to be read on what was rendered.
    static func recordOnboardingVariant(_ variant: String) {
        defaults.set(variant, forKey: Key.onboardingVariant)
    }

    /// One pitch was put in front of the user. Called from
    /// `StoreService.trackPaywallImpression` so every surface is covered without
    /// each call site remembering to.
    static func recordPitchView(impressionID: String) {
        let surface = surface(fromImpressionID: impressionID)
        let d = defaults
        d.set(d.integer(forKey: Key.totalViews) + 1, forKey: Key.totalViews)
        d.set(d.integer(forKey: Key.views(surface)) + 1, forKey: Key.views(surface))
        d.set(surface, forKey: Key.lastSurface)
        if d.object(forKey: Key.firstSeen) == nil {
            d.set(Date.now.timeIntervalSince1970, forKey: Key.firstSeen)
            // Frozen on the first pitch only: someone who sees a paywall on day
            // 30 was not retroactively asked on day 30 if the first ask was on
            // day one. Added later than the rest of this file, so installs that
            // predate it report neither value rather than a wrong zero.
            d.set(d.integer(forKey: Key.appOpens), forKey: Key.opensBeforeFirstPitch)
            if let installed = installDate {
                let days = Calendar.current.dateComponents([.day], from: installed, to: .now).day ?? 0
                d.set(max(0, days), forKey: Key.daysSinceInstallAtFirstPitch)
            }
        }
        logger.info("Pitch view: \(surface, privacy: .public) (total \(d.integer(forKey: Key.totalViews)))")
    }

    /// A purchase went through. Freezes what the funnel looked like at that
    /// moment, so later views can't rewrite the story of how they converted.
    ///
    /// Only the *first* conversion is recorded: a renewal or a plan change is
    /// not a new answer to "what sold this person".
    /// - Parameters:
    ///   - variant: the Upgrade-tab layout this binary was rendering, which is
    ///     not the same fact as the offering RevenueCat assigned: a build that
    ///     does not know an arm falls back to catalog while still counting as
    ///     enrolled in it.
    ///   - offeringID: the offering the arm came from, so a result can be tied
    ///     back to the experiment that produced it.
    static func recordConversion(
        plan: String,
        startedTrial: Bool,
        variant: String? = nil,
        offeringID: String? = nil
    ) {
        let d = defaults
        guard d.string(forKey: Key.convertedOn) == nil else { return }
        d.set(d.string(forKey: Key.lastSurface) ?? "unknown", forKey: Key.convertedOn)
        d.set(d.integer(forKey: Key.totalViews), forKey: Key.viewsAtConvert)
        d.set(plan, forKey: Key.convertedPlan)
        d.set(startedTrial, forKey: Key.convertedWithTrial)
        if let variant { d.set(variant, forKey: Key.convertedVariant) }
        if let offeringID { d.set(offeringID, forKey: Key.convertedOffering) }
        d.set(Date.now.timeIntervalSince1970, forKey: Key.convertedAt)
        if let first = firstSeenDate {
            let days = Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0
            d.set(max(0, days), forKey: Key.daysToConvert)
        }
        logger.info("Conversion on \(d.string(forKey: Key.convertedOn) ?? "?", privacy: .public) after \(d.integer(forKey: Key.viewsAtConvert)) pitches")
    }

    // MARK: - Reading

    /// One app launch. Stamps the install date on the very first call, which is
    /// the closest thing to an install timestamp available without a server.
    static func recordAppOpen() {
        let d = defaults
        if d.object(forKey: Key.installedAt) == nil {
            d.set(Date.now.timeIntervalSince1970, forKey: Key.installedAt)
        }
        d.set(d.integer(forKey: Key.appOpens) + 1, forKey: Key.appOpens)
    }

    static var appOpens: Int { defaults.integer(forKey: Key.appOpens) }

    static var installDate: Date? {
        let stamp = defaults.double(forKey: Key.installedAt)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    static var totalPitchViews: Int { defaults.integer(forKey: Key.totalViews) }
    static var lastSurface: String? { defaults.string(forKey: Key.lastSurface) }

    static var firstSeenDate: Date? {
        let stamp = defaults.double(forKey: Key.firstSeen)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Every per-surface count that is non-zero, keyed by surface.
    static var viewsBySurface: [String: Int] {
        var result: [String: Int] = [:]
        let prefix = "conv.pitchViews."
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            let surface = String(key.dropFirst(prefix.count))
            guard surface != "total", let count = value as? Int, count > 0 else { continue }
            result[surface] = count
        }
        return result
    }

    /// The whole record as RevenueCat subscriber attributes. Keys stay under
    /// RevenueCat's 40-character limit and values are plain strings, which is
    /// all that API accepts.
    static var subscriberAttributes: [String: String] {
        var attributes: [String: String] = [:]
        let d = defaults

        let total = totalPitchViews
        guard total > 0 else { return attributes }
        attributes["pitch_views_total"] = String(total)
        for (surface, count) in viewsBySurface {
            let key = "pitch_views_\(surface)"
            attributes[String(key.prefix(40))] = String(count)
        }
        if let last = lastSurface { attributes["pitch_last"] = last }
        if let arm = d.string(forKey: Key.onboardingVariant) {
            attributes["onboarding_variant"] = arm
        }
        // Absent on installs that predate the onboarding food question, which
        // is the honest answer: they were never asked.
        if let logsFood = d.object(forKey: Key.logsFood) as? Bool {
            attributes["logs_food"] = logsFood ? "true" : "false"
        }
        if let first = firstSeenDate {
            attributes["pitch_first_seen"] = ISO8601DateFormatter().string(from: first)
            let days = Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0
            attributes["days_since_first_pitch"] = String(max(0, days))
        }
        // Absent on installs that predate these two, which is the honest answer:
        // their real install date is unknown, not zero.
        if d.object(forKey: Key.daysSinceInstallAtFirstPitch) != nil {
            attributes["days_since_install"] = String(d.integer(forKey: Key.daysSinceInstallAtFirstPitch))
        }
        if d.object(forKey: Key.opensBeforeFirstPitch) != nil {
            attributes["opens_before_first_pitch"] = String(d.integer(forKey: Key.opensBeforeFirstPitch))
        }
        if let convertedOn = d.string(forKey: Key.convertedOn) {
            // `converted_on` used to carry this and reads as a date to anyone
            // looking at a customer record; it is a surface name. The storage
            // key keeps its old spelling so the "first conversion only" guard
            // still recognises existing installs.
            attributes["converted_surface"] = convertedOn
            let stamp = d.double(forKey: Key.convertedAt)
            if stamp > 0 {
                attributes["converted_at"] = ISO8601DateFormatter()
                    .string(from: Date(timeIntervalSince1970: stamp))
            }
            attributes["pitch_views_at_convert"] = String(d.integer(forKey: Key.viewsAtConvert))
            attributes["days_to_convert"] = String(d.integer(forKey: Key.daysToConvert))
            attributes["converted_plan"] = d.string(forKey: Key.convertedPlan) ?? "unknown"
            attributes["converted_with_trial"] = d.bool(forKey: Key.convertedWithTrial) ? "true" : "false"
            if let variant = d.string(forKey: Key.convertedVariant) {
                attributes["converted_variant"] = variant
            }
            if let offering = d.string(forKey: Key.convertedOffering) {
                attributes["converted_offering"] = offering
            }
        }
        return attributes
    }

    #if DEBUG
    /// Test seam — the counters are App Group state that outlives a launch.
    static func reset() {
        let d = defaults
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("conv.") {
            d.removeObject(forKey: key)
        }
    }
    #endif
}
