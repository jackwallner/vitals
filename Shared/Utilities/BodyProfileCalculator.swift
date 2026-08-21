import Foundation

/// Adult BMI categories for display. Thresholds follow the standard WHO adult
/// ranges. This is a simple height/weight reference, not a diagnosis.
enum BMICategory: String, CaseIterable, Sendable {
    case underweight
    case healthy
    case overweight
    case obesity

    var label: String {
        switch self {
        case .underweight: "Underweight"
        case .healthy: "Healthy"
        case .overweight: "Overweight"
        case .obesity: "Obesity"
        }
    }

    /// Classify a finite BMI value. Non-finite inputs fall back to `.healthy`
    /// but callers should guard with `BodyProfileCalculator.bmi` which returns
    /// nil for invalid inputs, so this is only reached with a real number.
    static func from(bmi: Double) -> BMICategory {
        switch bmi {
        case ..<18.5: .underweight
        case 18.5..<25: .healthy
        case 25..<30: .overweight
        default: .obesity
        }
    }
}

/// Pure BMI math, unit conversions, validation, and formatting. No HealthKit,
/// no storage — kept dependency-free so it can be unit-tested in isolation
/// (it's compiled into the VitalsTests target directly).
enum BodyProfileCalculator {
    // MARK: - Validation ranges (metric, normalized storage units)

    /// ~3 ft to ~8 ft 2 in.
    static let heightMetersRange: ClosedRange<Double> = 0.9...2.5
    /// ~55 lb to ~772 lb.
    static let weightKilogramsRange: ClosedRange<Double> = 25...350
    static let bodyFatPercentRange: ClosedRange<Double> = 2...75

    // MARK: - Conversions

    static let metersPerInch = 0.0254
    static let inchesPerFoot = 12.0
    static let kilogramsPerPound = 0.45359237

    static func meters(feet: Double, inches: Double) -> Double {
        (feet * inchesPerFoot + inches) * metersPerInch
    }

    static func meters(centimeters: Double) -> Double {
        centimeters / 100.0
    }

    static func kilograms(pounds: Double) -> Double {
        pounds * kilogramsPerPound
    }

    /// Parses decimal input from the device locale, with a comma fallback for
    /// pasted values on devices that use a dot decimal separator.
    static func parseDecimal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed) { return value }

        let separator = Locale.current.decimalSeparator ?? "."
        var normalized = trimmed
        if separator != "." {
            normalized = normalized.replacingOccurrences(of: separator, with: ".")
        } else if !normalized.contains(".") {
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        }
        return Double(normalized)
    }

    /// Returns (feet, inches) for a height in meters, inches rounded to nearest.
    static func feetInches(fromMeters meters: Double) -> (feet: Int, inches: Int) {
        let totalInches = (meters / metersPerInch).rounded()
        var feet = Int(totalInches) / 12
        var inches = Int(totalInches) % 12
        if inches == 12 { feet += 1; inches = 0 }
        return (feet, inches)
    }

    static func pounds(fromKilograms kilograms: Double) -> Double {
        kilograms / kilogramsPerPound
    }

    static func centimeters(fromMeters meters: Double) -> Double {
        meters * 100.0
    }

    // MARK: - Validation

    static func isValidHeight(meters: Double) -> Bool {
        meters.isFinite && heightMetersRange.contains(meters)
    }

    static func isValidWeight(kilograms: Double) -> Bool {
        kilograms.isFinite && weightKilogramsRange.contains(kilograms)
    }

    static func isValidBodyFat(percent: Double) -> Bool {
        percent.isFinite && bodyFatPercentRange.contains(percent)
    }

    // MARK: - BMI

    /// BMI = kg / m². Returns nil unless both inputs are valid and finite, so a
    /// caller can treat nil as "not enough valid data to show a number."
    static func bmi(heightMeters: Double, weightKilograms: Double) -> Double? {
        guard isValidHeight(meters: heightMeters),
              isValidWeight(kilograms: weightKilograms) else { return nil }
        let value = weightKilograms / (heightMeters * heightMeters)
        guard value.isFinite else { return nil }
        return value
    }

    static func category(heightMeters: Double, weightKilograms: Double) -> BMICategory? {
        guard let value = bmi(heightMeters: heightMeters, weightKilograms: weightKilograms) else { return nil }
        return BMICategory.from(bmi: value)
    }

    // MARK: - Formatting

    /// One-decimal BMI string, e.g. "23.4". Returns "—" for nil so the UI has a
    /// stable placeholder.
    static func formattedBMI(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f", value)
    }

    static func formattedBodyFat(_ percent: Double?) -> String {
        guard let percent, percent.isFinite else { return "—" }
        return String(format: "%.1f%%", percent)
    }
}
