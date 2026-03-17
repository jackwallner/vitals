import SwiftUI
import SwiftData

@main
struct VitalsApp: App {
    @StateObject private var healthKit = HealthKitService.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .task {
                    try? await healthKit.requestAuthorization()
                    healthKit.enableBackgroundDelivery()
                }
        }
        .modelContainer(DataService.sharedModelContainer)
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
            Group {
                if selectedTab == 0 {
                    DashboardView()
                } else {
                    HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            HStack(spacing: 0) {
                TabButton(
                    icon: "heart.fill",
                    label: "Today",
                    isSelected: selectedTab == 0
                ) { selectedTab = 0 }

                TabButton(
                    icon: "chart.bar.fill",
                    label: "History",
                    isSelected: selectedTab == 1
                ) { selectedTab = 1 }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            .padding(.bottom, 12)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct TabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.caloriesPrimary : Theme.textTertiary)
            .frame(width: 72, height: 44)
            .background(
                isSelected ? Theme.caloriesPrimary.opacity(0.12) : .clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
