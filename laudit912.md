# Audit: Vitals 1.8.6 (194)

Date: 2026-09-13
Audited commit: `e2c72ee`
Feature range: `aaa46bc..HEAD`, primarily `c00a970` and `a724a53`
Scope: Excluded Days, Pause Averages, entitlement gating, reports, trends, widgets, watch sync, and UI coverage.

No application or test source files were changed during this audit. The only intended worktree addition is this report.

## Verdict

Not ready to call this update clean. The shared calculations pass and all four app targets compile in Release, but several exclusion paths still produce incorrect or misleading results. The feature UI suite also failed once as a six-test run, then passed when the failing test was isolated.

## Findings

### P1: A stale cached entitlement can keep exclusions active after a subscription lapse

`Shared/Services/GoalSettings.swift:521-537` gates `excludedDayKeys` with the persisted App Group value `isProCached`. The app UI gates the pause banner and the Excluded Days screen with live `StoreService.isPro` in `Vitals/App.swift:578-579`.

On a cold launch after a subscriber lapses, `StoreService.isPro` starts as `false` (`Shared/Services/StoreService.swift:269`). If RevenueCat resolves the customer as free, `apply` does not assign `isPro` because it is already false (`Shared/Services/StoreService.swift:717-735`), so the `didSet` that clears `isProCached` never runs. The old cached value can remain true. History and HealthKit calculations can therefore continue filtering picked or paused days while the live UI hides the banner and the Excluded Days controls. A failed status refresh leaves the same stale state.

This can recreate the inaccessible silent-filter problem the update was intended to fix. The app-side calculation gate should use the live entitlement, or the cached mirror must be explicitly invalidated when a resolved customer is free. Add a cold-launch test with `isProCached = true` and live `isPro = false`.

### P1: Vitals+ reports still include excluded days

`PremiumFeaturesView.generateReport` in `Vitals/App.swift:1551-1601` converts the raw `history` and `previous` arrays directly into `ReportDay` values. `SummaryReportGenerator` then totals, averages, selects peaks, counts goal hits, and calculates trends from every supplied day (`Shared/Services/SummaryReportGenerator.swift:105-179`).

This affects the Vitals+ Monthly Summary PDF and Custom-Range Reports. The History screen's separate report paths correctly use `countedRecords` and `ExcludedDays.excluding` (`Vitals/Views/HistoryView.swift:903-935` and `981-1000`), so the inconsistency is easy to miss. A user can see excluded days removed from History figures, then receive a report containing them.

### P1: Deep Trends has two exclusion leaks

The Vitals+ tab loads raw records and passes them to both `DeepTrendsBuilder.insights` and `DeepTrendsBuilder.highlights` (`Vitals/App.swift:1462-1474`). Its averages, comparisons, active-day count, and peak-day text can therefore include excluded days.

The History screen fixes the insight inputs but still passes raw `records` to `DeepTrendsBuilder.highlights` (`Vitals/Views/HistoryView.swift:1061-1067`). An excluded outlier can remain the displayed peak calories or peak steps, and the active-day count can still include it. The shared calculation tests do not cover either SwiftUI call path.

### P2: Excluded-day visual behavior is incomplete on watchOS and in some iOS detail views

- iOS Net Deficit builds `netRecords` from `countedRecords` (`Vitals/Views/HistoryView.swift:362-367`), so excluded days disappear from the Net Deficit chart and Recent Days list instead of remaining visible and reversible (`286-307`, `1716-1724`).
- iOS Macros uses the same filtered source for `macroRecords` and `macroChartData` (`Vitals/Views/HistoryView.swift:410-412`, `436-454`), so excluded macro days also disappear from those charts and lists.
- The watch trend models carry `isExcluded`, but the calorie and step renderers never read it (`VitalsWatch/Views/TodayView.swift:541-563`, `622-644`). Positive excluded days are drawn like ordinary days. The Net Deficit renderer uses only `counts` (`VitalsWatch/Views/TodayView.swift:711-741`), so an excluded day is indistinguishable from an unlogged-food placeholder.

The iOS calorie and step daily charts do correctly keep excluded records and dim them (`Vitals/Views/HistoryView.swift:254-270`, `1113-1184`). The numeric shared trend tests also pass. The missing rendering and list coverage still contradicts the feature contract that excluded days remain visible as excluded rather than looking like missing data.

