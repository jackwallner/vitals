import Foundation
import SwiftData

// Accessible from any isolation context (widgets, complications)
let vitalsAppGroupID = "group.com.jackwallner.vitals"

@MainActor
enum DataService {
    static let appGroupID = vitalsAppGroupID

    static var sharedModelContainer: ModelContainer = {
        let schema = Schema([DailyHealthRecord.self])
        let url = containerURL

        // Try with existing database first
        if let container = makeContainer(schema: schema, url: url) {
            return container
        }

        // Database is corrupt — delete and retry
        print("DataService: ModelContainer failed, deleting corrupt store and retrying")
        let storeFiles = [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")]
        for file in storeFiles {
            try? FileManager.default.removeItem(at: file)
        }

        if let container = makeContainer(schema: schema, url: url) {
            return container
        }

        // Last resort: use in-memory store so the app at least launches
        print("DataService: falling back to in-memory store")
        let inMemory = ModelConfiguration("Vitals", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [inMemory])
    }()

    private static func makeContainer(schema: Schema, url: URL) -> ModelContainer? {
        let config = ModelConfiguration(
            "Vitals",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [config])
    }

    private static var containerURL: URL {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Vitals.store")
    }
}
