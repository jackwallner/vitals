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

These already exist (verified 2026-08-26):

| Offering | `upgrade_tab` | Note |
|---|---|---|
| `default` | `timeline` | current; unknown to 1.8.3, falls back to `catalog` |
| `pw_full_list` | `full_list` | |
| `pw_short_list` | `catalog` | duplicate of `upgrade_catalog` |
| `upgrade_catalog` | `catalog` | duplicate of `pw_short_list` |
| `pw_macro` | `feature_led` | |
| `pw_maintenance` | `maintenance_led` | |

Two catalog offerings exist where one is needed. Retire one before wiring an
experiment, so the control arm has a single unambiguous identifier.

**Every arm must contain the identical set of packages.** The arms are layout
only. The onboarding trial page reads its yearly package off the same
`offerings.current`, so an arm with a different product, price, or trial length
would silently change what onboarding sells, not just how the Upgrade tab looks.

## Audiences: RevenueCat cannot branch on the food answer

**Corrected 2026-08-26.** An earlier version of this document split the test into
a food-logger audience and a non-logger audience. RevenueCat will not do that.

`logs_food` does reach RevenueCat, as a subscriber attribute with value `"true"`
or `"false"` (`StoreService.recordLogsFood`, `ConversionDiagnostics`). But a
subscriber attribute is readable, not routable. The audience builder rejects it:

```
POST /internal/v1/developers/me/projects/{pid}/audiences/actions/preview
{"rules":{"groups":[{"conditions":[{"field":"logs_food", ...}]}]}}
-> 400  Field "logs_food" is not a valid audience rule field.
```

Audiences and experiment targeting accept RevenueCat's own built-in fields (app,
app version, platform, SDK version, country), not custom attributes. Verified
against the live project, not inferred from the docs.

So the attribute keeps its full value for **analysis**: every result below can be
sliced by `logs_food` after the fact. It just cannot decide who sees what. Any
branch on the food answer has to live in the app.

## Experiments

RevenueCat supports up to four variants in one experiment, split evenly.

**Option A, no code change, can run as soon as 1.8.3 has adoption.**
One experiment, everyone, 3 variants:
`full_list` / `catalog` / `maintenance_led`

None of these three need food logging, so nobody is sold a blank screen. The
macro arm simply is not tested yet.

**Option B, needs one more build.** One 4-arm experiment including `feature_led`,
with the app substituting at draw time: if the assigned arm is the macro card and
`goals.logsFoodInHealth == false`, draw the maintenance card instead. Loggers get
a clean 4-way test; non-loggers get 3 arms with maintenance at double weight.
`paywall_variant` already records what was actually drawn, so the substitution
appears in the data rather than hiding in it.

The macro arm cannot ship unsubstituted to everyone: the macro card renders blank
for someone who logs no food, so it is not a paywall, it is a bug with a price on
it. That constraint is what Option B buys its way around.

Recommended: A first, fold B into whatever ships after 1.8.3.

## Timing: this is gated on 1.8.3 adoption, not on the build being ready

Do not start any experiment while 1.8.2 is the version most customers run. See
`RELEASE-1.8.3.md`, "Do not start the experiment yet", for the full reasoning.
The short version: live 1.8.2 falls back to `timeline`, not `catalog`, so both
arms render the same screen on that population and the signal dilutes to nothing.

Two live changes belong to the 1.8.3 rollout, in this order, and neither is
housekeeping that can be done early:

1. **Delete the targeting rule "1.8.3 tester (Jack) - macro card"**
   (`app_version = 1.8.3` -> `pw_macro`). Harmless while 1.8.3 is TestFlight
   only, because it matches one tester. The moment 1.8.3 is public it pins every
   customer on that version to the macro card, non-loggers included. This must be
   gone before the release goes live.
2. **Change `default` metadata from `timeline` to `catalog`.** Not a typo fix.
   `timeline` is a real layout in the live 1.8.2 binary, so this immediately
   changes what every current customer sees. Do it deliberately, as part of the
   rollout, once 1.8.3 is the version that matters.

Scope the experiment itself with an app-version condition so older builds are
never enrolled.

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
