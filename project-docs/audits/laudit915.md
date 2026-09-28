# Release audit: Vitals 1.8.7, build 200

Date: 2026-09-15

Scope: latest App Store Connect submission, comparison with the live 1.8.6 build 199, focused regression testing of Excluded Days and History, and an expanded review of onboarding, HealthKit empty and error states, entitlement changes, History math, widgets, watch sync, localization, and accessibility copy.

## Decision

Proceed with 1.8.7 through App Review. No release-blocking regression was found in the changed user paths. The submission fixes the two severe regressions identified in live 1.8.6: History becoming unresponsive during a long pause, and Excluded Days showing or editing the wrong dates for non-Gregorian calendars.

This is not a clean UX sign-off for the product as a whole. The expanded review found several existing live issues, including P2 trust, data, and latency problems. They are not introduced by 1.8.7, but should be prioritized after submission.

The clearest current problem is an entitlement state mismatch. When Vitals+ lapses, calculations correctly stop filtering excluded days, but the locked Excluded Days screen still describes the saved pause as active. The user sees copy that says today is excluded even though today's data is being counted again.

The full UI suite timed out without returning a failure summary, so this remains a focused readiness sign-off with explicit evidence limits below.

## App Store Connect state

| Surface | Version and build | ASC state | Build state |
| --- | --- | --- | --- |
| Latest submitted | 1.8.7, build 200 | WAITING_FOR_REVIEW | VALID, uploaded 2026-09-15 00:24 PDT |
| Current live | 1.8.6, build 199 | READY_FOR_SALE | VALID, uploaded 2026-09-13 23:19 PDT |

The 1.8.7 version was created on 2026-09-14 23:45 PDT. It has 50 localizations. Its release notes describe only the History performance fix and the non-Gregorian Excluded Days date fix, with no new features, permissions, or data collection. The attached build has minimum OS 17.0 and is not expired.

## Candidate versus live

The live source baseline is commit `b71a49e`. The submitted source is commit `d7aeec7`, with build 200. The product delta is narrow:

- `ExcludedDays` now parses stored Gregorian keys with an explicit Gregorian calendar.
- `GoalSettings` caches the effective excluded-day set until the next local midnight and invalidates it when the picked days or pause changes.
- `HistoryView` computes chart data and averages once before building chart marks, instead of repeating the work for each mark.
- Settings copy no longer points lapsed subscribers at a Vitals+ pause banner.
- Unit and UI coverage was added for long pauses and non-Gregorian dates.
- The remaining changes are versioning, release metadata, and test-fixture timing.

There are no candidate changes to HealthKit access, onboarding, paywall flow, widgets, or watch product logic in this source delta. The additional issues below are therefore existing live behavior, not new 1.8.7 regressions.

## Findings

### P1 fixed: History performance during a long pause

Live 1.8.6 rebuilt a long paused-date set repeatedly while History assembled records and chart bars. The result could make History progressively slower or appear hung after a pause lasting many weeks.

In 1.8.7, `ExcludedDays.KeyCache` reuses the effective set until the next local midnight, and `HistoryView` hoists the chart calculations out of the per-mark builder. The focused regression test `testLongPauseKeepsHistoryResponsiveAcrossPeriods` passed across the tested chart periods. No new delay or layout regression was observed in the changed flow.

### P1 fixed: Wrong dates with non-Gregorian calendars

Live 1.8.6 stored Gregorian `yyyy-MM-dd` keys but reconstructed them with `Calendar.current`. On Buddhist, Japanese, Islamic, and other calendars this could produce a different year, so the Excluded Days list, calendar selection, and deletion could target the wrong date or appear not to work.

1.8.7 reconstructs keys with `Calendar(identifier: .gregorian)` while retaining the device time zone. `testBuddhistCalendarDayCanBeExcludedUnpickedAndDeleted` passed, including selection, unselection, and deletion. The underlying parser is calendar-independent. Direct UI coverage was run for Buddhist dates; Islamic and Japanese UI variants were not separately exercised.

