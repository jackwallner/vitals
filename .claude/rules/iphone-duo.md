---
paths:
  - "Vitals/App.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "Vitals/Views/CTAGlow.swift"
  - "scripts/render-duo-screenshots.py"
---

# Vitals: iPhone Duo (2026-10-21)

- Unfolded (regular width, at least 720 pt), `MainTabView` puts the tabs (Today
  or Upgrade, plus the tab bar) on the leading side of the fold and History on
  the trailing side; the History tab button is hidden there. The fold edges come
  from `GeometryProxy.verticalFold()` (iOS 27.1 `reservedRegions(.division)`),
  else an even split. Portrait unfolded (669 pt) and every compact width keep the
  single column.
- Unfolded, the tab bar heads the leading pane, as on iPad: the pane starts
  below the bar's measured height (`UnfoldedSplit.primaryTopInset`) and runs to
  the display's bottom edge like History, and `\.isUnfoldedPane` drops the
  90 pt floating-bar clearance in Today, History and Vitals+. A bar docked
  under the pane was rejected (2026-10-23): Settings and Vitals+ scroll past
  the pane, so their last card was always sliced at the bar's edge. Settings
  fills the Today pane (overlay outside Dashboard's NavigationStack) instead
  of a form sheet dimming both panes across the fold. Both panes fade out
  over the last 28 pt at the display's bottom edge, so no line is sliced there.
- Folding only moves frames: Dashboard and History stay mounted, so scroll and
  period survive. Keep `ReadableWidth` branch-free for the same reason.
- Each pane gets `horizontalSizeClass = .compact`, so its screen lays out as on a
  phone. A pane frame must sit after any `safeAreaInset`, which fills its
  proposal and centred the paywall across the fold.
- Simulator: `agent-sim checkout vitals --slot 11`, `duo-hinge -d <udid> flat|closed`.
  The outer display only renders after a cold boot in the closed pose. Display
  ids change per boot; resolve them from `simctl io <udid> enumerate` by width
  (outer 1398, inner 2007).
- App Store set (`APP_IPHONE_DUO`, 1398x2034): `scripts/render-duo-screenshots.py`
  over raw captures; current set in `captures/vitals/duo-20261024/` (source 17c07cd, passed independent
  review 2026-10-24). Store frames: Today, deficit, Vitals+ tools, Body Profile, folded.
  Macros is left out: its pushed back chevron sits beside the fold.
- Captures: one `gh-sim all --device "iPhone Duo"` with `--env
  VITALS_SCREENSHOT_MODE=1` and one `--screen "-ScreenshotScene <scene>"` per
  surface (the launch argument overrides `VITALS_SCREENSHOT_SCENE`). Never
  `--url`: iOS 27.1 raises an "Open in" alert.
- The Duo set is all subscriber scenes (`premiumDashboard`, `calorieIntake`,
  `netDeficit`, `macroHistory`, `premiumActive`, `bodyProfile`, `settingsPro`).
  `bodyProfile` reads height, weight and body fat from `ScreenshotFixtures`. `history` and
  `premium` are free-tier (Upgrade tab with a lock, locked Custom and PDF in
  History) and were rejected as inconsistent with the rest of the set
  (2026-10-23); they stay in the phone set only.
- Every captured figure comes from `ScreenshotFixtures`. Seed each HealthKit
  read the surface shows: an empty dietary history made History's deficit equal
  its calories (rejected 2026-10-23). `ScreenshotFixturesTests` guards it.
- A detail scene opens pushed over History (`HistoryView(pushing:)`), never as
  its own stack root, so it has its back button.
- Unfolded, a pushed detail hides the navigation bar and draws its own back
  button and title (`paneDetailHeader`), like History's header. iOS 27.1 put
  the system back button in the vertical bar under the status bar at the
  display's edge, outside the pane (rejected 2026-10-23).
  `toolbarVerticalBehavior(.disabled)` on the panes is not the fix: it moved
  the status bar into an 80 pt band over both panes and shifted pane margins.
  Other pushed screens (Body Profile, Excluded Days) use
  `.unfoldedPaneBackHeader(title)` for the same row. Settings in the pane has
  a sheet's rounded top under the tab bar.
