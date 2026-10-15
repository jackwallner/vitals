package com.jackwallner.vitals.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.R

/**
 * `Theme.swift`. iOS uses semantic system colors for surfaces and text, so the
 * light and dark values here are the iOS system values; the calorie, step and
 * macro palettes are fixed in both appearances, exactly as on iOS.
 */
class VitalsPalette(
    val background: Color,
    val cardSurface: Color,
    val cardSurfaceLight: Color,
    val ringTrack: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val isDark: Boolean,
)

val LightPalette = VitalsPalette(
    background = Color(0xFFFFFFFF),
    cardSurface = Color(0xFFF2F2F7),
    cardSurfaceLight = Color(0xFFFFFFFF),
    ringTrack = Color(0x2E787880),
    textPrimary = Color(0xFF000000),
    textSecondary = Color(0x993C3C43),
    textTertiary = Color(0x4D3C3C43),
    isDark = false,
)

val DarkPalette = VitalsPalette(
    background = Color(0xFF000000),
    cardSurface = Color(0xFF1C1C1E),
    cardSurfaceLight = Color(0xFF2C2C2E),
    ringTrack = Color(0x5C787880),
    textPrimary = Color(0xFFFFFFFF),
    textSecondary = Color(0x99EBEBF5),
    textTertiary = Color(0x4DEBEBF5),
    isDark = true,
)

val LocalPalette = staticCompositionLocalOf { LightPalette }

object VitalsColors {
    val caloriesPrimary = Color(0xFFFF6B6B)
    val caloriesSecondary = Color(0xFFFF8A5C)
    val caloriesGlow = Color(0x4DFF6B6B)
    val stepsPrimary = Color(0xFF00B08D)
    val stepsSecondary = Color(0xFF3DBAB3)
    val stepsGlow = Color(0x4D00B08D)
    val activePrimary = Color(0xFFFF8A5C)
    val restingPrimary = Color(0xFF8C59BF)
    val streakPrimary = Color(0xFF4DC773)
    val netDeficitBrand = Color(0xFF9E66D1)
    val netDeficitPositive = Color(0xFF33AD73)
    val netDeficitNegative = Color(0xFFEB6B61)
    val macrosBrand = Color(0xFF4D96FF)
    val ahead = Color(0xFF34C759)
}

object Geo {
    val cardRadius = 20.dp
    val cardPadding = 20.dp
    val gutter = 24.dp
}

object Gradients {
    val calories: Brush = Brush.linearGradient(listOf(VitalsColors.caloriesPrimary, VitalsColors.caloriesSecondary))
    val steps: Brush = Brush.linearGradient(listOf(VitalsColors.stepsPrimary, VitalsColors.stepsSecondary))
}

/** Nunito stands in for SF Rounded, the face every Vitals screen is set in. */
@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
object VitalsFonts {
    private val weights = listOf(FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold, FontWeight.ExtraBold)

    val rounded = FontFamily(weights.map { weight ->
        Font(R.font.nunito, weight, FontStyle.Normal, variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight)))
    })
}

object Type {
    fun rounded(size: TextUnit, weight: FontWeight = FontWeight.Normal) =
        TextStyle(fontFamily = VitalsFonts.rounded, fontWeight = weight, fontSize = size, lineHeight = size * 1.28f)

    fun bigNumber(size: TextUnit) = rounded(size, FontWeight.Bold).copy(lineHeight = size * 1.05f)

    val largeTitle = rounded(32.sp, FontWeight.Bold)
    val title = rounded(28.sp, FontWeight.Bold)
    val title3 = rounded(20.sp, FontWeight.Bold)
    val headline = rounded(17.sp, FontWeight.SemiBold)
    val body = rounded(17.sp)
    val callout = rounded(16.sp)
    val subhead = rounded(15.sp)
    val footnote = rounded(13.sp)
    val caption = rounded(12.sp)
    val caption2 = rounded(11.sp)
}

@Composable
fun VitalsTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val palette = if (dark) DarkPalette else LightPalette
    val scheme = if (dark) {
        darkColorScheme(
            primary = VitalsColors.caloriesPrimary,
            background = palette.background,
            surface = palette.cardSurface,
            onSurface = palette.textPrimary,
            onBackground = palette.textPrimary,
            surfaceVariant = palette.cardSurface,
            onSurfaceVariant = palette.textSecondary,
            outline = palette.ringTrack,
        )
    } else {
        lightColorScheme(
            primary = VitalsColors.caloriesPrimary,
            background = palette.background,
            surface = palette.cardSurface,
            onSurface = palette.textPrimary,
            onBackground = palette.textPrimary,
            surfaceVariant = palette.cardSurface,
            onSurfaceVariant = palette.textSecondary,
            outline = palette.ringTrack,
        )
    }
    CompositionLocalProvider(LocalPalette provides palette) {
        MaterialTheme(
            colorScheme = scheme,
            typography = MaterialTheme.typography.copy(
                bodyLarge = Type.body, bodyMedium = Type.subhead, bodySmall = Type.caption,
                labelLarge = Type.rounded(15.sp, FontWeight.SemiBold), titleLarge = Type.title3,
            ),
            content = content,
        )
    }
}

val palette: VitalsPalette @Composable get() = LocalPalette.current
