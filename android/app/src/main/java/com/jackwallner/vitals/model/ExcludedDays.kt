package com.jackwallner.vitals.model

import java.time.LocalDate

/**
 * Days the user has taken out of everything the app computes (Vitals+). The
 * data is never deleted: excluded days stay in charts (dimmed), in Recent Days
 * and in the CSV, and are neutral for streaks. Keys are "yyyy-MM-dd", the same
 * spelling iOS stores, so a day has one identity across the app.
 */
object ExcludedDays {
    const val PICKED_KEY = "excludedDays"
    const val PAUSED_SINCE_KEY = "averagesPausedSince"

    fun key(date: LocalDate): String = date.toString()

    fun date(key: String): LocalDate? = runCatching { LocalDate.parse(key) }.getOrNull()

    /** Every day covered by a running pause: the pause day through today, inclusive. */
    fun pausedKeys(since: LocalDate?, today: LocalDate): Set<String> {
        if (since == null || since.isAfter(today)) return emptySet()
        val keys = HashSet<String>()
        var cursor: LocalDate = since
        while (!cursor.isAfter(today)) {
            keys += key(cursor)
            cursor = cursor.plusDays(1)
        }
        return keys
    }

    fun contains(date: LocalDate, keys: Set<String>): Boolean = keys.isNotEmpty() && key(date) in keys
}
