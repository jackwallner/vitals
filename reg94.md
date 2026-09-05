# REG94: released build versus latest TestFlight build

Date: 2026-09-04

Result: conditional NO-GO for the onboarding treatment rollout. Build 189
preserves the released control path and fixes the prior false-number issue,
but treatment arms with taller two-line headers clip their main headline under
the onboarding sheet edge.

## Comparison

- App Store Connect live version: 1.8.3, build 186, `READY_FOR_SALE`. Build
  metadata id: `8cb7baa5-c7e0-421a-983f-530df43be10d`.
- Latest TestFlight build: 1.8.4, build 189, `VALIDATED`, uploaded 2026-09-04
  at 12:28 PM. Build metadata id:
  `d3dfb4e2-2a97-488f-afc7-d2b0a45049b4`.
- Build 189 is in the internal `jack` group with two testers and is
  `Ready to Submit`. The TestFlight page exposed no install, session, crash,
  or feedback signal for this build.
- Both binaries report bundle id `com.jackwallner.vitals`, minimum iOS 17.0,
  arm64, HealthKit capability, the same App Group, and iPhone plus Apple Watch
  device families. No entitlement or platform metadata drift was found.
- Source comparison: commit `6577a82` (released 1.8.3 source) to commit
  `27ff178` (1.8.4 build 189 source).
- The exact TestFlight IPA was not downloaded or installed. Runtime findings
  below use a Debug simulator build from commit `27ff178`, with the release
  baseline built from commit `6577a82`. No production RevenueCat key or real
  purchase was used.

## Findings

### REG94-01: P1, treatment pitch headline is clipped and cannot be scrolled into view

Status: Open. Confirmed in arms `b` and `c` at the default iPhone 17 Pro
simulator size and text size.

The released 1.8.3 build shows the complete trial hero, headline, five selling
points, CTA, disclosure, and legal links. In the 1.8.4 source-equivalent build:

- Arm `b`, the food-logger pitch, displays only the lower portion of the first
  line of `Your food, against your burn` under the rounded sheet's top edge.
- Arm `c`, the maintenance pitch, displays only the lower portion of the first
  line of `We know your maintenance` under the same edge. This was reproduced
  with eight days of Health data, which is the state that makes this arm's real
  maintenance card render.
- Arms `a`, `d`, and `e` fit at this default size during the same pass. The
  defect is therefore tied to the taller combinations, not a general inability
  to reach the CTA.
- A downward swipe does not recover the hidden text. The trial page is not
  scrollable, so the customer cannot inspect the primary value proposition.

Evidence files from the simulator pass:

- Release baseline: `/tmp/vitals-reg94-release-trial.png`
- Current arm `b`: `/tmp/vitals-reg94-current-b-trial.png`
- Current arm `c`: `/tmp/vitals-reg94-current-c-trial.png`
- Current control arm `a`: `/tmp/vitals-reg94-current-a-trial-final.png`
- Current arm `d`: `/tmp/vitals-reg94-current-d-trial.png`
- Current arm `e`: `/tmp/vitals-reg94-current-e-trial.png`

Likely cause: `Vitals/Views/DashboardView.swift:2441-2446` places
`trialPage` in a fixed, max-height container, while
`Vitals/Views/DashboardView.swift:3179-3238` stacks a multi-line header, a hero
card, supporting rows, and spacers. The fixed bottom bar reserves the CTA,
disclosure, and legal footer at `Vitals/Views/DashboardView.swift:2730-2750`.
The combined content exceeds the available height and is clipped at the top.

Impact: customers assigned to an affected treatment see a visibly broken
first-run purchase screen and lose the explanation of what they would receive.
The CTA remains usable, but the most important conversion content is hidden and
there is no user recovery path. Arm `c` is exposed by the current read-only
RevenueCat allocation observed during the audit.

Reproduction:

1. Install a fresh build from commit `27ff178`.
2. In a Debug run, force `VITALS_ONBOARDING_PITCH=b` or `c`, then complete
   Welcome, the food question, and Goals. This only selects the compiled arm;
   production uses RevenueCat assignment.
3. Observe the trial screen and try to swipe the clipped headline into view.

Acceptance: keep the complete header visible for every routed arm and supported
text size, either by making the content scrollable above a fixed CTA or by
reducing the card and vertical spacing while respecting the sheet safe area.

### REG94-02: P1/P2, live ASC copy says there are no servers while the app uses a billing service

Status: Open, metadata-only issue. This is not a binary regression introduced
by build 189, but it remains a mismatch in the current release listing.

The live ASC description says that no data leaves the phone and that there are
no servers. The repository's current listing copy says health data is never
uploaded, but also says purchases are processed by Apple and RevenueCat
(`fastlane/metadata/en-US/description.txt:57-62`). The product site makes the
same distinction, stating that Apple and RevenueCat are the only network calls
(`docs/index.html:566-573`). Health data can remain local while the blanket
"no servers" and "no data leaves your phone" statements are still misleading.

Impact: the released listing can undermine user trust and create privacy or
review risk because its absolute claims do not match the app's subscription
status behavior.

Acceptance: reconcile the ASC description with the implementation. State that
health data stays on-device, while Apple and RevenueCat handle purchase and
subscription status without receiving health data.

## Experiment state observed

The 1.8.4 binary contains onboarding arms `a` through `e`. The read-only
RevenueCat snapshot still routed the observed offering only between `a` and `c`;
the food-dependent arms were not reachable from that live table. This makes the
arm `c` clipping a currently exposed path, while the arm `b` result is a
compiled-layout check for a treatment that the documented experiment may later
serve. No RevenueCat or App Store Connect state was changed.

## Verified with no release-to-test regression found

- Release and current source-equivalent app builds succeeded. The products
  reported 1.8.3 (186) and 1.8.4 (189), respectively.
- The current unit suite passed 132/132 tests with zero failures.
- The release and current onboarding paths both reached the Health Access
  prompt after the food answer. No permission-order regression was observed.
- The current paywall displayed yearly, monthly, and lifetime plans. Selecting
  monthly and lifetime updated the CTA and disclosure, and Restore showed the
  expected no-purchase message in the test environment.
- History's Custom flow opened its focused PDF pitch and dismissed cleanly.
- The previous arm `c` false-personalization issue is fixed in build 189 source:
  the card uses actual Health history when available and an honest skeleton when
  it is not. It no longer renders the old fixed numbers as the customer's data.
- No watch-specific source change was found between the release and build 189
  commits. Watch runtime behavior was not independently exercised.

## Limits

- ASC binary metadata was verified directly, but the exact internal TestFlight
  IPA was not installed. Runtime evidence is from source-equivalent Debug
  builds, with the production purchase path excluded.
- The full UI test invocation exceeded the 300-second XcodeBuildMCP timeout and
  was terminated. It is not counted as a pass or fail. The manual arm pass and
  the unit suite are the usable verification signals.
- No app source, App Store Connect, RevenueCat, or release configuration was
  changed by this audit. `reg94.md` is the only task-owned repository file.
