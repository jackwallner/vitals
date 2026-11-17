# Pre-submit deep review: Vitals 1.9.3 (build 254), 2026-11-08

Scope: origin/main at `22c9628` on branch `review/2026-11-08-vitals-deep`. The live App Store version is 1.9.2. Its last commit is `f783fd2`, the parent of `a2adf20`, which bumped MARKETING_VERSION to 1.9.3. The diff from `f783fd2` to HEAD covers 25 app source files. In this deep pass I read every changed app file line by line and also covered the reachable paths outside the diff: purchase, restore, onboarding, persistence and migration, notifications, widgets, watch, intents, iPhone Duo and localization.

## What was checked

- **Purchase and restore** (`StoreService`, `PaywallView`, `TrialOfferPitch`, onboarding trial step)
  - Exit offer removal: nothing still reads the `exit_offer` offering, so the current offering is the only plan source.
  - `isPro` is any active entitlement, so 1.9.1 to 1.9.2 customers on `yearly.exit` keep access.
  - Ask to Buy deferral leaves the sheet up. An approved deferral records the funnel once.
  - Restore reports "no purchase" separately from a failure.
  - The paywall dismisses on `isPro`. Terms (Apple EULA), Privacy and Restore sit on every paywall and pitch.
  - Trial copy is gated on resolved StoreKit eligibility. Prices come only from StoreKit.
- **Lapse handling**
  - `EntitlementStatus.lapseConfirmed` needs a server answer, so a cached "no access" at launch no longer turns off Net Deficit or Macros, closes the recap, or drops Custom History.
- **Pause day migration** (`ExcludedDays.legacyPauseDay`)
  - Read through for UTC, east and west offsets, half-hour zones and a DST change between pause and read.
  - Keys are always Gregorian, so Buddhist, Japanese and Islamic calendar devices round-trip.
  - Watch sync accepts the new day key and an older phone's instant.
- **Today day stepping**
  - Covers `DayBrowser`, `loadPastDay` cancellation, the background reset to today and midnight rollover.
  - Goal celebrations, projections and widget writes still read today's figures, not the viewed day's.
- **Weekly recap**
  - Restore after a later notification grant uses one stable identifier with remove-then-add, so it can't double-schedule.
  - It cancels again if a lapse lands mid-call. The tap route waits for an unconfirmed entitlement.
- **Rating tenure**
  - `syncProRunStart` has a 3 s deadline and handles lifetime-only buyers (no auto-renewable periods).
  - A 16-day billing-retry gap is not counted as a lapse.
- **Onboarding**
  - The flag is persisted in the App Group and the sheet can't be swiped away.
  - Every exit (Get Started, purchase, restore, already Pro) goes through `finishOnboarding()`.
- **SwiftData**
  - There is one model, and every field added later has a default.
  - A failed store open quarantines the old files and rebuilds the cache, then falls back to in-memory.
  - No `Codable` decoding of saved data anywhere.
- **Widgets, watch, intents**
  - Premium readouts are gated on `isProCached`, and the watch gets values the phone already gated.
  - Goal fallbacks prevent division by zero.
- **Crash patterns**
  - Every `!`, `[0]`, `first!`, `try!`, `Int(` of a division and `fatalError` in `Shared/`, `Vitals/` and the extensions.
  - Only constant URLs and an unreachable `init(coder:)` remain.
- **Localization**
  - `python3 Tools/Localization/check.py`: 837 keys, 39 languages, 0 problems.
  - Every new 1.9.3 string has all translations.
- **App Review**
  - All debug UI and launch overrides sit behind `#if DEBUG`.
  - No Android or Play links in the iOS UI, no hard-coded prices, and no treat, cure or diagnose wording.

## Findings

No P0 or P1 found. Nothing was changed in app code.

| Severity | File:line | What happens | Status |
|---|---|---|---|
| P2 | `Shared/Services/HealthKitService.swift:1041` | `saveHistoryToCache` overwrites the last 32 cached days with whatever `fetchHistory` returns. It has no all-zero guard like the one `refreshCache` has for today. If a background refresh (`Vitals/App.swift:327`) or the midnight rollover reads zeros while the phone is locked, the TDEE widget and the week bars would show those days as empty until the next foreground refresh. | Not fixed: unproven. HealthKit may throw `errorDatabaseInaccessible` on a locked device instead of returning zeros, and the existing `catch` would cover that. Worth a device check with a locked phone. |
| P2 | `Vitals/App.swift:265` | `ReviewPromptTracker.recordAppLaunch()` and `ConversionDiagnostics.recordAppOpen()` run in `VitalsApp.init`. That also runs when HealthKit background delivery relaunches a terminated app, so the second-launch rating gate can pass early and the `appOpens` count sent to RevenueCat is inflated. | Not fixed: no user-visible defect. The rating ask still needs a goal hit on screen and the 30-day cooldown. Analytics only otherwise. |

## Tests

`gh-sim test --scheme Vitals` on HEAD. The run id and result are in the commit that adds them below.
