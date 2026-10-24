import XCTest

#if DEBUG
/// Capture runs read every HealthKit figure from these fixtures, so History's
/// deficit tiles are only as honest as the food the fixtures log.
final class ScreenshotFixturesTests: XCTestCase {
    private let end = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 16))!

    func testFoodIsLoggedEveryDayTheMacrosAre() {
        let food = ScreenshotFixtures.dietaryHistory(days: 30, end: end)
        let macros = ScreenshotFixtures.macroHistory(days: 30, end: end)
        XCTAssertEqual(food.map(\.date), macros.map(\.date))
        for (eaten, logged) in zip(food, macros) {
            XCTAssertGreaterThanOrEqual(eaten.foodCalories, logged.macros.calories)
            XCTAssertLessThan(eaten.foodCalories - logged.macros.calories, 150)
        }
    }

    /// The rejected capture showed AVG DEFICIT equal to AVG CALORIES because
    /// no food was logged. Burned minus eaten must be a modest, positive gap.
    func testMonthDeficitIsBurnedMinusEatenAndPositive() {
        let burned = ScreenshotFixtures.history(days: 30, end: end).map { $0.active + $0.resting }
        let eaten = ScreenshotFixtures.dietaryHistory(days: 30, end: end).map(\.foodCalories)
        XCTAssertEqual(burned.count, eaten.count)
        let avgBurned = burned.reduce(0, +) / Double(burned.count)
        let avgDeficit = zip(burned, eaten).map { $0 - $1 }.reduce(0, +) / Double(burned.count)
        XCTAssertGreaterThan(avgDeficit, 0)
        XCTAssertLessThan(avgDeficit, avgBurned / 4)
    }

    func testDayCountIsInclusive() {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: end)!
        XCTAssertEqual(ScreenshotFixtures.dayCount(from: start, to: end), 7)
        XCTAssertEqual(ScreenshotFixtures.dayCount(from: end, to: end), 1)
    }

    /// Body Profile is captured filled in: a complete Health profile with a
    /// BMI in the healthy range, and no body fat for free users.
    func testBodyProfileIsCompleteAndHealthy() {
        let profile = ScreenshotFixtures.bodyProfile(includeBodyFat: true)
        XCTAssertTrue(profile.hasHeightAndWeight)
        let bmi = profile.weightKilograms! / (profile.heightMeters! * profile.heightMeters!)
        XCTAssertTrue((18.5..<25).contains(bmi), "BMI \(bmi)")
        XCTAssertNotNil(profile.bodyFatPercent)
        XCTAssertNil(ScreenshotFixtures.bodyProfile(includeBodyFat: false).bodyFatPercent)
    }
}
#endif
