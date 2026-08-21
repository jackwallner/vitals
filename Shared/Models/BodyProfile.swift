import Foundation

/// Where the displayed height/weight/body-fat values came from.
enum BodyProfileSource: String, CaseIterable, Sendable {
    case appleHealth
    case manual

    var label: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .manual: "Manual"
        }
    }
}

/// Unit system for manual entry + display. `automatic` resolves from the
/// device locale at render time.
enum BodyProfileUnitSystem: String, CaseIterable, Sendable {
    case automatic
    case us
    case metric

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .us: "US"
        case .metric: "Metric"
        }
    }
}

/// Raw measurements fetched from Apple Health (any field may be missing). All
/// values are normalized to metric storage units (meters, kilograms, percent).
struct HealthBodyProfile: Sendable, Equatable {
    var heightMeters: Double?
    var weightKilograms: Double?
    var bodyFatPercent: Double?

    static let empty = HealthBodyProfile(heightMeters: nil, weightKilograms: nil, bodyFatPercent: nil)

    var hasHeightAndWeight: Bool {
        heightMeters != nil && weightKilograms != nil
    }
}

/// Manually entered measurements (metric storage units). Any field may be unset.
struct ManualBodyProfile: Sendable, Equatable {
    var heightMeters: Double?
    var weightKilograms: Double?
    var bodyFatPercent: Double?

    static let empty = ManualBodyProfile(heightMeters: nil, weightKilograms: nil, bodyFatPercent: nil)

    var hasHeightAndWeight: Bool {
        heightMeters != nil && weightKilograms != nil
    }
}

/// The resolved metrics actually shown to the user, with the source that won.
struct ResolvedBodyProfile: Sendable, Equatable {
    var heightMeters: Double?
    var weightKilograms: Double?
    var bodyFatPercent: Double?
    var source: BodyProfileSource

    var bmi: Double? {
        guard let heightMeters, let weightKilograms else { return nil }
        return BodyProfileCalculator.bmi(heightMeters: heightMeters, weightKilograms: weightKilograms)
    }

    var category: BMICategory? {
        bmi.map(BMICategory.from(bmi:))
    }
}

/// Pure resolution of which measurements to display, given the user's preferred
/// source and the data available from each. Kept dependency-free so it can be
/// unit-tested alongside the calculator.
///
/// Rules (see 625plan.md §6.3):
/// - Preferred Apple Health: use Health when it has a complete height+weight
///   pair; otherwise fall back to manual so the feature still works.
/// - Preferred Manual: use manual values directly.
/// - Body fat is filled in from the resolved source first, then the other
///   source as a fallback (so a Pro user who only has body-fat in Health still
///   sees it even when entering height/weight manually).
enum BodyProfileResolver {
    static func resolve(
        preferred: BodyProfileSource,
        health: HealthBodyProfile,
        manual: ManualBodyProfile
    ) -> ResolvedBodyProfile {
        switch preferred {
        case .appleHealth:
            if health.hasHeightAndWeight {
                return ResolvedBodyProfile(
                    heightMeters: health.heightMeters,
                    weightKilograms: health.weightKilograms,
                    bodyFatPercent: health.bodyFatPercent ?? manual.bodyFatPercent,
                    source: .appleHealth
                )
            }
            // Health incomplete — fall back to manual so BMI can still render.
            return ResolvedBodyProfile(
                heightMeters: manual.heightMeters ?? health.heightMeters,
                weightKilograms: manual.weightKilograms ?? health.weightKilograms,
                bodyFatPercent: manual.bodyFatPercent ?? health.bodyFatPercent,
                source: .manual
            )
        case .manual:
            return ResolvedBodyProfile(
                heightMeters: manual.heightMeters,
                weightKilograms: manual.weightKilograms,
                bodyFatPercent: manual.bodyFatPercent ?? health.bodyFatPercent,
                source: .manual
            )
        }
    }
}
