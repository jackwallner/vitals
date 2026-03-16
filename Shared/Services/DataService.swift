import Foundation
import SwiftData

@MainActor
enum DataService {
    static let appGroupID = "group.com.jackwallner.vitals"

    static var sharedModelContainer: ModelContainer = {
        let schema = Schema([DailyHealthRecord.self])
        let config = ModelConfiguration(
            "Vitals",
            schema: schema,
            url: containerURL,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    private static var containerURL: URL {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Vitals.store")
    }
}
