# Audit: Vitals 1.8.6 (build 199), 2026-09-14

Audited commit: `b71a49e` (build 199 source; nothing but pbxproj sync after the bump).
Compared against: `cd00d3e` (1.8.5 build 191, live).
Scope: every source change since 1.8.5: Excluded Days + Pause Averages, entitlement reconcile, reports, Deep Trends, History, watch sync, widgets, onboarding HealthKit scope (`d73fb3f`), What's New, release and review notes.
No repo files were changed except adding this report. Probes ran on a scratch copy of the source.

## Store state (ASC API, read at audit time)

- 1.8.6 is **`PENDING_DEVELOPER_RELEASE`** (approved, manual release), build 199 attached, processing `VALID`.
- 1.8.5 is `READY_FOR_SALE`.

So the real decision is whether to press Release on 199.

## Verdict

**Do not release build 199.** It has two new-in-1.8.6 bugs that hit paying users of the headline feature:

1. Pausing averages makes History progressively slower, then unresponsive. Reproduced on the simulator.
2. On a non-Gregorian device calendar (the default in Thailand, and we ship a `th` listing), the Excluded Days screen shows wrong dates, and swipe-to-delete does nothing.

Both fixes are small and local. Everything else found is P3 polish that could ship.

## Findings

### P1: A running pause makes History hang, and the hang grows with the pause

`GoalSettings.excludedDayKeys` (`Shared/Services/GoalSettings.swift:521`) is a computed property. Every read does three things:

- reads the App Group entitlement bool;
- copies the picked set;
- rebuilds a date-key string for every day of the running pause (`ExcludedDays.pausedKeys`).

History calls it once per record, through `isExcluded` (`Vitals/Views/HistoryView.swift:193`) via `goals.isDayExcluded`. `countedRecords` (`:200`) and every `*ChartData` property rebuild the whole list on each access. The chart closures make it quadratic: for every bar they re-evaluate `calorieChartData.filter` and `chartAvgCalories` (`:1161`, `:1216`, `:1272`). Each of those is a full `records` pass, and each record re-reads `excludedDayKeys`.

Evidence:

- **Host benchmark (optimized build, same algorithm).** One 365-record exclusion pass costs 1.3 ms with no pause, 19.8 ms with a 14-day pause, and 70 ms with a 60-day pause. History does dozens of these passes per render, plus two per bar per chart.
- **Simulator, instrumented copy, `settingsPro` fixtures, same machine load for both runs:**
  - No pause: the History tab opened in 3.0 s; 30D 0.5 s, 90D 4.0 s, 1Y 7.5 s.
  - 60-day pause: the History tab took 60.6 s to open. The app then stopped answering accessibility queries ("Timed out while evaluating UI query") and the test failed.
  - The counter logged **555,000 reads of `excludedDayKeys` and about 177 s spent inside the getter**, still climbing when the test was killed.

The machine load average was 400 to 1000 (other sessions), so absolute times are inflated. The read count does not depend on load, and the same run with no pause stayed responsive.

