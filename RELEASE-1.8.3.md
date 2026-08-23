# Vitals 1.8.3 release staging

Date: 2026-08-23
Branch: `fix/audit822-polish`
Marketing version 1.8.3, build 173 (bumped by `scripts/testflight.sh`).

This is the plan for shipping 1.8.3 and starting the Upgrade-tab paywall
experiment. It exists because the experiment and the release have a dependency
that is easy to get wrong: **the experiment must not start until 1.8.3 is the
version most customers are running.** See "Do not start the experiment yet".

## What is in the build

Three commits carried the feature work, and this staging pass added the funnel
integrity fixes that `AUDIT823.md` flagged as P0.

Feature work already on the branch:

- Onboarding is welcome → goals → food → pitch. The food question is a question,
  not a permission prompt; only a yes triggers the dietary HealthKit request,
  in a second sheet, so a decline cannot cost the free app its core permissions.
- The pitch follows the answer. Loggers get Macros and Net deficit; everyone
  else gets features that will actually have data.
- The onboarding CTA no longer moves between pages, and every primary button
  carries the same treatment.
- `PaywallUIVariant` is `catalog` (control, default) and `feature_led`
  (treatment). Unknown values fall back to catalog.
- The Upgrade tab shows all three plans above the purchase button. Lifetime used
  to sit ~59pt below the viewport on an iPhone 17 Pro.
- The trial timeline is gone from every pitch surface.
- Net Deficit in the iOS widget is ANDed with the cached entitlement.

Added in this staging pass:

- **Purchase state is truthful.** `PurchaseState` is now
  `purchased | pending | cancelled | unavailable`. A deferred transaction is no
  longer treated as a sale at any of the six call sites, and
  `ConversionDiagnostics.recordConversion` is gated behind the entitlement
  check, so an unresolved transaction can no longer be frozen into the funnel
  record as a conversion. This is the fix that makes any paywall experiment
  readable at all.
- **The onboarding CTA cannot dead-end.** It waits 6 seconds for RevenueCat,
  then becomes pressable with the label "See Vitals+ Plans" and routes to the
  full paywall, which owns the retry and error UI. Previously a failed product
  load left a disabled spinner, with the only recovery route sitting behind the
  button nobody could press.
- **The arm is recorded with the sale.** `paywall_variant` and `offering_id` go
  to RevenueCat as subscriber attributes, and `converted_variant` /
  `converted_offering` are frozen at the moment of conversion. RevenueCat
  reports the offering a customer was *assigned*; these record what the binary
  actually drew, which differs whenever an older build falls back to catalog.
- **The feature-led arm names the subscription.** It replaced the header that
  was the only place "Vitals+" appeared, and neither the plan rows nor the
  3.1.2 disclosure say it. That is a Guideline 3.1.2 exposure in the treatment
  arm; it now carries a VITALS+ eyebrow above the macro card.
- **Privacy claims match the binary** in all 50 App Store localizations, on the
  marketing site, on the support page, and in the review notes. See below.
- **The conversion record has a timestamp.** `converted_on` held a surface name
  under a key that reads as a date, so a customer record answered "when did they
  convert" with "settings". It is `converted_surface` now, alongside a real
  ISO 8601 `converted_at`.

## Test state

- `Vitals` scheme: **106 unit tests, 0 failures.**
- `VitalsUITests` scheme: **24 tests, 0 failures**, on a freshly rebooted
  simulator with nothing else running.

The one real failure found along the way was
`testFeatureLedVariantShowsEveryPlanAboveTheButton`, reproducing across two full
runs: the feature-led arm never rendered the string "Vitals+". Fixed, not
silenced. Every other intermittent failure traced to machine load, and one run
was invalidated outright by the simulator dying ("Invalid device state",
`(ipc/mig) server died`) after a second test process was pointed at the same
device. Do not run two xcodebuild test invocations against one leased UDID.

New coverage added here:

- `OnboardingCTARecoveryUITests` — fault-injects a product-load failure
  (`VITALS_FAIL_PRODUCT_LOAD=1`) and asserts the CTA recovers, reaches the full
  paywall's retry, and that the free exit still works.
- `ConversionDiagnosticsTests` — the arm is recorded with the sale, absent when
  unknown, and never rewritten by a later purchase.
- `VitalsConversionCopyTests` — pending copy promises nothing it cannot deliver
  and never names a trial for an ineligible customer.

## Privacy copy: what changed and why

The binary configures RevenueCat and sends subscriber attributes. The listing
said "No analytics. No ads. No servers. No accounts. No tracking." and "No data
leaves your phone"; the site went further with "no third-party SDKs, no network
requests". Those are not true, and they are least true at the exact moment a
customer reaches a purchase surface.

The supportable claim is now stated instead: health data stays on the device,
and purchases are processed by Apple and RevenueCat, which never receive health
data. Applied to all 50 locales, the site, the support page, and the review
notes. Every localized description is still under the 4,000-character limit.

