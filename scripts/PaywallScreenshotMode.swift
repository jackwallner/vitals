#if DEBUG
import Foundation

/// Launch with `-PaywallSnapshot trial|monthly|yearly|lifetime` to render paywall
/// surfaces for portfolio screenshot capture (see `capture-portfolio-paywall-screenshots.sh`).
enum PaywallScreenshotMode: String {
    case trial
    case monthly
    case yearly
    case lifetime

    static var current: PaywallScreenshotMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PaywallSnapshot"),
              index + 1 < arguments.count else { return nil }
        return PaywallScreenshotMode(rawValue: arguments[index + 1])
    }

    static var isActive: Bool { current != nil }
}
#endif
