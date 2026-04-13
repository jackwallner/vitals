import SwiftUI

struct OnboardingView: View {
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false

    @State private var step = 0
    @State private var healthError: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0:
                    welcomePage
                case 1:
                    healthPage
                case 2:
                    locationPage
                default:
                    welcomePage
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Headache Logger")
                .font(.largeTitle.bold())
            Text("Log headaches with one tap. The app enriches each entry with time, optional Apple Health context, and optional local weather — so you and your clinician can spot patterns.")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue") {
                step = 1
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var healthPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Apple Health", systemImage: "heart.text.square.fill")
                .font(.title2.bold())
                .foregroundStyle(.pink)
            Text("Allow read access to metrics like activity, sleep, heart rate, and workouts. Nothing is written to Health, and you can change this anytime in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)

            if let healthError {
                Text(healthError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await enableHealthTapped() }
                } label: {
                    if isWorking {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Allow Health Access")
                    }
                }
                .disabled(isWorking)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(maxWidth: .infinity)

                Button("Not Now") {
                    HeadacheOnboardingStore.declinedHealthRead = true
                    Task {
                        await HealthKitService.shared.markHealthSkippedInOnboarding()
                        await MainActor.run { step = 2 }
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private var locationPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Location", systemImage: "location.fill")
                .font(.title2.bold())
                .foregroundStyle(.blue)
            Text("Used only to fetch approximate weather and place labels when you log. We don’t track you in the background.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await enableLocationTapped() }
                } label: {
                    if isWorking {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Allow Location Access")
                    }
                }
                .disabled(isWorking)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(maxWidth: .infinity)

                Button("Not Now") {
                    HeadacheOnboardingStore.declinedLocation = true
                    finishOnboarding()
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private func enableHealthTapped() async {
        healthError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await HealthKitService.shared.prepareAuthorizationDuringOnboarding()
            await MainActor.run { step = 2 }
        } catch {
            healthError = error.localizedDescription
        }
    }

    private func enableLocationTapped() async {
        isWorking = true
        defer { isWorking = false }
        await EnvironmentService.shared.prepareLocationAuthorizationDuringOnboarding()
        finishOnboarding()
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
    }
}
