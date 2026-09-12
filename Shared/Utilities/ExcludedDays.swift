import Foundation

/// Days the user has taken out of everything the app computes.
///
/// A day off the wrist, a sick week, a flight, a hospital stay: the data is
/// real, it just isn't representative, and one of those days drags a 7-day
/// average further than the user's actual behaviour ever does. Excluding a day
/// removes it from every figure Vitals derives (averages, totals, peaks,
/// pacing, TDEE/BMR, trends, the weekly recap) and makes it neutral for goal
/// streaks: it neither extends a streak nor breaks one.
///
/// What it deliberately does *not* do is delete the day. Excluded days stay in
/// the charts and lists, drawn dimmed, so the user can see what they excluded
/// and undo it. A day that vanished from a chart would read as missing data,
/// which is the one thing an exclusion must never look like.
///
/// Stored as a set of "yyyy-MM-dd" keys in the App Group defaults, so widgets
/// and complications honour it without a second source of truth. The set is
/// kept intentionally dumb (no ranges, no rules): the user picks days on a
/// calendar, and what they picked is exactly what is stored.
enum ExcludedDays {
    /// App Group `UserDefaults` key. Shared with the watch via `GoalSyncKeys`.
    static let defaultsKey = "excludedDays"

    /// App Group `UserDefaults` key for the running pause: the day the user hit
    /// Pause, or absent when averages are counting normally.
    ///
    /// Pause is the open-ended half of the same feature. Picking days on a
    /// calendar answers "that week was not me"; pausing answers "the next stretch
    /// won't be either, and I don't know how long it runs". While it is on, every
    /// day from the pause date through today is excluded, and the set grows on
    /// its own at midnight with nothing to remember and nothing to schedule.
    /// Resuming freezes those days into the stored set, so the record of what was
    /// excluded survives the pause ending.
    static let pausedSinceKey = "averagesPausedSince"

    /// Same "yyyy-MM-dd" spelling the SwiftData cache uses for its unique key,
    /// deliberately shared so a day has one identity across the whole app.
    static func key(for date: Date) -> String {
        DailyHealthRecord.key(for: date)
    }

    static func load(from defaults: UserDefaults?) -> Set<String> {
        guard let stored = defaults?.array(forKey: defaultsKey) as? [String] else { return [] }
        return Set(stored)
    }

    static func save(_ keys: Set<String>, to defaults: UserDefaults?) {
        if keys.isEmpty {
            defaults?.removeObject(forKey: defaultsKey)
        } else {
            defaults?.set(Array(keys).sorted(), forKey: defaultsKey)
        }
    }

    static func loadPausedSince(from defaults: UserDefaults?) -> Date? {
        defaults?.object(forKey: pausedSinceKey) as? Date
    }

    static func savePausedSince(_ date: Date?, to defaults: UserDefaults?) {
        if let date {
            defaults?.set(date, forKey: pausedSinceKey)
        } else {
            defaults?.removeObject(forKey: pausedSinceKey)
        }
    }

    /// Every day covered by a running pause: the pause day through today,
    /// inclusive. Empty when nothing is paused. Today is in the range because a
    /// paused day the user is currently living through is exactly the day they
    /// pressed Pause about.
    static func pausedKeys(since pausedSince: Date?, now: Date = .now, calendar: Calendar = .current) -> Set<String> {
        guard let pausedSince else { return [] }
        let start = calendar.startOfDay(for: pausedSince)
        let today = calendar.startOfDay(for: now)
        guard start <= today else { return [] }
        var keys: Set<String> = []
        var cursor = start
        while cursor <= today {
            keys.insert(key(for: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }

    /// The set every figure in the app actually filters on: days picked on the
    /// calendar, plus whatever a running pause covers.
    static func effectiveKeys(from defaults: UserDefaults?, now: Date = .now) -> Set<String> {
        load(from: defaults).union(pausedKeys(since: loadPausedSince(from: defaults), now: now))
    }

    static func contains(_ date: Date, in keys: Set<String>) -> Bool {
        guard !keys.isEmpty else { return false }
        return keys.contains(key(for: date))
    }

    /// Drops excluded days from any per-day collection. `date` pulls the day out
    /// of whatever row shape the caller has.
    static func excluding<T>(_ items: [T], keys: Set<String>, date: (T) -> Date) -> [T] {
        guard !keys.isEmpty else { return items }
        return items.filter { !contains(date($0), in: keys) }
    }
}
