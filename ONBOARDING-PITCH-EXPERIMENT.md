# Onboarding pitch experiment (1.8.4)

Scope for the next build. Supersedes the Upgrade-tab test in
`UPGRADE-TAB-EXPERIMENT.md`, which is being stopped because it varies a surface
that produces almost no conversions.

## Why this surface

Pulled 2026-08-30 from all 1,577 RevenueCat customers plus their subscriber
attributes, filtered to production (one sandbox test device was excluded; see
below). 127 customers carry the pitch instrumentation, 6 real conversions.

| Surface | Viewers | Views | Conversions |
|---|---|---|---|
| `onboarding_trial` | 73 | 76 | **5** |
| `history_deep_trends` | 70 | 104 | 0 |
| `trial_offer_launch` | 38 | 151 | 0 |
| `trial_offer_historyLoad` | 20 | 22 | 0 |
| `trial_offer_settings` | 11 | 23 | 0 |
| Upgrade tab, all three arms | 38 | 45 | 1 |

Three facts that decide the design:

1. **The onboarding pitch is the business.** 5 of 6 conversions, at 6.8% of the
   people who see it. Every other surface combined produced one sale on roughly
   300 views.
2. **Conversion is immediate.** All six converted on day 0, at a median of 1
   pitch view. Non-converters saw a median of 2 and up to 19. Nobody is talked
   into it later, so re-pitch volume is not a lever.
3. **The last experiment could not have worked.** `PaywallView.upgradeTabVariant`
   returns `.catalog` whenever `focus != nil`, and the onboarding step does not
   read the arm at all, so all three arms rendered an identical onboarding pitch.
   RevenueCat still credited those conversions to the arm, which is the whole of
   the 4/0/2 result.

**Sandbox caveat, load-bearing for anyone re-running this query.** The
attributes API does not filter sandbox; the experiment Results API does. One
customer looked like an arm-B sale and was a debug device: production and
sandbox subscriptions on one record, 6 subscriptions, `converted_with_trial:
false` (the Apple ID had burned its intro offer), backdated `first_seen_at`, and
both `pitch_views_upgrade_tab_catalog` and `..._full_list` set, which is
impossible for a real user because arm assignment is pinned. Always join to
`/customers/{id}/subscriptions` and drop `environment: sandbox` first.

## What is detectable, and therefore what to test

~22 new customers/day (627 in 28 days). The onboarding pitch is a new-customer
surface, so that is the whole enrollable population. Two arms gives ~11/arm/day.

At a 6.8% base rate, 80% power, alpha 0.05:

| Effect | n/arm | Days |
|---|---|---|
| 6.8% -> 13.6% (double) | ~309 | **~28** |
| 6.8% -> 10.2% (+50% rel) | ~1,150 | ~105 |

So a month buys a verdict on a large swing and nothing else. This is much better
than the Upgrade tab, where nothing was ever detectable, and it is entirely
because the base rate is 7x higher rather than because the traffic is.

Consequences, both non-negotiable:

- **Two arms. Never three.** A third arm pushes the one-month read to six weeks.
- **Test a big swing, not copy.** Headline and subhead wording cannot plausibly
  double a 6.8% rate, so testing them burns the only slot available this quarter.

## The arms

**A, control.** Today's pitch: sparkles glyph, `trialHeadline` /
`trialSubheadline`, three `TrialSellingPoint` rows.

**B, maintenance-led.** Replace the three feature rows with the user's own TDEE
/ maintenance number rendered as the real widget, the way `maintenance_led` does
on the Upgrade tab, with the feature rows demoted to a single line beneath it.

Why B is the evidence-led arm rather than a guess: on the Upgrade tab,
`maintenance_led` had both the only real sale and the highest tab-open rate
(36% of instrumented enrollees vs 25% and 26%). That is weak evidence, but it is
the only directional signal the last test produced, and it is the arm that shows
a personal number instead of a feature list.

Held constant across arms: packages, price, trial length, the `Get Started` soft
exit and its geometry (tuned against the fleet benchmark, do not touch it in
this test), and the existing `logsFoodInHealth` headline branch.

## Code changes

1. **New metadata key `onboarding_pitch`**, and a new `OnboardingPitchVariant`
   enum (`control` / `maintenance`), in `Shared/Utilities/`. Deliberately not
   reusing `upgrade_tab`: the two surfaces have to be independently settable, and
   `upgrade_tab` is entangled with `PaywallView`'s `focus` logic.
2. **Read the arm in the onboarding step.** `trialPage` in
   `Vitals/Views/DashboardView.swift:3090` branches on the new variant.
3. **Await the offering before drawing the pitch.** This is the main risk. The
   trial step renders seconds after first launch, and if the offering has not
   landed the arm silently falls back to control while RevenueCat still counts
   the customer as enrolled. That dilutes the treatment arm toward the control
   and is invisible in the results. Gate `trialPage` on the offering the same way
   the CTA is already gated on `conversionCTAReady`, reusing the 6s
   `trialCTAWaitLimit` and its fallback.
4. **Record what was drawn, not what was assigned.** New subscriber attribute
   `onboarding_variant`, written by `ConversionDiagnostics` alongside
   `paywall_variant`, so a fallback caused by (3) is visible in the data rather
   than hidden in it.
5. **Impression id carries the arm**, as the Upgrade tab already does:
   `vitals_onboarding_trial_<arm>`. Without this, impression-to-purchase pools
   two different screens.

## RevenueCat setup

- Two offerings, identical packages, differing only in
  `{"onboarding_pitch": "..."}`.
- **Enrollment: new customers only.** The opposite of the last experiment, and
  for a specific reason rather than a reversal of taste: existing customers never
  see onboarding again, so enrolling them adds people who cannot possibly convert
  on the tested surface. Under new-and-existing that would have been the large
  majority of enrollees.
- Condition `app_version >= 1.8.4`. `>=` not `=`, so 1.8.5 does not silently end
  enrollment.
- Primary metric: initial conversion rate. Read at 4 weeks; if the arms are
  within noise, ship control and move on rather than extending.
- New-customers-only enrollment means `Custom attribute` conditions are
  unavailable, so there is no `logs_food` branch. Fine: the headline already
  personalises on that answer inside both arms.

## Before 1.8.4 ships

Both belong to stopping the current experiment, in this order:

1. Set the `default` offering metadata to `{"upgrade_tab": "catalog"}`. It still
   reads `timeline`.
2. Stop `expb03a6c2204`. Stopping reverts every enrolled customer to `default` on
   their next paywall view, which is why the order matters.

## Not in scope

- Price, trial length, or plan sold (`onboardingTrialPackage` stays yearly).
  Those need new ASC products and are a different kind of experiment; keep the
  raise and its copy together when that day comes.
- Removing the soft exit. A hard gate is the one change that could plausibly move
  the number more than arm B, and it trades trial starts for retention and
  ratings on a health app. Not worth the slot.
- The zero-yield re-pitch surfaces. `trial_offer_launch` showing 151 views to 38
  people for zero sales is worth cutting, but it is a retention change, not a
  conversion experiment, and it should not be confounded with this test.
