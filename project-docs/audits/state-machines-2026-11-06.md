# State machine audit, 2026-11-06

Scope: iOS app, `Shared/`, widgets, watch targets, at HEAD (`63ba1b1`). There is no backend function in the repo (entitlements come from RevenueCat); Android is out of scope. Nothing was fixed. Read first: `AGENTS.md`, `.claude/rules/exit-offer.md`, `trial-note.md`, `cta-wording-test.md`, `localization.md`, `iphone-duo.md`.

**Summary: 9 findings. 3 proved by test (each failing test has a passing control in the same suite), 4 code path only, 2 product calls.**

How the tests were run: the suite `StateMachineAuditRepro` (file `state-machines-2026-11-06-repro.swift` next to this one) was placed in `VitalsTests/`, run with `gh-sim test --scheme Vitals --only VitalsTests/StateMachineAuditRepro` (run `vitals@20261106-111002-c0fb-claude-imacc7c3-1106-112513-8323`, Xcode 27.1, iPhone 17, iOS 27.2). Result: 9 tests, 6 passed (the controls), 3 failed (the bugs). `xcodegen` ran on the runner; no project file changes were committed. To rerun, copy the file back into `VitalsTests/`. Only units compiled into the standalone test bundle can be tested (`ExcludedDays`, `MilestoneCalculator`, `ReviewPromptTracker`, `ExitOffer`, `EntitlementStatus`, `DailyNudgePlanner`, ...). `StoreService`, `GoalSettings`, `NotificationService`, the views and HealthKit are not in it, so claims there are marked Code path with what would settle them. No RevenueCat key was configured and nothing was passed to gh-sim.

## Bugs, ranked by impact

