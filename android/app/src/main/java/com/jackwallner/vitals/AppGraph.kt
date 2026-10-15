package com.jackwallner.vitals

import android.content.Context
import androidx.glance.appwidget.updateAll
import com.jackwallner.vitals.billing.ConversionDiagnostics
import com.jackwallner.vitals.billing.StoreService
import com.jackwallner.vitals.data.AppSettings
import com.jackwallner.vitals.data.GoalCelebration
import com.jackwallner.vitals.data.HealthConnectSource
import com.jackwallner.vitals.data.HealthPermissionBridge
import com.jackwallner.vitals.data.HealthSource
import com.jackwallner.vitals.data.ReviewPromptTracker
import com.jackwallner.vitals.data.SharedPreferencesStore
import com.jackwallner.vitals.data.VitalsRepository
import com.jackwallner.vitals.widget.VitalsWidget
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/** Every long-lived object the screens share, built once per process. */
class AppGraph(context: Context) {
    val appContext: Context = context.applicationContext
    val scope = MainScope()
    val defaults = SharedPreferencesStore(appContext)
    val review = ReviewPromptTracker(defaults)
    val diagnostics = ConversionDiagnostics(defaults)
    val store = StoreService(appContext, defaults, diagnostics)
    val settings = AppSettings(defaults) { store.isPro }
    val health: HealthSource = HealthConnectSource(appContext)
    val repo = VitalsRepository(health, settings, defaults, onSnapshot = ::refreshWidgets)
    val celebration = GoalCelebration(defaults)
    val permissions = HealthPermissionBridge()

    /** The home-screen widget reads the snapshot the repository just wrote. */
    fun refreshWidgets() {
        scope.launch { runCatching { VitalsWidget().updateAll(appContext) } }
    }
}
