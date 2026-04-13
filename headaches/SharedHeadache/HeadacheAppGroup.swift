import Foundation

/// App group shared by iPhone app and Watch companion (onboarding flags, etc.).
enum HeadacheAppGroup {
    static let identifier = "group.com.jackwallner.headachelogger"

    static var userDefaults: UserDefaults {
        guard let suite = UserDefaults(suiteName: identifier) else {
            fatalError("HeadacheAppGroup: could not open UserDefaults suite \(identifier)")
        }
        return suite
    }
}

enum HeadacheStorageKey: String {
    case hasCompletedOnboarding = "hasCompletedHeadacheOnboarding"
    case declinedHealthRead = "headacheDeclinedHealthRead"
    case declinedLocation = "headacheDeclinedLocation"
}

enum HeadacheOnboardingStore {
    static var hasCompletedOnboarding: Bool {
        get { HeadacheAppGroup.userDefaults.bool(forKey: HeadacheStorageKey.hasCompletedOnboarding.rawValue) }
        set { HeadacheAppGroup.userDefaults.set(newValue, forKey: HeadacheStorageKey.hasCompletedOnboarding.rawValue) }
    }

    static var declinedHealthRead: Bool {
        get { HeadacheAppGroup.userDefaults.bool(forKey: HeadacheStorageKey.declinedHealthRead.rawValue) }
        set { HeadacheAppGroup.userDefaults.set(newValue, forKey: HeadacheStorageKey.declinedHealthRead.rawValue) }
    }

    static var declinedLocation: Bool {
        get { HeadacheAppGroup.userDefaults.bool(forKey: HeadacheStorageKey.declinedLocation.rawValue) }
        set { HeadacheAppGroup.userDefaults.set(newValue, forKey: HeadacheStorageKey.declinedLocation.rawValue) }
    }

    /// Reset for UI tests / previews only.
    static func resetForTesting() {
        hasCompletedOnboarding = false
        declinedHealthRead = false
        declinedLocation = false
    }
}
