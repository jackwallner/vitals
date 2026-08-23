import Foundation

/// Native Upgrade-tab layouts the binary already knows how to draw. RevenueCat
/// Experiments pick which one a customer sees by putting this key on the
/// offering they are assigned: `{ "upgrade_tab": "feature_led" }`.
///
/// Two rules keep this safe to drive from a dashboard:
///
/// 1. **Missing or unknown values fall through to `catalog`**, the layout that
///    ships as the default. A typo in the dashboard, or a variant name added
///    for a build that is not live yet, degrades to the known-good screen
///    rather than to a blank one.
/// 2. **Only builds that contain a layout can draw it.** Older versions never
///    read this key at all, so nothing here can change what they show. That is
///    what keeps an experiment scoped to the release that understands it.
enum PaywallUIVariant: String, Equatable {
    static let metadataKey = "upgrade_tab"

    /// The shipping layout: hero, benefit list, plans. Control arm.
    case catalog
    /// Leads with one feature rendered as the real thing rather than a list.
    case featureLed = "feature_led"

    static func from(metadata: [String: Any]?) -> PaywallUIVariant {
        guard let raw = metadata?[metadataKey] as? String else { return .catalog }
        return PaywallUIVariant(rawValue: raw) ?? .catalog
    }
}
