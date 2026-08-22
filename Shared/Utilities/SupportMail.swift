import Foundation

/// mailto: helpers for Settings. Get Help and Feature Request share one inbox
/// and differ only by subject (and whether a diagnostics footer is attached).
enum SupportMail {
    static let address = "jackwallner+tc@gmail.com"

    enum Kind: Equatable {
        case getHelp
        case featureRequest

        var subject: String {
            switch self {
            case .getHelp: "Total Calories: Get Help"
            case .featureRequest: "Total Calories: Feature Request"
            }
        }
    }

    /// On-device facts we already have. Nothing here needs a new permission
    /// prompt: Health and notification *status* are reads of answers the user
    /// already gave, and the rest is Bundle / Darwin / RevenueCat state.
    struct Snapshot: Equatable {
        var appVersion: String
        var build: String
        var systemVersion: String
        var deviceModel: String
        var localeIdentifier: String
        var timeZone: String
        var isPro: Bool
        var appUserID: String?
        var healthAuthorized: Bool?
    }

    static func diagnosticsBlock(_ snapshot: Snapshot) -> String {
        var lines = [
            "App: \(snapshot.appVersion) (\(snapshot.build))",
            "iOS \(snapshot.systemVersion) · \(snapshot.deviceModel)",
            "Locale/TZ: \(snapshot.localeIdentifier) / \(snapshot.timeZone)",
            "Vitals+: \(snapshot.isPro ? "active" : "off")",
        ]
        if let id = snapshot.appUserID, !id.isEmpty {
            lines.append("RC user: \(id)")
        }
        if let health = snapshot.healthAuthorized {
            lines.append("Health: \(health ? "authorized" : "not authorized")")
        }
        return lines.joined(separator: "\n")
    }

    static func body(kind: Kind, snapshot: Snapshot?) -> String {
        switch kind {
        case .getHelp:
            guard let snapshot else { return "" }
            return "\n\n\n---\n\(diagnosticsBlock(snapshot))\n"
        case .featureRequest:
            guard let snapshot else { return "" }
            return "\n\n\n---\nTotal Calories \(snapshot.appVersion) (\(snapshot.build))\n"
        }
    }

    static func url(kind: Kind, snapshot: Snapshot?) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: kind.subject),
            URLQueryItem(name: "body", value: body(kind: kind, snapshot: snapshot)),
        ]
        return components.url
    }

    /// Hardware identifier (`iPhone17,1`) from `uname`, no extra permission.
    static func deviceModelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
