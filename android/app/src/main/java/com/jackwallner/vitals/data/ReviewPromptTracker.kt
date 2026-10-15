package com.jackwallner.vitals.data

import java.time.LocalDate

/** What the user did about a review. Only opening the write-review page ends the passive asks. */
enum class ReviewOutcome(val raw: String) {
    OPENED_WRITE_REVIEW("openedWriteReview"),
    SUBMITTED_FEEDBACK("submittedFeedback"),
}

/**
 * Port of `ReviewPromptTracker.swift`: launch counts, positive moments and
 * eligibility for the rating ask, with the same keys and thresholds. On Android
 * the ask is Google's in-app review card, called directly with no enjoyment
 * question first and never from a button.
 */
class ReviewPromptTracker(
    private val defaults: KeyValueStore,
    private val nowMillis: () -> Long = System::currentTimeMillis,
    private val today: () -> LocalDate = LocalDate::now,
) {
    var appLaunchCount: Int
        get() = maxOf(defaults.getInt(LAUNCH_COUNT), 0)
        private set(value) = defaults.putInt(LAUNCH_COUNT, value)

    var positiveMomentCount: Int
        get() = maxOf(defaults.getInt(MOMENT_COUNT), 0)
        private set(value) = defaults.putInt(MOMENT_COUNT, value)

    var trackedDayCount: Int
        get() = maxOf(defaults.getInt(TRACKED_DAYS), 0)
        private set(value) = defaults.putInt(TRACKED_DAYS, value)

    val hasPendingPositiveMoment: Boolean get() = defaults.getBoolean(PENDING)

    val outcome: ReviewOutcome?
        get() = defaults.getString(OUTCOME)?.let { raw -> ReviewOutcome.entries.firstOrNull { it.raw == raw } }

    val lastShownMillis: Long? get() = if (defaults.contains(LAST_SHOWN)) defaults.getLong(LAST_SHOWN) else null

    /** Once per process launch. */
    fun recordAppLaunch() {
        if (!defaults.contains(FIRST_OPEN)) defaults.putLong(FIRST_OPEN, nowMillis())
        appLaunchCount += 1
    }

    /** A satisfaction moment, such as a daily goal reached. */
    fun recordPositiveMoment() {
        positiveMomentCount += 1
        defaults.putBoolean(PENDING, true)
    }

    /** Distinct days the app was opened. Reports whether this is the launch that crossed seven. Fires once ever. */
    fun recordTrackedDay(): Boolean {
        val day = today().toString()
        if (defaults.getString(LAST_TRACKED_DAY) == day) return false
        defaults.putString(LAST_TRACKED_DAY, day)
        trackedDayCount += 1
        if (trackedDayCount < MINIMUM_TRACKED_DAYS || defaults.getBoolean(HABIT_FIRED)) return false
        defaults.putBoolean(HABIT_FIRED, true)
        recordPositiveMoment()
        return true
    }

    /** A paying subscriber who has kept Vitals+ for 30 days is the best-disposed user the app has. Fires once ever. */
    fun recordProStatus(isPro: Boolean): Boolean {
        if (!isPro) return false
        if (!defaults.contains(PRO_SINCE)) {
            defaults.putLong(PRO_SINCE, nowMillis())
            return false
        }
        val elapsed = nowMillis() - defaults.getLong(PRO_SINCE)
        if (elapsed < SUBSCRIBER_MOMENT_DAYS * DAY_MS || defaults.getBoolean(SUBSCRIBER_FIRED)) return false
        defaults.putBoolean(SUBSCRIBER_FIRED, true)
        recordPositiveMoment()
        return true
    }

    /** A milestone that counts once, keyed by what caused it (`report_exported`, `streak_30`). Returns whether it fired. */
    fun recordOneShotPositiveMoment(key: String): Boolean {
        val storageKey = "reviewPrompt.oneShot.$key"
        if (defaults.getBoolean(storageKey)) return false
        defaults.putBoolean(storageKey, true)
        recordPositiveMoment()
        return true
    }

    fun consumePendingPositiveMoment() = defaults.putBoolean(PENDING, false)

    fun passivePromptAllowed(): Boolean {
        if (outcome == ReviewOutcome.OPENED_WRITE_REVIEW) return false
        val last = lastShownMillis ?: return true
        return nowMillis() - last >= COOLDOWN_DAYS * DAY_MS
    }

    fun canRequestReview(hasCompletedSetup: Boolean): Boolean {
        if (!hasCompletedSetup || !passivePromptAllowed()) return false
        return appLaunchCount >= MINIMUM_LAUNCH_COUNT
    }

    fun shouldShowAfterPositiveMoment(hasCompletedSetup: Boolean): Boolean =
        hasPendingPositiveMoment && canRequestReview(hasCompletedSetup)

    fun markShown() {
        defaults.putLong(LAST_SHOWN, nowMillis())
        consumePendingPositiveMoment()
    }

    fun markOpenedWriteReview() {
        defaults.putString(OUTCOME, ReviewOutcome.OPENED_WRITE_REVIEW.raw)
        markShown()
    }

    /** Never overwrites `OPENED_WRITE_REVIEW`: feedback sent after the review page must not reopen the asks. */
    fun markFeedbackSubmitted() {
        if (outcome != ReviewOutcome.OPENED_WRITE_REVIEW) defaults.putString(OUTCOME, ReviewOutcome.SUBMITTED_FEEDBACK.raw)
        markShown()
    }

    companion object {
        const val MINIMUM_LAUNCH_COUNT = 2
        const val MINIMUM_TRACKED_DAYS = 7
        const val SUBSCRIBER_MOMENT_DAYS = 30
        const val COOLDOWN_DAYS = 30

        private const val LAUNCH_COUNT = "reviewPrompt.appLaunchCount"
        private const val FIRST_OPEN = "reviewPrompt.firstAppOpenDate"
        private const val LAST_SHOWN = "reviewPrompt.lastShownDate"
        private const val OUTCOME = "reviewPrompt.outcome"
        private const val MOMENT_COUNT = "reviewPrompt.positiveMomentCount"
        private const val PENDING = "reviewPrompt.pendingPositiveMoment"
        private const val TRACKED_DAYS = "reviewPrompt.trackedDayCount"
        private const val LAST_TRACKED_DAY = "reviewPrompt.lastTrackedDay"
        private const val HABIT_FIRED = "reviewPrompt.habitMomentFired"
        private const val PRO_SINCE = "reviewPrompt.proSince"
        private const val SUBSCRIBER_FIRED = "reviewPrompt.subscriberMomentFired"
    }
}
