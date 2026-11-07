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
    ///
    /// Stored as the calendar day, not an instant: the midnight of Nov 7 in New
    /// York is the evening of Nov 6 in Los Angeles, so an instant moved the start
    /// a day earlier when the phone travelled west.
    static let pausedDayDefaultsKey = "averagesPausedDay"

    /// Builds up to 1.9.3 build 251 stored the instant. Read once and replaced.
    static let pausedSinceKey = "averagesPausedSince"

    /// Same "yyyy-MM-dd" spelling the SwiftData cache uses for its unique key,
    /// deliberately shared so a day has one identity across the whole app.
    static func key(for date: Date) -> String {
        DailyHealthRecord.key(for: date)
    }

    static func key(for date: Date, timeZone: TimeZone) -> String {
        DailyHealthRecord.key(for: date, timeZone: timeZone)
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

    static func loadPausedDay(from defaults: UserDefaults?) -> String? {
        if let day = defaults?.string(forKey: pausedDayDefaultsKey) { return day }
        guard let legacy = defaults?.object(forKey: pausedSinceKey) as? Date else { return nil }
        let day = legacyPauseDay(legacy)
        savePausedDay(day, to: defaults)
        return day
    }

    /// The day an old pause began. It was stored as local midnight, so the instant
    /// itself says which offset wrote it, wherever the device has moved since. A few
    /// instants fit two offsets a day apart: the device's own wins, then the one
    /// people live in (UTC-10 over UTC+14, UTC+13 over UTC-11, UTC+12 over UTC-12).
    static func legacyPauseDay(_ instant: Date, currentOffset: Int = Calendar(identifier: .gregorian).timeZone.secondsFromGMT()) -> String {
        let intoUTCDay = Int(instant.timeIntervalSince1970.rounded(.down)) % 86_400
        let west = -intoUTCDay
        let east = 86_400 - intoUTCDay
        let offset = [west, east].contains(currentOffset) ? currentOffset : (west >= -10 * 3_600 ? west : east)
        return key(for: instant.addingTimeInterval(TimeInterval(offset)), timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt)
    }

    static func savePausedDay(_ day: String?, to defaults: UserDefaults?) {
        defaults?.removeObject(forKey: pausedSinceKey)
        if let day {
            defaults?.set(day, forKey: pausedDayDefaultsKey)
        } else {
            defaults?.removeObject(forKey: pausedDayDefaultsKey)
        }
    }

    /// The start of the paused day where the device is now.
    static func loadPausedSince(from defaults: UserDefaults?) -> Date? {
        loadPausedDay(from: defaults).flatMap { date(fromKey: $0) }
    }

    static func savePausedSince(_ date: Date?, to defaults: UserDefaults?) {
        savePausedDay(date.map { key(for: $0) }, to: defaults)
    }

    /// The pause day the phone sent the watch. An empty day means no pause. A
    /// phone on an older build sends only the instant.
    static func syncedPausedDay(day: String?, legacyInstant: Double?) -> String? {
        if let day { return day.isEmpty ? nil : day }
        guard let legacyInstant, legacyInstant > 0 else { return nil }
        return legacyPauseDay(Date(timeIntervalSince1970: legacyInstant))
    }

    /// Every day covered by a running pause: the pause day through today,
    /// inclusive. Empty when nothing is paused. Today is in the range because a
    /// paused day the user is currently living through is exactly the day they
    /// pressed Pause about. A westward date-line flight can put the pause day
    /// ahead of today, and today still counts as paused then.
    static func pausedKeys(since pausedSince: Date?, now: Date = .now, calendar: Calendar = .current) -> Set<String> {
        guard let pausedSince else { return [] }
        let today = calendar.startOfDay(for: now)
        var keys: Set<String> = []
        var cursor = min(calendar.startOfDay(for: pausedSince), today)
        while cursor <= today {
            keys.insert(key(for: cursor, timeZone: calendar.timeZone))
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

    /// Parses a stored key back into the local start of that day. The key is
    /// Gregorian, so it is read with a Gregorian calendar: handing the numbers to
    /// `Calendar.current` puts a Buddhist-calendar user in 1483 and a Japanese one
    /// in 4044.
    static func date(fromKey key: String, timeZone: TimeZone = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Holds the effective set between reads. History asks for it once per
    /// record, per chart bar, and rebuilding a long pause's keys on every one of
    /// those reads made the screen hang. Valid until the next local midnight,
    /// when a running pause grows by a day; the owner calls `invalidate()`
    /// whenever the picked days or the pause change.
    struct KeyCache {
        private var keys: Set<String> = []
        private var validFrom: Date = .distantFuture
        private var validUntil: Date = .distantPast
        private var validTimeZone: TimeZone?

        mutating func invalidate() {
            validFrom = .distantFuture
            validUntil = .distantPast
        }

        mutating func keys(
            picked: Set<String>,
            pausedSince: Date?,
            now: Date = .now,
            calendar: Calendar = .current
        ) -> Set<String> {
            if validFrom <= now && now < validUntil && validTimeZone == calendar.timeZone { return keys }
            let today = calendar.startOfDay(for: now)
            keys = picked.union(ExcludedDays.pausedKeys(since: pausedSince, now: now, calendar: calendar))
            validFrom = today
            validUntil = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            validTimeZone = calendar.timeZone
            return keys
        }
    }

    static func contains(_ date: Date, in keys: Set<String>) -> Bool {
        guard !keys.isEmpty else { return false }
        return keys.contains(key(for: date))
    }

    static func contains(_ date: Date, in keys: Set<String>, timeZone: TimeZone) -> Bool {
        guard !keys.isEmpty else { return false }
        return keys.contains(key(for: date, timeZone: timeZone))
    }

    /// Drops excluded days from any per-day collection. `date` pulls the day out
    /// of whatever row shape the caller has.
    static func excluding<T>(_ items: [T], keys: Set<String>, date: (T) -> Date) -> [T] {
        guard !keys.isEmpty else { return items }
        return items.filter { !contains(date($0), in: keys) }
    }
}
