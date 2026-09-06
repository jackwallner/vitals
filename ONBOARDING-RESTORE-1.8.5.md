# Onboarding restore (1.8.5)

Supersedes `ONBOARDING-PITCH-EXPERIMENT.md` and `UPGRADE-TAB-EXPERIMENT.md`.
1.8.5 puts the onboarding pitch back to the 1.7.4/1.7.5 page and removes the
arm machinery entirely.

## Why: the July rate was a real effect, and it was thrown away

Trial starts per App Store install, from ASC daily reports
(`SUBSCRIPTION_EVENT` "Start Introductory Offer" over `SALES` app units, app
`6761743504`). Windows are the dates each version was actually live in the
wild, established from the version reported by single-session RevenueCat
customers on the day they were first seen, not from the ASC created/uploaded
dates.

| Live window | Installs | Trials | Rate | 95% CI |
|---|---|---|---|---|
| 1.7.3 and earlier, May 01 - Jul 10 | 630 | 50 | 7.94% | 6.1 - 10.3 |
| **1.7.4, Jul 11 - 16** | 71 | 14 | **19.72%** | 12.1 - 30.4 |
| **1.7.5, Jul 17 - 21** | 67 | 15 | **22.39%** | 14.1 - 33.7 |
| 1.7.6, Jul 22 - 23 | 37 | 5 | 13.51% | 5.9 - 28.0 |
| 1.7.7, Jul 24 - Aug 18 | 482 | 56 | 11.62% | 9.1 - 14.8 |
| 1.8.0, Aug 19 - 20 | 51 | 9 | 17.65% | 9.6 - 30.3 |
| 1.8.1, Aug 21 - 22 | 50 | 4 | 8.00% | 3.2 - 18.8 |
| 1.8.2, Aug 23 - 26 | 95 | 12 | 12.63% | 7.4 - 20.8 |
| 1.8.3, Aug 27 - Sep 03 | 177 | 13 | 7.34% | 4.3 - 12.2 |

1.7.4 and 1.7.5 carry **byte-identical onboarding** (the only diff between them
is the 30-day TDEE widget), so they are one design and pool: **29 of 138,
21.0%**. Against the pre-pitch baseline p<0.001; against 1.7.7 p=0.005.

The onboarding trial step is what did it. It landed in `5b3035e` on 2026-07-10
and 1.7.4 went live on the 11th, which is the day the rate moves. It is still
the whole funnel on 1.8.3: 94% of instrumented customers see
`onboarding_trial`, and it produced 10 of 15 conversions.

Country mix is stable (~66% tier 1 in every window), so the decline is not ASO
reach diluting the funnel, and it holds inside tier 1 on its own.

## What changed between 21% and 7.3%

Every onboarding commit after 1.7.5 softened the pitch or added to it:
the disclosure moved below the CTA, "Get Started" was unbolded and narrowed to
hug its text, example figures were blurred, an example card and a fifth feature
row were added, and 1.8.4 added four more arms with hero cards. The 1.8.3 pitch
overflows its sheet at default type: the last feature row is cut off mid
sentence.

None of that is individually implicated at p<0.05 (1.8.3 vs 1.8.0-1.8.2 is
p=0.079). The direction is consistent, the endpoint is a return to the exact
pre-pitch baseline, and 138 installs of evidence for the older page beats a
sequence of unmeasured softenings.

## What 1.8.5 does

Restored to `23ca7f4` (build 137):

- **Three steps**: welcome -> goals -> trial. The food question is gone.
- **One HealthKit prompt**, fired on the way out of welcome, carrying the
  dietary and macro types unconditionally.
- **One pitch for everybody**: sparkles glyph, "Go further with Vitals+",
  "Extras that sit on top of your daily calories and steps.", and four rows -
  Net deficit, Streaks & projections, Deeper trends, Summary reports. No
  example card, no hero card, no segmentation.
- **Billing disclosure back above the CTA**, which is where 1.7.5 had it.
- **Soft exit back to full width, subheadline semibold, directly above the
  button.** This is deliberately the shape
  `fleet-soft-exit-cta-benchmark` argues against. Measured in-app evidence for
  this arrangement outranks a cross-app heuristic, and
  `testSoftExitSitsCentredDirectlyAboveTheCTA` pins it so a tidy-up cannot
  revert the revert.
