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

    /// The shipping layout: hero, short benefit list, plans. Control arm.
    case catalog
    /// The 1.8.2 layout: the whole ten-feature list above the plans. Kept as a
    /// testable arm so "short list" is a claim with evidence rather than an
    /// assumption. The one thing not reproduced is the defect: 1.8.2 pushed
    /// Lifetime below the fold, and no arm ships a plan nobody can see.
    case fullList = "full_list"
    /// Leads with one feature rendered as the real thing rather than a list.
    /// The macro card: only argues for itself to someone who logs food.
    case featureLed = "feature_led"
    /// Leads with the maintenance widget. The free app answers "what did I
    /// burn"; this is the paid half of the same question, "what can I eat",
    /// and it is the only strong Vitals+ feature that needs no food logging.
    case maintenanceLed = "maintenance_led"

    static func from(metadata: [String: Any]?) -> PaywallUIVariant {
        guard let raw = metadata?[metadataKey] as? String else { return .catalog }
        return PaywallUIVariant(rawValue: raw) ?? .catalog
    }
}
