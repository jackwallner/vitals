package com.jackwallner.vitals

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.core.view.WindowCompat
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.lifecycleScope
import com.jackwallner.vitals.data.Appearance
import com.jackwallner.vitals.ui.LocalGraph
import com.jackwallner.vitals.ui.RootScreen
import com.jackwallner.vitals.ui.theme.VitalsTheme
import kotlinx.coroutines.launch

@OptIn(ExperimentalComposeUiApi::class)
class MainActivity : ComponentActivity() {
    private val graph: AppGraph get() = (application as VitalsApplication).graph

    private val healthPermissions = registerForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
        graph.permissions.complete(granted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val graph = graph
        graph.permissions.launch = { healthPermissions.launch(it) }
        if (savedInstanceState == null) {
            graph.review.recordAppLaunch()
            graph.review.recordTrackedDay()
            graph.diagnostics.recordAppOpen()
            DebugLaunchOptions.apply(graph, intent)
        }
        enableEdgeToEdge()
        lifecycleScope.launch { graph.store.start() }
        setContent {
            val dark = when (graph.settings.appearance) {
                Appearance.SYSTEM -> isSystemInDarkTheme()
                Appearance.LIGHT -> false
                Appearance.DARK -> true
            }
            val view = LocalView.current
            SideEffect {
                val controller = WindowCompat.getInsetsController(window, view)
                controller.isAppearanceLightStatusBars = !dark
                controller.isAppearanceLightNavigationBars = !dark
            }
            CompositionLocalProvider(LocalGraph provides graph) {
                VitalsTheme(dark = dark) {
                    // Test tags double as resource ids so UI Automator and capture scripts can find controls.
                    Box(Modifier.semantics { testTagsAsResourceId = true }) { RootScreen(graph) }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Renewals, restores and late grants flip the app promptly, like iOS's foreground refresh.
        lifecycleScope.launch { graph.store.refreshCustomerInfo() }
    }

    override fun onStop() {
        super.onStop()
        graph.store.syncConversionAttributes()
    }

    override fun onDestroy() {
        if (isFinishing) graph.permissions.launch = null
        super.onDestroy()
    }
}
