package com.jackwallner.vitals.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.vitals.model.DayStats
import com.jackwallner.vitals.model.TodayCalculator
import java.time.LocalDate
import java.time.LocalDateTime
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Why the Today screen has nothing to show. Mirrors `HealthNotice` on iOS. */
enum class HealthNotice(val title: String, val message: String, val button: String?) {
    UNAVAILABLE(
        "Health Connect needed",
        "Total Calories reads your calories and steps from Health Connect. Install or update it, then come back.",
        "Get Health Connect",
    ),
    ACCESS_NEEDED(
        "Health access needed",
        "Allow Health Connect access so Total Calories can load your active calories, resting calories, and steps.",
        "Enable Health",
    ),
    ACCESS_BLOCKED(
        "Health access is off",
        "In Health Connect: App permissions > Total Calories, then turn on each category to load your data.",
        "Open Health Connect",
    ),
    NO_DATA(
        "No Health data yet",
        "If you just granted access, Health Connect may still be catching up. Make sure a watch or fitness app is writing to it.",
        "Open Health Connect",
    ),
    LOAD_ERROR(
        "Couldn't refresh Health data",
        "Try reopening the app in a moment, or check Health Connect access.",
        "Open Health Connect",
    ),
}

/**
 * The app's one live view of Health Connect: the fetched window behind Today,
 * today's food for Net Deficit, and the notice when there is nothing to show.
 * History loads its own ranges through [stats] and [food].
 */
class VitalsRepository(
    private val source: HealthSource,
    private val settings: AppSettings,
    private val defaults: KeyValueStore,
    private val clock: () -> LocalDateTime = LocalDateTime::now,
    private val onSnapshot: () -> Unit = {},
) {
    var window by mutableStateOf<List<DayStats>>(emptyList())
        private set
    var foodToday by mutableStateOf(0.0)
        private set
    var foodReady by mutableStateOf(false)
        private set
    var foodFailed by mutableStateOf(false)
        private set
    var notice by mutableStateOf<HealthNotice?>(null)
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    var hasLoaded by mutableStateOf(false)
        private set
    var lastRefresh by mutableStateOf<LocalDateTime?>(null)
        private set
    var hasHistoryAccess by mutableStateOf(false)
        private set
    var hasFoodAccess by mutableStateOf(false)
        private set

    private val lock = Mutex()

    fun now(): LocalDateTime = clock()

    suspend fun stats(start: LocalDate, end: LocalDate): List<DayStats> = source.stats(start, end, clock())
    suspend fun food(start: LocalDate, end: LocalDate): Map<LocalDate, Double> = source.food(start, end, clock())
    suspend fun access(): HealthAccess = source.access()

    /** Reloads the window behind Today. Safe to call from every resume; overlapping calls queue. */
    suspend fun refresh(wantsFood: Boolean) = lock.withLock {
        isRefreshing = true
        try {
            val access = source.access()
            hasFoodAccess = source.hasFoodAccess()
            hasHistoryAccess = source.hasHistoryAccess()
            when (access) {
                HealthAccess.UNAVAILABLE -> notice = HealthNotice.UNAVAILABLE
                HealthAccess.NEEDS_PERMISSION -> notice = if (defaults.getBoolean(ASKED_KEY)) HealthNotice.ACCESS_BLOCKED else HealthNotice.ACCESS_NEEDED
                HealthAccess.READY -> load(wantsFood)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            if (window.none { it.hasData }) notice = HealthNotice.LOAD_ERROR
        } finally {
            isRefreshing = false
            hasLoaded = true
        }
    }

    fun markPermissionAsked() = defaults.putBoolean(ASKED_KEY, true)

    private suspend fun load(wantsFood: Boolean) {
        val now = clock()
        val today = now.toLocalDate()
        val days = TodayCalculator.windowDays(settings.pacingLookback)
        val rows = source.stats(today.minusDays(days.toLong()), today, now)
        window = rows
        lastRefresh = now
        val todayRow = rows.lastOrNull()
        notice = if (rows.none { it.hasData }) HealthNotice.NO_DATA else null
        if (wantsFood && hasFoodAccess) {
            runCatching { source.food(today, today, now) }
                .onSuccess { foodToday = it[today] ?: 0.0; foodReady = true; foodFailed = false }
                .onFailure { if (it is CancellationException) throw it; foodFailed = true; foodReady = false }
        } else {
            foodReady = false
            foodFailed = wantsFood && !hasFoodAccess
        }
        if (todayRow != null) writeSnapshot(todayRow, now)
    }

    /** The home-screen widget reads this, never Health Connect, so it paints at once. */
    private fun writeSnapshot(day: DayStats, now: LocalDateTime) {
        defaults.putString(WidgetSnapshot.CALORIES, day.total.toString())
        defaults.putInt(WidgetSnapshot.STEPS, day.steps)
        defaults.putString(WidgetSnapshot.DAY, now.toLocalDate().toString())
        defaults.putLong(WidgetSnapshot.UPDATED, System.currentTimeMillis())
        settings.calorieGoal?.let { defaults.putString(WidgetSnapshot.CALORIE_GOAL, it.toString()) } ?: defaults.remove(WidgetSnapshot.CALORIE_GOAL)
        settings.stepGoal?.let { defaults.putInt(WidgetSnapshot.STEP_GOAL, it) } ?: defaults.remove(WidgetSnapshot.STEP_GOAL)
        onSnapshot()
    }

    companion object {
        private const val ASKED_KEY = "healthPermissionAsked"
    }
}

/** Keys shared between the repository and the Glance widget. */
object WidgetSnapshot {
    const val CALORIES = "widget.calories"
    const val STEPS = "widget.steps"
    const val DAY = "widget.day"
    const val UPDATED = "widget.updated"
    const val CALORIE_GOAL = "widget.calorieGoal"
    const val STEP_GOAL = "widget.stepGoal"
}

/** One celebration per goal per day, so crossing a goal buzzes once and not on every refresh. */
class GoalCelebration(private val defaults: KeyValueStore, private val today: () -> LocalDate = LocalDate::now) {
    /** Returns the banner text when this refresh newly crosses a goal today, or null. */
    fun check(calories: Double, calorieGoal: Double?, steps: Int, stepGoal: Int?): String? {
        val key = today().toString()
        var crossedCalories = false
        var crossedSteps = false
        if (calorieGoal != null && calorieGoal > 0 && calories >= calorieGoal && defaults.getString(CALORIE_KEY) != key) {
            defaults.putString(CALORIE_KEY, key)
            crossedCalories = true
        }
        if (stepGoal != null && stepGoal > 0 && steps >= stepGoal && defaults.getString(STEP_KEY) != key) {
            defaults.putString(STEP_KEY, key)
            crossedSteps = true
        }
        return when {
            crossedCalories && crossedSteps -> "Both goals reached!"
            crossedCalories -> "Calorie goal reached!"
            crossedSteps -> "Step goal reached!"
            else -> null
        }
    }

    private companion object {
        const val CALORIE_KEY = "goalCelebration.calorieDate"
        const val STEP_KEY = "goalCelebration.stepDate"
    }
}
