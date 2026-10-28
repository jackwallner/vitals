import SwiftUI

enum Theme {
    // MARK: - Adaptive colors (light/dark)

    #if os(watchOS)
    static let background = Color.black
    static let cardSurface = Color(white: 0.12)
    static let cardSurfaceLight = Color(white: 0.18)
    static let ringTrack = Color(white: 0.2)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.7)
    static let textTertiary = Color(white: 0.5)
    #else
    static let background = Color(.systemBackground)
    static let cardSurface = Color(.secondarySystemBackground)
    static let cardSurfaceLight = Color(.tertiarySystemBackground)
    static let ringTrack = Color(.systemFill)
    static let textPrimary = Color(.label)
    // System secondary/tertiary label measure 3:1 or less on white. These keep
    // the hierarchy but clear 4.5:1 on both backgrounds and cards.
    static let textSecondary = adaptive(light: 0x5C5C61, dark: 0xA8A8AE)
    static let textTertiary = adaptive(light: 0x66666B, dark: 0x9C9CA2)
    #endif

    /// Accent text on a light or tinted surface: the brand hue darkened to 4.5:1.
    static let caloriesText = adaptive(light: 0xC23B3B, dark: 0xFF6B6B)
    static let positiveText = adaptive(light: 0x17713A, dark: 0x4DDB7A)
    static let stepsText = adaptive(light: 0x007A63, dark: 0x3DD6B3)

    // Calories palette
    static let caloriesPrimary = Color(red: 1.0, green: 0.42, blue: 0.42)   // #FF6B6B coral
    static let caloriesSecondary = Color(red: 1.0, green: 0.54, blue: 0.36) // #FF8A5C warm orange
    static let caloriesGlow = Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.3)

    // Steps palette
    static let stepsPrimary = Color(red: 0.0, green: 0.69, blue: 0.55)      // #00B08D teal
    static let stepsSecondary = Color(red: 0.24, green: 0.73, blue: 0.70)   // #3DBAB3 cyan
    static let stepsGlow = Color(red: 0.0, green: 0.69, blue: 0.55).opacity(0.3)

    // Active/resting calories
    static let activePrimary = Color(red: 1.0, green: 0.54, blue: 0.36)     // warm orange
    static let restingPrimary = Color(red: 0.55, green: 0.35, blue: 0.75)   // muted purple

    // Goal streaks — always green: a live streak is a win regardless of metric
    static let streakPrimary = Color(red: 0.30, green: 0.78, blue: 0.45)  // #4DC773 green

    // Net deficit (burned − food)
    static let netDeficitBrand = Color(red: 0.62, green: 0.40, blue: 0.82)   // purple
    static let netDeficitPositive = Color(red: 0.20, green: 0.68, blue: 0.45)
    static let netDeficitNegative = Color(red: 0.92, green: 0.42, blue: 0.38)

    // Macros: one hue per macronutrient, kept clear of the calorie coral and
    // step teal so a stacked macro bar never reads as "calories" or "steps".
    static let macrosBrand = Color(red: 0.30, green: 0.59, blue: 1.0)         // #4D96FF blue
    static let proteinPrimary = Color(red: 0.30, green: 0.59, blue: 1.0)      // blue
    static let carbsPrimary = Color(red: 0.95, green: 0.71, blue: 0.25)       // amber
    static let fatPrimary = Color(red: 0.78, green: 0.49, blue: 0.84)         // orchid

    static func macroColor(_ kind: MacroKind) -> Color {
        switch kind {
        case .protein: proteinPrimary
        case .carbs: carbsPrimary
        case .fat: fatPrimary
        }
    }

    #if os(watchOS)
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(red: Double((dark >> 16) & 0xFF) / 255,
              green: Double((dark >> 8) & 0xFF) / 255,
              blue: Double(dark & 0xFF) / 255)
    }
    #else
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    #endif

    // MARK: - Constants

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

extension View {
    /// Pads a small footer link to a 44 pt tap target without moving its text.
    func legalTapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}
