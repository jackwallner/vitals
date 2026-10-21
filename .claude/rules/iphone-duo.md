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
  over raw captures; current set in `captures/vitals/duo-split-20261021/`.
