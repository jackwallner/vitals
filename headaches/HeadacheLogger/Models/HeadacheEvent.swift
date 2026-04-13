import Foundation
import SwiftData

enum CaptureStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case complete
    case partial
    case failed
}

enum CaptureSourceStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case captured
    case unavailable
    case failed
}

enum PartOfDay: String, Codable, CaseIterable, Sendable {
    case overnight
    case morning
    case afternoon
    case evening

    static func from(_ date: Date, calendar: Calendar = .current) -> PartOfDay {
        switch calendar.component(.hour, from: date) {
        case 0..<6: .overnight
        case 6..<12: .morning
        case 12..<17: .afternoon
        default: .evening
        }
    }
}

enum PressureTrend: String, Codable, CaseIterable, Sendable {
    case rising
    case falling
    case steady
    case unavailable
}

struct HealthSnapshot: Sendable {
    var stepsToday: Int? = nil
    var activeEnergyKcalToday: Double? = nil
    var distanceWalkingRunningKmToday: Double? = nil
    var exerciseMinutesToday: Double? = nil
    var sleepHoursLastNight: Double? = nil
    /// End time of the longest merged asleep block in the sleep query window (proxy for last wake from main sleep).
    var lastMainSleepWakeTime: Date? = nil
    /// Hours from `lastMainSleepWakeTime` to the event timestamp when wake is known.
    var hoursSinceMainSleepWake: Double? = nil
    var restingHeartRateBpm: Double? = nil
    var recentHeartRateAverageBpm: Double? = nil
    var hrvSDNNMs: Double? = nil
    var respiratoryRateBrpm: Double? = nil
    var workoutsLast24h: Int? = nil
    var workoutMinutesLast24h: Double? = nil
    /// Average environmental sound level (A-weighted dB) over the 6 hours before capture, when available.
    var environmentalAudioExposureDbA: Double? = nil
    /// Blood oxygen saturation as percent (0–100) when available.
    var oxygenSaturationPercent: Double? = nil
    var vo2MaxMlPerKgPerMin: Double? = nil
    var walkingSpeedMetersPerSecond: Double? = nil
    var appleStandMinutesToday: Double? = nil
    var basalEnergyKcalToday: Double? = nil
    var flightsClimbedToday: Double? = nil
    var mindfulMinutesToday: Double? = nil
    /// Change in barometric pressure (hPa) from oldest to newest sample in the 6 hours before capture (device/wearable samples).
    var barometricPressureDeltaHpa6h: Double? = nil
}

struct HealthCaptureResult: Sendable {
    var status: CaptureSourceStatus
    var message: String?
    var snapshot: HealthSnapshot?
}

struct EnvironmentSnapshot: Sendable {
    var locality: String? = nil
    var region: String? = nil
    var weatherSummary: String? = nil
    var weatherCode: Int? = nil
    var temperatureC: Double? = nil
    var apparentTemperatureC: Double? = nil
    var humidityPercent: Double? = nil
    var pressureHpa: Double? = nil
    var pressureTrend: PressureTrend = .unavailable
    var precipitationMm: Double? = nil
    var windSpeedKph: Double? = nil
    var windDirectionDegrees: Double? = nil
    var cloudCoverPercent: Double? = nil
    var uvIndex: Double? = nil
    var usAQI: Double? = nil
    var europeanAQI: Double? = nil
    var pm25: Double? = nil
    var pm10: Double? = nil
    var ozone: Double? = nil
    var nitrogenDioxide: Double? = nil
    var sulphurDioxide: Double? = nil
    var carbonMonoxide: Double? = nil
    var alderPollen: Double? = nil
    var birchPollen: Double? = nil
    var grassPollen: Double? = nil
    var mugwortPollen: Double? = nil
    var olivePollen: Double? = nil
    var ragweedPollen: Double? = nil
}

struct EnvironmentCaptureResult: Sendable {
    var status: CaptureSourceStatus
    var message: String?
    var snapshot: EnvironmentSnapshot?
}