### P2 existing: authorized but empty HealthKit state is reported as permission failure

On both iPhone and Apple Watch, an all-zero HealthKit fetch is classified as `accessBlocked` whenever `HKAuthorizationRequestStatus` is `.unnecessary`. That status means the permission sheet has already been shown. It does not prove that the user denied reads.

On a new device, a user can grant every requested permission and still have no Health samples. The dashboard then says `Health access is off` and directs the user to turn on every category. The watch uses the same classification and says `Health access is off` there too. This is a false diagnosis at the first-use moment when the user is most likely to need guidance.

Evidence: `Vitals/Views/DashboardView.swift:1683-1704` documents and implements the ambiguity, and `VitalsWatch/Views/TodayView.swift:329-342` repeats it. This is existing live behavior, not a candidate change. Fix direction: distinguish `no samples yet` from denied access using a persisted successful-read signal or an explicit first-use state, and reserve `accessBlocked` for evidence of a failed read after prior data.

### P2 existing: History can fail as a whole when one core Health permission is unavailable

`HealthKitService.fetchHistory` starts active energy, resting energy, and steps queries as one tuple and awaits all three at `Shared/Services/HealthKitService.swift:420-424`. If one category is denied or unresolved, the entire History load falls into `Couldn't Load History`, even when the other categories could be displayed.

Today already treats Steps as best effort at `HealthKitService.swift:248-255`, which makes the History behavior inconsistent. A user who disables Steps should not lose calorie History, and a user with incomplete access should get a per-metric explanation rather than a blank screen.

### P2 existing: History activity averages have an unclear and inconsistent denominator

HealthKit fills one row per calendar day, including zero rows, and `fetchHistory(days:)` includes the current partial day. History then computes `Avg Calories` and `Avg Steps` by dividing by every non-excluded row at `Vitals/Views/HistoryView.swift:214-229`.

Other surfaces use different rules:

- Deep Trends drops zero values in `HistoryView.swift:2284-2324`.
- Three-month and one-year chart buckets average only non-zero metric days at `HistoryView.swift:3101-3133`.
- Macro cards explicitly say `Per logged day` and show their denominator at `HistoryView.swift:1496-1504`.
- TDEE and BMR exclude today and skip days without resting energy.

The activity cards do not disclose their denominator. If only 3 of 30 rows have activity, the card can show roughly one tenth of the active-day average while Deep Trends presents the active-day figure. Early in the day, the partial current row also pulls the average down. If every row is excluded, the cards display zero rather than a no-counted-days state. This is a data-trust issue even when each individual calculation follows its own code path.

Fix direction: choose and name one denominator, preferably `logged days` for behavior averages, exclude today from completed-period summaries, and show the sample count beside the cards.

### P2 existing: History mislabels dietary read failures as no food logged

When the Net Deficit or Macros feature is enabled, History fetches dietary energy at `Vitals/Views/HistoryView.swift:1987-2002`. The catch block only logs the error and leaves `foodByDay` empty. The Net Deficit card then renders `No food logged this period` at `HistoryView.swift:1336-1344`.

A HealthKit read failure therefore tells an existing food logger to log meals, with no retry or Health permissions action. Dashboard has an explicit dietary failure state, but History does not. This is existing live behavior and should be fixed by carrying a dietary-load-failed state through the card.

### P2 existing: first History load waits for a second, older HealthKit window

On a cold History load, the app fetches the selected window, then dietary data, then macros, then awaits the preceding equal-length window before setting `isLoading = false`. The preceding fetch is described as fire-and-forget at `HistoryView.swift:2041-2044`, but it is awaited synchronously. A first 1Y load therefore waits for the current year plus the previous year before showing the current charts.

This is separate from the fixed paused-date CPU regression. The current data could be shown as soon as it arrives, with Deep Trends loading independently. The finding is code-based; no new stopwatch was taken for an unpaused build in this follow-up.

### P3 existing: cold-start cached data can look current after a failed refresh