### P2: The feature UI suite is not stable as a suite

The first run of `VitalsUITests/ExcludedDaysUITests` passed 5 of 6 tests. `testExcludingADayFromHistoryMarksItAndSaysSo` failed because `Recent Days` never became hittable after tapping the Calories card, and no `recent-day-row` was found (`VitalsUITests/ExcludedDaysUITests.swift:156-161`). The captured hierarchy was still the full History screen.

Running that same test alone passed 1 of 1. This points to test order, state, or timing contamination rather than a deterministic feature failure, but it means the claimed six-test green result is not reproducible. The test should be made isolated and the full class rerun before relying on it as release evidence.

### P2: Monthly Summary eligibility does not account for exclusions

`shouldOfferMonthlySummary` checks `records.count >= 7` (`Vitals/Views/HistoryView.swift:236-238`), while the generator now removes excluded days (`981-1000`). If all of the available period is excluded, the UI can still offer a report that contains zero counted days. This gate predates the feature, but the new filtering makes the edge case user-visible.

### P3: Release succeeds with two pre-existing compiler warnings

The Release simulator build succeeded, including Vitals, VitalsWidget, VitalsWatch, and VitalsWatchWidget. It reports:

- `Shared/Services/SummaryReportGenerator.swift:106`, unused `nonZeroStepDays`.
- `Vitals/Views/DashboardView.swift:1811`, an `await` with no async operations.

`git blame` places both lines before the Excluded Days commits, so these are cleanup items rather than regressions from this update. Several passing UI tests also logged `Invalid frame dimension (negative or non-finite)`. That warning did not fail those tests, but it should be investigated separately.

## Verification

- Unit test run: 136 passed, 0 failed, 0 skipped.
- Excluded Days UI class: 5 passed, 1 failed in the first suite run; the failed test passed when isolated.
- Release simulator build: passed with `CODE_SIGNING_ALLOWED=NO`.
- The prior `SeededHealthFlowUITests` baseline failure was not rerun here, so a full UI-suite green result is not established.

Artifacts:

- Unit result: `/Users/jackwallner/Library/Developer/XcodeBuildMCP/workspaces/vitals-791acf9f00e7/result-bundles/test_sim_2026-09-13T07-01-58-364Z_pid52094_750470d5.xcresult`
- UI suite result: `/Users/jackwallner/Library/Developer/XcodeBuildMCP/workspaces/vitals-791acf9f00e7/result-bundles/test_sim_2026-09-13T07-04-04-983Z_pid52094_07574fe3.xcresult`
- Isolated UI result: `/Users/jackwallner/Library/Developer/XcodeBuildMCP/workspaces/vitals-791acf9f00e7/result-bundles/test_sim_2026-09-13T07-16-30-534Z_pid52094_9fccc362.xcresult`
- Release build log: `/Users/jackwallner/Library/Developer/XcodeBuildMCP/workspaces/vitals-791acf9f00e7/logs/build_sim_2026-09-13T07-18-44-936Z_pid52094_ce632b42.log`

## Resolution (2026-09-13)

- P1 stale entitlement: `StoreService.apply` now overwrites the `isProCached` mirror with every resolved customer, changed or not, then refreshes GoalSettings observers and widget timelines. Not unit-testable (StoreService is outside the standalone VitalsTests bundle).
- P1 reports: Vitals+ tab Monthly Summary and Custom-Range reports filter excluded days from current and previous windows, and refuse an all-excluded range with a message.
- P1 Deep Trends: Vitals+ tab insights and highlights use counted days and reload when exclusions change; History highlights use `countedRecords`.
- P2 visuals: iOS Net Deficit and Macros daily charts and Recent Days keep excluded days, dimmed and badged; aggregates and averages still use counted days only. Watch calorie, step, and net bars dim excluded days; net points gained `isLogged` so an excluded logged day is no longer drawn as an unlogged placeholder (unit test added).
- P2 UI suite: the History test targets the chart card by accessibility identifier and retries a dropped push. Full `ExcludedDaysUITests` class passed 6/6 twice in a row.
- P2 Monthly Summary gate counts `countedRecords`, and the generator refuses zero counted days.
- P3: both compiler warnings removed. Release simulator build of all four targets succeeds with no warnings in project sources.
- Unit tests: 137 passed.
