import Foundation

/// App Store review deep links for Total Calories.
enum AppStoreReviewLinks {
    static let appStoreID = "6761743504"

    /// Opens the App Store write-review page (use for explicit user-initiated rating CTAs).
    static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }
}
