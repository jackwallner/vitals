import SwiftUI

struct RootTabView: View {
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Headache Logger", systemImage: "figure.head.profile")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("About", systemImage: "slider.horizontal.3")
            }
        }
        .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
        .preferredColorScheme(AppAppearance.from(storageValue: appearanceRaw).preferredColorScheme)
    }
}
