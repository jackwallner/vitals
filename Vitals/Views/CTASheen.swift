import SwiftUI

/// A slow highlight that sweeps across a purchase button, then waits before
/// coming back. Kept deliberately quiet — a soft white band at 0.35 alpha on a
/// long duty cycle — so it reads as a polished button rather than a loading
/// skeleton or a flashing ad.
///
/// Overlay it *on* the filled shape and pass the same shape, so the sheen is
/// clipped to the button rather than to its bounding box.
struct CTASheen<S: Shape>: View {
    let shape: S
    /// Seconds for one sweep plus the pause after it.
    var period: Double = 3.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Travels from fully off the leading edge to fully off the trailing
            // one, so no part of the band is ever parked on the button.
            let band = max(width * 0.28, 44)
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.35), location: 0.5),
                    .init(color: .white.opacity(0), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: band)
            .rotationEffect(.degrees(18))
            .offset(x: sweep ? width + band : -band)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 0.9).repeatForever(autoreverses: false).delay(period - 0.9),
                value: sweep
            )
        }
        .clipShape(shape)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            sweep = true
        }
    }
}
