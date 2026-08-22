import Foundation

/// Native Upgrade-tab layouts the binary already knows how to draw. RevenueCat
/// Experiments pick which one a customer sees by putting this key on the
/// offering they are assigned: `{ "upgrade_tab": "timeline" }`.
///
/// Missing or unknown values fall through to `timeline`, the layout that leads
/// with how the trial works rather than a feature catalog.
enum PaywallUIVariant: String, Equatable {
    static let metadataKey = "upgrade_tab"

    case catalog
    case timeline

    static func from(metadata: [String: Any]?) -> PaywallUIVariant {
        guard let raw = metadata?[metadataKey] as? String else { return .timeline }
        return PaywallUIVariant(rawValue: raw) ?? .timeline
    }
}
