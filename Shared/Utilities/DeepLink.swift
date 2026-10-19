import Foundation

/// Every place outside the app that can open it on a specific screen: widget
/// taps, notification taps, and App Shortcuts. One URL shape for all of them so
/// the app has a single router (`DeepLinkRouter`) instead of one per source.
///
/// `totalcalories://today`, `totalcalories://metric/steps`,
/// `totalcalories://recap`.
enum DeepLink: Equatable, Sendable {
    case today
    case metric(Metric)
    case weeklyRecap

    /// Mirrors the iOS `HistoryMetric` cases by raw value. Kept separate because
    /// `HistoryMetric` carries SwiftUI colors and lives in the app target only.
    enum Metric: String, Sendable, CaseIterable {
        case calories
        case steps
        case net
        case macros
    }

    static let scheme = "totalcalories"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today:
            components.host = "today"
        case .metric(let metric):
            components.host = "metric"
            components.path = "/\(metric.rawValue)"
        case .weeklyRecap:
            components.host = "recap"
        }
        // Built from constants, so this can only fail on a programming error.
        return components.url ?? URL(string: "\(Self.scheme)://today")!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        switch url.host?.lowercased() {
        case "today":
            self = .today
        case "recap":
            self = .weeklyRecap
        case "metric":
            let name = url.pathComponents.first { $0 != "/" }?.lowercased() ?? ""
            guard let metric = Metric(rawValue: name) else { return nil }
            self = .metric(metric)
        default:
            return nil
        }
    }

    /// Notification `userInfo` key carrying `url.absoluteString`.
    static let userInfoKey = "deepLink"
}
