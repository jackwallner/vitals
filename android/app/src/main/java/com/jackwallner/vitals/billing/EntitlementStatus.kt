package com.jackwallner.vitals.billing

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.vitals.data.KeyValueStore

/** Unresolved billing keeps the last resolved access decision. */
class EntitlementStatus(private val defaults: KeyValueStore) {
    enum class Resolution { UNRESOLVED, ACTIVE, INACTIVE }

    var resolution by mutableStateOf(Resolution.UNRESOLVED)
        private set
    var isPro by mutableStateOf(defaults.getBoolean(CACHED_PRO_KEY))
        private set

    fun resolve(active: Boolean) {
        isPro = active
        resolution = if (active) Resolution.ACTIVE else Resolution.INACTIVE
        defaults.putBoolean(CACHED_PRO_KEY, active)
    }

    fun refreshFailed() {
        resolution = Resolution.UNRESOLVED
    }

    companion object {
        const val CACHED_PRO_KEY = "isProCached"
    }
}
