package com.jackwallner.vitals.data

import com.jackwallner.vitals.model.PacingComparison
import com.jackwallner.vitals.model.PacingLookback
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SettingsAndCelebrationTest {
    private val today = LocalDate.of(2026, 7, 16)

    @Test fun defaultsMatchTheIosUserDefaults() {
        val s = AppSettings(InMemoryStore())
        assertFalse(s.hasCompletedSetup)
        assertEquals(2_500.0, s.calorieGoal)
        assertEquals(10_000, s.stepGoal)
        assertTrue(s.showCalories && s.showSteps && s.showPacing)
        assertFalse(s.showNet || s.showStreaks || s.showProjections || s.showEnergyAverages || s.showActiveResting)
        assertEquals(PacingComparison.DAY_OF_WEEK, s.pacingComparison)
        assertEquals(PacingLookback.THIRTY, s.pacingLookback)
        assertEquals(Appearance.SYSTEM, s.appearance)
        assertNull(s.logsFoodInHealth)
    }

    @Test fun goalsSaveThroughTheSameKeysAndNullTurnsAGoalOff() {
        val store = InMemoryStore()
        AppSettings(store).saveGoals(3_000, null)
        val reloaded = AppSettings(store)
        assertEquals(3_000.0, reloaded.calorieGoal)
        assertNull(reloaded.stepGoal)
        assertEquals(3_000, store.getInt("calorieGoal"))
        assertFalse(store.getBoolean("stepGoalEnabled", true))
    }

    @Test fun excludedDaysAreProOnlyAndSurviveLapse() {
        var pro = true
        val s = AppSettings(InMemoryStore()) { pro }
        s.setExcluded(LocalDate.of(2026, 7, 3), true)
        assertEquals(setOf("2026-07-03"), s.excludedKeys(today))
        pro = false
        assertTrue(s.excludedKeys(today).isEmpty())
        pro = true
        assertEquals(setOf("2026-07-03"), s.excludedKeys(today))
    }

    @Test fun pauseExcludesEveryDayThroughTodayAndResumeKeepsThem() {
        val s = AppSettings(InMemoryStore()) { true }
        s.pauseAverages(today.minusDays(2))
        assertTrue(s.isAveragesPaused)
        assertEquals(3, s.excludedKeys(today).size)
        s.resumeAverages(today)
        assertFalse(s.isAveragesPaused)
        assertEquals(3, s.excludedKeys(today.plusDays(5)).size)
    }

    @Test fun clearingTheLastPickedDayRemovesTheKey() {
        val store = InMemoryStore()
        val s = AppSettings(store) { true }
        s.setExcluded(today, true)
        assertTrue(store.contains("excludedDays"))
        s.setExcluded(today, false)
        assertFalse(store.contains("excludedDays"))
    }

    @Test fun lapsedSubscriberSwitchesProFeaturesBackOff() {
        val s = AppSettings(InMemoryStore()) { true }
        s.showNet = true
        s.showStreaks = true
        s.switchOffProFeatures()
        assertFalse(s.showNet || s.showStreaks)
    }

    @Test fun celebrationFiresOncePerGoalPerDay() {
        var date = today
        val c = GoalCelebration(InMemoryStore()) { date }
        assertNull(c.check(2_000.0, 2_500.0, 5_000, 10_000))
        assertEquals("Calorie goal reached!", c.check(2_600.0, 2_500.0, 5_000, 10_000))
        assertNull(c.check(2_700.0, 2_500.0, 5_000, 10_000))
        assertEquals("Step goal reached!", c.check(2_700.0, 2_500.0, 10_500, 10_000))
        date = today.plusDays(1)
        assertEquals("Both goals reached!", c.check(2_600.0, 2_500.0, 10_500, 10_000))
    }

    @Test fun celebrationIgnoresMissingGoals() {
        val c = GoalCelebration(InMemoryStore()) { today }
        assertNull(c.check(9_000.0, null, 99_000, null))
    }
}
