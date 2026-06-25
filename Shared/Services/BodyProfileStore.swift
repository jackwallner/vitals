import Foundation
import Combine
import os

private let bodyProfileLogger = Logger(subsystem: "com.jackwallner.vitals", category: "BodyProfile")

/// Persists manually-entered body measurements and the user's preferred data
/// source in the App Group `UserDefaults`. Kept separate from `GoalSettings` so
/// goals/appearance don't become a catch-all for body measurements.
///
/// Manual values are stored locally only (never written to Apple Health, never
/// added to SwiftData `DailyHealthRecord` — BMI is a latest/profile value, not a
/// daily cache metric).
@MainActor
final class BodyProfileStore: ObservableObject {
    static let shared = BodyProfileStore()

    private enum Keys {
        static let manualHeight = "bodyProfile.manualHeightMeters"
        static let manualWeight = "bodyProfile.manualWeightKilograms"
        static let manualBodyFat = "bodyProfile.manualBodyFatPercent"
        static let preferredSource = "bodyProfile.preferredSource"
        static let unitSystem = "bodyProfile.unitSystem"
    }

    private let defaults: UserDefaults

    @Published var manualHeightMeters: Double? {
        didSet { persist(manualHeightMeters, forKey: Keys.manualHeight) }
    }

    @Published var manualWeightKilograms: Double? {
        didSet { persist(manualWeightKilograms, forKey: Keys.manualWeight) }
    }

    @Published var manualBodyFatPercent: Double? {
        didSet { persist(manualBodyFatPercent, forKey: Keys.manualBodyFat) }
    }

    @Published var preferredSource: BodyProfileSource {
        didSet { defaults.set(preferredSource.rawValue, forKey: Keys.preferredSource) }
    }

    @Published var unitSystem: BodyProfileUnitSystem {
        didSet { defaults.set(unitSystem.rawValue, forKey: Keys.unitSystem) }
    }

    private init() {
        let defaults = UserDefaults(suiteName: DataService.appGroupID) ?? .standard
        self.defaults = defaults

        self.manualHeightMeters = Self.readOptionalDouble(defaults, key: Keys.manualHeight)
        self.manualWeightKilograms = Self.readOptionalDouble(defaults, key: Keys.manualWeight)
        self.manualBodyFatPercent = Self.readOptionalDouble(defaults, key: Keys.manualBodyFat)

        if let raw = defaults.string(forKey: Keys.preferredSource),
           let source = BodyProfileSource(rawValue: raw) {
            self.preferredSource = source
        } else {
            // Default to Apple Health: most users have height/weight there, and
            // resolution falls back to manual when it's missing.
            self.preferredSource = .appleHealth
        }

        if let raw = defaults.string(forKey: Keys.unitSystem),
           let system = BodyProfileUnitSystem(rawValue: raw) {
            self.unitSystem = system
        } else {
            self.unitSystem = .automatic
        }
    }

    // MARK: - Derived state

    var manual: ManualBodyProfile {
        ManualBodyProfile(
            heightMeters: manualHeightMeters,
            weightKilograms: manualWeightKilograms,
            bodyFatPercent: manualBodyFatPercent
        )
    }

    /// Resolve which metrics to display by combining stored manual values with a
    /// freshly-fetched Health snapshot and the user's preferred source.
    func resolved(health: HealthBodyProfile) -> ResolvedBodyProfile {
        BodyProfileResolver.resolve(preferred: preferredSource, health: health, manual: manual)
    }

    /// The effective unit system, resolving `.automatic` from the device locale.
    var effectiveUnitSystem: BodyProfileUnitSystem {
        switch unitSystem {
        case .automatic:
            return Locale.current.measurementSystem == .metric ? .metric : .us
        case .us, .metric:
            return unitSystem
        }
    }

    // MARK: - Mutation helpers (validate before storing)

    /// Store a manual height in meters, rejecting out-of-range/non-finite values.
    @discardableResult
    func setManualHeight(meters: Double?) -> Bool {
        guard let meters else { manualHeightMeters = nil; return true }
        guard BodyProfileCalculator.isValidHeight(meters: meters) else {
            bodyProfileLogger.error("Rejected manual height meters=\(meters, privacy: .public) (out of range)")
            return false
        }
        manualHeightMeters = meters
        return true
    }

    @discardableResult
    func setManualWeight(kilograms: Double?) -> Bool {
        guard let kilograms else { manualWeightKilograms = nil; return true }
        guard BodyProfileCalculator.isValidWeight(kilograms: kilograms) else {
            bodyProfileLogger.error("Rejected manual weight kg=\(kilograms, privacy: .public) (out of range)")
            return false
        }
        manualWeightKilograms = kilograms
        return true
    }

    @discardableResult
    func setManualBodyFat(percent: Double?) -> Bool {
        guard let percent else { manualBodyFatPercent = nil; return true }
        guard BodyProfileCalculator.isValidBodyFat(percent: percent) else {
            bodyProfileLogger.error("Rejected manual body fat percent=\(percent, privacy: .public) (out of range)")
            return false
        }
        manualBodyFatPercent = percent
        return true
    }

    // MARK: - Private

    private func persist(_ value: Double?, forKey key: String) {
        if let value, value.isFinite {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func readOptionalDouble(_ defaults: UserDefaults, key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.double(forKey: key)
        return value.isFinite && value > 0 ? value : nil
    }
}
