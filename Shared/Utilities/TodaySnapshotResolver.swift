import Foundation

/// Which numbers Siri and Shortcuts answer with for today. Pure, so the
/// locked-phone case is testable without a device.
enum TodaySnapshotResolver {
    struct Stats: Equatable {
        let active: Double
        let resting: Double
        let steps: Int
    }

    /// Live Health first (it reads all zeros while the phone is locked), then the
    /// cache the widgets read. `nil` means there is no honest answer: locked
    /// with nothing cached for today yet, where a zero would be wrong.
    static func resolve(live: Stats?, cached: Stats?, protectedDataAvailable: Bool) -> Stats? {
        if let live, !isAllZero(live) { return live }
        if let cached { return cached }
        guard protectedDataAvailable else { return nil }
        return Stats(active: 0, resting: 0, steps: 0)
    }

    private static func isAllZero(_ stats: Stats) -> Bool {
        stats.active == 0 && stats.resting == 0 && stats.steps == 0
    }
}
