import Foundation
import SwiftData

/// SwiftData store for Headache Logger.
///
/// **Crash fix (TestFlight):** Do not use `ModelConfiguration`'s `groupContainer:` parameter when the app group
/// may be unavailable — SwiftData asserts in `discoverDirectory`. Resolve a concrete file URL instead: prefer
/// the App Group container when the entitlement is present, otherwise Application Support (same pattern as Vitals `DataService`).
enum HeadacheModelStore {
    static let appGroupID = "group.com.jackwallner.headachelogger"

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([HeadacheEvent.self])
        let url = storeURL

        if let container = makeContainer(schema: schema, url: url) {
            return container
        }

        consoleError("HeadacheModelStore: ModelContainer failed, deleting corrupt store and retrying", trace: ["url": url.path])
        let storeFiles = [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")]
        for file in storeFiles {
            try? FileManager.default.removeItem(at: file)
        }

        if let container = makeContainer(schema: schema, url: url) {
            return container
        }

        consoleError("HeadacheModelStore: falling back to in-memory store", trace: [:])
        let inMemory = ModelConfiguration("HeadacheLogger", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            fatalError("HeadacheModelStore: ModelContainer could not initialize even in-memory: \(error)")
        }
    }()

    private static func makeContainer(schema: Schema, url: URL) -> ModelContainer? {
        let config = ModelConfiguration(
            "HeadacheLogger",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [config])
    }

    private static var storeURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("HeadacheLogger.store")
    }

    private static func consoleError(_ message: String, trace: [String: String]) {
        var parts = [message]
        if !trace.isEmpty {
            parts.append(trace.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        }
        print(parts.joined(separator: " | "))
    }
}
