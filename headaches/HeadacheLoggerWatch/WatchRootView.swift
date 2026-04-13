import SwiftUI
import WatchConnectivity

struct WatchRootView: View {
    @StateObject private var session = WatchConnectivityController()

    var body: some View {
        logView
            .onAppear {
                session.activate()
            }
    }

    private var logView: some View {
        VStack(spacing: 12) {
            Text("Headache")
                .font(.headline)
            Button {
                session.requestLogFromPhone()
            } label: {
                Label("Log headache", systemImage: "figure.head.profile")
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
