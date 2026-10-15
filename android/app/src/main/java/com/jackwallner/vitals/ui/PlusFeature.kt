package com.jackwallner.vitals.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.PlusOne
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material.icons.filled.Whatshot
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.jackwallner.vitals.ui.theme.VitalsColors

/**
 * The Vitals+ features this port ships, with the iOS paywall copy (`PlusFeature`
 * in `PaywallView.swift`) reworded for Health Connect. Macros, Body Profile and
 * Weekly Recap are not in the Android v1 and are not offered.
 */
enum class PlusFeature(
    val icon: ImageVector,
    val tint: Color,
    val title: String,
    val detail: String,
    val featureListTitle: String,
    val intentHeadline: String,
    val intentSubheadline: String,
) {
    NET_DEFICIT(
        Icons.Filled.PlusOne, VitalsColors.netDeficitBrand,
        "Net Deficit", "Burned minus food logged in Health Connect, updated through the day.",
        "Net Deficit: burned minus food logged, live",
        "Track your live deficit", "Calories burned minus food logged, updated all day from Health Connect.",
    ),
    ACTIVE_RESTING(
        Icons.Filled.LocalFireDepartment, VitalsColors.caloriesPrimary,
        "Active vs. resting", "See how much of today's burn came from activity vs. resting.",
        "Active vs. resting calorie breakdown",
        "Split active and resting burn", "See what actually moved today's calorie number.",
    ),
    ENERGY_AVERAGES(
        Icons.Filled.Speed, VitalsColors.caloriesPrimary,
        "TDEE & BMR", "30-day maintenance (TDEE) and resting burn (BMR) from your data.",
        "TDEE & BMR from your Health Connect averages",
        "See your maintenance calories", "TDEE and BMR averaged over the last 30 days from your own data.",
    ),
    DEEP_TRENDS(
        Icons.Filled.ShowChart, VitalsColors.stepsPrimary,
        "Deep Trends", "Compare any period to the one before it.",
        "Deep Trends: every period vs. the one before",
        "Compare every period", "Stack this week against last week, this month against the last.",
    ),
    CUSTOM_RANGES_PDF(
        Icons.Filled.CalendarMonth, VitalsColors.stepsSecondary,
        "Custom ranges + PDF", "Pick any dates in History and export a summary PDF.",
        "Custom date ranges + PDF reports",
        "Export any date range", "Pull any window from History into a clean PDF.",
    ),
    PROJECTIONS(
        Icons.Filled.MyLocation, VitalsColors.stepsPrimary,
        "End-of-day projections", "Where today's calories and steps will land at your current pace.",
        "End-of-day projections from your pace",
        "Know where today lands", "Projected calories and steps based on your pace so far today.",
    ),
    STREAKS(
        Icons.Filled.Whatshot, VitalsColors.streakPrimary,
        "Goal streaks", "See how many days in a row you've hit your goal.",
        "Goal streaks: keep the chain alive",
        "Keep your streak alive", "Track consecutive days you hit your goal.",
    ),
    EXCLUDED_DAYS(
        Icons.Filled.Block, VitalsColors.stepsSecondary,
        "Excluded days", "Leave sick days and days off the wrist out of your averages.",
        "Excluded days: keep odd days out of your averages",
        "Keep odd days out of your averages",
        "Pick the days that shouldn't count (sick days, travel, a day off the wrist) and every average, total, and streak skips them.",
    );

    val companions: List<PlusFeature>
        get() = when (this) {
            NET_DEFICIT -> listOf(PROJECTIONS, ENERGY_AVERAGES)
            ACTIVE_RESTING -> listOf(NET_DEFICIT, ENERGY_AVERAGES)
            ENERGY_AVERAGES -> listOf(NET_DEFICIT, PROJECTIONS)
            DEEP_TRENDS -> listOf(CUSTOM_RANGES_PDF, PROJECTIONS)
            CUSTOM_RANGES_PDF -> listOf(DEEP_TRENDS, NET_DEFICIT)
            PROJECTIONS -> listOf(NET_DEFICIT, STREAKS)
            STREAKS -> listOf(PROJECTIONS, DEEP_TRENDS)
            EXCLUDED_DAYS -> listOf(ENERGY_AVERAGES, DEEP_TRENDS)
        }

    companion object {
        /** The default Upgrade-tab list: the iOS catalog layout minus what Android v1 leaves out. */
        val catalog = listOf(NET_DEFICIT, ENERGY_AVERAGES, DEEP_TRENDS, CUSTOM_RANGES_PDF, ACTIVE_RESTING)
        const val REMAINING = "Plus projections, streaks, and excluded days."
    }
}
