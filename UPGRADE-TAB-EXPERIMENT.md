# Upgrade-tab layout experiment (1.8.3+)

Everything in the binary is ready. This is the RevenueCat-side setup, to be done
**before** the manual release of 1.8.3, so the first customers on the new build
are already being assigned arms.

## The arms

All four layouts already exist in the app. RevenueCat picks one by putting a
metadata key on the offering it assigns:

```json
{ "upgrade_tab": "full_list" }
```

| Jack's letter | Layout | `upgrade_tab` value |
|---|---|---|
| a | Full catalog (all ten features above the plans) | `full_list` |
| b | Condensed list (hero, short benefit list, plans) | `catalog` |
| c | Macros (macro card rendered as the real thing) | `feature_led` |
| d | TDEE (maintenance widget) | `maintenance_led` |

`catalog` is the control and the fallback: a missing key, an unknown value, or a
build that predates an arm all degrade to it rather than to a blank screen. Only
builds containing a layout can draw it, so this experiment cannot reach anyone on
1.8.2 or older.

## Offerings

Create four offerings, one per arm, each carrying its `upgrade_tab` metadata.

**Every arm must contain the identical set of packages.** The arms are layout
only. The onboarding trial page reads its yearly package off the same
`offerings.current`, so an arm with a different product, price, or trial length
would silently change what onboarding sells, not just how the Upgrade tab looks.

## Audiences

The split is conditioned on the onboarding food question, which reaches
RevenueCat as the subscriber attribute `logs_food`, value `"true"` or `"false"`.

- **Food loggers**: `logs_food` is `"true"`
- **Non-loggers**: `logs_food` is `"false"`

Customers with no value at all (installs predating the food question, anyone who
never finished onboarding) match neither. Leave them on the default offering
serving `catalog`; do not write the second audience as "not true", or every
unanswered install lands in the non-logger test and dilutes it.

## Experiments

RevenueCat supports up to four variants in one experiment, split evenly, so both
of these are a single experiment each rather than a stack of A/B tests.

**Experiment 1, scoped to the food-logger audience, 4 variants:**
`full_list` / `catalog` / `feature_led` / `maintenance_led`

**Experiment 2, scoped to the non-logger audience, 3 variants:**
`full_list` / `catalog` / `maintenance_led`

The macro arm is deliberately absent from experiment 2: the macro card renders
blank for someone who logs no food, so it is not a paywall, it is a bug with a
price on it.

## Timing caveat, read this one

Audience membership is evaluated when offerings are fetched. `logs_food` is now
pushed to RevenueCat the moment the food question is answered
(`StoreService.recordLogsFood`), followed by a refetch, which is as early as the
answer exists. But RevenueCat caches offerings for a few minutes, so a customer
who answers the question and reaches the Upgrade tab inside that window can still
be served the assignment made while the answer was unknown. The next cold launch
corrects it.

Before this build, `logs_food` only reached RevenueCat once a paywall had already
been seen, which was always after the assignment it is supposed to steer. That
was the blocker; it is fixed.

## What is already being collected

No further app work is needed to read the results.

- RevenueCat splits the experiment by offering on its own.
- `paywall_variant` subscriber attribute: the arm this binary actually drew.
  Not the same fact as the offering assigned, because an older build falls back
  to `catalog` while still counting as enrolled in a treatment.
- `offering_id`: the offering the arm came from.
- Paywall impressions are reported per arm, as
  `vitals_upgrade_tab_<arm>`, so impression-to-purchase is measurable per arm
  rather than pooled across four different screens.
- At the moment of purchase, frozen and never rewritten by later views:
  `converted_variant`, `converted_offering`, `converted_surface`,
  `converted_plan`, `converted_with_trial`, `pitch_views_at_convert`,
  `days_to_convert`.
- `logs_food`, for segmenting anything else by the same answer.

## Not in this build

The hidden ten-tap arm rotator is now `#if DEBUG` and is absent from the
TestFlight and App Store binaries (verified: none of its strings survive in a
Release build). Walking the arms by hand means installing a debug build.
