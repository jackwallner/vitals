import HealthKit

enum HealthNotice: Equatable {
    case accessNeeded
    case noData
    case loadError

    /// HealthKit hides read authorization, so an empty read cannot establish denial.
    static func emptyFetch(requestStatus: HKAuthorizationRequestStatus?) -> HealthNotice {
        requestStatus == .shouldRequest ? .accessNeeded : .noData
    }

    var iconName: String {
        switch self {
        case .accessNeeded: "heart.text.square.fill"
        case .noData: "heart.text.clipboard"
        case .loadError: "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch self {
        case .accessNeeded: "Health access needed"
        case .noData: "No Health data yet"
        case .loadError: "Couldn't refresh Health data"
        }
    }

    var message: String {
        switch self {
        case .accessNeeded:
            "Grant Apple Health access so Total Calories can load your active calories, resting calories, and steps."
        case .noData:
            "Apple Health may still be syncing. Check that your watch or fitness app has added data, or check Health access."
        case .loadError:
            "Try reopening the app in a moment, or check Apple Health access."
        }
    }

    var buttonTitle: String? {
        switch self {
        case .accessNeeded:
            "Enable Health"
        case .noData:
            "Check Health Access"
        case .loadError:
            "Open Health"
        }
    }
}
