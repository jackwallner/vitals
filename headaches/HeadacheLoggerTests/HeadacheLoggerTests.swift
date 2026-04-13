import XCTest
@testable import HeadacheLogger

final class HeadacheLoggerTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        HeadacheAppGroup.userDefaults.set(true, forKey: HeadacheStorageKey.hasCompletedOnboarding.rawValue)
    }

    func testPartOfDayMapping() {
        let calendar = Calendar(identifier: .gregorian)

        let overnight = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 2))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 8))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 14))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 20))!

        XCTAssertEqual(PartOfDay.from(overnight, calendar: calendar), .overnight)
        XCTAssertEqual(PartOfDay.from(morning, calendar: calendar), .morning)
        XCTAssertEqual(PartOfDay.from(afternoon, calendar: calendar), .afternoon)
        XCTAssertEqual(PartOfDay.from(evening, calendar: calendar), .evening)
    }

    func testFinalizeCaptureMarksCompleteWhenBothSourcesCaptured() {
        let event = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_744_406_400))

        event.apply(
            HealthCaptureResult(
                status: .captured,
                message: nil,
                snapshot: HealthSnapshot(stepsToday: 1200, activeEnergyKcalToday: 340)
            )
        )
        event.apply(
            EnvironmentCaptureResult(
                status: .captured,
                message: nil,
                snapshot: EnvironmentSnapshot(
                    locality: "Austin",
                    region: "TX",
                    weatherSummary: "Cloudy",
                    weatherCode: 3,
                    temperatureC: 22,
                    apparentTemperatureC: 24,
                    humidityPercent: 52,
                    pressureHpa: 1013,
                    pressureTrend: .steady,
                    precipitationMm: 0,
                    windSpeedKph: 8,
                    windDirectionDegrees: 180,
                    cloudCoverPercent: 75,
                    uvIndex: 3,
                    usAQI: 32,
                    europeanAQI: 18,
                    pm25: 4,
                    pm10: 8,
                    ozone: 80,
                    nitrogenDioxide: 12,
                    sulphurDioxide: 1,
                    carbonMonoxide: 200,
                    alderPollen: nil,
                    birchPollen: nil,
                    grassPollen: nil,
                    mugwortPollen: nil,
                    olivePollen: nil,
                    ragweedPollen: nil
                )
            )
        )

        event.finalizeCapture()

        XCTAssertEqual(event.captureStatus, .complete)
        XCTAssertEqual(event.healthStatus, .captured)
        XCTAssertEqual(event.environmentStatus, .captured)
    }

    func testFinalizeCaptureMarksPartialWhenOnlyOneSourceAvailable() {
        let event = HeadacheEvent()
        event.healthStatus = .captured
        event.environmentStatus = .unavailable

        event.finalizeCapture()

        XCTAssertEqual(event.captureStatus, .partial)
    }

    func testFinalizeCaptureMarksPartialWhenBothSourcesUnavailable() {
        let event = HeadacheEvent()
        event.apply(HealthCaptureResult(status: .unavailable, message: nil, snapshot: nil))
        event.apply(EnvironmentCaptureResult(status: .unavailable, message: nil, snapshot: nil))

        event.finalizeCapture()

        XCTAssertEqual(event.captureStatus, .partial)
    }

    func testSleepIntervalMergeCombinesCloseSegments() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = SleepIntervalMerge.Interval(start: t0, end: t0.addingTimeInterval(3600))
        let b = SleepIntervalMerge.Interval(
            start: t0.addingTimeInterval(3600 + 30 * 60),
            end: t0.addingTimeInterval(7200)
        )
        let merged = SleepIntervalMerge.merge([a, b], mergeGap: 45 * 60)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].duration, 7200, accuracy: 0.001)
    }

    func testWakeTimeAfterLongestSleep() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let shortSleep = SleepIntervalMerge.Interval(start: t0, end: t0.addingTimeInterval(1800))
        let longSleep = SleepIntervalMerge.Interval(start: t0.addingTimeInterval(10_000), end: t0.addingTimeInterval(10_000 + 28_800))
        let merged = SleepIntervalMerge.merge([shortSleep, longSleep], mergeGap: 60)
        let wake = SleepIntervalMerge.wakeTimeAfterLongestSleep(merged)
        XCTAssertEqual(wake, longSleep.end)
    }

    func testCSVExportIncludesImportantColumnsAndValues() throws {
        let event = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_744_406_400))
        event.locality = "Austin"
        event.region = "TX"
        event.weatherSummary = "Rain"
        event.temperatureC = 19.5
        event.stepsToday = 3456
        event.sleepHoursLastNight = 6.75
        event.lastMainSleepWakeTime = Date(timeIntervalSince1970: 1_744_400_000)
        event.hoursSinceMainSleepWake = 1.78
        event.vo2MaxMlPerKgPerMin = 44.2
        event.barometricPressureDeltaHpa6h = -1.2
        event.usAQI = 41
        event.captureStatus = .partial
        event.healthStatus = .captured
        event.environmentStatus = .failed
        event.healthStatusMessage = "Heart data unavailable"
        event.environmentStatusMessage = "Pollen unavailable"
        event.userNotes = "Saw aura first"

        let url = try ExportService.exportCSV(events: [event])
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(csv.contains("# Headache Logger"))
        XCTAssertTrue(csv.contains("# row_count: 1"))
        XCTAssertTrue(csv.contains("event_id,timestamp,timezone"))
        XCTAssertTrue(csv.contains(",user_notes"))
        XCTAssertTrue(csv.contains("last_main_sleep_wake_utc"))
        XCTAssertTrue(csv.contains("barometric_pressure_delta_hpa_6h"))
        XCTAssertTrue(csv.contains("\"44.2\""))
        XCTAssertTrue(csv.contains("\"-1.2\""))
        XCTAssertTrue(csv.contains("\"Austin, TX\""))
        XCTAssertTrue(csv.contains("\"Rain\""))
        XCTAssertTrue(csv.contains("\"3456\""))
        XCTAssertTrue(csv.contains("\"6.75\""))
        XCTAssertTrue(csv.contains("\"Heart data unavailable\""))
        XCTAssertTrue(csv.contains("\"Pollen unavailable\""))
        XCTAssertTrue(csv.contains("\"Saw aura first\""))
    }
}
