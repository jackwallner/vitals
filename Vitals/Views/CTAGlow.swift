import SwiftUI

/// A soft coral halo that breathes behind a purchase button — the same idea as
/// the "7 DAYS FREE" badge on the trial sheet, which is the one thing on that
/// screen the eye lands on first.
///
/// Replaces an earlier sweeping sheen, which read as a loading skeleton rather
/// than a button worth pressing. This is deliberately quiet: it never moves the
/// button, never changes its colour, and only varies the spread and opacity of
/// light around it.
struct CTAGlow: ViewModifier {
    /// The button's own shape, so the halo matches its silhouette exactly.
    var tint: Color = Theme.caloriesPrimary
    /// Seconds for one full breath in and out.
    var period: Double = 2.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    func body(content: Content) -> some View {
        content
            // Two shadows: a tight one that keeps the button's own edge crisp,
            // and a wide soft one that is the glow people actually notice.
            .shadow(color: tint.opacity(0.35), radius: 6, x: 0, y: 2)
            .shadow(
                color: tint.opacity(open ? 0.45 : 0.18),
                radius: open ? 22 : 12,
                x: 0,
                y: 4
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: period).repeatForever(autoreverses: true),
                value: open
            )
            .onAppear {
                // Reduce Motion still gets the halo, just a still one at its
                // resting spread — it is emphasis, not motion, that carries it.
                guard !reduceMotion else { return }
                open = true
            }
    }
}

extension View {
    /// Draws attention to the one button on the screen that matters.
    func ctaGlow(tint: Color = Theme.caloriesPrimary) -> some View {
        modifier(CTAGlow(tint: tint))
    }
}

/// Applies `CTAGlow` only when `active`, without changing the view's identity
/// when it isn't — the onboarding bottom bar depends on its primary button
/// measuring the same on every page.
struct OptionalCTAGlow: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.modifier(CTAGlow())
        } else {
            content
        }
    }
}

/// Caps content at a readable column on regular-width displays (iPad, iPhone
/// Duo inner display, wide windows) and centres it. Compact width is untouched,
/// so the folded or ordinary iPhone layout keeps its exact behaviour.
struct ReadableWidth: ViewModifier {
    var maxWidth: CGFloat = 640
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // One branch for both widths: an `if` here rebuilt the wrapped screen, and
    // lost its state, every time the Duo opened or closed.
    // nil bounds size the frame to its content, so compact layout is unchanged.
    func body(content: Content) -> some View {
        let isRegular = horizontalSizeClass == .regular
        content
            .frame(maxWidth: isRegular ? maxWidth : nil)
            .frame(maxWidth: isRegular ? .infinity : nil)
    }
}

extension View {
    func readableWidth(_ maxWidth: CGFloat = 640) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}
