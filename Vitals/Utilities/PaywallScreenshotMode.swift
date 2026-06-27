#if DEBUG
import Foundation

/// Launch args for portfolio screenshot capture.
/// `-PaywallSnapshot trial` — generic trial sheet
/// `-PaywallSnapshot yearly` — generic full paywall, yearly selected
/// `-PaywallSnapshot trial-tdee` — intent trial sheet (TDEE toggle)
/// `-PaywallSnapshot yearly-net-deficit` — intent full paywall, yearly selected
struct PaywallSnapshotRequest: Equatable {
    enum Plan: String {
        case trial
        case monthly
        case yearly
        case lifetime
    }

    let plan: Plan
    /// Slug after `-`, e.g. `tdee` in `trial-tdee`. Nil = generic upgrade pitch.
    let focusSlug: String?

    static var current: PaywallSnapshotRequest? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PaywallSnapshot"),
              index + 1 < arguments.count else { return nil }
        return PaywallSnapshotRequest.parse(arguments[index + 1])
    }

    static var isActive: Bool { current != nil }

    static func parse(_ raw: String) -> PaywallSnapshotRequest? {
        let parts = raw.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let plan = Plan(rawValue: String(first)) else { return nil }
        let slug = parts.count > 1 ? String(parts[1]) : nil
        return PaywallSnapshotRequest(plan: plan, focusSlug: slug?.isEmpty == true ? nil : slug)
    }

    var filename: String {
        if let focusSlug { return "\(plan.rawValue)-\(focusSlug)" }
        return plan.rawValue
    }
}

/// Back-compat for call sites that only need the plan enum.
enum PaywallScreenshotMode: String {
    case trial
    case monthly
    case yearly
    case lifetime

    static var current: PaywallScreenshotMode? {
        guard let plan = PaywallSnapshotRequest.current?.plan else { return nil }
        return PaywallScreenshotMode(rawValue: plan.rawValue)
    }

    static var isActive: Bool { PaywallSnapshotRequest.isActive }
}
#endif
