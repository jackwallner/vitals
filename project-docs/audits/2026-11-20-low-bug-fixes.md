# Low bug fixes, 2026-11-20 (B8 to B15)

Base commit: 28ed8cf. Branch: fleet/20261120-210941-ad00-claude.

**Nothing in this list has been compiled or run.** This fleet machine has no
Swift toolchain and `gh` is not logged in here, so `gh-sim test` stops at
"gh auth login" before it dispatches (the repo is public; the private check is
just the unauthenticated API call failing). Every change was checked by reading
only. The first job for the reviewer is one `gh-sim test` run of the full suite
and one `gh-sim launch` at the largest accessibility text size.

| Id | Title | Outcome | Commit | Proof | What changed |
|----|-------|---------|--------|-------|--------------|
| B8 | Long streak reads 89 after install | fixed | 6701534 | `testFirstTodaySyncWritesTheWholeStreakWindow` (written, not run) | The first Today history sync writes `MilestoneCalculator.streakHistoryDays` (400) days, later syncs 90; a one-time flag in the App Group marks the backfill. |
| B9 | Custom range shifts a day after a zone change | fixed | f2c9e1e | `testCustomRangeDaysKeepTheirCalendarDayAcrossZones`, `testCustomRangeInstantShiftsADayAcrossZones` (written, not run) | The range is saved as `yyyy-MM-dd` keys (`CustomRangeDays`) and rebuilt as local midnight on load. Old saved instants still read once and are rewritten as keys. A one-day range (start and end on the same day) stays valid. |
| B10 | Purchase that throws after payment shows a plain failure | fixed (code read only, not unit testable) | d475d0d | None: `StoreService` links RevenueCat and is not in the test target. | When `Purchases.purchase` throws a non-deferred error for a free customer, `StoreService.purchase` re-reads customer info with `.fetchCurrent`, runs Restore first for already-purchased and receipt-in-use errors, and returns `.purchased` if the entitlement is there. Otherwise it rethrows the same error, with `lastError` as it was. |
| B11 | Second-launch gate counts background relaunches | fixed | ae820aa | `testForegroundLaunchCountsOncePerProcess` (written, not run); call site by reading only | Launches (rating tracker and RevenueCat app-opens counter) are counted once per process at the first `scenePhase == .active` in `RootView`, not in `VitalsApp.init`. |
| B12 | Today cannot go down until midnight | fixed | 9fc914f | `testLowerLiveStepsReplaceAHigherCachedRead`, `testAnEmptyLiveReadFallsBackToTheCache` (written, not run; they pin `TodaySnapshotResolver`, the logic the view now uses) | `refresh()` shows the live read, falling back to the cached row only when the live read is all zeros. The Watch has its own SwiftData store (`VitalsWatch/App.swift`), so the old "Watch writes a higher number" comment was wrong. |
| B13 | Deep Trends Calculating forever after a failed reload | fixed (code read only, no harness for a thrown HealthKit error) | 61f4b09 | None | A failed newest load cancels the preceding-window task and clears `isCalculatingTrends`; `loadPreviousWindow` returns at once if its token is already stale, so a late-starting task cannot set the flag back. |
| B14 | Buy button label cut at accessibility sizes | fixed | 876aaed | Not yet seen on screen. Needs `gh-sim launch --args "-PaywallSnapshot yearly -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"` | Label allows 3 lines at accessibility sizes (1 otherwise) and the button is `minHeight: 50` instead of `height: 50`. Non-accessibility layout is unchanged. |
| B15 | Trial sheet footer at accessibility sizes | fixed | 0d06670 | Not yet seen on screen. Same launch, with a trial sheet scene | Restore, Terms and Privacy stack vertically at accessibility sizes (no dot separators), and the sheet also offers `.large` there. Other sizes keep the single 78% detent and one-line links. |

Tests for B8, B9, B11 and B12 are in `VitalsTests/BugCatalogFixTests.swift`
(commit 3030578). All use files the test target already compiles, so no
`project.yml` change or `xcodegen generate` was needed. No new Swift files and no
new or changed user-facing strings, so the localization catalog is untouched
(`python3 Tools/Localization/check.py`: 0 problems).

## Verification status

- Final green full-suite run: none. No run was possible (see top).
- Tests failing on the base commit: not known.

## For the reviewer

- Run the full suite first. A compile error is possible anywhere below.
- B10: `ErrorCode.productAlreadyPurchasedError` and `.receiptAlreadyInUseError` were used from memory of the RevenueCat SDK; the compile will confirm. Check `purchase` for a customer who is already Pro (`wasPro`): it rethrows as before.
- B9: `HistoryPrefs.sanitizedRange` changed its "start must precede end" test to a comparison of the stored start, so a range whose start and end are the same day stays a one-day range. Check the legacy path (instants saved by older builds).
- B8: existing installs run the 400-day read once on the next Today refresh (one-time extra HealthKit work in a utility-priority task).
- B11: `onChange(of: scenePhase, initial: true)` on `RootView`; confirm it fires on a cold launch in the simulator and that UI tests which expect the rating or pitch flows still pass.
- B12: a live read that is all zeros while the phone is unlocked still falls back to the cache, as before.

## Needs Jack

- Log `gh` in on this machine (or rerun the verification on the Air) so the suite and the two accessibility screenshots can run.

## Found while verifying B14 and B15

At the largest text size the pinned checkout filled the whole paywall, so the
plan choices could not be seen, and the trial sheet opened showing only its
buttons. At accessibility sizes the checkout now scrolls below the plans, plan
cards stack name over price, benefit rows and headlines read in full, and the
trial sheet opens at full height. Checked on a local simulator at the largest
size (scrolled top to bottom) and at the default size (unchanged). Full suite:
gh-sim `vitals-mbaire203-1120-235259-11991`, 300 passed.