Dashboard paints cached values immediately, and on a later HealthKit failure it applies the cache and clears the health notice at `Vitals/Views/DashboardView.swift:1840-1858`. The only freshness signal is the previous `lastRefreshDate` at `DashboardView.swift:573-577`. On a cold launch where no successful read has happened in the session, that date is nil, so cached values can appear without an explicit `Showing saved data` label.

Watch explicitly labels this state as `Showing last good saved data`; iPhone should do the same. This is existing live behavior.

### P3 existing: Excluded Days statistics query grows with the full pause, not the visible rows

`ExcludedDaysView.loadStats` finds the earliest key in `goals.excludedDayKeys` and fetches HealthKit history from that date through now at `Vitals/Views/ExcludedDaysView.swift:373-386`. A running pause contributes every day since it began, even though the screen renders only hand-picked `excludedDates` rows. A long pause can therefore make opening the screen perform a months- or years-wide query.

The candidate fixes the History path but does not change this screen. Fetch only the hand-picked dates, or query a bounded recent range and leave pause-owned rows without per-day stats.

### P3 existing: a long pause makes TDEE and BMR appear to be rebuilding without naming the cause

Energy averages need seven valid completed days. A pause can reduce the valid sample count below that floor, after which Today and the widget say `estimate building: x/7 days` at `DashboardView.swift:832-847` and `EnergyAveragesWidget.swift:118-148`. The user is not told that their own excluded days caused the figure to disappear, so the feature looks broken or reset.

### P3 existing: lapsed pause copy contradicts the active calculation state

`GoalSettings.excludedDayKeys` correctly returns an empty effective set while Vitals+ is inactive at `Shared/Services/GoalSettings.swift:519-525`. That restores plain averages while preserving the user's picked days for a future resubscription.

The locked Excluded Days screen still reads the persisted pause date and displays `Paused since ...` at `Vitals/Views/ExcludedDaysView.swift:285-318`. Its footer also says today and every day until resume are excluded, although the locked switch is off and no filtering is active. On resubscription, the old pause can immediately cover every day since the original pause, potentially months of history, without a fresh confirmation.

The Dashboard Settings row itself currently uses generic free copy while lapsed, so the earlier concern that this row displays the paused subtitle was too broad. The contradictory state is specifically the locked Excluded Days screen. This is existing live behavior, not a 1.8.7 regression.

### P3 existing: a pause followed immediately by Resume permanently excludes today

`resumeAverages` intentionally converts every day covered by the pause, including today, into a picked exclusion at `GoalSettings.swift:581-589`. The footer explains this behavior, but an accidental tap on Pause followed by Resume leaves a new excluded day and changes today's streak and averages. A confirmation or an explicit `Resume and include today` action would better match user expectation.

### P3 existing: lapsed users lose Net Deficit and Macros choices

When entitlement changes from active to inactive, `DashboardView.swift:342-352` sets `goals.showNetCalories` and `goals.showMacros` to false. Those preferences are not restored on resubscription, unlike several other Vitals+ settings that remain stored behind an entitlement gate. A returning subscriber must rediscover and re-enable both features, and the app has discarded their preferred dashboard layout.

### P3 existing: product-load failure can drop the action that led to the paywall

The app stores a pending excluded day or feature enable in `MainTabView.handleIntentTap` at `Vitals/App.swift:889-907`. If products are unavailable, it routes to Upgrade. The trial sheet's non-Pro dismissal path clears that pending context at `App.swift:1225-1235`, so a user who buys from the Upgrade tab may not get the day or feature they originally tapped. The recovery CTA itself works, but the intent handoff is not durable through the degraded path.

### P3 existing: watch can briefly clear exclusions during entitlement resolution

The phone sends an empty exclusion set when `StoreService.shared.isPro` is still false at `Vitals/App.swift:35-53`. RevenueCat later re-pushes the correct state, but a background-only activation that is suspended first can leave the watch displaying unfiltered trends until the next foreground sync. This is an existing lifecycle race, not a candidate change.

### P3 unverified: the pause banner may cover the last scroll content

