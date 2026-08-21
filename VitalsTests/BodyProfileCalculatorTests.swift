import XCTest

final class BodyProfileCalculatorTests: XCTestCase {
    // MARK: - BMI formula

    func testBMIFormula() {
        // 1.80 m, 81 kg → 81 / 3.24 = 25.0
        let bmi = try? XCTUnwrap(BodyProfileCalculator.bmi(heightMeters: 1.80, weightKilograms: 81.0))
        XCTAssertEqual(try XCTUnwrap(bmi), 25.0, accuracy: 0.05)
    }

    func testBMINilForInvalidInputs() {
        XCTAssertNil(BodyProfileCalculator.bmi(heightMeters: 0, weightKilograms: 70))
        XCTAssertNil(BodyProfileCalculator.bmi(heightMeters: 1.7, weightKilograms: 0))
        XCTAssertNil(BodyProfileCalculator.bmi(heightMeters: .nan, weightKilograms: 70))
        XCTAssertNil(BodyProfileCalculator.bmi(heightMeters: 1.7, weightKilograms: .infinity))
    }

    // MARK: - Formatting

    func testFormattedBMIOneDecimal() {
        XCTAssertEqual(BodyProfileCalculator.formattedBMI(23.456), "23.5")
        XCTAssertEqual(BodyProfileCalculator.formattedBMI(nil), "—")
        XCTAssertEqual(BodyProfileCalculator.formattedBMI(.nan), "—")
    }

    // MARK: - Category boundaries

    func testCategoryBoundaries() {
        XCTAssertEqual(BMICategory.from(bmi: 18.49), .underweight)
        XCTAssertEqual(BMICategory.from(bmi: 18.5), .healthy)
        XCTAssertEqual(BMICategory.from(bmi: 24.99), .healthy)
        XCTAssertEqual(BMICategory.from(bmi: 25.0), .overweight)
        XCTAssertEqual(BMICategory.from(bmi: 29.99), .overweight)
        XCTAssertEqual(BMICategory.from(bmi: 30.0), .obesity)
    }

    // MARK: - Unit conversions

    func testFeetInchesToMeters() {
        // 5 ft 11 in = 71 in * 0.0254 = 1.8034 m
        XCTAssertEqual(BodyProfileCalculator.meters(feet: 5, inches: 11), 1.8034, accuracy: 0.0001)
    }

    func testCentimetersToMeters() {
        XCTAssertEqual(BodyProfileCalculator.meters(centimeters: 180), 1.80, accuracy: 0.0001)
    }

    func testPoundsToKilograms() {
        XCTAssertEqual(BodyProfileCalculator.kilograms(pounds: 154), 69.85, accuracy: 0.02)
    }

    func testDecimalParsingSupportsDotAndComma() {
        XCTAssertEqual(BodyProfileCalculator.parseDecimal("1.75"), 1.75)
        XCTAssertEqual(BodyProfileCalculator.parseDecimal("1,75"), 1.75)
        XCTAssertNil(BodyProfileCalculator.parseDecimal(""))
    }

    func testMetersToFeetInchesRoundTrip() {
        let (feet, inches) = BodyProfileCalculator.feetInches(fromMeters: 1.8034)
        XCTAssertEqual(feet, 5)
        XCTAssertEqual(inches, 11)
    }

    func testFeetInchesRollsOverAt12() {
        // 1.9558 m ≈ 77 in → 6 ft 5 in, never "5 ft 12 in".
        let (feet, inches) = BodyProfileCalculator.feetInches(fromMeters: 1.9558)
        XCTAssertEqual(feet, 6)
        XCTAssertEqual(inches, 5)
    }

    // MARK: - Validation

    func testValidationRanges() {
        XCTAssertFalse(BodyProfileCalculator.isValidHeight(meters: 0.5))
        XCTAssertTrue(BodyProfileCalculator.isValidHeight(meters: 1.75))
        XCTAssertFalse(BodyProfileCalculator.isValidHeight(meters: 3.0))

        XCTAssertFalse(BodyProfileCalculator.isValidWeight(kilograms: 10))
        XCTAssertTrue(BodyProfileCalculator.isValidWeight(kilograms: 80))
        XCTAssertFalse(BodyProfileCalculator.isValidWeight(kilograms: 500))

        XCTAssertFalse(BodyProfileCalculator.isValidBodyFat(percent: 1))
        XCTAssertTrue(BodyProfileCalculator.isValidBodyFat(percent: 20))
        XCTAssertFalse(BodyProfileCalculator.isValidBodyFat(percent: 90))
        XCTAssertFalse(BodyProfileCalculator.isValidBodyFat(percent: .nan))
    }

