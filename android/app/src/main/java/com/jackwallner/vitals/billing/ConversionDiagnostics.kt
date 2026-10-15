package com.jackwallner.vitals.billing

import com.jackwallner.vitals.data.DAY_MS
import com.jackwallner.vitals.data.KeyValueStore

/**
 * On-device record of how someone met the Vitals+ pitch before buying, mirrored
 * onto the RevenueCat customer as attributes. Counts, dates and surface names
 * only; no health data.
 */
class ConversionDiagnostics(
    private val defaults: KeyValueStore,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    fun recordAppOpen() {
        if (!defaults.contains(INSTALLED_AT)) defaults.putLong(INSTALLED_AT, nowMillis())
        defaults.putInt(APP_OPENS, defaults.getInt(APP_OPENS) + 1)
    }

    fun recordPitchView(impressionId: String) {
        val surface = impressionId.removePrefix(PREFIX)
        defaults.putInt(TOTAL_VIEWS, defaults.getInt(TOTAL_VIEWS) + 1)
        defaults.putInt(views(surface), defaults.getInt(views(surface)) + 1)
        defaults.putString(LAST_SURFACE, surface)
        if (!defaults.contains(FIRST_SEEN)) {
            defaults.putLong(FIRST_SEEN, nowMillis())
            defaults.putInt(OPENS_BEFORE_FIRST_PITCH, defaults.getInt(APP_OPENS))
            if (defaults.contains(INSTALLED_AT)) defaults.putInt(DAYS_TO_FIRST_PITCH, daysSince(defaults.getLong(INSTALLED_AT)))
        }
    }

    fun recordConversion(plan: String, offeringId: String?) {
        if (defaults.contains(CONVERTED_ON)) return
        defaults.putString(CONVERTED_ON, defaults.getString(LAST_SURFACE) ?: "unknown")
        defaults.putInt(VIEWS_AT_CONVERT, defaults.getInt(TOTAL_VIEWS))
        defaults.putString(CONVERTED_PLAN, plan)
        defaults.putLong(CONVERTED_AT, nowMillis())
        offeringId?.let { defaults.putString(CONVERTED_OFFERING, it) }
        if (defaults.contains(FIRST_SEEN)) defaults.putInt(DAYS_TO_CONVERT, daysSince(defaults.getLong(FIRST_SEEN)))
    }

    val subscriberAttributes: Map<String, String>
        get() {
            val total = defaults.getInt(TOTAL_VIEWS)
            if (total <= 0) return emptyMap()
            val out = mutableMapOf("pitch_views_total" to total.toString())
            defaults.keys().filter { it.startsWith(VIEWS_PREFIX) && it != TOTAL_VIEWS }.forEach { key ->
                val count = defaults.getInt(key)
                if (count > 0) out["pitch_views_${key.removePrefix(VIEWS_PREFIX)}".take(40)] = count.toString()
            }
            defaults.getString(LAST_SURFACE)?.let { out["pitch_last"] = it }
            if (defaults.contains(FIRST_SEEN)) {
                out["days_since_first_pitch"] = daysSince(defaults.getLong(FIRST_SEEN)).toString()
            }
            if (defaults.contains(OPENS_BEFORE_FIRST_PITCH)) out["opens_before_first_pitch"] = defaults.getInt(OPENS_BEFORE_FIRST_PITCH).toString()
            defaults.getString(CONVERTED_ON)?.let { surface ->
                out["converted_surface"] = surface
                out["pitch_views_at_convert"] = defaults.getInt(VIEWS_AT_CONVERT).toString()
                out["days_to_convert"] = defaults.getInt(DAYS_TO_CONVERT).toString()
                out["converted_plan"] = defaults.getString(CONVERTED_PLAN) ?: "unknown"
                defaults.getString(CONVERTED_OFFERING)?.let { out["converted_offering"] = it }
            }
            return out
        }

    private fun daysSince(millis: Long): Int = maxOf(0, ((nowMillis() - millis) / DAY_MS).toInt())
    private fun views(surface: String) = "$VIEWS_PREFIX$surface"

    private companion object {
        const val PREFIX = "vitals_"
        const val VIEWS_PREFIX = "conv.pitchViews."
        const val TOTAL_VIEWS = "conv.pitchViews.total"
        const val FIRST_SEEN = "conv.pitchFirstSeen"
        const val LAST_SURFACE = "conv.pitchLastSurface"
        const val INSTALLED_AT = "conv.installedAt"
        const val APP_OPENS = "conv.appOpens"
        const val OPENS_BEFORE_FIRST_PITCH = "conv.opensBeforeFirstPitch"
        const val DAYS_TO_FIRST_PITCH = "conv.daysToFirstPitch"
        const val CONVERTED_ON = "conv.convertedOn"
        const val CONVERTED_AT = "conv.convertedAt"
        const val VIEWS_AT_CONVERT = "conv.viewsAtConvert"
        const val DAYS_TO_CONVERT = "conv.daysToConvert"
        const val CONVERTED_PLAN = "conv.convertedPlan"
        const val CONVERTED_OFFERING = "conv.convertedOffering"
    }
}
