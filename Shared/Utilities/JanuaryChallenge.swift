import Foundation

/// The New Year Goal Challenge: hit a daily goal on all 31 days of January
/// 2027. It is the in-app event behind the App Store event card, opened by
/// `totalcalories://challenge`. Pure date math over daily totals, so the Today
/// row, the sheet and the tests read one answer.
enum JanuaryChallenge {
    static let year = 2027
    static let length = 31

    enum Mark: Equatable, Sendable {
        case hit
        /// Today or earlier without a goal reached. Today can still turn.
        case open
        case ahead
    }

    struct Day: Equatable, Identifiable, Sendable {
        let date: Date
        let number: Int
        let mark: Mark
        let isToday: Bool
        var id: Int { number }
    }

    struct Snapshot: Equatable, Sendable {
        let hasStarted: Bool
        let days: [Day]
        var goalDays: Int { days.filter { $0.mark == .hit }.count }
        var isComplete: Bool { goalDays == JanuaryChallenge.length }
    }

    /// The 31 local midnights of January.
    static func days(calendar: Calendar = .current) -> [Date] {
        (1...length).map { date(month: 1, day: $0, year: year, calendar: calendar) }
    }

    /// Today shows the row from the day the App Store starts promoting the
    /// event (two weeks before) until a week after it ends.
    static func showsRow(now: Date, calendar: Calendar = .current) -> Bool {
        let opens = date(month: 12, day: 18, year: year - 1, calendar: calendar)
        return now >= opens && acceptsLink(now: now, calendar: calendar)
    }

    /// The link opens the challenge any time before it is put away.
    static func acceptsLink(now: Date, calendar: Calendar = .current) -> Bool {
        now < date(month: 2, day: 8, year: year, calendar: calendar)
    }

    /// A goal day is one where either goal was reached, the same rule as the
    /// goal streak (`MilestoneCalculator.currentGoalStreak`).
    static func snapshot(
        now: Date,
        records: [MilestoneDay],
        calorieGoal: Double?,
        stepGoal: Int?,
        calendar: Calendar = .current
    ) -> Snapshot {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(
            records.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { _, last in last }
        )
        let dates = days(calendar: calendar)
        let marked = dates.enumerated().map { index, date -> Day in
            let mark: Mark
            if date > today {
                mark = .ahead
            } else if let record = byDay[date], isGoalDay(record, calorieGoal: calorieGoal, stepGoal: stepGoal) {
                mark = .hit
            } else {
                mark = .open
            }
            return Day(date: date, number: index + 1, mark: mark, isToday: date == today)
        }
        return Snapshot(hasStarted: today >= (dates.first ?? .distantFuture), days: marked)
    }

    static func isGoalDay(_ day: MilestoneDay, calorieGoal: Double?, stepGoal: Int?) -> Bool {
        let hitCalories = calorieGoal.map { day.calories >= $0 } ?? false
        let hitSteps = stepGoal.map { day.steps >= $0 } ?? false
        return hitCalories || hitSteps
    }

    private static func date(month: Int, day: Int, year: Int, calendar: Calendar) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return calendar.startOfDay(for: calendar.date(from: components) ?? .distantPast)
    }

    /// The clock the challenge reads. Always the real one in a release build.
    static func clock() -> Date {
        #if DEBUG
        if let debugNow { return debugNow }
        #endif
        return .now
    }

    #if DEBUG
    /// `-challengeNow 2027-01-12`: the challenge's clock for captures and UI
    /// tests, which cannot wait for January.
    static let debugNow: Date? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-challengeNow"), index + 1 < args.count else { return nil }
        let parts = args[index + 1].split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        return Calendar.current.date(from: components)
    }()
    #endif
}
