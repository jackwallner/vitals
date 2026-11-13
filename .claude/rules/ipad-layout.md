---
paths:
  - "Vitals/App.swift"
  - "Vitals/Views/DashboardView.swift"
  - "Vitals/Views/PaywallView.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "Vitals/Views/CTAGlow.swift"
  - "VitalsUITests/IPadCaptureUITests.swift"
  - "scripts/capture-ipad.sh"
  - "project.yml"
---

# Vitals: iPad layout (2026-11-12)

iPad support is free: `TARGETED_DEVICE_FAMILY "1,2"` on the app and the iOS
widget (the watch targets stay as they are), all four orientations in
`UISupportedInterfaceOrientations~ipad`.

- No iPad-only layout tree. The iPhone Duo split (see `iphone-duo.md`) already
  puts Today (with the tab bar) on the leading side and History on the trailing
  side at regular width of 720 pt or more. A 13-inch iPad in portrait (1032 pt)
  and landscape (1376 pt) takes it; Split View below 720 pt keeps the single
  column, where `ReadableWidth` caps content at 640 pt. Each pane is forced
  compact, so a pane lays out as a phone.
- A pane is twice a phone's height, so `DashboardView.mainContent` scales the
  ring, line width and figure caps by 1.4 on an iPad (idiom `.pad`, pane at
  least 480 pt wide). Phone and Duo panes keep the phone caps. Without it the
  free Today pane showed a small ring with a hole between it and the steps card.
- `PaywallView.pinsPlanCards` is off on an iPad: its pane fits the pitch and
  every plan, and pinning them left a hole between the benefits and the button.
- Sheets (onboarding, trial pitch, review) open as iPad form sheets; Settings
  opens in the Today pane, as on the Duo.
- Copy still says "iPhone" in two places (onboarding "never leaves your iPhone",
  Settings steps caption). Both are true of Health data and were left alone;
  changing them means 35 translations.
- Captures: `scripts/capture-ipad.sh <out> [scene ...]` (throwaway 13-inch iPad
  simulator, local) or `gh-sim test --scheme VitalsUITests --only
  VitalsUITests/IPadCaptureUITests --device "iPad Pro 13-inch (M5)"`.
  `IPadCaptureUITests` rotates the device (nothing else can headless). The gh-sim
  attachments of a landscape frame come back rotated 90 degrees clockwise:
  `sips -r 270` fixes them. The local script takes undistorted `simctl io` frames.
  Programmatic `requestGeometryUpdate` does not rotate an iPad. gh-sim `launch`
  manages about 2 screens per run on an iPad (10-minute step limit).
