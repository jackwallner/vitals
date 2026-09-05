# REG94: released build versus latest TestFlight build

Date: 2026-09-04

Result: GO. The clipped-headline defect is fixed and verified against a
same-harness capture of the build it was found in. The remaining item is
metadata that is already correct in the repository and reaches the store with
the 1.8.4 listing upload.

## Comparison

- App Store Connect live version: 1.8.3, build 186, `READY_FOR_SALE`. Build
  metadata id: `8cb7baa5-c7e0-421a-983f-530df43be10d`.
- Latest TestFlight build at audit time: 1.8.4, build 189, `VALIDATED`,
  uploaded 2026-09-04 at 12:28 PM. Build metadata id:
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

### REG94-01: P1, treatment pitch headline drawn off the top of the sheet

Status: **Fixed**, verified. Was open against build 189, confirmed in arms `b`,
`c`, and `e` at the default iPhone 17 Pro size and text size.

The released 1.8.3 build shows the complete trial hero, headline, five selling
points, CTA, disclosure, and legal links. In build 189 the trial step is a
fixed-height container (`Vitals/Views/DashboardView.swift:2441`) holding a page
whose Spacers centre it above the zero-shift CTA bar. That was right for the
one pitch 1.8.3 shipped. 1.8.4 added four more arms, each with a hero card the
released pitch never carried, and an arm whose content exceeds the container
has nowhere to go: it overflows the Spacers and draws over the dimmed
background above the sheet's rounded top edge, where nothing can scroll it back
into view.

Measured on the same capture harness, distance from the sheet's top edge
(y=190px) to the first ink of the headline. Negative means the headline was
drawn outside the sheet:

| arm | build 189 | fixed | verdict |
|---|---|---|---|
| `a` current (control) | +10px | +38px | was flush against the edge |
| `b` macro/food | **-4px** | +39px | headline was outside the sheet |
| `c` locked numbers | **-4px** | +40px | headline was outside the sheet |
| `c` no history | +67px | +67px | unchanged, pixel-identical |
| `d` two weeks | +49px | +49px | unchanged, pixel-identical |
| `e` two weeks + food | **+2px** | +39px | headline touching the edge |

The original audit recorded arm `e` as fitting. It did not: its headline sat
2px inside the sheet edge and bled over the rounded corners. Arm `a`, the
control, was 10px inside, which is flush rather than clipped. Only `d` and the
no-history state of `c` had real clearance.

**The fix** (`Vitals/Views/DashboardView.swift:2441`): the trial step is a
`ViewThatFits(in: .vertical)`. The first branch is the shipped layout, and an
arm that fits still gets it to the pixel. The second is the same page in a
`ScrollView`, taken only by an arm that would otherwise overflow, so nothing
can be drawn where the customer cannot reach it. `trialPage` takes a `minGap`
so the fit test measures the pitch rather than the padding around it: at the
old minimum of 8 the test rejected arm `a` over 8pt it would have given back
the moment it was laid out for real.

This also covers the case the audit never exercised. Every arm overflows at a
large enough Dynamic Type size, and before this change every one of them
overflowed off the top of the sheet.

Cost, and it is the only one: arm `a` sits close enough to the edge of fitting
that it takes the scrolling branch, which puts the last wrapped line of its
fourth selling point ("moved for") just below the fold, with a sliver visible
as the scroll affordance. It buys the headline 28px of clearance it did not
have. Arms `d` and `c`-no-history are byte-identical to build 189 (mean pixel
difference 0.04, which is the clock).

Evidence, both sets captured through `OnboardingPitchScreenshotUITests` on
`agent-sim-1` so they are directly comparable:

- Before: `/tmp/reg94-fix-evidence/before-<arm>.png`
- After: `/tmp/reg94-fix-evidence/after-<arm>.png`

### REG94-02: P2, live ASC copy says there are no servers while the app uses a billing service

Status: **Already fixed in the repository, pending upload.** Not a binary
regression and not something a TestFlight build changes.

The live 1.8.3 listing says "No data leaves your phone." and "No analytics. No
ads. No servers. No accounts. No tracking." while the app calls RevenueCat for
subscription status. Verified against ASC directly rather than from memory:

- Repository locales carrying the honest disclosure: **50 of 50**.
- Live 1.8.3 locales carrying it: **0 of 50**.

So the corrected copy already exists for every locale
(`fastlane/metadata/en-US/description.txt:57-62` and its 49 siblings) and says
health data stays on device while Apple and RevenueCat handle purchases without
receiving it. The product site already matches (`docs/index.html:566-573`). The
gap is only that it has never been uploaded: a `READY_FOR_SALE` version cannot
be edited, so this reaches customers when the 1.8.4 draft version is created
and its metadata is uploaded. No action is available before then, and none is
needed after, provided the 1.8.4 release runs
`./scripts/upload-appstore-metadata.sh`.

## Experiment state observed

Read live from RevenueCat during this pass, not inferred:

```
enroll_pct 100, fallback a, force null, salt 1840a
logs_food    {a: 50, c: 50}
no_food_log  {a: 50, c: 50}
```

Both live arms, `a` and `c`, were among the affected ones, so the defect was on
the path 100% of 1.8.4 first-runs would have taken. Arms `b`, `d`, and `e` are
compiled but not routed; they are covered because the table is editable without
a build. No RevenueCat or App Store Connect state was changed by this audit or
by the fix.

Timing note the original report understated: 1.8.4 is not on the App Store, so
no paying customer ever saw the clipped headline. The exposure was TestFlight
only, and the fix lands before the version ships.

## Verified

- Release and current source-equivalent app builds succeeded. The products
  reported 1.8.3 (186) and 1.8.4 (189+), respectively.
- Unit suite: 132/132, zero failures, on the fixed tree.
- `OnboardingPitchScreenshotUITests` runs to completion in ~195s and passes on
  the fixed tree. The original report could not use it because the invocation
  exceeded a 300-second tool timeout; run it on the `VitalsUITests` scheme, not
  `Vitals`, which does not include the target.
- All six pitch states captured before and after on the same device and
  harness, and compared numerically rather than by eye.
- The release and current onboarding paths both reached the Health Access
  prompt after the food answer. No permission-order regression was observed.
- The current paywall displayed yearly, monthly, and lifetime plans. Selecting
  monthly and lifetime updated the CTA and disclosure, and Restore showed the
  expected no-purchase message in the test environment.
- History's Custom flow opened its focused PDF pitch and dismissed cleanly.
- The previous arm `c` false-personalization issue remains fixed: the card uses
  actual Health history when available and an honest skeleton when it is not.
- No watch-specific source change was found between the release and build 189
  commits, and the fix does not touch watch sources. Watch runtime behavior was
  not independently exercised.

## Limits

- ASC binary metadata was verified directly, but the exact internal TestFlight
  IPA was not installed. Runtime evidence is from source-equivalent Debug
  builds, with the production purchase path excluded.
- Verification is at the default text size on an iPhone 17 Pro. The fix is
  what makes larger text sizes safe, but no capture was taken at one.
- `OnboardingPitchScreenshotUITests` flaked once on arm `a`, failing to
  register the tap on the food card under machine load. It is a known
  load-related flake in this suite, not a product defect; the run was repeated
  and passed.
