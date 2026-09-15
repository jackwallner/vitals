# Release audit: Vitals 1.8.7, build 200

Date: 2026-09-15

Scope: latest App Store Connect submission, comparison with the live 1.8.6 build 199, and focused regression and UX review of the changed Excluded Days and History flows.

## Decision

Proceed with 1.8.7 through App Review. No release-blocking regression was found in the changed user paths. The submission fixes the two severe regressions identified in live 1.8.6: History becoming unresponsive during a long pause, and Excluded Days showing or editing the wrong dates for non-Gregorian calendars.

One existing P3 copy mismatch remains for lapsed subscribers. It is not introduced by 1.8.7 and does not affect the calculations, but it should be fixed in a follow-up because it can make the pause state appear active when it is not.

This is a focused readiness sign-off. The full UI suite timed out without returning a failure summary, so it is recorded as an evidence limit below.

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

There are no candidate changes to HealthKit access, onboarding, paywall flow, widgets, or watch product logic in this source delta.

## Findings

### P1 fixed: History performance during a long pause

Live 1.8.6 rebuilt a long paused-date set repeatedly while History assembled records and chart bars. The result could make History progressively slower or appear hung after a pause lasting many weeks.

In 1.8.7, `ExcludedDays.KeyCache` reuses the effective set until the next local midnight, and `HistoryView` hoists the chart calculations out of the per-mark builder. The focused regression test `testLongPauseKeepsHistoryResponsiveAcrossPeriods` passed across the tested chart periods. No new delay or layout regression was observed in the changed flow.

### P1 fixed: Wrong dates with non-Gregorian calendars

Live 1.8.6 stored Gregorian `yyyy-MM-dd` keys but reconstructed them with `Calendar.current`. On Buddhist, Japanese, Islamic, and other calendars this could produce a different year, so the Excluded Days list, calendar selection, and deletion could target the wrong date or appear not to work.

1.8.7 reconstructs keys with `Calendar(identifier: .gregorian)` while retaining the device time zone. `testBuddhistCalendarDayCanBeExcludedUnpickedAndDeleted` passed, including selection, unselection, and deletion. The underlying parser is calendar-independent. Direct UI coverage was run for Buddhist dates; Islamic and Japanese UI variants were not separately exercised.

### P3 residual: lapsed-subscriber pause copy is still contradictory

The calculation path correctly returns an empty excluded-day set when Vitals+ is inactive, preserving the user's picked days for a future resubscription. However, two views still use the persisted pause date without checking the entitlement:

- `Vitals/Views/DashboardView.swift:3494-3500` can show `Paused · 0 days excluded` after lapse.
- `Vitals/Views/ExcludedDaysView.swift:285-318` can show `Paused since ...` and say that today is excluded beside a locked control.

This can make a lapsed user believe current averages are still filtered, even though the app has returned to plain averages. It is an existing live behavior, not a 1.8.7 regression. Follow-up: gate pause-specific copy on the active entitlement, or explicitly explain that the saved pause is dormant until resubscription.

## UX review

- The changed Excluded Days screen was launched from the current build with seeded data. The title, pause control, calendar, empty state, and explanatory footer were readable and visually stable.
- Pausing remains reversible without deleting data. Resuming ends the automatic pause and keeps already excluded days excluded, matching the product copy.
- The candidate release notes are consistent with the actual source delta and are present in all 50 submitted localizations.
- No new user-facing changes were found in the main dashboard, HealthKit permission flow, purchase flow, widgets, or watch code.
- The focused UI paths did not show an obvious visual or interaction regression.

## Verification

- ASC read-only API check: 1.8.7/build 200 is attached to the submitted version and is `VALID`; 1.8.6/build 199 is the live version.
- `git diff --check b71a49e..HEAD`: passed.
- Simulator build of the submitted source: passed with no build errors.
- `VitalsTests`: 150 passed, 0 failed, 0 skipped.
- Focused UI tests: 2 passed, 0 failed:
  - `ExcludedDaysUITests/testLongPauseKeepsHistoryResponsiveAcrossPeriods`
  - `ExcludedDaysUITests/testBuddhistCalendarDayCanBeExcludedUnpickedAndDeleted`
- Manual simulator launch and screenshot review of Settings and Excluded Days: passed.
- Full UI suite: inconclusive. The run exceeded the 300-second tool timeout without returning a pass or failure summary. The exact still-running test processes were stopped after validation; no product failure was reported.

The simulator build is source-equivalent evidence, not a downloaded App Store binary. No physical-device, Apple Watch, production purchase, or live HealthKit authorization test was performed for this audit.
