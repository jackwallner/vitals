import Foundation

enum ExportService {
    static func exportCSV(events: [HeadacheEvent]) throws -> URL {
        let timestampFormatter = makeTimestampFormatter()
        let decimalFormatter = makeDecimalFormatter()

        let generatedAt = ISO8601DateFormatter().string(from: .now)
        let preambleLines = csvPreamble(
            eventCount: events.count,
            generatedAtISO8601: generatedAt
        )

        let header = [
            "event_id",
            "timestamp",
            "timezone",
            "weekday",
            "hour",
            "minute",
            "part_of_day",
            "capture_status",
            "health_status",
            "environment_status",
            "location",
            "weather_summary",
            "temperature_c",
            "feels_like_c",
            "humidity_percent",
            "pressure_hpa",
            "pressure_trend",
            "precipitation_mm",
            "wind_speed_kph",
            "wind_direction_deg",
            "cloud_cover_percent",
            "uv_index",
            "us_aqi",
            "european_aqi",
            "pm2_5",
            "pm10",
            "ozone",
            "nitrogen_dioxide",
            "sulphur_dioxide",
            "carbon_monoxide",
            "alder_pollen",
            "birch_pollen",
            "grass_pollen",
            "mugwort_pollen",
            "olive_pollen",
            "ragweed_pollen",
            "steps_today",
            "active_energy_kcal_today",
            "distance_walking_running_km_today",
            "exercise_minutes_today",
            "sleep_hours_last_night",
            "last_main_sleep_wake_utc",
            "hours_since_main_sleep_wake",
            "resting_heart_rate_bpm",
            "recent_heart_rate_avg_bpm",
            "hrv_sdnn_ms",
            "respiratory_rate_brpm",
            "workouts_last_24h",
            "workout_minutes_last_24h",
            "environmental_audio_db_a",
            "oxygen_saturation_percent",
            "vo2_max_ml_kg_min",
            "walking_speed_m_s",
            "apple_stand_minutes_today",
            "basal_energy_kcal_today",
            "flights_climbed_today",
            "mindful_minutes_today",
            "barometric_pressure_delta_hpa_6h",
            "health_message",
            "environment_message",
            "user_notes",
        ].joined(separator: ",")

        let rows = events.map { event in
            [
                csv(event.id.uuidString),
                csv(timestampFormatter.string(from: event.timestamp)),
                csv(event.timezoneIdentifier),
                csv(event.weekdayName),
                csv(String(event.hourOfDay)),
                csv(String(event.minuteOfHour)),
                csv(event.partOfDay.rawValue),
                csv(event.captureStatus.rawValue),
                csv(event.healthStatus.rawValue),
                csv(event.environmentStatus.rawValue),
                csv(event.locationLabel),
                csv(event.weatherSummary),
                csv(number(event.temperatureC, formatter: decimalFormatter)),
                csv(number(event.apparentTemperatureC, formatter: decimalFormatter)),
                csv(number(event.humidityPercent, formatter: decimalFormatter)),
                csv(number(event.pressureHpa, formatter: decimalFormatter)),
                csv(event.pressureTrend.rawValue),
                csv(number(event.precipitationMm, formatter: decimalFormatter)),
                csv(number(event.windSpeedKph, formatter: decimalFormatter)),
                csv(number(event.windDirectionDegrees, formatter: decimalFormatter)),
                csv(number(event.cloudCoverPercent, formatter: decimalFormatter)),
                csv(number(event.uvIndex, formatter: decimalFormatter)),
                csv(number(event.usAQI, formatter: decimalFormatter)),
                csv(number(event.europeanAQI, formatter: decimalFormatter)),
                csv(number(event.pm25, formatter: decimalFormatter)),
                csv(number(event.pm10, formatter: decimalFormatter)),
                csv(number(event.ozone, formatter: decimalFormatter)),
                csv(number(event.nitrogenDioxide, formatter: decimalFormatter)),
                csv(number(event.sulphurDioxide, formatter: decimalFormatter)),
                csv(number(event.carbonMonoxide, formatter: decimalFormatter)),
                csv(number(event.alderPollen, formatter: decimalFormatter)),
                csv(number(event.birchPollen, formatter: decimalFormatter)),
                csv(number(event.grassPollen, formatter: decimalFormatter)),
                csv(number(event.mugwortPollen, formatter: decimalFormatter)),
                csv(number(event.olivePollen, formatter: decimalFormatter)),
                csv(number(event.ragweedPollen, formatter: decimalFormatter)),
                csv(event.stepsToday.map(String.init)),
                csv(number(event.activeEnergyKcalToday, formatter: decimalFormatter)),
                csv(number(event.distanceWalkingRunningKmToday, formatter: decimalFormatter)),
                csv(number(event.exerciseMinutesToday, formatter: decimalFormatter)),
                csv(number(event.sleepHoursLastNight, formatter: decimalFormatter)),
                csv(event.lastMainSleepWakeTime.map { timestampFormatter.string(from: $0) }),
                csv(number(event.hoursSinceMainSleepWake, formatter: decimalFormatter)),
                csv(number(event.restingHeartRateBpm, formatter: decimalFormatter)),
                csv(number(event.recentHeartRateAverageBpm, formatter: decimalFormatter)),
                csv(number(event.hrvSDNNMs, formatter: decimalFormatter)),
                csv(number(event.respiratoryRateBrpm, formatter: decimalFormatter)),
                csv(event.workoutsLast24h.map(String.init)),
                csv(number(event.workoutMinutesLast24h, formatter: decimalFormatter)),
                csv(number(event.environmentalAudioExposureDbA, formatter: decimalFormatter)),
                csv(number(event.oxygenSaturationPercent, formatter: decimalFormatter)),
                csv(number(event.vo2MaxMlPerKgPerMin, formatter: decimalFormatter)),
                csv(number(event.walkingSpeedMetersPerSecond, formatter: decimalFormatter)),
                csv(number(event.appleStandMinutesToday, formatter: decimalFormatter)),
                csv(number(event.basalEnergyKcalToday, formatter: decimalFormatter)),
                csv(number(event.flightsClimbedToday, formatter: decimalFormatter)),
                csv(number(event.mindfulMinutesToday, formatter: decimalFormatter)),
                csv(number(event.barometricPressureDeltaHpa6h, formatter: decimalFormatter)),
                csv(event.healthStatusMessage),
                csv(event.environmentStatusMessage),
                csv(event.userNotes),
            ].joined(separator: ",")
        }

        let contents = (preambleLines + [header] + rows).joined(separator: "\n")
        let filename = "headache-events-\(Int(Date.now.timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Lines prefixed with `#` so spreadsheet tools and simple parsers can treat them as comments; tabular CSV starts after the preamble.
    private static func csvPreamble(eventCount: Int, generatedAtISO8601: String) -> [String] {
        [
            "# Headache Logger — exported headache event log",
            "# What this file is: one row per time you tapped Headache in the app; each row is a timestamped snapshot of optional context (not a diagnosis).",
            "# Time: timestamp (UTC ISO8601 with fractional seconds), timezone ID, weekday name, hour/minute, part_of_day (overnight/morning/afternoon/evening).",
            "# Health (Apple Health when permitted): activity (steps, active/basal energy, distance, exercise, stand, flights), sleep (hours in window, inferred main-sleep wake time, hours since wake), heart (resting, recent avg, HRV, SpO₂, VO₂ max, walking speed), breathing rate, environmental audio (6h avg dB), mindful minutes today, barometric pressure change over 6h (device samples), workouts in last 24h.",
            "# Environment (when location/weather services work): human-readable location, weather summary, temperature, humidity, pressure and trend, precipitation, wind, cloud cover, UV, air quality indices and pollutants, pollen-style counts when exposed by the data provider.",
            "# Status columns: capture_status plus health_status / environment_status reflect whether those bundles were captured; health_message and environment_message explain gaps or errors when present.",
            "# user_notes: optional text you added later in History (not captured at tap time).",
            "# Empty quoted cells mean the value was unavailable or not recorded for that event.",
            "# This export is for personal tracking and sharing with a clinician or researcher; it does not establish medical facts by itself.",
            "#",
            "# export_generated_at_utc: \(generatedAtISO8601)",
            "# row_count: \(eventCount)",
            "#",
        ]
    }

    private static func csv(_ value: String?) -> String {
        let raw = value ?? ""
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func number(_ value: Double?, formatter: NumberFormatter) -> String? {
        guard let value else { return nil }
        return formatter.string(from: NSNumber(value: value))
    }

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeDecimalFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.minimumIntegerDigits = 1
        return formatter
    }
}
