import Foundation
import SwiftData
import os

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

        // The store would not open. It is only a cache (HealthKit is the source
        // of truth and the app rebuilds from it), but "would not open" covers a
        // transient file lock or a migration we could still fix, and deleting
        // outright threw away the only copy along with any evidence of why.
        // Move it aside instead: the app gets a clean store, and the failed one
        // survives for a later look.
        quarantineStore(at: url)

        if let container = makeContainer(schema: schema, url: url) {
            return container
        }

        // Last resort: in-memory, so the app launches and can still read
        // HealthKit. Nothing persists, and widgets get an empty cache.
        let logger = Logger(subsystem: "com.jackwallner.vitals", category: "DataService")
        logger.warning("DataService: on-disk store unavailable, falling back to in-memory")
        let inMemory = ModelConfiguration("Vitals", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            // The previous code retried the identical configuration with `try!`,
            // which cannot succeed where the first attempt just failed. It only
            // traded a describable error for an opaque crash. A single-model
            // in-memory container failing means SwiftData itself is unusable, so
            // say that plainly instead.
            logger.critical("ModelContainer failed even in-memory: \(String(describing: error), privacy: .public)")
            fatalError("SwiftData could not create an in-memory container for \(schema): \(error)")
        }
    }()

    /// Moves a store that would not open, plus its WAL and SHM siblings, into a
    /// timestamped `quarantine` folder beside it. Only the most recent failure
    /// is kept, so a device that keeps failing cannot fill the App Group.
    private static func quarantineStore(at url: URL) {
        let fm = FileManager.default
        let logger = Logger(subsystem: "com.jackwallner.vitals", category: "DataService")
        let quarantine = url.deletingLastPathComponent().appendingPathComponent("quarantine", isDirectory: true)

        // One failure's worth of evidence, not every failure's.
        try? fm.removeItem(at: quarantine)
        do {
            try fm.createDirectory(at: quarantine, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create quarantine dir: \(String(describing: error), privacy: .public)")
            return
        }

        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "wal", "shm"] {
            let file = suffix.isEmpty ? url : url.appendingPathExtension(suffix)
            guard fm.fileExists(atPath: file.path) else { continue }
            let name = "\(stamp)-\(file.lastPathComponent)"
            do {
                try fm.moveItem(at: file, to: quarantine.appendingPathComponent(name))
            } catch {
                // Moving failed, so the file is still in the way. Removing it is
                // the only way the app opens at all, and a cache the user cannot
                // reach is worth less than a launchable app.
                logger.error("Quarantine move failed for \(name, privacy: .public), removing: \(String(describing: error), privacy: .public)")
                try? fm.removeItem(at: file)
            }
        }
        logger.warning("DataService: store would not open; moved aside to \(quarantine.lastPathComponent, privacy: .public)")
    }

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
        ) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Vitals.store")
    }
}
