# Health Connect feasibility for Total Calories (Android)

Decision date: 2026-10-15. Verdict: feasible. The core value (total calories burned for the day,
split into active and resting, plus steps) survives on Health Connect. Resting energy is derived
by an explicit rule below, and the Watch and complication features map to a Glance widget.

## What iOS reads and what Android reads

| iOS (HealthKit) | Android (Health Connect aggregate) |
|---|---|
| `activeEnergyBurned` | `ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL` |
| `basalEnergyBurned` | `TotalCaloriesBurnedRecord.ENERGY_TOTAL` minus active, else `BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL` |
| `stepCount` | `StepsRecord.COUNT_TOTAL` |
| `dietaryEnergyConsumed` (Net Deficit) | `NutritionRecord.ENERGY_TOTAL` |

Every figure goes through `aggregateGroupByPeriod` (one bucket per local day), never through
`readRecords`, so the platform does the merging.

## Findings, with sources

1. Aggregates exist for all four. The Health Connect aggregate guide lists `ACTIVE_CALORIES_TOTAL`,
   `ENERGY_TOTAL`, `BASAL_CALORIES_TOTAL` and `COUNT_TOTAL` and the `aggregateGroupByPeriod` request
   used for daily buckets (period buckets take `LocalDateTime`, not `Instant`).
   https://developer.android.com/health-and-fitness/health-connect/aggregate-data
2. Deduplication across apps is done by the aggregate API using the user's app priority. The guide:
   "Health Connect deduplicates only Activity and Sleep data types ... the API keeps only the data from
   the highest-priority app." Active calories, total calories and steps are Activity types. In the
   platform source, `MergeDataHelper.shouldAddDataPoint` admits a record only when its app is in the
   priority list, and `TotalCaloriesBurnedRecordHelper.deriveAggregate` calls `MergeDataHelper` with
   that list. Basal rate is a body measurement, not prioritised.
   https://android.googlesource.com/platform/packages/modules/HealthFitness/+/refs/heads/main/service/java/com/android/server/healthconnect/storage/datatypehelpers/MergeDataHelper.java
3. `ENERGY_TOTAL` already fills gaps. After merging total records, any interval with no total record
   is filled with active calories plus basal calories (`DeriveTotalCaloriesBurnedHelper`). A phone that
   writes only active energy plus a basal rate therefore still yields a full-day total from one call.
   https://android.googlesource.com/platform/packages/modules/HealthFitness/+/refs/heads/main/service/java/com/android/server/healthconnect/storage/datatypehelpers/TotalCaloriesBurnedRecordHelper.java
4. `BASAL_CALORIES_TOTAL` never comes back empty. With no basal record it falls back to lean body mass,
   then to height and weight from the profile, then to built-in defaults (73 kg, 1.7 m, age 30)
   (`DeriveBasalCaloriesBurnedHelper`). So a non-null basal total does not mean anything measured it.
   The app uses the aggregate's `dataOrigins` to tell measured from derived: empty origins means no
   record contributed.
   https://android.googlesource.com/platform/packages/modules/HealthFitness/+/refs/heads/main/service/java/com/android/server/healthconnect/storage/datatypehelpers/DeriveBasalCaloriesBurnedHelper.java
5. Total calories include basal plus active (the record's reference text); a basal record is a rate
   (power) at an instant, summed over the interval by the aggregate.
   https://developer.android.com/health-and-fitness/health-connect/data-types
6. History: apps read the 30 days before the first permission grant. Older data needs
   `READ_HEALTH_DATA_HISTORY`; background reads (the widget) need `READ_HEALTH_DATA_IN_BACKGROUND`.
   Both are declared; the app works without them (30-day window, widget refreshes only when the app
   opens). Both are optional in the user's grant on the test image: the Health Connect dialog listed
   the five data types and did not turn history or background on with "Allow all".
7. An app only counts toward aggregates after Health Connect itself grants it write access (that is
   when the platform appends it to the priority list). Granting with `adb shell pm grant` does not.
   This only matters for the debug seeder; a reader app reads other apps' data and is never in the
   list. `DebugPermissionActivity` drives the real dialog for the seeder.

## Resting energy rule

Implemented in `EnergyResolver` (`model/Energy.kt`), pinned by unit tests and by
`HealthConnectFeasibilityTest` on the emulator. For each local day:

| Records present (by `dataOrigins`) | total | active | resting | note |
|---|---|---|---|---|
| total + active | `ENERGY_TOTAL` | active | total - active | measured |
| total + basal rate | `ENERGY_TOTAL` | total - basal | basal | measured |
| total only | `ENERGY_TOTAL` | unknown | unknown | ring works, breakdown hidden |
| active + basal rate | active + basal | active | basal | measured |
| active only | active + derived basal | active | derived basal | marked "estimated" in the UI |
| basal rate only | basal | 0 | basal | steps still shown |
| nothing | 0 | none | none | empty state, never a synthetic number |

Estimated resting is shown with an "est." label and is never used for the TDEE/BMR averages unless
the day has measured resting energy (those averages skip estimated days, as iOS skips days with zero
resting energy).

## Emulator proof (2026-10-15, API 36 Google Play image, Pro host)

`HealthConnectFeasibilityTest` seeds each combination on a past day from a debug build and reads it
back through `HealthConnectSource`:

| Seeded | Read back |
|---|---|
| total 2300 + active 600 | total 2300, active 600, resting 1700 |
| active 600 + basal rate 1700/day | active 600, resting 1699, total 2299 |
| total only 2300 | total 2300, split unknown |
| total 2300 + basal 1700 | total 2300, resting 1699, active 601 |
| active only 600 | total 2164.5 = 600 + 1564.5 default basal, flagged estimated |
| total 1000 until noon + active 500 | total 2104 (platform filled the gap) |
| nothing | 0, no synthetic value |
| steps 8123, food 1800 + 400 | steps 8123, food 2200 |

What the emulator cannot prove: how a given wearable writes (interval size, which types). The code
makes no assumption: it handles every row of the table. Cross-app dedup (two apps writing the same
total) relies on the documented platform behaviour in finding 2, because one app cannot play two
origins. Real Pixel Watch, Fitbit, Samsung Health or Garmin data is the one thing left to check on
a physical phone.

## Product consequences

- Total ring, steps, history, pacing, streaks, projection, excluded days, deep trends and PDFs all
  depend only on `DayStats(total, active?, resting?, steps)`, so they work for every row above.
- Active/resting breakdown and TDEE/BMR need a split. They hide, with a one-line explanation, when
  the user's apps report only a total.
- Net Deficit needs food energy (`NutritionRecord`) written by a food app. Health Connect does not
  dedupe nutrition across apps: two food apps writing the same meal would double count, noted in the
  app's explainer.
- Widget: Glance, small and medium, free (iOS widgets are free). It needs background read to
  refresh on its own; without it, it updates when the app opens.
- Wear OS: skipped for v1.
