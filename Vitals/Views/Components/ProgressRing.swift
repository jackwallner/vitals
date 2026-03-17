import SwiftUI

struct ProgressRing: View {
    let progress: Double // 0.0 to 1.0+
    let gradient: LinearGradient
    let glowColor: Color
    let lineWidth: CGFloat
    let size: CGFloat

    init(
        progress: Double,
        gradient: LinearGradient,
        glowColor: Color,
        lineWidth: CGFloat = 14,
        size: CGFloat = 180
    ) {
        self.progress = progress
        self.gradient = gradient
        self.glowColor = glowColor
        self.lineWidth = lineWidth
        self.size = size
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(
                    Theme.ringTrack,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Progress arc
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: glowColor, radius: 8, x: 0, y: 0)
        }
        .frame(width: size, height: size)
    }
}

struct StepProgressBar: View {
    let progress: Double
    let gradient: LinearGradient
    let glowColor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Theme.ringTrack)

                // Fill
                Capsule()
                    .fill(gradient)
                    .frame(width: geo.size.width * min(progress, 1.0))
                    .shadow(color: glowColor, radius: 6, x: 0, y: 0)
            }
        }
        .frame(height: 10)
    }
}
