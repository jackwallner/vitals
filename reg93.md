# REG93: released build versus latest TestFlight build

Date: 2026-09-04

Result: conditional NO-GO for interpreting the 1.8.4 onboarding experiment. The
core onboarding path is stable in the simulator pass, but the `c` arm makes a
false personalization claim and the current RevenueCat state is not the
experiment described in the repository.

Status as of 2026-09-04, after the follow-up pass in this repository: REG93-01
and REG93-03 are fixed in source and shipping in build 189. REG93-02 is
unchanged and still open, because it is remote RevenueCat configuration rather
than code and it is an experiment-design decision. See "Resolution" below.

## Comparison

- App Store Connect live version: 1.8.3, build 186, `READY_FOR_SALE`.
- Latest valid TestFlight build: 1.8.4, build 188, uploaded 2026-09-03.
- Exact TestFlight archive: `build/Vitals.xcarchive`, ASC build id
  `14db20d1-bc91-4684-aa53-7f73790cdd29`.
- Source comparison: commit `6577a82` (1.8.3 release source) to `9a9bff9`
  (1.8.4 source). The current dirty worktree was not used for findings.

## Findings

### REG93-01: P1, locked-number arm presents fixed numbers as personal data

The new `c` arm says “We can work out your numbers” and “Your own maintenance
and resting burn, from your own Health data”, then renders hard-coded values
`2,340`, `1,610`, and `730`. The card's accessibility label also describes
these as “Your maintenance, resting and active burn”. The exact 1.8.4 source
does not load HealthKit data for this card.

Evidence:

- `Vitals/Views/DashboardView.swift:3131-3137` selects the locked-number card.
- `Vitals/Views/DashboardView.swift:3276-3305` contains the fixed values and
  personal-data copy.
- The `pitch-c-locked-numbers` attachment in
  `/tmp/vitals-audit-evidence93/pitch/` renders the card in the 1.8.4 source
  pass.
- Current RevenueCat routing sends 50% of eligible users to `c` from the
  current offering, so this is an exposed path, not only an unreachable arm.

Impact: a health app is showing an invented maintenance preview while claiming
it comes from the customer's Health data. Blurring the values does not make the
personalization claim true, and VoiceOver receives the same misleading claim.

Reproduction: reach onboarding's trial page as a user routed to `c`. The card
is identical regardless of the user's Health history.

Acceptance: either label the figures as an example, or load and validate the
customer's actual HealthKit-derived values before describing them as personal.

### REG93-02: P1, live RevenueCat state does not run the documented 1.8.4 test

The 1.8.4 binary contains arms `a` through `e`, but the read-only RevenueCat
snapshot taken during this audit shows:

- Current `default`: `enroll_pct: 100`, with only `a` and `c` at 50/50 in both
  segments.
- `ob_control`: `enroll_pct: 0`, fallback `a`.
- `ob_newpitch`: `enroll_pct: 100`, but also only `a` and `c` at 50/50 in both
  segments.
- `exp2f942dc97b` is `draft` with `started_at: null`, and conflicts with the
  running Upgrade-tab experiment `expb03a6c2204`.

Therefore the current state can serve `a` or `c`, but cannot serve the
documented food arms `b` and `e` or the non-food arm `d`. If the new experiment
is started without correcting the offering metadata and conflict, its
treatment is not the documented new-arm treatment.

Impact: TestFlight results cannot be attributed to the intended 1.8.4
comparison. The new build also changes the user-visible experience relative to
1.8.3 for users assigned to `c`, even though the repository experiment notes
describe the new experiment as staged and not yet affecting customers.

Acceptance: make the remote offering tables, experiment status, conflict state,
and test documentation agree, then verify assignments with fresh 1.8.4
customers before reading conversion results.

### REG93-03: P2, arm impression attribution can race the offering refresh

`onboardingArm` is recomputed from `currentOffering` on every SwiftUI draw, but
the onboarding impression is sent once from the trial view's `onAppear` with
`oncePerSession: true` (`Vitals/Views/DashboardView.swift:2406-2427,
3093-3103`). The food answer also triggers an asynchronous offerings refetch
(`Shared/Services/StoreService.swift:607-615`).

If the trial page first draws while RevenueCat is unavailable, it records the
fallback `a`; if the offering arrives afterward, the screen can redraw as `c`
or another arm without sending a matching arm impression. The diagnostic
attribute can then contain the final arm while RevenueCat has the earlier
impression id.

Impact: the per-arm funnel can be wrong for slow or offline launches. This is
an instrumentation defect rather than a user-facing crash, and it was not
exercised by the screenshot harness because that harness bypasses RevenueCat
impression recording.