Impact: anyone who uses Pause Averages for a stretch (the release notes' "pause averages until you're back") finds History slower every day, and eventually unusable. It survives Resume, because Resume folds every paused day into the picked set. A 14-day pause is already about 15x the per-pass cost.

Fix direction: read `excludedDayKeys` once per body evaluation and pass the set down, or cache it in `GoalSettings` and invalidate on change or midnight. Hoist `chartData` and averages out of the `Chart` closures. Add a UI or perf test with a long pause at 1Y.

### P1: Excluded Days screen breaks on non-Gregorian calendars

`ExcludedDays.key(for:)` writes Gregorian `yyyy-MM-dd`. `GoalSettings.date(fromDayKey:)` (`GoalSettings.swift:619`) reads those numbers back with `Calendar.current`. Verified with a Swift script, key `2026-09-03` parses to:

| Device calendar | Parsed date |
|---|---|
| Gregorian | 2026-09-03 (correct) |
| Buddhist (Thailand default) | 1483-09-03 |
| Japanese | 4044-09-03 |
| Islamic Umm al-Qura | 2587-11-24 |
| Hebrew | 1735-04-27 |
| Persian | 2647-11-24 |

Consequences in `Vitals/Views/ExcludedDaysView.swift`:

- The Excluded Days list rows show the wrong date and year (`goals.excludedDates`).
- Swipe-to-delete is a no-op: `setDay(excludedDates[index], excluded: false)` (`:155`) re-keys the wrong date, so nothing is removed. Only Clear All works.
- The calendar no longer draws picked days as selected (the getter at `:74` builds components from the wrong dates). Tapping a picked day cannot un-pick it. Tapping any day hands `setExcludedDays` (`:84`) a set built from the bad dates, which can drop real exclusions or store bogus keys. This follows from the code; the picker's exact callback contents were not observed (see limits).
- `loadStats` (`:375`) fetches HealthKit history from the earliest parsed date. For Buddhist that is 1483, so it runs three daily statistics queries across about 200,000 days, again on every exclusion change. Japanese dates land in the future (`from > to`).

The averages math itself is unaffected, because it compares keys directly. Only the screen that manages the feature is broken. Reach is limited to non-Gregorian users, but for them the feature cannot be managed.

Fix direction: parse with the same fixed Gregorian calendar `DailyHealthRecord.key` uses. Add a unit test with a Buddhist `Calendar`.

### P3: Pause, then immediate Resume, leaves today permanently excluded

`resumeAverages` (`GoalSettings.swift:580`) folds the paused range, which includes today, into the picked set. Toggling Pause on and off by accident leaves "1 Excluded Day" (today) in the list, and today becomes a neutral streak day. This matches the footer copy, but it surprises anyone testing the switch.

### P3: A lapsed subscriber with a running pause sees contradictory copy

- The Settings footer (`Vitals/Views/DashboardView.swift:3504`) checks `goals.isAveragesPaused` without the entitlement. It says "Averages are paused... Open this row (or the banner above the tab bar)", but the banner is Pro-gated and hidden, and nothing is being filtered.
- On the locked Excluded Days screen, the pause row (`ExcludedDaysView.swift:285`) still says "Paused since X · N days" beside a switch drawn off with a lock.
- The pause keeps running while lapsed. On resubscribe, every day since the original pause (possibly months) is excluded instantly.

### P3: Banner may cover the bottom of Today and History (unverified)

When paused, `pausedAveragesBanner` (`Vitals/App.swift:599`) stacks about 50 pt above the tab capsule. The Today and History scroll content still reserves a fixed `.padding(.bottom, 90)` (`DashboardView.swift:825`, `HistoryView.swift:755`, `:1565`). The last card may sit under the banner at full scroll. A screenshot was not captured (see limits); check it on a device.

### P3: A long pause blanks the averages widget and card

`EnergyAveragesCalculator` needs 7 valid days in its window. A pause of 3+ weeks leaves too few, so the Energy Averages widget and card fall back to the not-enough-data state. That is correct behavior, but nothing tells the user why.

### P3: Product-load-failure path drops the pending excluded day

A free History long-press sends the pitch through `TrialOfferCoordinator`. If products fail to load, `onNeedsPlanPicker` (`App.swift:1247`) closes the pitch while the user is still free. The pitch's `onDismiss` then clears `pendingExcludedDay`, so buying from the Upgrade tab does not exclude the pressed day. The same pre-existing pattern drops `pendingFeatureEnable`. This is an edge case.

### P3: Watch can briefly clear exclusions after a background launch

`pushCurrentGoals` sends an empty exclusion set whenever `StoreService.shared.isPro` is still false. That includes the WatchConnectivity activation push before RevenueCat resolves. `onChange(of: store.isPro)` re-pushes once it resolves, but a background-only launch that suspends first can leave the watch trends unfiltered until the next foreground. `showNetCalories` has the same existing behavior.

## Checked and fine

- **Shared math.** Calorie, step, net-deficit and macro trend models, the energy-averages calculator and cache reader, pacing "usual" samples, weekly recap, month review and streak walk all filter by key, and all are gated on the entitlement mirror. Streak steps over excluded days and is bounded.
- **Stale entitlement (prior audit P1).** `reconcileCachedEntitlement` overwrites the mirror on every resolved customer, reloads widgets and posts a reload to Today.
- **Reports.** Vitals+ tab and History reports both mark excluded days, filter the previous window, and refuse an all-excluded range. PDF counts use `countedDayCount`.
- **Deep Trends.** Both call sites use counted days. A stale load cannot overwrite a newer set.
- **Free funnel.** Locked calendar and pause taps raise the pitch. The picker resets after the pitch closes, and buying carries out the tap. Impression IDs flow through `ConversionDiagnostics.surface` generically.
- **Debug hooks.** `VITALS_STALE_PRO_CACHE` and `VITALS_RC_APP_USER_ID` compile to no-ops in Release, so there is no production RevenueCat user-ID override.
- **Onboarding.** `d73fb3f` asks for the three energy and step types only, which matches the review notes ("allow all three read types"). Dietary and macro auth are still requested by their toggles.
- **What's New.** Bumped to 1.8.6. Fresh installs are seeded past it (`GoalSettings.swift:766`), so only updaters see it.
- **Listing copy.** Release notes and review notes describe the shipped behavior. The en-US What's New makes no medical claims.

## Verification run

- Unit suite on a leased iOS 26.5 simulator (`agent-sim-7`): **143 passed, 0 failed**. Result bundle: `scratchpad/unit.xcresult`.
- Perf probe (scratch copy with a read counter plus a backdated pause): no pause passed; the 60-day pause hung as described.
- Calendar parsing: standalone Swift script, output in the table above.
- ASC: read-only API queries for version state and builds.

## Verification limits

- The machine load average was 400 to 1000 from other sessions for the whole audit. A second simulator pass sat for 30 minutes without starting a test and was abandoned. That pass would have covered the Buddhist-calendar UI walk-through, a 14-day pause, the no-pause read count, and the bottom-of-screen banner screenshot. The calendar finding rests on the deterministic parse proof and a code trace; its picker-level consequences are inferred.
- The existing UI suite (38 tests) was not rerun; the 2026-09-13 audit records it green on build 198. The only app-code change since then is `2c0ee92` (a row lock change in Settings).
- No physical device, no watch simulator run, no production purchase sheet.