| id | bug | what the user sees | user route | evidence | file:line |
|---|---|---|---|---|---|
| CP-1 | Weekly Recap switch reads ON when nothing was scheduled, and never schedules after permission is granted later | Switch is on, the Sunday "Your week in review" notification never arrives | Vitals+ user, notifications denied (or taps "Don't Allow" on the first prompt). Today > gear > Settings > Notifications > Weekly Recap switch on. Later: iOS Settings > turn notifications on > back to the app. The switch is still on, nothing is pending | Code path | `DashboardView.swift:4150-4168` (getter `store.isPro && goals.weeklyRecapEnabled`, no `notificationStatus` check; sibling getters at `:4173` and `:4183` have it), `NotificationService.swift:63-67` (returns false when not authorized, result ignored by the caller), nothing reschedules on permission change (`:4738-4742` refresh only the status). Evening and Goal Reached self-heal because they rewrite on every cache write (`DailyNudgeService.swift:32-36`); the recap is scheduled only from the toggle, Pro regain (`:427`), `App.swift:1181` and `DashboardView.swift:2353`. Would settle: UI test with notifications denied, switch on, grant, read `pendingNotificationRequests()` for `vitals.weeklyRecap` |
| SM-1 | Averages pause start moves one day earlier after the phone moves west | Banner reads "Since Nov 6" for a pause started Nov 7, one more day is left out of every average, and Resume saves that day in the excluded list as if the user had picked it | Vitals+ user in New York: Today > gear > Settings > Averages > Excluded Days > Pause (or any screen's Pause). Travel to Los Angeles (iPhone follows the time zone automatically). Open any tab: banner "Averages paused, Since Nov 6 · N days excluded". Tap Resume: Nov 6 joins Settings > Excluded Days list | Proved: `testPauseStartSurvivesAWestwardTimeZoneMove` failed with keys `["2026-11-06", "2026-11-07", "2026-11-09", "2026-11-08"]`, expected `["2026-11-07","2026-11-08","2026-11-09"]`. Controls passed: same zone, and eastward move | `GoalSettings.swift:456-458` (stores the midnight instant), `ExcludedDays.swift:76-90` (re-derives the start day in the current zone), `GoalSettings.swift:464-469` (Resume freezes them), banner `App.swift:724-777` |
| CP-3 | Custom History range stays selected and shows its data after Vitals+ lapses | A free user opens History and sees the Custom range with its data, while the Custom chip carries a lock | Vitals+ user: History > Custom > pick dates > Apply. Subscription ends. Reopen the app > History tab: Custom is still selected (chip shows the lock), chart and numbers are for the custom dates | Code path. Would settle: UI test that applies Custom, flips `isProCached` false, relaunches, asserts the period | `HistoryView.swift:154` (`@State selectedPeriod = HistoryPrefs.savedPeriod()`, `:57-60` no entitlement check), gate only on the chip tap `:625-632` and `:1619`. Promise: `PaywallView.swift:73,91` "Custom ranges + PDF ... Pick any dates in History" is a Vitals+ feature, and `App.swift` routes the free tap to the pitch (`lockedCustomRange`) |
| CP-2 | Tapping the Weekly Recap notification opens the Vitals+ recap with no entitlement check | A lapsed subscriber sees the recap for free once | Vitals+ user with Weekly Recap on. Subscription ends while the app stays closed (the repeating request is only cancelled when the app runs, `DashboardView.swift:424-426`). Sunday 6 pm: tap "Your week in review". Recap sheet opens | Code path. The URL route is guarded ("The recap is Vitals+; a typed URL must not open it for free users", `App.swift:959-963`) but the notification route is not. Would settle: unit test of the delegate with `isProCached=false` | `App.swift:483-491` (no `isPro`), `:1483-1490` (no `isPro`), `WeeklyRecapView.swift` has no store reference. Window is narrow: the cache still says Pro until the first customer response |
| SM-3 | "Kept Vitals+ for a month" review moment counts a lapsed stretch | The App Store rating ask appears on the first day of a resubscription | Start Vitals+ (trial), let it lapse after a week, resubscribe 40 days after the first start, open Today once the numbers load: the rating prompt is requested (`evaluateHabitMilestones`) | Proved: `testResubscribingAfterALapseStartsTenureAgain` failed (`recordProStatus` returned true on day 40). Controls passed: a continuous subscriber fires at day 31 and not at day 29, a lapsed one never fires | `ReviewPromptTracker.swift:143-153` (`proSince` is written once and never cleared on lapse). Promise: `:34-36` "Days a paying subscriber must have kept Vitals+", `:139-141` "only while they still have it" |
| SM-2 | Streak celebration fires a lower tier after a higher one | A free user gets "14-day streak!" and next session "7-day streak!" while on a 16-day streak, plus a second Vitals+ upsell sheet and a second rating-ask moment | Free user, onboarding done (existing streak seeded as 0). Hit a goal every day for 15 days without opening the app. Open Today: "14-day streak!". Quit, reopen next day: "7-day streak!" | Proved: `testCelebratingAHigherTierRetiresTheLowerOnes` failed with `goalStreak(n: 7)`. Controls passed: seeding retires every tier at or below the streak, and the largest tier is celebrated first | `MilestoneCalculator.swift:121-131` (returns the largest unfired tier only), `App.swift:1203-1206` (stores only that id), seed path `:134-139` does retire lower tiers. Promise: `:56-58` "spacing is wide enough that consecutive celebrations don't feel piled-on". Severity is low: both statements are true, the sequence is not what the comments describe |
| CP-4 | A deferred purchase (Ask to Buy) that is later approved leaves no conversion record | No visible change. The funnel attributes `converted_*` and `exit_offer_outcome=purchased` are never written | Child Apple ID: tap "Start 7-day free trial", Ask Your Parent, sheet says it is pending. Parent approves later: `isPro` turns on through the delegate and the sheet closes | Code path. `recordConversion` and `recordOutcome(.purchased)` have exactly one call site, inside `purchase()` after the entitlement check (`StoreService.swift:819-826`), and `.pending` returns before it (`:815`); the delegate path `apply` (`:876`) writes neither. Promise: `:812` "there is no second write to take it back". Would settle: fake `CustomerInfo` through `apply` and read `ConversionDiagnostics.subscriberAttributes` |
| PC-1 | A goal is announced twice: push, then toast | Lock the phone, hit the step goal, get "Step goal reached" push. Open the app: "Step goal reached!" toast, haptic and, the first time, the notification card | As described | Product call, code path. Dedupe runs one way only: the push reads `goalCelebration.*` (`DailyNudgeService.swift:21-24,50-53`), the dashboard never reads `goalNotified.*` (`DashboardView.swift:1788-1815`). Copy: `DashboardView.swift:4227` "tells you the first time each goal is met in a day" | |
| PC-2 | Net Deficit and Macros are switched off at lapse and not restored on resubscribe | After a lapse and resubscribe the user must turn both back on and re-answer the HealthKit prompts. Recap and Evening are restored | Pro user with Net Deficit on. Subscription ends, open app, resubscribe | Product call, code path. `DashboardView.swift:410-413` clears `showNetCalories` and `showMacros`; the regain branch `:427-432` restores only recap and evening | |

Not counted (checked, documented as inert or intended): exit offer and welcome price (consistent with `exit-offer.md` under relaunch, clock moves, retries), trial note ask, onboarding, goal edits, cache rollover, watch sync, Pro persisting while offline (`EntitlementStatus.refreshFailed`), `showTrialPaywall` dead flag, `ExcludedDays.KeyCache` stale until midnight after a time zone change, tracked-day double count after a westward move, rapid on/off of the recap switch, `max(live, cache)` on Today (self-corrects at the next observer write).

## Fix groups, in order

1. Notification state (CP-1, CP-2): make the recap switch reflect real scheduling, reschedule when permission arrives, gate the notification route on Vitals+. Same file area, one change.
2. Calendar-day identity (SM-1): store the pause as a day key (or a key plus zone) instead of an instant. Then the banner date, `pausedKeys` and Resume agree.
3. Entitlement gates that survive a lapse (CP-3, PC-2): sanitize persisted state (`history.period`) against `isPro`, decide on Net Deficit and Macros restore.
4. Tier bookkeeping (SM-2, SM-3): retire lower tiers when a tier fires; clear `proSince` on lapse.
5. Funnel accuracy (CP-4, PC-1): write the conversion record from `apply` when access appears after a pending purchase; share one per-day announced key between push and toast.

## State machines

Notation: each table row is `from -> to : trigger`. "Breaks" names the invariant (I-n) the transition violates; a dash means the transition is fine. Bug ids refer to the table above. Only code reachable from the shipping UI is listed. Debug-only launch arguments are ignored.

### 1. Entitlement (Vitals+)

Files: `Shared/Utilities/EntitlementStatus.swift`, `Shared/Services/StoreService.swift` (`apply`, `resolveEntitlement`, `reconcileCachedEntitlement`), App Group key `isProCached`.

State = (`cachedPro`: Bool, `resolution`: unresolved | active | inactive).

Invariants:
- I-1.1 `isPro == cachedPro` always.
- I-1.2 `isProCached` in the App Group equals the last resolved `cachedPro` (widgets, complications and `GoalSettings.excludedDayKeys` gate on it).
- I-1.3 A failed refresh never changes access (`refreshFailed` only sets `resolution = unresolved`).
- I-1.4 Everything that was switched on by Vitals+ and is gated by it stops when `isPro` falls: notifications, Net Deficit, Macros, exclusions, Custom range.

| from | to | trigger | breaks |
|---|---|---|---|
| (cachedPro=c, unresolved) | (c, unresolved) | launch, `store.start()` | - |
| any | (true, active) | `customerInfo` with any active entitlement (`hasVitalsProEntitlement`), purchase, restore, delegate push | - |
| any | (false, inactive) | `customerInfo` with none | I-1.4 for Custom range (CP-3), Net Deficit and Macros are cleared and not restored (PC-2) |
| (c, *) | (c, unresolved) | `customerInfo` throws | - |
| (true, active) | (true, unresolved) | offline after lapse | none by design: Pro persists offline (product call, not counted) |
| (true, *) | (false, inactive) while a recap notification is pending | lapse while the app is closed | I-1.4: recap and evening request stay pending until the app runs (`DashboardView.onChange(of: store.isPro)` is the only canceller), CP-2 |

### 2. Purchase

Files: `StoreService.purchase`, `PurchaseState`, `TrialOfferPitchSheet.startPurchase`, `PaywallView.startPurchase`, `OnboardingSheet.startTrial`, `MainTabView.startMilestoneDirectTrial`.

States: idle, inFlight (`purchaseInFlight`, local `isPurchasing`), then one of purchased, cancelled, pending, unavailable, thrown.

Invariants:
- I-2.1 `.purchased` is returned only when an entitlement is active in the returned `CustomerInfo`.
- I-2.2 The conversion record (`ConversionDiagnostics.recordConversion`, `ExitOffer.recordOutcome(.purchased)`) is written exactly once, when access first becomes active through a purchase.
- I-2.3 A sheet that offers a purchase cannot be dismissed while one is in flight (`interactiveDismissDisabled(isPurchasing)`, buttons disabled).

| from | to | trigger | breaks |
|---|---|---|---|
| idle | inFlight | CTA tap | - |
| inFlight | purchased | entitlement active | - |
| inFlight | pending | `paymentPendingError` or no entitlement yet | - |
| pending | (access granted, no record) | Ask to Buy approved, delegate `apply` | I-2.2 (CP-4) |
| inFlight | cancelled | `userCancelled` | - |
| inFlight | unavailable | RevenueCat not configured | - |

### 3. Exit offer and welcome price

Files: `Shared/Utilities/ExitOffer.swift`, `StoreService` (`exitOfferOnClose`, `refreshWelcomePrice`, `exitOfferDue`), `MainTabView.presentExitOfferWhenClear`, `ExitOfferPriceTiles`.

State: arm (nil, offer, holdout), `closedAt` (nil | date), `pending`, `shownAt` (nil | date), `welcomeEnded`, `outcome` (nil | declined | purchased).

Invariants:
- I-3.1 The first deliberate close is recorded once, for both arms, and never overwritten.
- I-3.2 The offer is shown at most once (`shownAt` set once; Keychain survives reinstall in Release).
- I-3.3 The half price stands for exactly 48 hours from `shownAt` and never restarts.
- I-3.4 Pro customers see none of it.
- I-3.5 `pending` is true only between a close in the offer arm and the sheet appearing.

| from | to | trigger | breaks |
|---|---|---|---|
| (closedAt=nil) | (closedAt set, arm set) | first deliberate close with arm known | - |
| (closedAt=nil) | (closedAt=nil) | close while the `exit_offer` offering has not loaded | - (documented, retried by the next close) |
| closed, pending=false | pending=true | close, offer arm, plan loaded, `shownAt==nil` | - |
| pending | shown | return >= 1 h after close, Today clear for 3 s | - |
| shown | window open | tiles `onAppear` -> `recordShown` | - |
| window open | ended | clock past `shownAt+48h`, or clock earlier than `shownAt` | none (documented) |
| pending | cleared | `isPro` becomes true | - |
| shown | outcome=declined | "No thanks" | - (swipe-down leaves outcome nil, documented) |
| shown | outcome=purchased | buy `exit_annual` | I-2.2 skipped when the buy is deferred (CP-4) |

No bug counted here. The state machine is consistent with its documentation under retries, relaunch and clock moves.

### 4. Trial pitch presentation and cooldowns

Files: `Vitals/App.swift` (`MainTabView`, `TrialOfferCoordinator`), `GoalSettings.lastTrialOfferShownDate`, `lastHistoryTrialOfferShownDate`.

State: `trialPitch` (nil | request), `pendingIntent`, `pendingFeatureEnable`, `pendingExcludedDay`, `launchOfferShownThisSession`, `skipPassiveTrialThisSession`, `milestoneShownThisSession`, `showWhatsNew`, `pendingMilestone`, `showReviewPrompt`, `showWeeklyRecap`, plus `coveringSheetIsPresented`.

Invariants:
- I-4.1 At most one conversion sheet is up (`trialPitch == nil` checked by every presenter).
- I-4.2 `pendingFeatureEnable` is applied only after a purchase made from the sheet that set it, and is cleared on a dismiss without purchase.
- I-4.3 Passive pitches respect the 14-day cooldown, intent pitches ignore it, the exit offer does not stamp it.
- I-4.4 `showTrialPaywall` is never set (declared and read only), so the `PaywallView` sheet branch is unreachable.

| from | to | trigger | breaks |
|---|---|---|---|
| trialPitch=nil | request | passive launch, History load, intent tap, exit offer | - |
| request | nil + enable feature | purchase, then `onDismiss` with `isPro` | - |
| request | nil + clear pending | dismiss without purchase | - |
| recap request | dropped | `recapCoordinator.pendingPresent` while a sheet is up: `clear()` runs before the guard | the notification tap is lost (minor, not counted) |

### 5. Trial note and "what to fix"

Files: `TrialNote.swift`, `StoreService.apply`, `MainTabView.presentWhatToFixWhenClear`.

State: `trialNote.seen`, `trialNote.whatToFixAsked`, entitlement (periodType, willRenew, billingIssue).

Invariants:
- I-5.1 The ask is shown at most once (`markAsked` on present).
- I-5.2 A billing retry is not a decision to leave (`willRenew || billingIssueDetectedAt != nil`).
- I-5.3 Re-enabling renewal before the sheet is up cancels the ask (`whatToFixDue` is recomputed on every `CustomerInfo`).

Transitions are consistent. No bug counted.

### 6. Onboarding

Files: `OnboardingSheet` (step welcome, goals, trial), `hasCompletedSetup`, `GoalSettings.init` seeding.

Invariants:
- I-6.1 `hasCompletedSetup` flips true on every exit: Get Started, purchase, restored entitlement, sheet dismissal.
- I-6.2 The HealthKit prompt is asked once, when leaving the welcome step.
- I-6.3 A returning subscriber is not pitched (`isPro` on appear of the trial step finishes onboarding).
- I-6.4 Passive pitches are suppressed for the rest of the session in which onboarding finished.

| from | to | trigger | breaks |
|---|---|---|---|
| welcome | goals | Continue, requests HealthKit | - |
| goals | trial | Continue | - |
| trial | done | Get Started (records exit-offer close), purchase, restore, `isPro` | - |
| any | done | `onDismiss` sets `hasCompletedSetup` | - (sheet is `interactiveDismissDisabled`) |

No bug counted.

### 7. Notifications (authorization x toggles x pending requests)

Files: `NotificationService.swift`, `Vitals/Utilities/DailyNudgeService.swift`, `DailyNudgePlanner.swift`, `DashboardView` Settings (`weeklyRecapBinding`, `goalReachedBinding`, `eveningReminderBinding`, `acceptNotificationAsk`), `DashboardView.celebrateGoalsIfNeeded`.

State per channel: (toggle flag in `GoalSettings`, iOS authorization status, pending request present, per-day dedupe key).

| channel | toggle | pending request | self-heals when permission arrives later |
|---|---|---|---|
| Goal Reached | `goalReachedNotificationsEnabled` | none, posted immediately on cache write | yes (every cache write re-evaluates) |
| Evening Reminder | `eveningReminderEnabled` + Pro | one request, today only, rewritten each cache write | yes |
| Weekly Recap | `weeklyRecapEnabled` + Pro | one repeating request | no: scheduled only on toggle, Pro regain, `applyPendingFeatureEnable`, `acceptNotificationAsk` |

Invariants:
- I-7.1 A switch that reads ON has a request that will fire, or the screen says why not.
- I-7.2 A channel is withdrawn when Vitals+ lapses.
- I-7.3 A goal is announced once per day per surface (push or toast).
- I-7.4 Goal Reached never posts while the app is active.
- I-7.5 A tap on a Vitals+ notification opens only for Vitals+.

| from | to | trigger | breaks |
|---|---|---|---|
| Recap off | toggle on, status denied or "Don't Allow" | Settings, Weekly Recap switch | I-7.1 (CP-1) |
| Recap toggle on, nothing pending | still nothing pending | permission later granted in iOS Settings, user returns | I-7.1 (CP-1) |
| Recap pending | pending after lapse | app not opened since expiry | I-7.2 until next launch |
| Recap pending | recap sheet | tap on notification | I-7.5 (CP-2); the URL route has the guard, the notification route does not |
| goal pushed | goal toasted | open app after a background push | I-7.3 (PC-1) |
| toggle on+off quickly | request present while off | `Task` ordering around `requestAuthorization` | I-7.1, code path only, not counted (needs sub-100 ms toggling) |

### 8. Review prompt

File: `ReviewPromptTracker.swift`, `MainTabView.scheduleReviewPromptAfterPositiveMoment`.

State: `appLaunchCount`, `lastShownDate`, `outcome`, `hasPendingPositiveMoment`, one-shot flags, `proSince`, `subscriberMomentFired`, tracked days.

Invariants:
- I-8.1 No ask in the first session, in setup, inside the 30-day cooldown, or after `openedWriteReview`.
- I-8.2 Each one-shot moment records at most once.
- I-8.3 The subscriber moment means Vitals+ was kept for 30 days and is not fired for a lapsed subscriber.

| from | to | trigger | breaks |
|---|---|---|---|
| proSince=nil | proSince=t0 | first `isPro` evaluation | - |
| proSince=t0 | proSince=t0 | lapse: not cleared | I-8.3 |
| proSince=t0 (lapsed) | moment fires | resubscribe after 30 days | I-8.3 (SM-3) |
| lastTrackedDay | counted again | westward time zone move on the same day | counts a day twice (minor, not counted) |

### 9. Streak milestones

Files: `MilestoneCalculator.swift`, `DashboardView.checkGoalStreakMilestone`, `MainTabView.handleMilestone`, `GoalSettings.firedMilestoneIds`, `hasSeededStreakMilestones`.

State: fired ids subset of {streak_7, 14, 30, 60, 100, month_YYYY-MM}, seeded flag.

Invariants:
- I-9.1 A tier fires at most once.
- I-9.2 First evaluation adopts the existing streak silently (every tier at or below it is marked fired).
- I-9.3 After tier T is celebrated, no tier below T is celebrated.
- I-9.4 Pro users get no celebration sheet and the seed waits until they are free.

| from | to | trigger | breaks |
|---|---|---|---|
| unseeded | seeded | first free-tier evaluation | - |
| fired={} streak 15 | fired={14} | evaluation | - |
| fired={14} streak 16 | celebrates 7 | next session | I-9.3 (SM-2) |

### 10. Excluded days and averages pause

Files: `ExcludedDays.swift`, `GoalSettings` (`pickedExcludedDayKeys`, `averagesPausedSince`, `pauseAverages`, `resumeAverages`, `excludedDayKeys`), `ExcludedDaysView`, `MainTabView.pausedAveragesBanner`, watch sync.

State: picked set of "yyyy-MM-dd", `pausedSince` (instant or nil), `isProCached`.

Invariants:
- I-10.1 Effective set = picked union (pause start day ... today) while Pro, empty otherwise.
- I-10.2 The pause covers exactly the days from the day it was started.
- I-10.3 Resume freezes exactly the days the pause covered.
- I-10.4 Future days are never stored.
- I-10.5 Phone and watch agree (watch gets an empty set when lapsed).

| from | to | trigger | breaks |
|---|---|---|---|
| nil | pausedSince=midnight instant | Pause | - |
| paused | paused, start day moved | time zone moves west | I-10.2 (SM-1) |
| paused | picked += covered | Resume, in the new time zone | I-10.3 (SM-1: the extra day is frozen as if picked) |
| paused | paused | midnight, set grows | - |
| paused, Pro lapsed | filter off, banner hidden | lapse | the pause keeps running with no Resume reachable, and covers the whole lapsed stretch when Vitals+ returns (visible banner, recoverable, product call, not counted) |
| any | key cache stale until next midnight or invalidation | time zone change inside the day | I-10.1 (transient, not counted: no hook on `significantTimeChange` invalidates `KeyCache`) |

### 11. Today cache, day rollover and HealthKit access

Files: `HealthKitService.refreshCache`, `finalizeDayRolloverIfNeeded`, `DayRollover`, `DashboardView.refresh`, `HealthNotice`.

State: `lastCachedDayKey`, today row, `isAuthorized`, `HealthNotice` (nil, accessNeeded, noData, loadError).

Invariants:
- I-11.1 A rollover finalizes the finished day before today is written (marker advanced only after success).
- I-11.2 An all-zero read never overwrites a row that has data.
- I-11.3 `refresh()` never runs twice at once (second call is dropped).
- I-11.4 Today shows `max(live, cache)` because totals only grow within a day.

Transitions behave as documented. I-11.4's premise can be false (Health samples deleted, or a time zone move re-cutting the day), but the observer path writes the live value to the cache, so the stale high value lasts only until the next observer delivery. Not counted.

### 12. Goals and recalibration

Files: `GoalSettings` (`calorieGoal`, `stepGoal`, `*SetAt`, snooze), `GoalRecalibration.swift`, `SettingsSheet.commitGoalDrafts`.

Invariants: goals are within 500...50,000 and 100...500,000, a changed goal rests 14 days before a suggestion, "Keep" snoozes 30 days, an invalid typed goal never overwrites the stored one. `isLoading` stops `init` from counting as a change. Consistent. Turning a goal on with an invalid draft leaves the stored goal nil while the switch reads ON, with the red range message beside it (visible, not counted).

### 13. History period

`selectedPeriod` is persisted in the App Group (`history.period`) and restored at init with no entitlement check.

| from | to | trigger | breaks |
|---|---|---|---|
| custom (Pro) | custom (free) | lapse, relaunch | Custom is a Vitals+ range (CP-3) |

### 14. Dashboard prompt slot

`DashboardPrompt` (nil, notifications, goal(suggestion)) is a single slot. A goal moment that finds `prompt != nil` skips the notification ask and keeps the review ask pending; a suggestion arriving after waits 0.6 s and re-checks. Consistent.

### 15. Watch sync

`PhoneGoalSyncService.pushCurrentGoals` runs on changes of goals, show flags, `isPro`, picked days and pause start. `showMacros` and `visibleMacros` are in the payload but have no `onChange` trigger; the watch app never reads them, so there is no visible effect (not counted).
