# Release audit: Vitals 1.8.6 (199)

Date: 2026-09-14
Audited commit: `b71a49e`
Scope: Excluded Days, Pause Averages, entitlement gating, reports, trends, widgets, watch sync, localized behavior, release metadata, and test evidence.

Build 199 is source-equivalent to build 198. The only changes after the build 198 source was verified are the project build-number updates in `30d4bb9` and `b71a49e`.

## Verdict

Not release ready. The release build and shared calculation tests are clean, but the current code still has two entitlement consistency problems and a localized date corruption path. Hold the release until these are fixed and covered by regression tests.

## Findings

### P1: RevenueCat refresh failure leaves entitlement state inconsistent

`StoreService.isPro` starts as `false` on every launch (`Shared/Services/StoreService.swift:269-277`). Startup then requests current customer information asynchronously (`Shared/Services/StoreService.swift:325-337`). A successful response applies the entitlement and reconciles the App Group mirror (`Shared/Services/StoreService.swift:717-755`), but the error path only records an error message (`Shared/Services/StoreService.swift:693-700`). It does not change either `isPro` or `isProCached`.

`GoalSettings.excludedDayKeys` gates the data calculation with the persisted App Group value `isProCached` (`Shared/Services/GoalSettings.swift:521-537`), while the app UI gates the Vitals+ controls with live `StoreService.isPro`.

Customer-visible scenario:

- A subscriber previously had Vitals+ and `isProCached == true`, with excluded days or a pause saved.
- The app cold-starts with `isPro == false` and RevenueCat cannot refresh because the device is offline or the service request fails.
- The Vitals+ controls are hidden, but the stale App Group value keeps excluded days out of Today, History, and other averages.

The user sees numbers that are still filtered by a feature they can no longer reach, with no way to understand or undo the filter. A later successful refresh may repair the mirror, but the inconsistent state persists while the refresh is failing. The opposite case also hides paid UI for an active subscriber, which is poor but conservative.

Required before release: choose one explicit policy for unknown entitlement state and use it consistently for UI and calculations. Add a cold-launch test that forces a customer-info failure with `isProCached == true`, then verifies that the visible controls and all calculation filters agree.

### P1: The watch Net Deficit complication has no entitlement gate

`VitalsWatchWidget.loadGoals()` reads the persisted `showNetCalories` preference directly from the App Group (`VitalsWatchWidget/WatchComplication.swift:101-110`). It does not also check `StoreService.cachedProKey`, unlike the iOS widget gate in `VitalsWidget/VitalsWidget.swift:15-23`.

The phone normally sends `showNetCalories && StoreService.shared.isPro` to the watch (`Vitals/App.swift:35-53`), and retries that sync on an entitlement change (`Vitals/App.swift:204-207`). That protection is not guaranteed to reach a complication. On a cold launch, `isPro` begins as `false`, so an old persisted `showNetCalories == true` does not itself create a `false` to `true` or `true` to `false` transition. If WatchConnectivity is not activated, fails, or the watch timeline runs before the context update arrives, the complication can continue to render Net Deficit for a lapsed or free user.

This is a paid-feature access-control leak and creates disagreement between the phone, the watch app, and the watch complication. It remains possible even after a successful phone-side entitlement reconciliation because the complication does not read the reconciled entitlement key.

Required before release: make the complication enforce the same entitlement decision locally, or clear the persisted premium preference as part of a confirmed free state and prove the no-sync case. Add a lapsed-subscriber complication test with a stale `showNetCalories` value and no WatchConnectivity context update.

### P2: Excluded Days dates are mis-parsed for non-Gregorian calendars

The stored key format is explicitly Gregorian. `DailyHealthRecord.key(for:)` emits Gregorian `yyyy-MM-dd` components (`Shared/Models/HealthRecord.swift:26`, `Shared/Models/HealthRecord.swift:42-47`). The reverse conversion in `GoalSettings.date(fromDayKey:)` passes those same numeric components to `Calendar.current` (`Shared/Services/GoalSettings.swift:616-626`). `Calendar.current` can be Buddhist, Islamic, Persian, or another calendar based on the user's locale.

Foundation verification for the same stored key, `2025-09-10`, produced these calendar identifiers and timestamps:

| Locale | Current calendar | Parsed timestamp |
| --- | --- | ---: |
| `en_US` | Gregorian | `1757487600` |
| `th_TH` | Buddhist | `-15377184422` |
| `ar_SA` | Islamic Umm al-Qura | `19468972800` |
| `fa_IR` | Persian | `21361392000` |

The parsed dates can therefore move by centuries instead of representing the stored day. `ExcludedDaysView` uses these dates for calendar selection, list rows, deletion, accessibility labels, and the HealthKit stats query (`Vitals/Views/ExcludedDaysView.swift:68-80`, `:142-155`, `:345-385`). A user with one of these calendars can see the wrong excluded date, fail to match the day in the picker, or get no matching calorie and step details.

Required before release: parse stored keys with an explicit Gregorian calendar using the app's intended time zone. Add round-trip tests for at least Thai, Arabic Saudi, and Persian locales, including list display and removal behavior.

## Checks completed

- 143 unit tests passed, with 0 failures and 0 skips, on the leased iOS simulator.
- Release build for `Vitals`, `VitalsWidget`, `VitalsWatch`, and `VitalsWatchWidget` succeeded with `CODE_SIGNING_ALLOWED=NO`; no project compiler warnings were reported.
- Built artifacts report marketing version `1.8.6` and build `199` for all four targets.
- Info.plist, privacy manifest, HealthKit capability, App Group entitlement, and background-delivery declarations passed the read-only lint checks.
- All 50 localized metadata sets are within the checked App Store limits, and all release-notes files are non-empty. The English app description contains the required health disclaimer.
- `git diff --check` passed for the audited release range and the pre-existing worktree changes.
- The prior build 198 verification recorded 38 of 38 UI tests passing, the Excluded Days purchase and lapse flows passing against the RevenueCat Test Store, an iOS 27 subset passing, and the relevant visual checks passing. This is relevant historical evidence because build 199 has no source changes from build 198.

## Verification limits

- A current targeted UI run for `ExcludedDaysUITests` and `SeededHealthFlowUITests` was interrupted with exit 143 after the app and test runner began launching. The host load was above 700 because other simulator work was running. No individual test completed, so this run is inconclusive and is not classified as a product failure or a pass.
- The entitlement findings were verified from the cold-start and failure paths in source. No production RevenueCat transaction was performed, and no production key was used on the simulator.
- No physical iPhone or Apple Watch run was available for the localized calendar and no-context complication scenarios.

## Worktree integrity

No application or test source files were changed during this audit. The following unrelated changes were already present at the start and were preserved:

- Modified: `fastlane/report.xml`, `scripts/.asc-state.json`, `scripts/testflight.sh`
- Untracked: `.agents/`, `.codex/`, `RELEASE-AUDIT-2026-09-05.md`, `revenuecat-dashboard/`

The only intended addition from this audit is this report.