    // MARK: - Source resolution

    func testResolvePrefersAppleHealthWhenComplete() {
        let health = HealthBodyProfile(heightMeters: 1.80, weightKilograms: 80, bodyFatPercent: 18)
        let manual = ManualBodyProfile(heightMeters: 1.70, weightKilograms: 70, bodyFatPercent: nil)
        let resolved = BodyProfileResolver.resolve(preferred: .appleHealth, health: health, manual: manual)
        XCTAssertEqual(resolved.source, .appleHealth)
        XCTAssertEqual(resolved.heightMeters, 1.80)
        XCTAssertEqual(resolved.weightKilograms, 80)
        XCTAssertEqual(resolved.bodyFatPercent, 18)
    }

    func testResolveFallsBackToManualWhenHealthMissing() {
        let health = HealthBodyProfile(heightMeters: nil, weightKilograms: nil, bodyFatPercent: nil)
        let manual = ManualBodyProfile(heightMeters: 1.70, weightKilograms: 70, bodyFatPercent: nil)
        let resolved = BodyProfileResolver.resolve(preferred: .appleHealth, health: health, manual: manual)
        XCTAssertEqual(resolved.source, .manual)
        XCTAssertEqual(resolved.heightMeters, 1.70)
        XCTAssertEqual(resolved.weightKilograms, 70)
    }

    func testResolveCombinesManualFallbackWithPartialHealth() {
        let health = HealthBodyProfile(heightMeters: 1.80, weightKilograms: nil, bodyFatPercent: nil)
        let manual = ManualBodyProfile(heightMeters: nil, weightKilograms: 80, bodyFatPercent: nil)
        let resolved = BodyProfileResolver.resolve(preferred: .appleHealth, health: health, manual: manual)

        XCTAssertEqual(resolved.source, .manual)
        XCTAssertEqual(resolved.heightMeters, 1.80)
        XCTAssertEqual(resolved.weightKilograms, 80)
        XCTAssertNotNil(resolved.bmi)
    }

    func testResolveManualPreferredUsesManual() {
        let health = HealthBodyProfile(heightMeters: 1.80, weightKilograms: 80, bodyFatPercent: 18)
        let manual = ManualBodyProfile(heightMeters: 1.70, weightKilograms: 70, bodyFatPercent: nil)
        let resolved = BodyProfileResolver.resolve(preferred: .manual, health: health, manual: manual)
        XCTAssertEqual(resolved.source, .manual)
        XCTAssertEqual(resolved.heightMeters, 1.70)
        XCTAssertEqual(resolved.weightKilograms, 70)
        // Body fat absent in manual falls back to health so a Pro user still sees it.
        XCTAssertEqual(resolved.bodyFatPercent, 18)
    }

    func testResolveManualPreferredDoesNotUseHealthHeightOrWeight() {
        let health = HealthBodyProfile(heightMeters: 1.80, weightKilograms: 80, bodyFatPercent: 18)
        let resolved = BodyProfileResolver.resolve(
            preferred: .manual,
            health: health,
            manual: .empty
        )

        XCTAssertEqual(resolved.source, .manual)
        XCTAssertNil(resolved.heightMeters)
        XCTAssertNil(resolved.weightKilograms)
        XCTAssertNil(resolved.bmi)
        XCTAssertEqual(resolved.bodyFatPercent, 18)
    }

    func testResolvedBMIComputed() {
        let health = HealthBodyProfile(heightMeters: 1.80, weightKilograms: 81, bodyFatPercent: nil)
        let resolved = BodyProfileResolver.resolve(preferred: .appleHealth, health: health, manual: .empty)
        XCTAssertEqual(try XCTUnwrap(resolved.bmi), 25.0, accuracy: 0.05)
        XCTAssertEqual(resolved.category, .overweight)
    }
}
