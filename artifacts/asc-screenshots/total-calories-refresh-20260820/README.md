# Total Calories ASC screenshot refresh

Ten 1284 x 2778 RGB App Store screenshot candidates in the same screen-first style as the current Total Calories ASC set and the supplied Claude Design source.

## Final order

1. `final/01-total-burn.png` - Total burn from Apple Health
2. `final/02-active-resting.png` - Active, resting, TDEE, and BMR breakdown
3. `final/03-daily-patterns.png` - Calorie and step history
4. `final/04-net-deficit.png` - Burned minus food logged
5. `final/05-macros.png` - Protein, carbs, fat, and macro calories
6. `final/06-macro-goals.png` - Progress against macro goals
7. `final/07-macro-patterns.png` - 30-day macro history and trends
8. `final/08-on-your-wrist.png` - Apple Watch and complication context
9. `final/09-dark-mode.png` - Dark appearance
10. `final/10-go-further.png` - Vitals+ feature pitch

## Provenance

- `raw/` contains the literal Vitals simulator captures used by the compositor.
- `raw/capture-report.json` records the leased simulator, source dimensions, capture status, and lease check-in.
- `qa/provenance.json` records hashes for each raw source and final frame.
- `qa/contact-sheet.png` is the visual review sheet.
- The reference source was `/Users/jackwallner/Downloads/Total Calories.zip`, especially `screenshots-app/panels.jsx` and `screenshots-app/phone-screens.jsx`.
- `watch-capture.png` is the current local Watch capture used in the Watch composition.
- `macro-still-life.png` is the only generated visual. It is used as a background plate; no phone UI was sent to image generation.

The macro captures use the app's screenshot fixtures: 142 g protein, 186 g carbs, 61 g fat on the dashboard; 150 g, 250 g, and 70 g goals; and a 30-day history chart. The TDEE/BMR capture uses 2,380 TDEE, 1,715 BMR, and a 30-day Apple Health average label.

## Verification

- 10 final PNGs
- Every final PNG is 1284 x 2778 and RGB
- Raw capture status is `ok`
- Simulator lease was checked in
- Unit tests: `xcodebuild test ...`, 67 tests passed

These are review artifacts only. Nothing was uploaded or changed in App Store Connect.
