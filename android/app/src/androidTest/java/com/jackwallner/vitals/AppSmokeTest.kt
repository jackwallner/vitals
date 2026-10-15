package com.jackwallner.vitals

import android.content.Context
import android.content.Intent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** First-run path and the Vitals+ paid boundary, driven through the debug launch extras. */
@RunWith(AndroidJUnit4::class)
class AppSmokeTest {
    @get:Rule val compose = createEmptyComposeRule()
    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(vararg extras: Pair<String, Any>) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val intent = Intent(context, MainActivity::class.java).putExtra("resetAll", true)
        extras.forEach { (key, value) ->
            when (value) {
                is Boolean -> intent.putExtra(key, value)
                is String -> intent.putExtra(key, value)
            }
        }
        scenario = ActivityScenario.launch(intent)
    }

    @After fun tearDown() { scenario?.close() }

    @Test fun firstRunMovesFromGoalsToTheTrialPage() {
        launch("onboardingStep" to "goals", "previewStore" to true, "appearance" to "light")
        compose.onNodeWithText("Set your daily goals").assertIsDisplayed()
        compose.onNodeWithText("Continue").performClick()
        compose.onNodeWithText("Go further with Vitals+").assertIsDisplayed()
        compose.onNodeWithText("Get Started").assertIsDisplayed()
    }

    @Test fun freeUserLandsOnTodayWithTheRing() {
        launch("completeSetup" to true, "tab" to "today", "appearance" to "light")
        compose.waitUntil(15_000) { compose.onAllNodesWithTextCount("Today") > 0 }
        compose.onAllNodes(hasText("Today")).onFirst().assertIsDisplayed()
        compose.onAllNodes(hasText("History")).onFirst().assertIsDisplayed()
        compose.onAllNodes(hasText("Upgrade")).onFirst().assertIsDisplayed()
    }

    @Test fun lockedSettingRaisesThePaywallInsteadOfTurningOn() {
        launch("completeSetup" to true, "overlay" to "settings", "previewStore" to true, "appearance" to "light")
        compose.waitUntil(15_000) { compose.onAllNodesWithTextCount("Active + Resting Breakdown") > 0 }
        compose.onNodeWithText("Unlock Vitals+").assertIsDisplayed()
        compose.onNodeWithText("Unlock Vitals+").performClick()
        compose.waitUntil(10_000) { compose.onAllNodesWithTextCount("Start My Free Trial") > 0 }
    }

    @Test fun proUserSeesActiveStatusAndNoUpsell() {
        launch("completeSetup" to true, "overlay" to "settings", "demoPro" to true, "appearance" to "light")
        compose.waitUntil(15_000) { compose.onAllNodesWithTextCount("Vitals+ Active") > 0 }
        compose.onNodeWithText("Vitals+ Active").assertIsDisplayed()
        assertEquals(0, compose.onAllNodesWithTextCount("Unlock Vitals+"))
    }

    @Test fun proTabListsEveryPaidTool() {
        launch("completeSetup" to true, "tab" to "upgrade", "demoPro" to true, "appearance" to "light")
        compose.waitUntil(15_000) { compose.onAllNodesWithTextCount("Excluded Days") > 0 }
        compose.onAllNodes(hasText("Net Deficit")).onFirst().assertIsDisplayed()
        compose.onAllNodes(hasText("Excluded Days")).onFirst().assertIsDisplayed()
    }

    @Test fun freeUserOpeningExcludedDaysSeesTheLockedPitch() {
        launch("completeSetup" to true, "overlay" to "excluded", "previewStore" to true, "appearance" to "light")
        compose.waitUntil(15_000) { compose.onAllNodesWithTextCount("Try Excluded Days") > 0 }
        compose.onNodeWithText("Try Excluded Days").performClick()
        compose.waitUntil(10_000) { compose.onAllNodesWithTextCount("Start My Free Trial") > 0 }
    }

    private fun androidx.compose.ui.test.junit4.ComposeTestRule.onAllNodesWithTextCount(text: String): Int =
        onAllNodes(hasText(text)).fetchSemanticsNodes().size
}
