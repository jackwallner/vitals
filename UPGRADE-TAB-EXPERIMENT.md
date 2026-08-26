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

## Audiences: the food split works, but it costs the enrollment mode

**Corrected twice. This version is from reading the Create-experiment form
directly on 2026-08-26; trust it over the two above it.**

`logs_food` reaches RevenueCat as a subscriber attribute (`StoreService.recordLogsFood`,
`ConversionDiagnostics`) and **is** selectable as an experiment enrollment
condition. The earlier claim in this file that RevenueCat cannot branch on it was
wrong. What is true is narrower:

> Custom attributes aren't supported when enrolling only new customers.
> (tooltip on the disabled option, Create experiment form)

So the enrollment mode decides whether the food branch is available at all:

| Enrollment | Conditions offered |
|---|---|
| **New customers** | Any audience, Country, App, App version, Platform, RC SDK version. `Custom attribute` present but greyed out. |
| **New and existing customers** | All of the above **plus `Custom attribute`**, whose key list includes `logs_food`, `paywall_variant`, `offering_id`, `pitch_*`, `days_since_first_pitch`. |

Two things that earlier notes got wrong and this settles:

- The `audiences/actions/preview` API rejecting `logs_food` ("not a valid
  audience rule field") was the **Targeting** feature, a different surface from
  experiment enrollment criteria. It says nothing about experiments.
- A 2024 RevenueCat community answer saying new customers enroll regardless of
  app version is stale. `App version` is a live condition in both modes now.

**Cost of choosing "new and existing":** it enrolls customers who have already
seen the current Upgrade tab, sometimes many times. For a layout test that is a
dirtier population than new-only, because response to a new layout is confounded
by prior exposure. `pitch_views_at_convert` at least makes the confound visible.
It also carries a hard SDK floor, applied automatically and not editable:
iOS 5.66.0+. Vitals is on **5.71.0**, so this is satisfied.

## Experiments

Up to 4 variants, split evenly. Audience percentage slider, default 100%.

**Option A, cleanest population, no food branch.**
Enrollment: new customers. Condition: `App version = 1.8.3`. 3 variants:
`full_list` / `catalog` / `maintenance_led`. None need food logging, so nobody
is sold a blank screen; the macro arm simply is not tested.

**Option B, the original two-audience plan, now known to be buildable.**
Enrollment: new and existing. Conditions: `App version = 1.8.3` **and**
`logs_food = true`, 4 variants including `feature_led`; plus a second experiment
on `logs_food = false`, 3 variants without it. Costs the clean new-only
population, per above.

**Option C, one 4-arm test, branch in the app.** Enrollment: new customers,
`App version` scoped. The app substitutes at draw time: if the assigned arm is
the macro card and `goals.logsFoodInHealth == false`, draw the maintenance card.
`paywall_variant` records what was actually drawn, so the substitution appears in
the data rather than hiding in it. Needs one build.

The macro arm cannot ship unsubstituted to a non-logger: that card renders blank
without food data, so it is not a paywall, it is a bug with a price on it. B and
C are two different ways of buying around that.

## Timing: draft it now, start it on 1.8.3 adoption

The form has **Save as draft** and **Start experiment** as separate buttons, so
the setup can be staged in advance and started later. Draft it whenever; do not
start it while 1.8.2 is the version most customers run. See `RELEASE-1.8.3.md`,
"Do not start the experiment yet": live 1.8.2 falls back to `timeline`, not
`catalog`, so both arms render the same screen on that population and the signal
dilutes to nothing. The `App version = 1.8.3` condition is what actually prevents
this; the timing rule is the belt to its braces.

Two live dashboard changes belong to the 1.8.3 rollout, and neither is
housekeeping to be done early:

1. **The targeting rule "1.8.3 tester (Jack) - macro card"** (`app_version = 1.8.3`
   -> `pw_macro`) was moved from `live` to `inactive` on 2026-08-26. Do not
   reactivate it after 1.8.3 is submitted: it would pin every 1.8.3 customer to
   the macro card, non-loggers included.
2. **Change `default` metadata from `timeline` to `catalog`.** Not a typo fix.
   `timeline` is a real layout in the live 1.8.2 binary, so this immediately
   changes what every current customer sees. Do it deliberately, as part of the
   rollout.

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
