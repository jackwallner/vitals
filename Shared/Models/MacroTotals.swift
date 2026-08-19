import Foundation

/// The three macronutrients Vitals reads from Apple Health. Food apps
/// (MyFitnessPal, Cronometer, Lose It) write these alongside dietary energy, so
/// a user who already logs meals gets macros with no extra work.
enum MacroKind: String, CaseIterable, Sendable, Identifiable {
    case protein
    case carbs
    case fat

    var id: String { rawValue }

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
        protein > 0 || carbs > 0 || fat > 0
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
    /// Best protein day in the window, the macro people actually chase.
    let bestProteinDate: Date?
    let bestProtein: Double

    static func make(macrosByDay: [Date: MacroTotals], calendar: Calendar = .current) -> MacroSummary? {
        let logged = macrosByDay
            .filter { $0.value.hasData }
            .map { (date: calendar.startOfDay(for: $0.key), totals: $0.value) }
            .sorted { $0.date < $1.date }
        guard !logged.isEmpty else { return nil }

        let total = logged.reduce(MacroTotals.zero) { $0 + $1.totals }
        let best = logged.max { $0.totals.protein < $1.totals.protein }
        return MacroSummary(
            average: total / Double(logged.count),
            total: total,
            loggedDays: logged.count,
            bestProteinDate: best?.date,
            bestProtein: best?.totals.protein ?? 0
        )
    }
}
