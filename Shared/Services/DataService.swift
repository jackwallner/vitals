import Foundation
import SwiftData

// Accessible from any isolation context (widgets, complications)
let vitalsAppGroupID = "group.com.jackwallner.vitals"

@MainActor
enum DataService {
    static let appGroupID = vitalsAppGroupID

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
