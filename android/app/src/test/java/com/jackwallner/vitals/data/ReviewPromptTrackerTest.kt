package com.jackwallner.vitals.data

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Ports `ReviewPromptTrackerTests`: ask from launch 2, 30-day cooldown, only the review page ends the asks. */
class ReviewPromptTrackerTest {
    private val day = 86_400_000L
    private var now = 1_800_000_000_000L
    private var date = LocalDate.of(2026, 7, 1)
    private val store = InMemoryStore()
    private val tracker = ReviewPromptTracker(store, { now }, { date })

    private fun launches(count: Int) = repeat(count) { tracker.recordAppLaunch() }

    @Test fun asksFromTheSecondLaunch() {
        launches(2)
        assertTrue(tracker.canRequestReview(true))
    }

    @Test fun neverAsksInTheFirstSession() {
        launches(1)
        assertFalse(tracker.canRequestReview(true))
    }

    @Test fun requiresFinishedSetup() {
        launches(9)
        assertFalse(tracker.canRequestReview(false))
    }

    @Test fun waitsOutTheCooldown() {
        launches(9)
        tracker.markShown()
        now += 29 * day
        assertFalse(tracker.canRequestReview(true))
        now += 2 * day
        assertTrue(tracker.canRequestReview(true))
    }

    @Test fun openingTheReviewPageEndsTheAsks() {
        launches(9)
        tracker.markOpenedWriteReview()
        now += 400 * day
        assertFalse(tracker.canRequestReview(true))
    }

    @Test fun feedbackDoesNotStopTheAsks() {
        launches(9)
        tracker.markFeedbackSubmitted()
        now += 31 * day
        assertTrue(tracker.canRequestReview(true))
    }

    @Test fun feedbackAfterTheReviewPageKeepsTheAsksEnded() {
        launches(9)
        tracker.markOpenedWriteReview()
        tracker.markFeedbackSubmitted()
        assertEquals(ReviewOutcome.OPENED_WRITE_REVIEW, tracker.outcome)
        now += 400 * day
        assertFalse(tracker.canRequestReview(true))
    }

    @Test fun blockedAskKeepsTheMomentPending() {
        launches(9)
        tracker.recordPositiveMoment()
        assertTrue(tracker.shouldShowAfterPositiveMoment(true))
        assertTrue(tracker.shouldShowAfterPositiveMoment(true))
        tracker.markShown()
        assertFalse(tracker.shouldShowAfterPositiveMoment(true))
    }

    @Test fun seventhDistinctDayFiresTheHabitMomentOnce() {
        var fired = 0
        repeat(10) {
            if (tracker.recordTrackedDay()) fired++
            date = date.plusDays(1)
        }
        assertEquals(1, fired)
        assertEquals(10, tracker.trackedDayCount)
        assertTrue(tracker.hasPendingPositiveMoment)
    }

    @Test fun sameDayDoesNotCountTwice() {
        tracker.recordTrackedDay()
        assertFalse(tracker.recordTrackedDay())
        assertEquals(1, tracker.trackedDayCount)
    }

    @Test fun subscriberMomentFiresAfterThirtyDaysOnce() {
        assertFalse(tracker.recordProStatus(false))
        assertFalse(tracker.recordProStatus(true))
        now += 29 * day
        assertFalse(tracker.recordProStatus(true))
        now += 2 * day
        assertTrue(tracker.recordProStatus(true))
        assertFalse(tracker.recordProStatus(true))
    }

    @Test fun oneShotMomentsFireOncePerKey() {
        assertTrue(tracker.recordOneShotPositiveMoment("report_exported"))
        assertFalse(tracker.recordOneShotPositiveMoment("report_exported"))
        assertTrue(tracker.recordOneShotPositiveMoment("streak_30"))
        assertEquals(2, tracker.positiveMomentCount)
    }
}
