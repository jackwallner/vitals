package com.jackwallner.vitals.billing

import com.jackwallner.vitals.data.AppSettings
import com.jackwallner.vitals.data.InMemoryStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class EntitlementStatusTest {
    @Test fun cachedSubscriberHasAccessBeforeFirstResponseAndAfterFailure() {
        val defaults = InMemoryStore()
        defaults.putBoolean(EntitlementStatus.CACHED_PRO_KEY, true)
        val status = EntitlementStatus(defaults)
        assertEquals(EntitlementStatus.Resolution.UNRESOLVED, status.resolution)
        assertTrue(status.isPro)
        status.refreshFailed()
        assertEquals(EntitlementStatus.Resolution.UNRESOLVED, status.resolution)
        assertTrue(status.isPro)
        assertTrue(EntitlementStatus(defaults).isPro)
    }

    @Test fun unresolvedWithoutCachedAccessDoesNotGrantPro() {
        val status = EntitlementStatus(InMemoryStore())
        status.refreshFailed()
        assertEquals(EntitlementStatus.Resolution.UNRESOLVED, status.resolution)
        assertFalse(status.isPro)
    }

    @Test fun confirmedLapseReplacesCacheAndRetryCanRestoreAccess() {
        val defaults = InMemoryStore()
        defaults.putBoolean(EntitlementStatus.CACHED_PRO_KEY, true)
        val status = EntitlementStatus(defaults)
        status.resolve(false)
        assertEquals(EntitlementStatus.Resolution.INACTIVE, status.resolution)
        assertFalse(status.isPro)
        status.refreshFailed()
        assertFalse(status.isPro)
        assertFalse(EntitlementStatus(defaults).isPro)
        status.resolve(true)
        assertEquals(EntitlementStatus.Resolution.ACTIVE, status.resolution)
        status.refreshFailed()
        assertTrue(status.isPro)
        assertTrue(EntitlementStatus(defaults).isPro)
    }

    @Test fun savedPaidLayoutSurvivesDelayedResponseFailureAndConfirmedLapse() {
        val defaults = InMemoryStore()
        val keys = listOf("showActiveRestingBreakdown", "showEnergyAverages", "showProjections", "showStreaks", "showNetCalories")
        keys.forEach { defaults.putBoolean(it, true) }
        val status = EntitlementStatus(defaults)
        val settings = AppSettings(defaults) { status.isPro }
        fun assertLayoutSaved() {
            assertTrue(settings.showActiveResting && settings.showEnergyAverages && settings.showProjections && settings.showStreaks && settings.showNet)
            keys.forEach { assertTrue(defaults.getBoolean(it)) }
        }
        assertLayoutSaved()
        status.refreshFailed()
        assertLayoutSaved()
        status.resolve(false)
        assertLayoutSaved()
        status.resolve(true)
        assertTrue(status.isPro)
        assertLayoutSaved()
    }
}
