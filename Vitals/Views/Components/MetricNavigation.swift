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
        case .calories: return String(localized: "Calories")
        case .steps: return String(localized: "Steps")
        case .net: return String(localized: "Net Deficit")
        case .macros: return String(localized: "Macros")
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
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
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
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: shimmer)
                }
                .clipShape(shape)
        }
        // Scoped animations: a repeatForever `withAnimation` here also animated
        // the layout of everything appearing with the skeleton.
        .onAppear {
            pulse = true
            shimmer = true
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Unfolded, a pushed screen hides its navigation bar and draws its back
    /// button and title in the pane: iOS 27.1 moves the system back button
    /// into the vertical bar at the display's edge, outside the pane.
    func unfoldedPaneBackHeader(_ title: String, background: Color = Theme.background) -> some View {
        modifier(UnfoldedPaneBackHeader(title: title, background: background))
    }
}

private struct UnfoldedPaneBackHeader: ViewModifier {
    let title: String
    let background: Color
    @Environment(\.isUnfoldedPane) private var isUnfoldedPane
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if isUnfoldedPane { header }
            }
            .toolbar(isUnfoldedPane ? .hidden : .automatic, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 22, height: 22)
                    .padding(10)
                    .background(Theme.cardSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text(title)
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(background)
    }
}
