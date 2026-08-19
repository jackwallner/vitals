import SwiftUI

/// Identifies which metric a detail screen focuses on. Used as the
/// `navigationDestination` value pushed from Dashboard rows and History chart cards.
enum HistoryMetric: String, Identifiable, Hashable {
    case calories
    case steps
    case net
    case macros

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories: return "Calories"
        case .steps: return "Steps"
        case .net: return "Net Deficit"
        case .macros: return "Macros"
        }
    }

    var tint: Color {
        switch self {
        case .calories: return Theme.caloriesPrimary
        case .steps: return Theme.stepsPrimary
        case .net: return Theme.netDeficitBrand
        case .macros: return Theme.macrosBrand
        }
    }
}

/// A muted, gently pulsing placeholder used to reserve layout space while data
/// loads, so sections don't pop into existence and shift the surrounding content.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 8
    @State private var pulse = false
    @State private var shimmer = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { geo in
            let width = geo.size.width
            let band = max(width * 0.4, 48)
            shape
                .fill(Theme.textTertiary.opacity(pulse ? 0.18 : 0.08))
                // A LoadingBar-style highlight that sweeps across the skeleton, so
                // the placeholder reads as "loading" rather than a static block.
                .overlay {
                    shape
                        .fill(LinearGradient(
                            colors: [.clear, Theme.textTertiary.opacity(0.28), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: band)
                        .offset(x: shimmer ? width : -band)
                }
                .clipShape(shape)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
        .accessibilityHidden(true)
    }
}
