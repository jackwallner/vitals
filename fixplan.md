# Fix Plan — Vitals Bug Triage

**Date**: April 14, 2026
**Sources**: `kimifinds.md` (20 items), `claudefinds.md` (validation), `gptfinds.md` (validation)

---

## Triage Summary

| Verdict | Count | Notes |
|---------|-------|-------|
| Fix now | 1 | User-facing broken feature |
| Fix soon | 1 | Swift 6 correctness |
| Fix later | 2 | Resilience hardening |
| Skip | 16 | False positives or design choices |

All three reviewers converge on the same two real bugs. The remaining 16 items from `kimifinds.md` were independently rejected by both Claude and GPT as false positives — verified against the actual code.

---

## 1. FIX NOW — `dietaryEnergyReadGate()` is broken

**Priority**: 🔴 High — probable broken user-facing feature
**Files**:
- `Shared/Services/HealthKitService.swift:77-89`
- `Vitals/Views/DashboardView.swift:765-781, 93-95`

**The bug**: `dietaryEnergyReadGate()` calls `store.authorizationStatus(for:)`, which only returns **write/sharing** authorization status. The app never requests write access for dietary energy (`toShare: []`), so this always returns `.notDetermined`. As a result, `dietaryEnergyReady` is permanently `false`, and `netDeficitNumericReady` is always `false` — the net deficit section shows "—" even when `fetchDietaryEnergyToday()` succeeds with valid data.

**The fix**: Remove the gate entirely. Apple intentionally hides read authorization status — a successful fetch returning `0` is indistinguishable from "denied." The fetch result is the only reliable signal.

Concretely:
1. Delete `dietaryEnergyReadGate()` and the `DietaryEnergyReadGate` enum from `HealthKitService`.
2. In `DashboardView.refresh()`, replace the `switch healthKit.dietaryEnergyReadGate()` block: set `dietaryEnergyReady = true` after a successful fetch, regardless of the old gate.
3. Remove `dietaryEnergyAccessDenied` state if it no longer has a purpose (the `.denied` branch was also unreachable).

---

## 2. FIX SOON — Actor isolation violation in `queryStatisticsCollection`

**Priority**: 🟠 Medium — Swift 6 concurrency correctness
**File**: `Shared/Services/HealthKitService.swift:532-561`

**The bug**: `HealthKitService` is `@MainActor`. The `queryStatisticsCollection` method is `nonisolated` but accesses `self.store` (a MainActor-isolated property) without crossing the isolation boundary properly. This is a Swift 6 strict concurrency violation.

**Why it doesn't crash today**: `HKHealthStore` is designed by Apple to be used from any thread. But this will become a compiler error under `SWIFT_STRICT_CONCURRENCY = complete`.

**The fix** (pick one):
- **Option A** (simplest): Remove `nonisolated` — let the method inherit `@MainActor`. The continuation body still runs on HK's internal queue, so there's no performance concern.
- **Option B**: Keep `nonisolated`, but have the caller (which is `@MainActor`) capture `store` into a local and pass it as a parameter.

Option A is recommended — it's a one-word deletion.

---

## 3. FIX LATER — `fatalError` in DataService in-memory fallback

**Priority**: 🟡 Low — near-impossible failure, but unrecoverable
**File**: `Shared/Services/DataService.swift:36-38`

**The issue**: If the in-memory `ModelContainer` also fails (extremely unlikely), the app crashes with `fatalError`. This is the last-resort path, but `fatalError` in production is a code smell.

**The fix**: Replace with a graceful degradation — e.g., present an error UI or log and return a minimal container. Low urgency since in-memory SwiftData stores have essentially no failure modes.

---

## 4. FIX LATER — Watch background refresh cancellation is ineffective

**Priority**: 🟡 Low — not proven broken today
**File**: `VitalsWatch/App.swift:97-103`

**The issue**: `work.cancel()` only sets `Task.isCancelled`; the underlying `HKStatisticsCollectionQuery` inside `withCheckedThrowingContinuation` has no cancellation check. If HealthKit is ever slow, the cancel is a no-op.

**Why it's low priority**: HealthKit queries typically complete in <2 seconds, and the 8-second timeout is well within the ~15-second watchOS budget. No evidence of actual watchdog kills.

**The fix** (when convenient): Check `Task.isCancelled` inside the continuation, or store the `HKStatisticsCollectionQuery` reference so it can be stopped via `store.stop(query)` on cancel.

---

## SKIP — False positives from `kimifinds.md`

The following 16 items were independently rejected by both Claude and GPT. Verified against the code:

| # | Claim | Why it's not a bug |
|---|-------|--------------------|
| 2 | TZ data corruption | `DailyHealthRecord.key(for:)` uses one consistent static calendar for all key generation |
| 3 | Multi-process SwiftData conflicts | iPhone and Watch are separate devices with separate containers |
| 4 | HK auth not reactive | `HKHealthStoreDelegate` doesn't exist; app already calls `synchronizeAuthorizationStateForFetching()` |
| 5 | DashboardView state race | All `@State` mutations are MainActor-serialized — no race |
| 7 | Widget stale data | Standard WidgetKit behavior; `reloadAllTimelines()` is advisory by design |
| 8 | Pacing DST bug | `calendar.date(byAdding: .day, value: 1)` correctly returns 23/25h on DST days |
| 9 | WatchConnectivity invalid input | Data source is the app's own `GoalSettings`; no external vector |
| 10 | Widget reload spam | Users toggle settings one at a time; well within WidgetKit budget |
| 11 | CSV injection | All exported values are locally-generated numbers and formatted dates |
| 12 | History memory explosion | 10 years ≈ 146 KB; SwiftUI Charts handles this fine |
| 13 | Privacy manifest incomplete | HealthKit uses entitlements, not `NSPrivacyAccessedAPITypes` |
| 14 | Single ModelContext per refresh | Standard SwiftData pattern for discrete writes |
| 15 | URL force unwraps | Constant valid URL strings; standard Swift practice |
| 16 | DateFormatter thread safety | Static formatters; no concurrent mutation |
| 17 | BG task token accumulation | Code uses `do/catch` (not `try?`); `submit()` replaces, doesn't accumulate |
| 18 | ScreenshotConfig repeated lookup | `static let` — computed once, cached forever |

Items 19 (UserDefaults key naming) and 20 (orientation plist) are style/polish, not bugs.

---

## Execution Order

```
1. dietaryEnergyReadGate  →  ~30 min  →  fixes broken net deficit UI
2. Actor isolation         →  ~5 min   →  one-word change
3. fatalError fallback     →  ~15 min  →  next release
4. Watch cancel            →  ~30 min  →  next release
```
