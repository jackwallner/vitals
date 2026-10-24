package com.jackwallner.vitals.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.vitals.model.ExcludedDays
import com.jackwallner.vitals.model.PacingComparison
import com.jackwallner.vitals.model.PacingLookback
import java.time.LocalDate

enum class Appearance(val raw: Int, val label: String) {
    SYSTEM(0, "System"), LIGHT(1, "Light"), DARK(2, "Dark");

    companion object { fun from(raw: Int) = entries.firstOrNull { it.raw == raw } ?: SYSTEM }
}

/**
 * `GoalSettings` for Android: the same UserDefaults keys iOS uses, backed by the
 * KeyValueStore so JVM tests run against an in-memory store. Reads are Compose
 * state, so a toggle in Settings repaints Today at once.
 */
class AppSettings(private val defaults: KeyValueStore, private val isPro: () -> Boolean = { false }) {
    private fun bool(key: String, fallback: Boolean) = defaults.getBoolean(key, fallback)

    var hasCompletedSetup by mutableStateOf(bool("hasCompletedSetup", false))
        private set
    fun completeSetup() { hasCompletedSetup = true; defaults.putBoolean("hasCompletedSetup", true) }

    /** Onboarding's food question: null until asked. Decides whether the first prompt carries nutrition. */
    var logsFoodInHealth by mutableStateOf(if (defaults.contains("logsFoodInHealth")) bool("logsFoodInHealth", false) else null)
        private set
    fun setLogsFood(value: Boolean) { logsFoodInHealth = value; defaults.putBoolean("logsFoodInHealth", value) }

    var calorieGoalEnabled by mutableStateOf(bool("calorieGoalEnabled", true))
    var calorieGoalValue by mutableIntStateOf(defaults.getInt("calorieGoal", 2500))
    var stepGoalEnabled by mutableStateOf(bool("stepGoalEnabled", true))
    var stepGoalValue by mutableIntStateOf(defaults.getInt("stepGoal", 10_000))

    val calorieGoal: Double? get() = if (calorieGoalEnabled) calorieGoalValue.toDouble() else null
    val stepGoal: Int? get() = if (stepGoalEnabled) stepGoalValue else null

    fun saveGoals(calories: Int?, steps: Int?) {
        calorieGoalEnabled = calories != null
        if (calories != null) { calorieGoalValue = calories; defaults.putInt("calorieGoal", calories) }
        defaults.putBoolean("calorieGoalEnabled", calorieGoalEnabled)
        stepGoalEnabled = steps != null
        if (steps != null) { stepGoalValue = steps; defaults.putInt("stepGoal", steps) }
        defaults.putBoolean("stepGoalEnabled", stepGoalEnabled)
    }

    private fun flag(key: String, fallback: Boolean) = Flag(key, fallback)

    inner class Flag(private val key: String, fallback: Boolean) {
        private var state by mutableStateOf(bool(key, fallback))
        operator fun getValue(owner: Any?, property: Any?): Boolean = state
        operator fun setValue(owner: Any?, property: Any?, value: Boolean) {
            state = value
            defaults.putBoolean(key, value)
        }
    }

    var showCalories by flag("showCalories", true)
    var showSteps by flag("showSteps", true)
    var showPacing by flag("showPacing", true)
    var showActiveResting by flag("showActiveRestingBreakdown", false)
    var showEnergyAverages by flag("showEnergyAverages", false)
    var showProjections by flag("showProjections", false)
    var showStreaks by flag("showStreaks", false)
    var showNet by flag("showNetCalories", false)
    var netFasting by flag("netDeficitFastingMode", false)

    var pacingComparison by mutableStateOf(PacingComparison.from(defaults.getInt("pacingComparison", 0)))
        private set
    var pacingLookback by mutableStateOf(PacingLookback.from(defaults.getInt("pacingLookbackDays", 30)))
        private set
    fun choosePacingComparison(value: PacingComparison) { pacingComparison = value; defaults.putInt("pacingComparison", value.raw) }
    fun choosePacingLookback(value: PacingLookback) { pacingLookback = value; defaults.putInt("pacingLookbackDays", value.days) }

    var appearance by mutableStateOf(Appearance.from(defaults.getInt("appearance", 0)))
        private set
    fun chooseAppearance(value: Appearance) { appearance = value; defaults.putInt("appearance", value.raw) }

    // Excluded days (Vitals+): picked days plus a running pause.
    private var picked by mutableStateOf(defaults.getStringSet(ExcludedDays.PICKED_KEY))
    var pausedSince by mutableStateOf(
        defaults.getString(ExcludedDays.PAUSED_SINCE_KEY)?.let { runCatching { LocalDate.parse(it) }.getOrNull() },
    )
        private set

    val pickedExcludedKeys: Set<String> get() = picked
    val isAveragesPaused: Boolean get() = isPro() && pausedSince != null

    /** The set every figure filters on. Empty for free users: the feature is Vitals+. */
    fun excludedKeys(today: LocalDate): Set<String> =
        if (!isPro()) emptySet() else picked + ExcludedDays.pausedKeys(pausedSince, today)

    fun setExcluded(date: LocalDate, excluded: Boolean) {
        val key = ExcludedDays.key(date)
        picked = if (excluded) picked + key else picked - key
        persistPicked()
    }

    fun setPickedExcluded(keys: Set<String>) { picked = keys; persistPicked() }

    private fun persistPicked() {
        if (picked.isEmpty()) defaults.remove(ExcludedDays.PICKED_KEY) else defaults.putStringSet(ExcludedDays.PICKED_KEY, picked)
    }

    fun pauseAverages(today: LocalDate) {
        pausedSince = today
        defaults.putString(ExcludedDays.PAUSED_SINCE_KEY, today.toString())
    }

    /** Resuming freezes the paused days into the picked set so the record survives. */
    fun resumeAverages(today: LocalDate) {
        val since = pausedSince ?: return
        picked = picked + ExcludedDays.pausedKeys(since, today)
        persistPicked()
        pausedSince = null
        defaults.remove(ExcludedDays.PAUSED_SINCE_KEY)
    }
}
