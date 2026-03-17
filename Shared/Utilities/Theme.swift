import SwiftUI

enum Theme {
    // Background
    static let background = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let cardSurface = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let cardSurfaceLight = Color(red: 0.15, green: 0.15, blue: 0.18)

    // Calories palette
    static let caloriesPrimary = Color(red: 1.0, green: 0.42, blue: 0.42)   // #FF6B6B coral
    static let caloriesSecondary = Color(red: 1.0, green: 0.54, blue: 0.36) // #FF8A5C warm orange
    static let caloriesGlow = Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.3)

    // Steps palette
    static let stepsPrimary = Color(red: 0.0, green: 0.79, blue: 0.65)      // #00C9A7 teal
    static let stepsSecondary = Color(red: 0.31, green: 0.80, blue: 0.77)   // #4ECDC4 cyan
    static let stepsGlow = Color(red: 0.0, green: 0.79, blue: 0.65).opacity(0.3)

    // Active calories
    static let activePrimary = Color(red: 1.0, green: 0.54, blue: 0.36)     // warm orange
    static let restingPrimary = Color(red: 0.55, green: 0.35, blue: 0.75)   // muted purple

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    // Defaults
    static let calorieGoal: Double = 2500
    static let stepGoal: Int = 10000

    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 20

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
}
