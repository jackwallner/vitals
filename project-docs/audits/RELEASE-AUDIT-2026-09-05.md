# Release audit, 2026-09-05

## Baseline

Verified through App Store Connect on September 5:

- Live: 1.8.3 (186), `READY_FOR_SALE`, source commit `6577a82`.
- Latest TestFlight at audit start: 1.8.4 (190), `VALID`, internal testing active.
- Draft 1.8.4 remains `PREPARE_FOR_SUBMISSION`, attached to build 190 at audit start.
- Monthly, yearly, and lifetime products are all `APPROVED`.
- Retrieved crash feedback has no submissions newer than June 24. This is feedback evidence, not a complete crash-rate measurement.

Runtime testing uses source-equivalent simulator builds, not downloaded App Store or TestFlight binaries. Simulator purchases use RevenueCat's Test Store; the production key is excluded by the simulator guard.

## Scope

Compared the live source to current HEAD, reviewed app-wide data and purchase paths, and exercised the test suites. HealthKit calculations, cache schema, widget code, and Watch code have no changes from build 186 to build 190. The changes primarily introduce onboarding pitch variants and purchase attribution.

## Findings and corrections

### Non-loggers were shown food-dependent examples

The new control pitch's feature list respected the food-logging answer, but its example card and subtitle did not. Someone choosing "No, just track my burn" still saw net deficit and protein, even though these require food data.

The control now shows maintenance, a goal streak, and projected burn for a non-logger or an unanswered food preference. Food loggers retain net-deficit and protein examples. Both variants explicitly label the figures as examples, including their VoiceOver descriptions.

The segmentation UI tests now force the control arm and inspect the example card in addition to feature rows. This prevents remote experiment assignment from changing the scenario under test.

## Verification

- Unit suite: 132 tests passed, zero failures.
- Evidence: `/tmp/vitals-audit-unit-20260905.xcresult`.
- UI verification and final TestFlight upload are in progress.

## Verification limits

Physical-device HealthKit ingestion, locked-device background scheduling, and Apple's production purchase sheet cannot be fully proven by simulator testing. Release archive validation and TestFlight processing are separate checks from simulator results.
