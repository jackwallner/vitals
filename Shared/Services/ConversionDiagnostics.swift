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

        static let convertedOn = "conv.convertedOn"
        static let viewsAtConvert = "conv.viewsAtConvert"
        static let daysToConvert = "conv.daysToConvert"
        static let convertedPlan = "conv.convertedPlan"
        static let convertedWithTrial = "conv.convertedWithTrial"
    }

    /// Impression ids all carry an app prefix that says nothing once they are
    /// grouped under this app's customer record.
    static func surface(fromImpressionID id: String) -> String {
        id.hasPrefix("vitals_") ? String(id.dropFirst("vitals_".count)) : id
    }

    // MARK: - Recording

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
        }
        logger.info("Pitch view: \(surface, privacy: .public) (total \(d.integer(forKey: Key.totalViews)))")
    }

    /// A purchase went through. Freezes what the funnel looked like at that
    /// moment, so later views can't rewrite the story of how they converted.
    ///
    /// Only the *first* conversion is recorded: a renewal or a plan change is
    /// not a new answer to "what sold this person".
    static func recordConversion(plan: String, startedTrial: Bool) {
        let d = defaults
        guard d.string(forKey: Key.convertedOn) == nil else { return }
        d.set(d.string(forKey: Key.lastSurface) ?? "unknown", forKey: Key.convertedOn)
        d.set(d.integer(forKey: Key.totalViews), forKey: Key.viewsAtConvert)
        d.set(plan, forKey: Key.convertedPlan)
        d.set(startedTrial, forKey: Key.convertedWithTrial)
        if let first = firstSeenDate {
            let days = Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0
            d.set(max(0, days), forKey: Key.daysToConvert)
        }
        logger.info("Conversion on \(d.string(forKey: Key.convertedOn) ?? "?", privacy: .public) after \(d.integer(forKey: Key.viewsAtConvert)) pitches")
    }

    // MARK: - Reading

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
        if let first = firstSeenDate {
            attributes["pitch_first_seen"] = ISO8601DateFormatter().string(from: first)
            let days = Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0
            attributes["days_since_first_pitch"] = String(max(0, days))
        }
        if let convertedOn = d.string(forKey: Key.convertedOn) {
            attributes["converted_on"] = convertedOn
            attributes["pitch_views_at_convert"] = String(d.integer(forKey: Key.viewsAtConvert))
            attributes["days_to_convert"] = String(d.integer(forKey: Key.daysToConvert))
            attributes["converted_plan"] = d.string(forKey: Key.convertedPlan) ?? "unknown"
            attributes["converted_with_trial"] = d.bool(forKey: Key.convertedWithTrial) ? "true" : "false"
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
