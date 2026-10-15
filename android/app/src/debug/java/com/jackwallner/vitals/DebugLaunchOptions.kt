package com.jackwallner.vitals

import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import com.jackwallner.vitals.data.Appearance
import com.jackwallner.vitals.data.PackageKind
import com.jackwallner.vitals.data.PeriodUnit
import com.jackwallner.vitals.data.Plan
import com.jackwallner.vitals.data.PlanPeriod
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import kotlin.math.abs
import kotlin.math.sin
import kotlinx.coroutines.launch

/**
 * Debug builds only. Launch extras for screenshots and UI tests:
 * `resetAll`, `seedDemo`, `demoPro`, `previewStore`, `completeSetup`, `appearance`,
 * `tab` (today|history|upgrade), `overlay` (settings|paywall|excluded),
 * `onboardingStep` (welcome|goals|trial), `enable` (comma list: activeResting,
 * tdee, projections, streaks, net).
 */
object DebugLaunchOptions {
    var tab: String? = null
    var onboardingStep: String? = null
    var overlay: String? = null

    /** Wipes stored state and rebuilds the graph before anything reads it. */
    fun prepare(app: VitalsApplication, intent: Intent?) {
        if (intent?.getBooleanExtra("resetAll", false) != true) return
        app.graph.defaults.keys().toList().forEach { app.graph.defaults.remove(it) }
        app.rebuildGraph()
    }

    fun apply(graph: AppGraph, intent: Intent?) {
        intent ?: return
        tab = intent.getStringExtra("tab")
        onboardingStep = intent.getStringExtra("onboardingStep")
        overlay = intent.getStringExtra("overlay")
        when (intent.getStringExtra("appearance")) {
            "light" -> graph.settings.chooseAppearance(Appearance.LIGHT)
            "dark" -> graph.settings.chooseAppearance(Appearance.DARK)
        }
        if (intent.getBooleanExtra("completeSetup", false)) graph.settings.completeSetup()
        if (intent.hasExtra("demoPro")) graph.store.setLocalOverride(intent.getBooleanExtra("demoPro", false))
        if (intent.getBooleanExtra("previewStore", false)) graph.store.loadPreviewPlans(previewPlans())
        intent.getStringExtra("enable")?.split(',')?.forEach { name ->
            when (name.trim()) {
                "activeResting" -> graph.settings.showActiveResting = true
                "tdee" -> graph.settings.showEnergyAverages = true
                "projections" -> graph.settings.showProjections = true
                "streaks" -> graph.settings.showStreaks = true
                "net" -> graph.settings.showNet = true
            }
        }
        if (intent.getBooleanExtra("seedDemo", false)) {
            graph.scope.launch {
                runCatching { seedDemo(graph) }
                graph.repo.refresh(wantsFood = graph.settings.showNet)
            }
        }
    }

    private fun previewPlans(): List<Plan> = listOf(
        Plan("\$rc_annual", "com.jackwallner.vitals.yearly", PackageKind.YEARLY, 23_990_000, "$23.99", "USD", PlanPeriod(1, PeriodUnit.YEAR), PlanPeriod(7, PeriodUnit.DAY), "Yearly"),
        Plan("\$rc_monthly", "com.jackwallner.vitals.monthly", PackageKind.MONTHLY, 5_490_000, "$5.49", "USD", PlanPeriod(1, PeriodUnit.MONTH), PlanPeriod(7, PeriodUnit.DAY), "Monthly"),
        Plan("\$rc_lifetime", "com.jackwallner.vitals.plus.lifetime", PackageKind.LIFETIME, 47_990_000, "$47.99", "USD", null, null, "Lifetime"),
    )

    /** Ninety days of plausible wearable data written into Health Connect, so every screen has real input. */
    private suspend fun seedDemo(graph: AppGraph) {
        val client = HealthConnectClient.getOrCreate(graph.appContext)
        val seeder = HealthSeeder(client)
        val today = LocalDate.now()
        val now = LocalDateTime.now()
        seeder.clearAll(today.minusDays(120), today)
        for (offset in 0L..90L) {
            val day = today.minusDays(offset)
            val wave = sin(day.toEpochDay() / 2.3)
            val weekend = day.dayOfWeek.value >= 6
            val active = 520.0 + 260.0 * wave + if (weekend) 120.0 else 0.0
            val steps = (8_400 + 3_800 * wave + if (weekend) 1_600 else 0).toLong()
            val food = 2_050.0 + 360.0 * sin(day.toEpochDay() / 1.7)
            seeder.basalPerDay(day, 1_780.0 + (abs(wave) * 30.0))
            if (offset == 0L) {
                val end = now.toLocalTime().minusMinutes(5).takeIf { it.isAfter(LocalTime.of(7, 30)) } ?: LocalTime.of(7, 30)
                val share = (end.toSecondOfDay() - 7 * 3600) / (14.0 * 3600).coerceAtLeast(1.0)
                seeder.active(day, active * share.coerceIn(0.1, 1.0), to = end)
                seeder.steps(day, (steps * share.coerceIn(0.1, 1.0)).toLong(), to = end)
                seeder.food(day, 1_240.0, LocalTime.of(8, 10))
            } else {
                seeder.active(day, active)
                seeder.steps(day, steps)
                if (offset % 9L != 0L) seeder.food(day, food)
            }
        }
        graph.settings.saveGoals(calories = 2_800, steps = 10_000)
    }
}
