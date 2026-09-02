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

**B, personal-number-led.** Replace the three feature rows with one card showing
a number that is already the user's own, rendered as the real widget rather than
described in a bullet. Which card is chosen by the food answer, in the app:

| `goals.logsFoodInHealth` | Card |
|---|---|
| `true` | Macros (the macro ring, as `feature_led` draws it) |
| `false` | Maintenance / TDEE (as `maintenance_led` draws it) |

**The split happens in the app, not in RevenueCat.** `commitFoodAnswerAndContinue`
writes `goals.logsFoodInHealth` at the food step
(`Vitals/Views/DashboardView.swift:2882`), two steps before the trial step, so
the answer is on the device by the time the pitch draws. That matters for a
reason beyond convenience: routing on the answer inside RevenueCat would need a
`Custom attribute` enrollment condition, which forces new-and-existing
enrollment, which is exactly wrong for an onboarding-only surface. Branching
locally keeps new-customers-only. This is the old `UPGRADE-TAB-EXPERIMENT.md`
"Option C", and at this traffic level it is now clearly the right one.

It also fixes the reason the macro card was excluded last time. The 1.8.3 binary
could not substitute, so the macro card would have drawn blank for a non-logger.
Here the substitution is the design.

**B is one arm, not two.** The treatment is the strategy "show them their own
number", and the card is how that strategy is executed for each user. Reading
macro and TDEE as separate cells would halve each one (the instrumented split is
roughly 44% loggers / 56% non-loggers) and push the read from four weeks to
eight. `onboarding_variant` records which card actually drew, so the two can be
compared afterwards for direction. That comparison is a hypothesis generator for
the next test, not a decision this test is powered to make.

Held constant across arms: packages, price, trial length, the `Get Started` soft
exit and its geometry (tuned against the fleet benchmark, do not touch it in
this test), and the existing `logsFoodInHealth` headline branch.

## What the current data says about this test

From the same 2026-08-30 pull, sandbox excluded. 126 instrumented customers, 71
of whom answered the food question (the other 55 predate it and are existing
users who updated).

**The food answer does not predict conversion.**

| Answer | Saw the pitch | Converted | Rate |
|---|---|---|---|
| `true` (logs food) | 31 | 2 | 6.5% |
| `false` | 40 | 3 | 7.5% |

At n=31 and n=40 that is no difference and no evidence of one either way. The
useful reading is negative: do not expect the split itself to be the win. The
bet is that a personal number beats a feature list, and the split is only there
so that number is relevant to whoever is looking at it.

**The macro card is genuinely untested.** Exactly one customer has ever seen
`feature_led`, via the retired 1.8.3 targeting rule. Every prior argument for or
against it has been reasoning, not evidence. Arm B is the first time it reaches
real users.

**Plan the cells on 44/56.** Of the 71 who answered, 31 log food and 40 do not.

## Code changes

1. **New metadata key `onboarding_pitch`**, and a new `OnboardingPitchVariant`
   enum (`control` / `maintenance`), in `Shared/Utilities/`. Deliberately not
   reusing `upgrade_tab`: the two surfaces have to be independently settable, and
   `upgrade_tab` is entangled with `PaywallView`'s `focus` logic.
2. **Read the arm in the onboarding step.** `trialPage` in
   `Vitals/Views/DashboardView.swift:3090` branches on the new variant.
3. **Branch on the food answer in `trialPage`.** Read
   `goals.logsFoodInHealth` and pick the card. No RevenueCat condition, no new
   audience.

   The offering-fetch race is *not* a real risk here, contrary to an earlier
   draft of this file. The onboarding container starts `fetchProducts()` at the
   `welcome` step, and the trial step is three steps later behind a food
   question, two typed goal fields and the HealthKit permission sheet.
   `fetchProducts` also assigns `currentOffering` and `products` in the same
   call, so the existing `conversionCTAReady` gate already implies the offering
   metadata has landed. The only residual case is the pitch body drawing before
   the CTA is ready on a cold, slow network, which would show as a content
   flicker rather than as arm dilution. Draw the control body until the offering
   resolves, and let `onboarding_variant` (below) record if it ever happens.

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
  unavailable. That costs nothing here, because the food split is done in the
  app rather than by RevenueCat routing. See "The arms".

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