**Still open, and only Jack can do it:** the App Store Connect App Privacy
answers say "Data Not Collected". RevenueCat receives an anonymous app user ID
plus purchase and entitlement data, so that questionnaire needs updating before
submission.

## A second audit pass landed mid-session

Another session appended a Vitals addendum to `AUDIT823.md` (it is 1,044 lines
now, not the 429 this work started from) and committed it as `89c4096`. It
reviewed the purchase-state and CTA fixes while they were in progress and
records them as done-in-source, needing production validation. Its three new
P0-labelled items, assessed:

- **V-P0-01, `converted_on` is a surface not a timestamp.** Correct. Fixed here.
- **V-P0-02, "Save 38%" contradicts $6.99 x 12 versus $29.99 (~64%).** Real, but
  it is not user-facing. The app does not link RevenueCatUI and draws its own
  paywall; `StoreService.annualSavingsPercent` computes the badge from the live
  localized prices. The stale 38% lives in the RevenueCat dashboard's hosted
  paywall template, left from the $1.99 / $14.99 era. Worth cleaning so nobody
  is misled by the dashboard, not a submission blocker.
- **V-P0-03, the prior experiment had zero conversions.** Agreed, and see below:
  it ran for 1h45m.

## Do not start the experiment yet

The `feature_led` arm does not exist in RevenueCat. Current state:

| Offering | Identifier | Metadata | Current |
|---|---|---|---|
| Vitals+ | `default` | `{"upgrade_tab": "timeline"}` | yes |
| Upgrade tab · catalog (A/B control) | `upgrade_catalog` | `{"upgrade_tab": "catalog"}` | no |

The previous experiment, "Upgrade tab: timeline vs catalog", ran for 1h45m and
was stopped with no result.

Two facts decide the sequencing:

1. **Live 1.8.2 falls back to `timeline`, not `catalog`.** Its
   `PaywallUIVariant.from` returns `.timeline` for a missing or unknown value.
   1.8.3 removes that layout and falls back to `catalog`.
2. Therefore, if the experiment starts before 1.8.3 has adoption, every 1.8.2
   customer assigned to the treatment arm renders **timeline**, and the control
   arm renders timeline too. The experiment measures timeline against timeline
   on that population and dilutes the real signal to nothing.

Sequence that avoids it:

1. Ship 1.8.3 and let it reach the bulk of active installs.
2. Create an offering `upgrade_feature_led` with the same three packages and
   metadata `{"upgrade_tab": "feature_led"}`.
3. Change `default`'s metadata from `timeline` to `catalog`. Note this changes
   what live 1.8.2 customers see immediately, from timeline to catalog. That is
   consistent with where 1.8.3 is going, but it is a live change and should be
   a deliberate one.
4. Create the experiment `default` (catalog) vs `upgrade_feature_led`, with a
   targeting condition of app version ≥ 1.8.3 so older builds are never
   enrolled. Enrollment mode `only_new`, as before.

### Be honest about power

Last 28 days: 581 new customers, 994 active users, 22 active trials, 56 active
subscriptions, $551 revenue. Only a fraction of new customers ever open the
Upgrade tab, which is the only surface this experiment touches.

Detecting a 25% relative lift in trial-start rate at conventional power needs on
the order of a thousand exposed users per arm. At this volume that is months,
not weeks. Options, in order of preference:

- **Move the experiment to where the traffic is.** Every new customer sees the
  onboarding pitch (~581/28d); a small fraction see the Upgrade tab. Porting the
  feature-led treatment to the onboarding pitch would give roughly an order of
  magnitude more exposure for the same code.
- **Run it as a directional read** with a pre-registered stopping rule and the
  expectation that it informs a ship decision, not a significance claim.
- Run it as-is and accept a long clock.

Whichever is chosen, `AUDIT823.md`'s conclusion still holds: fix funnel
integrity first, then measure. The integrity fixes are in this build.

## Before submitting

- [ ] Full `VitalsUITests` run green on a quiet machine (machine load produces
      spurious "never rendered" failures; see the audit's note on this).
- [ ] Verify `PurchaseState.pending` in Sandbox with an Ask to Buy tester.
      The RevenueCat test store cannot produce a deferred transaction, so the
      simulator cannot exercise the P0 fix end to end.
- [ ] Release notes for the other 46 locales. English is written; the rest still
      carry the 1.8.2 "Macros are here" text and would ship as-is.
- [ ] Update the App Store Connect App Privacy answers (see above).
- [ ] `./scripts/testflight.sh`, then stage the pbxproj on the release commit
      (`testflight.sh` commits only `project.yml`).

## Known and accepted

- **Watch premium gating.** The phone ANDs `showNetCalories` with `isPro`
  before syncing to the watch, so a lapsed subscriber's watch corrects itself
  the next time the phone app runs. It cannot correct sooner: the phone is the
  only thing that can push the sync. Bounded, not fixed.
- **`Vitals.storekit` is not wired to any scheme.** Wiring it would not help
  while RevenueCat's test store owns the simulator purchase path. The docs said
  otherwise and have been corrected.
