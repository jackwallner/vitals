import SwiftUI

enum Theme {
    // MARK: - Adaptive colors (light/dark)

    static let background = Color(.systemBackground)
    static let cardSurface = Color(.secondarySystemBackground)
    static let cardSurfaceLight = Color(.tertiarySystemBackground)

    // Ring track
    static let ringTrack = Color(.systemFill)

    // Calories palette
    static let caloriesPrimary = Color(red: 1.0, green: 0.42, blue: 0.42)   // #FF6B6B coral
    static let caloriesSecondary = Color(red: 1.0, green: 0.54, blue: 0.36) // #FF8A5C warm orange
    static let caloriesGlow = Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.3)

    // Steps palette
    static let stepsPrimary = Color(red: 0.0, green: 0.69, blue: 0.55)      // #00B08D teal (slightly deeper for light mode contrast)
    static let stepsSecondary = Color(red: 0.24, green: 0.73, blue: 0.70)   // #3DBAB3 cyan
    static let stepsGlow = Color(red: 0.0, green: 0.69, blue: 0.55).opacity(0.3)

    // Active/resting calories
    static let activePrimary = Color(red: 1.0, green: 0.54, blue: 0.36)     // warm orange
    static let restingPrimary = Color(red: 0.55, green: 0.35, blue: 0.75)   // muted purple

    // Text — use semantic colors
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    // MARK: - Constants

    static let calorieGoal: Double = 2500
    static let stepGoal: Int = 10000

    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 20

    // MARK: - Gradients

    static var caloriesGradient: LinearGradient {
        LinearGradient(
            colors: [caloriesPrimary, caloriesSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var stepsGradient: LinearGradient {
        LinearGradient(
            colors: [stepsPrimary, stepsSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Typography

    static func bigNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
