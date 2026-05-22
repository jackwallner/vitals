import SwiftUI

/// Identifies which metric a detail screen focuses on. Used as the
/// `navigationDestination` value pushed from Dashboard rows and History chart cards.
enum HistoryMetric: String, Identifiable, Hashable {
    case calories
    case steps
    case net

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories: return "Calories"
        case .steps: return "Steps"
        case .net: return "Net Deficit"
        }
    }

    var tint: Color {
        switch self {
        case .calories: return Theme.caloriesPrimary
        case .steps: return Theme.stepsPrimary
        case .net: return Theme.netDeficitBrand
        }
    }
}

/// A muted, gently pulsing placeholder used to reserve layout space while data
/// loads, so sections don't pop into existence and shift the surrounding content.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.textTertiary.opacity(pulse ? 0.18 : 0.08))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
    }
}
