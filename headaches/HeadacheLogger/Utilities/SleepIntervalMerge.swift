import Foundation

/// Pure helpers to derive main sleep end (wake) time from overlapping sleep segments (no HealthKit dependency — testable).
enum SleepIntervalMerge: Sendable {
    struct Interval: Sendable, Equatable {
        let start: Date
        let end: Date

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// Merges intervals that are within `mergeGap` seconds of each other (Apple often splits sleep into adjacent segments).
    static func merge(_ intervals: [Interval], mergeGap: TimeInterval) -> [Interval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var out: [Interval] = []
        for interval in sorted {
            guard let last = out.last else {
                out.append(interval)
                continue
            }
            if interval.start <= last.end.addingTimeInterval(mergeGap) {
                out[out.count - 1] = Interval(start: last.start, end: max(last.end, interval.end))
            } else {
                out.append(interval)
            }
        }
        return out
    }

    /// End time of the longest merged block (proxy for “main sleep” wake time).
    static func wakeTimeAfterLongestSleep(_ merged: [Interval]) -> Date? {
        merged.max(by: { $0.duration < $1.duration })?.end
    }
}
