# Onboarding pitch experiment (1.8.4)

Shipped in build 187. Supersedes `UPGRADE-TAB-EXPERIMENT.md`, which varies a
surface that produced one real sale across 38 viewers.

## Why this surface

From all 1,577 RevenueCat customers plus subscriber attributes, 2026-08-30,
sandbox excluded. 126 instrumented customers, 6 real conversions.

| Surface | Viewers | Views | Conversions |
|---|---|---|---|
| `onboarding_trial` | 73 | 76 | **5** |
| `history_deep_trends` | 70 | 104 | 0 |
| `trial_offer_launch` | 38 | 151 | 0 |
| `trial_offer_historyLoad` | 20 | 22 | 0 |
| `trial_offer_settings` | 11 | 23 | 0 |
| Upgrade tab, all three arms | 38 | 45 | 1 |

Conversion is immediate: all six converted on day 0 at a median of one pitch
view, while non-converters saw a median of 2 and up to 19. Re-pitch volume is
not a lever. The food answer does not predict conversion either (6.5% of 31
loggers, 7.5% of 40 non-loggers), so the split exists to make the pitch
relevant, not because the segments convert differently.

**Sandbox caveat.** The attributes API does not filter sandbox; the experiment
Results API does. One debug device looked like an arm-B sale. Join to
`/customers/{id}/subscriptions` and drop `environment: sandbox` before reading
anything. See the `sandbox-pollutes-conversion-attrs` memory.

## The mechanism: rules in the dashboard, layouts in the binary

RevenueCat cannot assign the arm. It hands out the offering at the `welcome`
step, and `goals.logsFoodInHealth` is not committed until the `food` step two
screens later (`Vitals/Views/DashboardView.swift:2882`), so at assignment time it
does not know the segment. Custom-attribute enrollment conditions would also
force new-and-existing enrollment, which is wrong for a surface existing
customers never see again.

So the offering carries the *routing table* instead of an arm, under
`onboarding_pitch`, and the app applies it once the answer exists:

```json
{
  "onboarding_pitch": {
    "salt": "1840a",
    "enroll_pct": 100,
    "force": null,
    "segments": {
      "logs_food":   { "a": 25, "b": 25, "c": 25, "e": 25 },
      "no_food_log": { "a": 34, "c": 33, "d": 33 }
    },
    "fallback": "a"
  }
}
```

Weights are relative and an arm is retired with `0`. Assignment is FNV-1a over
the RevenueCat app user id plus the salt, so it is stable across launches and
reinstalls; Swift's own hashing is seeded per process and would reassign on
every launch.

**Changeable from the dashboard, no build:** which arms are live per segment,
their weights, `force` (kill switch and ship-the-winner switch), `enroll_pct`
(ramp), `salt` (reshuffle), and new segment rules.
**Needs a build:** the layouts themselves, and the code that reads the table.

`OnboardingPitchVariant.canDraw(logsFood:)` is the belt to that braces: a
dashboard edit putting `b` or `e` in the non-logger segment cannot ship a blank
card, which is the exact failure that kept the macro arm out of the 1.8.3 test.

## The arms

| Arm | Pitch | Segments |
|---|---|---|
| `a` | Current: glyph, headline, five feature rows | both, control |
| `b` | Macro ring hero, general rows underneath | loggers |
| `c` | Maintenance/BMR card rendered and blurred behind a lock | both, identical |
| `d` | Fourteen days of burn history | non-loggers |
| `e` | `d` plus the net-deficit strip | loggers |

`c` is byte-identical in both segments, so a gap between the two is a segment
effect rather than a pitch effect.

**Every hero card is captioned as an example.** At this step HealthKit access is
seconds old and the app has no history of its own, so a card captioned as the
user's own numbers would be showing invented ones. This is also the only honest
way to show the macro card to someone who has logged nothing yet.

## RevenueCat state

All six existing offerings now carry the table additively; `upgrade_tab` was not
touched on any of them, and no live 1.8.3 binary reads `onboarding_pitch`, so
this changed nothing for any live customer.

Two new offerings, identical packages to `upgrade_catalog` and identical
`upgrade_tab: catalog`, differing only in their table:

| Offering | id | Table |
|---|---|---|
| `ob_control` | `ofrng295d1ab201` | `enroll_pct: 0`, everyone gets `a` |
| `ob_newpitch` | `ofrngf40f8e7084` | loggers `b/c/e`, non-loggers `c/d` |

**Draft experiment `exp2f942dc97b`**, "Onboarding pitch: current vs new arms
(1.8.4)". Status `draft`, `started_at: null`, so it affects nobody. New
customers only, 100%, condition `app_version >= 1.8.4`.

**Two arms, not six, deliberately.** At 22 new customers a day a six-cell split
needs 75-127 days per cell to detect a doubling of the 6.8% base rate; two arms
sees it in about four weeks. Which new arm won is read afterwards from
`onboarding_variant`, for direction, not for the decision.

### Before starting it

`exp2f942dc97b` conflicts with the running `expb03a6c2204`: a customer can hold
only one offering assignment, and `>= 1.8.3` overlaps `>= 1.8.4`. Stopping the
Upgrade-tab experiment is the prerequisite, and the order matters:

1. Set the `default` offering's `upgrade_tab` from `timeline` to `catalog`.
2. Stop `expb03a6c2204`. Stopping reverts every enrolled customer to `default`
   on their next paywall view, which is why step 1 comes first.
3. Start `exp2f942dc97b`.

Neither step has been taken. `default` still reads `timeline`.

## Testing on TestFlight

Build 187 is 1.8.4. The debug rotator (`VITALS_ONBOARDING_PITCH=a`..`e`) is
`#if DEBUG` and absent from the TestFlight binary, so arms are walked from the
dashboard instead: set `force` on whichever offering the tester holds, reinstall
or wait for the next offerings fetch, and restart onboarding.

```json
"force": "b"
```

All six pre-existing offerings carry the table, so a tester enrolled in
`expb03a6c2204` still gets a valid one whichever arm they hold.

## Instrumentation

- `onboarding_variant`: the arm that actually **drew**, not the one the table
  nominated. A fallback caused by an unknown arm name or an undrawable segment
  shows up here rather than hiding.
- Impression id is `vitals_onboarding_trial_<arm>`, so per-arm impressions do
  not pool across five different screens.

## Not in scope

- Price, trial length, or plan sold. `onboardingTrialPackage` stays yearly.
- Removing the `Get Started` soft exit. It trades ratings for trial starts on a
  health app, and its geometry is already tuned against the fleet benchmark.
- Cutting the zero-yield re-pitch surfaces. `trial_offer_launch` showing 151
  views to 38 people for zero sales is worth doing, but it is a retention change
  and should not be confounded with this test.
