import Foundation

/// The three macronutrients Vitals reads from Apple Health. Food apps
/// (MyFitnessPal, Cronometer, Lose It) write these alongside dietary energy, so
/// a user who already logs meals gets macros with no extra work.
enum MacroKind: String, CaseIterable, Sendable, Identifiable, Comparable {
    case protein
    case carbs
    case fat

    var id: String { rawValue }

    /// Sets of macros are rendered in declaration order (protein, carbs, fat)
    /// everywhere, so a user toggling one off never reshuffles the other two.
    static func < (lhs: MacroKind, rhs: MacroKind) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }

    var label: String {
        switch self {
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        }
    }

    /// Single letter used in tight rows (recent-days list, dashboard splits).
    var initial: String {
        switch self {
        case .protein: "P"
        case .carbs: "C"
        case .fat: "F"
        }
    }

    /// Atwater factors — the same conversion food labels use.
    var kcalPerGram: Double {
        switch self {
        case .protein, .carbs: 4
        case .fat: 9
        }
    }

    /// Accepted range for a daily gram goal. Wide enough for keto through
    /// high-carb endurance eating, tight enough to catch a fat-fingered entry.
    var goalRange: ClosedRange<Int> {
        switch self {
        case .protein: 10...500
        case .carbs: 10...1000
        case .fat: 10...400
        }
    }

    var defaultGoal: Int {
        switch self {
        case .protein: 150
        case .carbs: 250
        case .fat: 70
        }
    }
}

/// Which macros draw a progress bar and which stay a plain gram pill.
///
/// Whether a macro has a target is a per-macro decision (a protein number to hit
/// while carbs and fat stay a reference readout is a normal way to eat), so the
/// answer is set arithmetic over three inputs rather than one switch. It lives
/// here, as pure functions, so the rules are testable without standing up the
/// app-group-backed `GoalSettings` singleton.
enum MacroGoalSelection {

    /// Visible macros with a target, canonical order. Empty when Macro Goals is
    /// off, so callers can treat it as the whole question of "does anything here
    /// have a target".
    static func goaled(enabled: Bool, goaled: Set<MacroKind>, visible: Set<MacroKind>) -> [MacroKind] {
        guard enabled else { return [] }
        return MacroKind.allCases.filter { goaled.contains($0) && visible.contains($0) }
    }

    /// Visible macros shown as a plain gram pill: no target, or Macro Goals off.
    static func ungoaled(enabled: Bool, goaled goaledSet: Set<MacroKind>, visible: Set<MacroKind>) -> [MacroKind] {
        let barred = Set(goaled(enabled: enabled, goaled: goaledSet, visible: visible))
        return MacroKind.allCases.filter { visible.contains($0) && !barred.contains($0) }
    }

    /// The last goaled macro can't be switched off: that state is Macro Goals
    /// off, and its switch sits directly above these rows.
    static func canDisableGoal(enabled: Bool, goaled goaledSet: Set<MacroKind>, visible: Set<MacroKind>) -> Bool {
        goaled(enabled: enabled, goaled: goaledSet, visible: visible).count > 1
    }
}

/// One day's macronutrient totals in grams.
struct MacroTotals: Equatable, Sendable {
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = MacroTotals(protein: 0, carbs: 0, fat: 0)

    init(protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        self.protein = max(protein, 0)
        self.carbs = max(carbs, 0)
        self.fat = max(fat, 0)
    }

    func grams(_ kind: MacroKind) -> Double {
        switch kind {
        case .protein: protein
        case .carbs: carbs
        case .fat: fat
        }
    }

    /// Energy the logged macros account for. Deliberately *not* compared against
    /// `dietaryEnergyConsumed` — alcohol and rounding mean the two rarely match,
    /// and reconciling them would only invite "your app disagrees with MFP".
    var calories: Double {
        MacroKind.allCases.reduce(0) { $0 + grams($1) * $1.kcalPerGram }
    }

