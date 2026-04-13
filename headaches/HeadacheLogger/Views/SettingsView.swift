import HealthKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @State private var locationStatus = EnvironmentService.shared.locationAuthorizationSummary()

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Color scheme", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("How Logging Works") {
                Text("The main screen is intentionally a one-tap logger. When you press Headache, the app saves the event immediately and then enriches it with whatever context it can collect.")
                Text("Nothing about the headache itself is typed in during logging. The goal is to make capture fast enough that you actually use it.")
            }

            Section("Permissions") {
                PermissionRow(
                    label: "Apple Health",
                    value: HKHealthStore.isHealthDataAvailable() ? "Available on this device" : "Unavailable",
                    valueIdentifier: "healthPermissionValue"
                )
                PermissionRow(
                    label: "Location",
                    value: locationStatus,
                    valueIdentifier: "locationPermissionValue"
                )
                Button("Open iPhone Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }

            Section("Captured Context") {
                Text("Time: weekday, hour, minute, timezone, part of day.")
                Text("Health: steps, active energy, walking distance, exercise minutes, sleep, heart data, breathing, recent workouts.")
                Text("Environment: local weather, humidity, pressure, precipitation, wind, cloud cover, UV, air quality, and pollen-style signals when available.")
            }

            Section("Sharing") {
                Text("The History tab can export all logged events as a CSV so you can email it, AirDrop it, or share it directly with your doctor.")
            }
        }
        .navigationTitle("About")
        .onAppear {
            locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
        }
    }
}

private struct PermissionRow: View {
    let label: String
    let value: String
    let valueIdentifier: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(valueIdentifier)
        }
    }
}