The banner and tab bar are stacked in an ignored-bottom-safe-area overlay at `Vitals/App.swift:1049-1092`, while Today and History reserve a fixed 90 point bottom inset at `DashboardView.swift:823-826` and `HistoryView.swift:753-755`. The combined banner, gap, tab bar, and bottom padding may leave the final card under the banner at full scroll. This was not captured in the targeted run and remains an on-device layout check.

## Localization finding

The App Store metadata has 50 locale directories, but the app project declares only `Base` and `en` at `Vitals.xcodeproj/project.pbxproj:826-831`. There are zero tracked in-app `.lproj`, `Localizable.strings`, `Localizable.xcstrings`, or `.stringsdict` resources. The source also contains hardcoded date formats such as `EEEE, MMM d, yyyy` and `MMM d`.

As a result, non-English users receive English UI and VoiceOver copy despite localized storefront listings. Dates are also inconsistent across surfaces for users with non-Gregorian calendars. This is an existing P2 market and accessibility problem, not a 1.8.7 regression. Either add actual in-app localization or reduce storefront localization promises until the binary is translated.

## What was checked and found healthy

- The 1.8.7 source delta is narrow and does not touch HealthKit access, onboarding, paywall, widget, or watch product logic.
- The lapsed entitlement test confirmed that stored exclusions stop filtering for a free customer.
- The product-load recovery test confirmed that a failed product fetch restores a usable CTA and opens the full paywall with a retry path.
- The changed Excluded Days screen was launched with seeded data. The title, pause control, calendar, empty state, and explanatory footer were readable and visually stable.
- Resuming a pause keeps the paused days excluded, matching the current copy. The issue is the lack of a low-surprise undo path, not an implementation mismatch.
- No new visual or interaction regression was found in the changed user paths.

## Recommended order

1. Correct HealthKit empty, partial-permission, and stale-cache states so the app does not accuse a user of denying access or tell an existing logger to add data.
2. Align History denominators and exclude the partial current day from completed-period averages. Show sample counts.
3. Add proper in-app localization, or reduce ASC storefront localization promises until the UI and VoiceOver copy are translated.
4. Make entitlement transitions explicit: dormant pause wording, resubscription confirmation, and restoration of stored feature choices.
5. Decouple current History rendering from the preceding trend window and bound Excluded Days statistics work.
6. Preserve pending feature and day actions through a degraded paywall handoff and send watch state only after entitlement is resolved.

## Verification

- ASC read-only API check: 1.8.7/build 200 is attached to the submitted version and is `VALID`; 1.8.6/build 199 is the live version.
- `git diff --check b71a49e..HEAD`: passed before this report expansion.
- Simulator build of the submitted source: passed with no build errors.
- `VitalsTests`: 150 passed, 0 failed, 0 skipped.
- Focused UI tests from the original audit: 2 passed, 0 failed:
  - `ExcludedDaysUITests/testLongPauseKeepsHistoryResponsiveAcrossPeriods`
  - `ExcludedDaysUITests/testBuddhistCalendarDayCanBeExcludedUnpickedAndDeleted`
- Additional focused UI tests in this expanded audit: 2 passed, 0 failed:
  - `SeededHealthFlowUITests/testLapsedSubscriberStopsFilteringExcludedDays`
  - `OnboardingCTARecoveryUITests/testRecoveredCTAOpensTheFullPaywall`
- Static localization scan: 50 App Store metadata locale directories, but zero tracked in-app `.lproj`, `Localizable.strings`, `Localizable.xcstrings`, or `.stringsdict` resources. The Xcode project declares only `Base` and `en`.
- Manual simulator launch and screenshot review of Settings and Excluded Days: passed.
- Full UI suite: inconclusive. The run exceeded the 300-second tool timeout without returning a pass or failure summary. The exact still-running test processes were stopped after validation; no product failure was reported.

The simulator build is source-equivalent evidence, not a downloaded App Store binary. No physical-device, Apple Watch, production purchase, or live HealthKit authorization test was performed for this audit.