- **No CTA glow.** `CTAGlow` was added in `b8ed8c9` on 2026-08-22, after 1.7.5,
  so the onboarding CTA is the flat coral slab the 21% pitch used. The
  `enabled:` parameter on `primaryLabel` went with it: the glow was its only
  consumer. `Vitals/Views/CTAGlow.swift` stays, because `PaywallView` still
  calls `.ctaGlow()` on the Upgrade tab, which is out of scope here.

Deleted: `Shared/Utilities/OnboardingPitchVariant.swift`,
`StoreService.onboardingPitchVariant` / `onboardingPitchRouting` /
`onboardingAssignmentID`, `Offering.vitalsOnboardingPitchRouting`,
`DebugLaunchConfig.onboardingPitchOverride` / `pitchMaintenanceOverride`,
`VitalsTests/OnboardingPitchRoutingTests.swift`,
`VitalsUITests/OnboardingPitchScreenshotUITests.swift`, and the food step with
`FoodAnswerCard`.

## Kept deliberately

- **Instrumentation.** The impression id is back to `vitals_onboarding_trial`
  with no arm suffix, which is the id the historical
  `pitch_views_onboarding_trial` series is keyed on, so the restore is directly
  comparable to 1.8.3 and earlier. `converted_surface`, `days_to_convert`,
  `pitch_views_at_convert` are untouched.
- **`logsFoodInHealth` on `GoalSettings`.** Onboarding no longer writes it, so
  it is `nil` for new installs and retains its stored value for everyone else.
  `TrialOfferPitch` still reads it and already handles `nil`.
  `ConversionDiagnostics` still reports `logs_food` when a value exists.
- **The `ViewThatFits` overflow guard on the trial page.** The restored pitch
  fits on every phone at default type, so this is invisible in the shipped
  layout, but large Dynamic Type can still overflow it and an unreachable
  headline is the one failure this page has actually had.
- **Every post-1.7.5 bug fix**: the keyboard Done bar, the zero-shift CTA, the
  Restore button on every purchase surface, the unsettled-transaction fix, the
  HealthKit total corrections.

## RevenueCat

Nothing was changed. The `onboarding_pitch` routing table is still on all eight
offerings at `enroll_pct: 100`, `a:50 / c:50` in both segments, and 1.8.4 - live
since 2026-09-06 - reads it. That split keeps running on the 1.8.4 population
while 1.8.5 is in review, which costs nothing and is the only head-to-head read
the arms will ever get.

**A 1.8.5 binary ignores the table entirely.** No dashboard change is needed
before or after it ships; the table simply stops being read as 1.8.5 adoption
climbs. `scripts/set-pitch-arm.py` now only affects customers still on 1.8.4.

Still true and still not done, from `ONBOARDING-PITCH-EXPERIMENT.md`: the
`default` offering's `upgrade_tab` still reads `timeline`, and `expb03a6c2204`
is still running. Both are cleanup for the dead Upgrade-tab test, neither
blocks anything here.

## Test state at the time of this change

Unit suite 117/117. All four `OnboardingFlowUITests` and all three
`OnboardingCTARecoveryUITests` pass.

**Sixteen UI tests in the premium screenshot scene fail, and they failed
before this change.** `UpgradeTabPlanVisibilityUITests` (5),
`TrialOfferPresentationUITests` (5), `VariantRotatorUITests` (3),
`SeededHealthFlowUITests` (2), all with some form of "purchase button never
rendered" / "Upgrade tab never rendered" / "Trial pitch never appeared".
`UpgradeTabPlanVisibilityUITests/testCatalogVariantShowsEveryPlanAboveTheButton`
was re-run against a clean stash of this branch's parent and fails identically
there, so none of it is caused by the restore. The other fifteen share the
signature and are assumed, not proven, to have the same cause.

Products load fine in the onboarding scene in the same run - the trial CTA
renders with a live price - so this looks specific to
`VITALS_SCREENSHOT_SCENE=premium` rather than to RevenueCat being unreachable.
**It is unresolved and worth its own pass**, particularly
`testHistoryUpgradeTapRendersARealPitchNotABlankSheet`, which guards the blank
sheet from `sheet-item-not-ispresented` that shipped in build 163.

## What to check, and when

Read trial starts per install from the ASC daily reports, not from a weekly
dashboard glance: weekly counts here are 10-25 trials, so a 2x weekly swing is
noise. Give it three weeks from 1.8.5 adoption, then compare against 21.0% and
against 7.3%, both of which are in the table above.

If it does not recover, the softenings are not the cause and the July peak was
something else that happened to land on 1.7.4's release date. That is a real
possibility and this document is the record of the bet.
