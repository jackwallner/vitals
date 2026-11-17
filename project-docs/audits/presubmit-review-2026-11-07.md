# Pre-submit review: Vitals 1.9.3 (build 254), 2026-11-07

Scope: app sources (`Shared/`, `Vitals/`, `VitalsWatch/`, `VitalsWidget/`,
`VitalsWatchWidget/`, `project.yml`, `Info.plist`) from the last 1.9.2 commit
(`a2adf203^`, build 243) to `origin/main` `22c96287` (1.9.3 build 254). 49
commits, 26 app files, about 1,600 lines added and 1,250 removed. Docs,
fastlane, qa/ and tests were not reviewed.

Areas read line by line: exit offer removal (StoreService, PaywallView,
TrialOfferPitch, MainTabView, onboarding), the server-confirmed lapse
(`EntitlementStatus.lapseConfirmed`) and everything gated on it, the deferred
purchase (Ask to Buy) conversion record, the pause stored as a day instead of
an instant (migration, watch sync, legacy phone payloads), the paid-run tenure
read from StoreKit, weekly recap restore and cold-launch routing, Today's
past-day browser and custom pull to refresh, History's Custom range lapse
handling and cache priming, streak milestone tiers, and the large-text layouts.

## Result

No P0 or P1 defect found. Nothing was changed in app code.

Checks run:
- `python3 Tools/Localization/check.py`: 837 keys, 39 languages, 0 problems.
  Every new string ("Previous day", "Next day", "Language", "Opens iOS
  Settings", the "for this day" empty states) is in the catalog.
- The legacy pause migration (`ExcludedDays.legacyPauseDay`) simulated in
  Python against every IANA zone, on ordinary and DST-change days, read back
  in summer and winter offsets: 0 wrong days.
- Paywall still has Restore, Terms (Apple EULA) and Privacy Policy links. No
  hard-coded prices, other-platform links or health claims added. Every new
  debug switch (`VITALS_DEFER_PURCHASE`, the Custom-range seed) sits inside
  `#if DEBUG`.
- `vitalsPaywallOffering` is still `current ?? "default"`, so the `exit_offer`
  offering can never become the paywall, and `products` no longer carries
  `exit_annual`. The offering and ASC plan stay live for 1.9.1-1.9.3 binaries
  as `.claude/rules/exit-offer.md` requires (dashboard side, not code).
- No SwiftData model changed. New UserDefaults reads (`averagesPausedDay`,
  `conv.pendingConversion`) use optional casts and fall back cleanly.

## Findings

| Severity | Location | What happens | Status |
|---|---|---|---|
| P2 | Vitals/Views/DashboardView.swift:5452 | `ScrollDragReader` adds itself as a target of Today's scroll view pan gesture and never removes it. UIKit does not retain gesture targets. If SwiftUI ever drops this background view while keeping the same `UIScrollView`, the pan keeps a dangling target. Today's view tree keeps both alive together in every path read, so no crash was reproduced. | Not fixed: not shown to break. Removing the target in `willMove(toWindow:)` would be cheap hardening. |
| P2 | Shared/Services/StoreService.swift:665 | `syncProRunStart` runs once, on Today's first data load, and only when `isPro` is already true. A subscriber whose cached flag is stale "free" at that moment, and turns Pro later in the session, gets no tenure read until the next launch, so the one-month "kept Vitals+" rating moment waits a launch. | Not fixed: it only delays a rating ask, by design of the gate. |
| P2 | Vitals/Views/HistoryView.swift:3044 | `ContentWeightedRow.columns` divides by the sum of ideal widths. If every child had zero ideal width and the proposal were narrower than the spacing, the widths would be NaN. Its children are always text cards with a label, so the sum is never zero in practice. | Not fixed: unreachable with current callers. |
| P2 | App Store Connect / RevenueCat | The `exit_offer` offering, `exit_annual` package and `com.jackwallner.vitals.yearly.exit` plan must stay live and sellable while 1.9.1-1.9.3 binaries are in use. 1.9.3 never reads them. | Not a code issue. Confirm before release that nothing archives them. |

## Tests

Not run to completion. `gh-sim test --scheme Vitals --only VitalsTests` was
submitted as run `vitals@20261107-223106-c504-claude-imac6d3e-1107-223631-5717`
(GitHub Actions run 42455450399) and stayed queued for the whole 90-minute
window behind other fleet runs. No test result exists for this review. No app
code changed, so build 254's own release gate results still stand. Once the
queued run finishes, `gh-sim get <id>` fetches its result.