    /// True once any macro has been logged. Days with no food (or a food app
    /// that only writes calories) stay out of averages and charts.
    var hasData: Bool {
        hasData(in: Set(MacroKind.allCases))
    }

    /// True when any of `kinds` was logged. A user tracking only carbs shouldn't
    /// see a day counted (or a chart bar drawn) because they logged protein.
    func hasData(in kinds: Set<MacroKind>) -> Bool {
        kinds.contains { grams($0) > 0 }
    }

    /// Share of the day's macro calories this macro accounts for, 0...1.
    /// Returns nil when nothing is logged, so callers render a dash, not "0%".
    func share(_ kind: MacroKind) -> Double? {
        let total = calories
        guard total > 0 else { return nil }
        return grams(kind) * kind.kcalPerGram / total
    }

    /// Whole-percent split that always sums to 100, via largest-remainder
    /// allocation. Rounding each share independently gives "31% / 40% / 30%",
    /// which is visibly wrong when the three are shown together on one line.
    /// Returns nil when nothing is logged.
    func sharePercentages() -> [MacroKind: Int]? {
        guard calories > 0 else { return nil }
        let exact = MacroKind.allCases.map { (kind: $0, value: (share($0) ?? 0) * 100) }
        var result = Dictionary(uniqueKeysWithValues: exact.map { ($0.kind, Int($0.value)) })
        var remainder = 100 - result.values.reduce(0, +)
        // Hand the leftover points to the macros with the largest fractional part.
        for entry in exact.sorted(by: { $0.value.truncatingRemainder(dividingBy: 1) > $1.value.truncatingRemainder(dividingBy: 1) }) {
            guard remainder > 0 else { break }
            result[entry.kind, default: 0] += 1
            remainder -= 1
        }
        return result
    }

    static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }

    static func / (lhs: MacroTotals, divisor: Double) -> MacroTotals {
        guard divisor > 0 else { return .zero }
        return MacroTotals(
            protein: lhs.protein / divisor,
            carbs: lhs.carbs / divisor,
            fat: lhs.fat / divisor
        )
    }
}

/// Period aggregate for the History screen: averages and totals over the days
/// that actually have macros logged. Days without macros are excluded rather
/// than averaged in as zeros — one unlogged day would otherwise drag a weekly
/// protein average down by a seventh and read as a real drop.
struct MacroSummary: Equatable, Sendable {
    let average: MacroTotals
    let total: MacroTotals
    let loggedDays: Int
    /// Logged days, oldest first, so callers can pick a best day per macro
    /// rather than being handed one the user may not even be tracking.
    let days: [Day]

    struct Day: Equatable, Sendable {
        let date: Date
        let totals: MacroTotals
    }

    /// Highest day for `kind`, or nil when nothing was logged for it.
    func bestDay(for kind: MacroKind) -> (date: Date, grams: Double)? {
        guard let best = days.max(by: { $0.totals.grams(kind) < $1.totals.grams(kind) }),
              best.totals.grams(kind) > 0
        else { return nil }
        return (best.date, best.totals.grams(kind))
    }

    /// - Parameter visible: which macros count toward "this day has data". Days
    ///   are still summed in full so the calorie split stays honest; the filter
    ///   only decides which days qualify.
    static func make(
        macrosByDay: [Date: MacroTotals],
        visible: Set<MacroKind> = Set(MacroKind.allCases),
        calendar: Calendar = .current
    ) -> MacroSummary? {
        let logged = macrosByDay
            .filter { $0.value.hasData(in: visible) }
            .map { Day(date: calendar.startOfDay(for: $0.key), totals: $0.value) }
            .sorted { $0.date < $1.date }
        guard !logged.isEmpty else { return nil }

        let total = logged.reduce(MacroTotals.zero) { $0 + $1.totals }
        return MacroSummary(
            average: total / Double(logged.count),
            total: total,
            loggedDays: logged.count,
            days: logged
        )
    }
}