@Model
final class HeadacheEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var createdAt: Date
    var captureCompletedAt: Date?

    var timezoneIdentifier: String
    var weekdayIndex: Int
    var weekdayName: String
    var hourOfDay: Int
    var minuteOfHour: Int
    var partOfDayRaw: String
    var captureStatusRaw: String

    var healthStatusRaw: String
    var environmentStatusRaw: String
    var healthStatusMessage: String?
    var environmentStatusMessage: String?

    var locality: String?
    var region: String?
    var weatherSummary: String?
    var weatherCode: Int?
    var temperatureC: Double?
    var apparentTemperatureC: Double?
    var humidityPercent: Double?
    var pressureHpa: Double?
    var pressureTrendRaw: String
    var precipitationMm: Double?
    var windSpeedKph: Double?
    var windDirectionDegrees: Double?
    var cloudCoverPercent: Double?
    var uvIndex: Double?
    var usAQI: Double?
    var europeanAQI: Double?
    var pm25: Double?
    var pm10: Double?
    var ozone: Double?
    var nitrogenDioxide: Double?
    var sulphurDioxide: Double?
    var carbonMonoxide: Double?
    var alderPollen: Double?
    var birchPollen: Double?
    var grassPollen: Double?
    var mugwortPollen: Double?
    var olivePollen: Double?
    var ragweedPollen: Double?

    var stepsToday: Int?
    var activeEnergyKcalToday: Double?
    var distanceWalkingRunningKmToday: Double?
    var exerciseMinutesToday: Double?
    var sleepHoursLastNight: Double?
    var restingHeartRateBpm: Double?
    var recentHeartRateAverageBpm: Double?
    var hrvSDNNMs: Double?
    var respiratoryRateBrpm: Double?
    var workoutsLast24h: Int?
    var workoutMinutesLast24h: Double?

    var lastMainSleepWakeTime: Date?
    var hoursSinceMainSleepWake: Double?
    var environmentalAudioExposureDbA: Double?
    var oxygenSaturationPercent: Double?
    var vo2MaxMlPerKgPerMin: Double?
    var walkingSpeedMetersPerSecond: Double?
    var appleStandMinutesToday: Double?
    var basalEnergyKcalToday: Double?
    var flightsClimbedToday: Double?
    var mindfulMinutesToday: Double?
    var barometricPressureDeltaHpa6h: Double?

    /// Optional notes added later from History (not collected at tap time).
    var userNotes: String?

    init(timestamp: Date = .now) {
        let calendar = Calendar.current

        self.id = UUID()
        self.timestamp = timestamp
        self.createdAt = .now
        self.captureCompletedAt = nil

        self.timezoneIdentifier = TimeZone.current.identifier
        self.weekdayIndex = calendar.component(.weekday, from: timestamp)
        self.weekdayName = Self.weekdayFormatter.string(from: timestamp)
        self.hourOfDay = calendar.component(.hour, from: timestamp)
        self.minuteOfHour = calendar.component(.minute, from: timestamp)
        self.partOfDayRaw = PartOfDay.from(timestamp, calendar: calendar).rawValue
        self.captureStatusRaw = CaptureStatus.pending.rawValue

        self.healthStatusRaw = CaptureSourceStatus.pending.rawValue
        self.environmentStatusRaw = CaptureSourceStatus.pending.rawValue
        self.healthStatusMessage = nil
        self.environmentStatusMessage = nil

        self.locality = nil
        self.region = nil
        self.weatherSummary = nil
        self.weatherCode = nil
        self.temperatureC = nil
        self.apparentTemperatureC = nil
        self.humidityPercent = nil
        self.pressureHpa = nil
        self.pressureTrendRaw = PressureTrend.unavailable.rawValue
        self.precipitationMm = nil
        self.windSpeedKph = nil
        self.windDirectionDegrees = nil
        self.cloudCoverPercent = nil
        self.uvIndex = nil
        self.usAQI = nil
        self.europeanAQI = nil
        self.pm25 = nil
        self.pm10 = nil
        self.ozone = nil
        self.nitrogenDioxide = nil
        self.sulphurDioxide = nil
        self.carbonMonoxide = nil
        self.alderPollen = nil
        self.birchPollen = nil
        self.grassPollen = nil
        self.mugwortPollen = nil
        self.olivePollen = nil
        self.ragweedPollen = nil

        self.stepsToday = nil
        self.activeEnergyKcalToday = nil
        self.distanceWalkingRunningKmToday = nil
        self.exerciseMinutesToday = nil
        self.sleepHoursLastNight = nil
        self.restingHeartRateBpm = nil
        self.recentHeartRateAverageBpm = nil
        self.hrvSDNNMs = nil
        self.respiratoryRateBrpm = nil
        self.workoutsLast24h = nil
        self.workoutMinutesLast24h = nil

        self.lastMainSleepWakeTime = nil
        self.hoursSinceMainSleepWake = nil
        self.environmentalAudioExposureDbA = nil
        self.oxygenSaturationPercent = nil
        self.vo2MaxMlPerKgPerMin = nil
        self.walkingSpeedMetersPerSecond = nil
        self.appleStandMinutesToday = nil
        self.basalEnergyKcalToday = nil
        self.flightsClimbedToday = nil
        self.mindfulMinutesToday = nil
        self.barometricPressureDeltaHpa6h = nil

        self.userNotes = nil
    }

    var partOfDay: PartOfDay {
        get { PartOfDay(rawValue: partOfDayRaw) ?? .afternoon }
        set { partOfDayRaw = newValue.rawValue }
    }

    var captureStatus: CaptureStatus {
        get { CaptureStatus(rawValue: captureStatusRaw) ?? .pending }
        set { captureStatusRaw = newValue.rawValue }
    }

    var healthStatus: CaptureSourceStatus {
        get { CaptureSourceStatus(rawValue: healthStatusRaw) ?? .pending }
        set { healthStatusRaw = newValue.rawValue }
    }

    var environmentStatus: CaptureSourceStatus {
        get { CaptureSourceStatus(rawValue: environmentStatusRaw) ?? .pending }
        set { environmentStatusRaw = newValue.rawValue }
    }

    var pressureTrend: PressureTrend {
        get { PressureTrend(rawValue: pressureTrendRaw) ?? .unavailable }
        set { pressureTrendRaw = newValue.rawValue }
    }

    var locationLabel: String {
        [locality, region]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    func apply(_ result: HealthCaptureResult) {
        healthStatus = result.status
        healthStatusMessage = result.message

        guard let snapshot = result.snapshot else { return }
        stepsToday = snapshot.stepsToday
        activeEnergyKcalToday = snapshot.activeEnergyKcalToday
        distanceWalkingRunningKmToday = snapshot.distanceWalkingRunningKmToday
        exerciseMinutesToday = snapshot.exerciseMinutesToday
        sleepHoursLastNight = snapshot.sleepHoursLastNight
        lastMainSleepWakeTime = snapshot.lastMainSleepWakeTime
        hoursSinceMainSleepWake = snapshot.hoursSinceMainSleepWake
        restingHeartRateBpm = snapshot.restingHeartRateBpm
        recentHeartRateAverageBpm = snapshot.recentHeartRateAverageBpm
        hrvSDNNMs = snapshot.hrvSDNNMs
        respiratoryRateBrpm = snapshot.respiratoryRateBrpm
        workoutsLast24h = snapshot.workoutsLast24h
        workoutMinutesLast24h = snapshot.workoutMinutesLast24h
        environmentalAudioExposureDbA = snapshot.environmentalAudioExposureDbA
        oxygenSaturationPercent = snapshot.oxygenSaturationPercent
        vo2MaxMlPerKgPerMin = snapshot.vo2MaxMlPerKgPerMin
        walkingSpeedMetersPerSecond = snapshot.walkingSpeedMetersPerSecond
        appleStandMinutesToday = snapshot.appleStandMinutesToday
        basalEnergyKcalToday = snapshot.basalEnergyKcalToday
        flightsClimbedToday = snapshot.flightsClimbedToday
        mindfulMinutesToday = snapshot.mindfulMinutesToday
        barometricPressureDeltaHpa6h = snapshot.barometricPressureDeltaHpa6h
    }

    func apply(_ result: EnvironmentCaptureResult) {
        environmentStatus = result.status
        environmentStatusMessage = result.message

        guard let snapshot = result.snapshot else { return }
        locality = snapshot.locality
        region = snapshot.region
        weatherSummary = snapshot.weatherSummary
        weatherCode = snapshot.weatherCode
        temperatureC = snapshot.temperatureC
        apparentTemperatureC = snapshot.apparentTemperatureC
        humidityPercent = snapshot.humidityPercent
        pressureHpa = snapshot.pressureHpa
        pressureTrend = snapshot.pressureTrend
        precipitationMm = snapshot.precipitationMm
        windSpeedKph = snapshot.windSpeedKph
        windDirectionDegrees = snapshot.windDirectionDegrees
        cloudCoverPercent = snapshot.cloudCoverPercent
        uvIndex = snapshot.uvIndex
        usAQI = snapshot.usAQI
        europeanAQI = snapshot.europeanAQI
        pm25 = snapshot.pm25
        pm10 = snapshot.pm10
        ozone = snapshot.ozone
        nitrogenDioxide = snapshot.nitrogenDioxide
        sulphurDioxide = snapshot.sulphurDioxide
        carbonMonoxide = snapshot.carbonMonoxide
        alderPollen = snapshot.alderPollen
        birchPollen = snapshot.birchPollen
        grassPollen = snapshot.grassPollen
        mugwortPollen = snapshot.mugwortPollen
        olivePollen = snapshot.olivePollen
        ragweedPollen = snapshot.ragweedPollen
    }

    func finalizeCapture() {
        captureCompletedAt = .now

        switch (healthStatus, environmentStatus) {
        case (.captured, .captured):
            captureStatus = .complete
        case (.failed, .failed),
             (.failed, .unavailable),
             (.unavailable, .failed):
            captureStatus = .failed
        case (.unavailable, .unavailable):
            // e.g. widget / offline log with no Health or weather in that process
            captureStatus = .partial
        case (.pending, _), (_, .pending):
            captureStatus = .pending
        default:
            captureStatus = .partial
        }
    }
}

private extension HeadacheEvent {
    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}