Acceptance: resolve and retain one arm before showing the trial page, or make
the recorded impression follow the arm that is actually displayed. Add a delayed
offering test covering the fallback-to-treatment transition.

## Verified during the audit

- Exact 1.8.3 and 1.8.4 source builds succeeded after regenerating only the
  temporary audit projects. The products reported 1.8.3 (186) and 1.8.4 (188).
- The 1.8.4 unit suite passed 123/123 tests, including 15/15 routing tests.
- The onboarding screenshot pass reached all five arms `a` through `e` without
  a crash or blocked CTA on an iPhone 17 Pro simulator running iOS 26.5.
- At the default text size, the five arm screenshots show the CTA, billing
  disclosure, and legal links. The `a` arm's layout and content remain the
  released control layout.
- The source diff from 1.8.3 to 1.8.4 is limited to onboarding pitch layouts,
  routing, conversion diagnostics, and DEBUG verification hooks. No HealthKit
  calculation, SwiftData cache, widget, or watch data-flow change was found.

## Limits

The runtime pass used the exact 1.8.4 source in a Debug simulator build; the
TestFlight archive metadata was verified separately as build 188. No physical
device HealthKit run, production purchase, accessibility-size run, or live
App Store purchase was performed. No app source, App Store Connect state, or
RevenueCat state was changed. This report is the only requested repository
file added by the audit.

## Resolution

### REG93-01: fixed, build 189

Arm `c` no longer invents a number. `buildingNumbersCard` reads the customer's
real maintenance through `HealthKitService.fetchEnergyAverages()` into
`pitchMaintenance`, loaded by a `.task(id: onboardingArm)` on `trialPage`.

- With enough history (the fetch looks back 30 days and needs 7 completed
  ones), the card shows the customer's own TDEE and BMR. These are blurred
  behind an Unlock capsule, which is honest here: the figure is real and
  computed from their own Health data, and what Vitals+ sells is access to it.
  The header reads "We know your maintenance" and the foot names the day count.
- With too little history, no figure is drawn at all. The card falls back to
  skeleton blocks, the header "Your numbers, still building", and the foot
  "Unlocks with Vitals+ once a week of Health data is in."
- Both VoiceOver labels now match what is on screen, and the blurred digits are
  `accessibilityHidden`, so assistive tech is not read an invented figure.

The other arms that show figures caption them: arm `a`'s chips are headed
"EXAMPLE · WHAT VITALS+ ADDS", arm `b`'s card "EXAMPLE · ONE DAY, JOINED".

`DebugLaunchConfig.pitchMaintenanceOverride` (`VITALS_PITCH_MAINTENANCE=none`
or `=tdee/bmr/days`) walks both states without seeding HealthKit.

### REG93-02: still open, remote configuration

Re-checked read-only with `scripts/set-pitch-arm.py show` on 2026-09-04. Every
offering, including `default (current)`, `ob_control`, and `ob_newpitch`, still
carries `{"a": 50, "c": 50}` in both segments. The finding stands: `b`, `d`,
and `e` cannot be served, so the documented five-arm test is not the test that
is running.

Not changed here. Editing the live routing table is a production change to what
real customers see and a decision about which arms to run and at what ramp, so
it needs a deliberate call rather than an audit follow-up. The one thing build
189 does change is that the 50% currently routed to `c` now see an honest card
instead of the invented preview.

### REG93-03: fixed, build 189

The arm is now fixed once, before the trial page can draw, instead of being
recomputed from `currentOffering` on every draw.

- `resolveOnboardingArm()` stores the arm in `resolvedArm`, and is called from
  the goals step's Continue action immediately before `step = .trial`. That is
  the last moment the offering has to arrive: `recordLogsFood` started the
  refetch a step earlier and the goal fields buy it the time.
- `onboardingArm` reads `resolvedArm` and only recomputes as a fallback.
- The `onAppear` impression, the rendered card, and the
  `ConversionDiagnostics` variant attribute therefore all name the same arm.
  A late offering can no longer flip the screen out from under an impression
  that was already sent for the fallback.

If the table is still `.disabled` at that moment it pins `.current`, which is
the shipping pitch. Pinning the fallback is deliberate: an arm that changes
under the reader is worse than a fallback that was chosen once and honestly.

## Follow-up verification

- `xcodegen generate`, then a clean simulator build of the `Vitals` scheme:
  BUILD SUCCEEDED.
- `VitalsTests`: 132/132 passed, 0 failures, on `agent-sim-5`
  (iPhone 17 Pro, iOS 27.0).
- No RevenueCat, App Store Connect, or offering state was changed by this pass.
