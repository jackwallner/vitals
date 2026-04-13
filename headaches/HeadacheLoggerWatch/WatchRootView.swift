import SwiftUI
import WatchConnectivity

struct WatchRootView: View {
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var onboardingComplete = false
    @StateObject private var session = WatchConnectivityController()

    var body: some View {
        Group {
            if onboardingComplete {
                logView
            } else {
                setupNeededView
            }
        }
        .onAppear {
            session.activate()
        }
    }

    private var setupNeededView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Set up on iPhone")
                    .font(.headline)
                Text("Open Headache Logger on your iPhone and complete the short Health & Location steps. This Watch app will match that when you’re done.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var logView: some View {
        VStack(spacing: 12) {
            Text("Headache")
                .font(.headline)
            Button {
                session.requestLogFromPhone()
            } label: {
                Label("Log on iPhone", systemImage: "figure.head.profile")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.95, green: 0.25, blue: 0.43))

            if let message = session.statusMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 4)
    }
}
