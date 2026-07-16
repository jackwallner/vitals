import Foundation

/// Stable energy reference figures averaged over recent completed days.
/// `tdee` = average full-day total burn (active + resting) ≈ maintenance calories.
/// `bmr`  = average full-day resting burn ≈ basal metabolic rate.
/// Both nil until `sampleDays` clears the minimum.
struct EnergyAveragesResult: Sendable, Equatable {
    let tdee: Double?
    let bmr: Double?
    let sampleDays: Int
}

/// Single source of truth for the TDEE/BMR averages. The app feeds it live
/// HealthKit history; the widget feeds it cached SwiftData rows. Keeping the
/// math here means both surfaces always report the same number.
enum EnergyAveragesCalculator {
    /// - Parameters:
    ///   - records: daily `(date, active, resting)` samples in any order.
    ///   - referenceDate: "now"; days on/after its start are treated as partial
    ///     and excluded. Days with 0 resting energy are dropped as non-wear so a
    ///     few watch-off days can't drag the figure down.
    ///   - minSamples: minimum valid days before a figure is returned.
    static func compute(
        records: [(date: Date, active: Double, resting: Double)],
        referenceDate: Date,
        minSamples: Int = 7
    ) -> EnergyAveragesResult {
        let today = DateHelpers.startOfDay(referenceDate)
        let valid = records.filter { DateHelpers.startOfDay($0.date) < today && $0.resting > 0 }
        guard valid.count >= minSamples else {
            return EnergyAveragesResult(tdee: nil, bmr: nil, sampleDays: valid.count)
        }
        let count = Double(valid.count)
        let bmr = valid.reduce(0.0) { $0 + $1.resting } / count
        let tdee = valid.reduce(0.0) { $0 + $1.active + $1.resting } / count
        return EnergyAveragesResult(tdee: tdee, bmr: bmr, sampleDays: valid.count)
    }
}
