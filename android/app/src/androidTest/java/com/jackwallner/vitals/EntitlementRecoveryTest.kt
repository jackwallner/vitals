package com.jackwallner.vitals

import android.content.Context
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jackwallner.vitals.billing.EntitlementStatus
import com.jackwallner.vitals.ui.LocalGraph
import com.jackwallner.vitals.ui.RootScreen
import com.jackwallner.vitals.ui.theme.VitalsTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EntitlementRecoveryTest {
    @get:Rule val compose = createComposeRule()

    @Test fun coldStartKeepsPaidLayoutWhileCustomerInfoIsDelayed() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = context.getSharedPreferences("vitals", Context.MODE_PRIVATE)
        val keys = listOf("showActiveRestingBreakdown", "showEnergyAverages", "showProjections", "showStreaks", "showNetCalories")
        prefs.edit().clear().apply {
            keys.forEach { putBoolean(it, true) }
        }.commit()
        val graph = AppGraph(context)
        graph.settings.completeSetup()
        graph.store.loadPreviewPlans(emptyList())

        compose.setContent {
            CompositionLocalProvider(LocalGraph provides graph) {
                VitalsTheme(dark = false) { RootScreen(graph) }
            }
        }
        compose.runOnIdle {
            assertEquals(EntitlementStatus.Resolution.UNRESOLVED, graph.store.entitlementStatus.resolution)
            keys.forEach { assertTrue("Saved $it was cleared before billing resolved", prefs.getBoolean(it, false)) }
            graph.store.entitlementStatus.resolve(true)
        }
        compose.runOnIdle {
            assertTrue(graph.store.isPro)
            graph.store.entitlementStatus.refreshFailed()
        }
        compose.runOnIdle {
            assertTrue(graph.store.isPro)
            assertEquals(EntitlementStatus.Resolution.UNRESOLVED, graph.store.entitlementStatus.resolution)
            keys.forEach { assertTrue(prefs.getBoolean(it, false)) }
            assertTrue(graph.settings.showActiveResting && graph.settings.showEnergyAverages && graph.settings.showProjections && graph.settings.showStreaks && graph.settings.showNet)
        }
    }
}
