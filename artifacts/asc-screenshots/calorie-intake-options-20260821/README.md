# Total Calories calorie intake screenshot options

Two eight-frame App Store review options built from the current validated Vitals captures.

## Options

### Option A: calorie-intake-led

Marked as the provisional `submission` set in `manifest.json`.

1. Total burn
2. Total burn on the wrist
3. Calorie intake at a glance
4. Burned minus eaten
5. Macro goals
6. Macro patterns
7. Active and resting burn
8. Dark mode

### Option B: net-deficit-led

Alternative sequence with the calorie gap as the third frame and the macro detail immediately after it.

1. Total burn
2. Total burn on the wrist
3. Calorie gap
4. Protein, carbs, and fat together
5. Macro goals
6. Intake patterns
7. Active and resting burn
8. Vitals+

## Intake proof

The literal UI shows 1,950 logged calories, 142 g protein, 186 g carbs, and 61 g fat, with the 31%, 40%, and 29% macro-calorie split. The net-deficit capture shows +450 from 2,400 burned minus 1,950 eaten.

## Provenance and QA

- `raw/` contains byte-for-byte copies of the corrected canonical iPhone captures from `total-calories-refresh-20260820`.
- `raw/capture-report.json` maps those copied files to the successful simulator run and preserves their hashes.
- The Watch hero is a validated staged local Watch capture, presented as a Watch hero treatment.
- `outputs/` contains the rendered RGB PNGs, transparent foregrounds, UI masks, contact sheets, search grids, and the independent audit report.
- Target is `iphone_65`, 1284 x 2778.
- `shotflow all` passed with two audited sets.

## Desktop review

The final PNGs are also copied to `/Users/jackwallner/Desktop/calorie-intake-options-20260821/`, with one folder per option.
