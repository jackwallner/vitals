# AUDIT823: Activation and Trial-Start Audit

Date: 2026-08-23  
Repository: `/Users/jackwallner/vitals`  
Branch: `fix/audit822-polish`  
Scope: user activation, first value, trial-start conversion, acquisition, trust, retention, and measurement  
Change policy: read-only audit. No app, release, RevenueCat, App Store Connect, or purchase state was changed.

## Executive decision

The app has a strong acquisition wedge, but the current funnel is not yet reliable enough to optimize confidently.

The strongest avoidable losses are:

1. A pending or unresolved purchase is treated as a successful trial or purchase in the onboarding and focused trial flows.
2. RevenueCat product-load failure can leave the highest-intent onboarding CTA as a disabled spinner, making the fallback paywall unreachable.
3. The primary onboarding flow asks for goals, food context, and a trial before the user sees their own dashboard data.
4. Conversion diagnostics start at the paywall and do not explain onboarding, HealthKit, product-load, first-value, or trial-state drop-off.
5. Acquisition and trust copy is inconsistent with the binary. The listing and site promise no analytics or network activity, while RevenueCat processes purchase, entitlement, and conversion data.

Do not start with a price reduction. Fix purchase-state truth, make the trial path reachable under degraded conditions, and test the timing of the offer against first real value before drawing conclusions from trial-start rate.

## Method

This audit used:

- Direct source and configuration review across the iPhone app, watch app, widgets, HealthKit, SwiftData, RevenueCat, StoreKit, tests, metadata, site, and support materials.
- Four independent read-only Luna 5.6 audits covering activation, monetization, acquisition, and technical trust friction.
- Review of `AUDIT822.md` and the current branch changes after that audit.
- A read-only check of the live App Store listing on 2026-08-23.

The Luna reviews edited no files, committed nothing, and pushed nothing. The existing working-tree state remained:

```text
 M fastlane/report.xml
?? .agents/
?? .codex/
?? revenuecat-dashboard/
```

No finding below should be read as permission to implement a fix in this audit.

## Funnel model

The meaningful funnel is:

```text
Acquisition source
  -> App Store page view
  -> install
  -> first open
  -> HealthKit authorization
  -> first real data paint
  -> onboarding completion
  -> trial offer shown
  -> plan selected
  -> purchase initiated
  -> trial entitlement active
  -> day-1 return
  -> trial-to-paid conversion
```

The current diagnostics mainly begin at `trial offer shown` and record a pitch-view tally plus a first conversion snapshot. They do not provide a trustworthy view of the earlier activation stages or the intermediate purchase states.

## Priority findings

| Priority | Finding | Confidence | Main conversion effect |
|---|---|---|---|
| P0 | Pending and unavailable purchase states are treated as success | Confirmed | False trial starts, false conversions, confused users, incorrect experiment data |
| P0 | Product-load failure makes the onboarding CTA unreachable | Confirmed | High-intent users cannot start a trial or reach the plan picker |
| P0 | Privacy and data-handling claims contradict RevenueCat traffic | Confirmed | Trust loss, App Review risk, privacy disclosure mismatch at the purchase moment |
| P1 | Trial is requested before first personal value in the main onboarding flow | Confirmed | More early exits before a user understands the product |
| P1 | HealthKit empty, denied, stale, and loading states are not clearly separated | Confirmed behavior, conversion effect is a hypothesis | Users can see zeroes, stale data, or a Settings detour instead of a useful first result |
| P1 | Passive trial exposure is gated by too many conditions | Confirmed | Eligible users may never see a trial at a useful value moment |
| P1 | Measurement does not capture the activation and purchase state machine | Confirmed gap | Trial-start rate cannot be diagnosed by source, step, or failure reason |
| P1 | StoreKit, pricing, metadata, and live listing are out of sync | Confirmed repository drift | Price shock, weak testing fidelity, and misleading commercial copy |
| P1 | Watch and widget premium state is inconsistent | Confirmed source behavior | Premium trust issue and weaker retention on the highest-value surface |
| P2 | Focused trial surfaces omit Restore and have inconsistent recovery UI | Confirmed | Returning users have less confidence at the purchase moment |
| P2 | English-only runtime copy and constrained paywall text create localization risk | Confirmed | Lower international activation and possible clipped legal or CTA text |
| P2 | Accessibility and chart interaction gaps reduce reachable conversion surface | Confirmed source gaps, runtime impact needs verification | Users using VoiceOver, large text, or nonvisual chart access can fail to act |
| P2 | Review and widget-install moments are useful but under-measured | Confirmed gap | Retention and organic acquisition loops cannot be tuned |

## P0 findings

### P0.1 Purchase state is not truthfully represented

`StoreService.purchase` returns `.pending` when RevenueCat is not configured and also returns `.pending` when the purchase result does not yet contain the active Vitals entitlement (`Shared/Services/StoreService.swift:552-575`).

The direct onboarding purchase handles `.purchased` and `.pending` together and finishes onboarding (`Vitals/Views/DashboardView.swift:2924-2946`). The focused trial sheet also dismisses for both states (`Vitals/Views/TrialOfferPitch.swift:165-188`). A pending StoreKit transaction is not an active trial and should not remove the pitch or tell the user that access is available.

The diagnostic conversion is recorded before the entitlement check (`Shared/Services/StoreService.swift:558-575`). That means an unresolved transaction can be counted as a conversion even when premium access is not active.

This is both a user problem and a measurement problem. It corrupts the denominator and numerator for every trial-start or paywall experiment that uses the current conversion record.

Required experiment guardrail, without prescribing an implementation in this document:

- Treat `purchase initiated`, `pending`, `entitlement active`, `trial active`, `paid`, `cancelled`, `failed`, and `restored` as separate states.
- Do not count a trial start until the expected entitlement is active and the introductory period is confirmed.
- Keep the purchase surface present during a pending state, with a clear status and a way to retry or close.

### P0.2 Product-load failure can dead-end onboarding

`StoreService.fetchProducts()` leaves `products` empty and stores an error when the RevenueCat request fails (`Shared/Services/StoreService.swift:306-321`). `conversionCTAReady` remains false without a usable package or resolved eligibility (`Shared/Services/StoreService.swift:467-473`).

The onboarding CTA hides its label, shows a spinner, and remains disabled while that condition holds (`Vitals/Views/DashboardView.swift:2646-2659`). The fallback branch that would open the full paywall is inside `startTrial()` (`Vitals/Views/DashboardView.swift:2924-2927`), so the user generally cannot tap far enough to reach it.

This turns a temporary RevenueCat, network, or StoreKit delay into a conversion dead end. The full paywall has a more useful loading and error path, but onboarding does not reuse it.

The measurable questions are:

- What percentage of first launches reach a package-ready CTA within 1, 3, and 10 seconds?
- What percentage see an error, spinner, or disabled CTA with no recovery action?
- How many users complete the free setup after plans fail rather than abandoning the app?
- Does a retry or plan-picker route recover trial starts without hurting first-session completion?

### P0.3 Privacy claims are inconsistent at the trust and purchase boundary

The active App Store description says:

- “No analytics. No ads. No servers. No accounts. No tracking.” (`fastlane/metadata/en-US/description.txt:57-61`)
- “No data leaves your phone.” (`fastlane/metadata/en-US/description.txt:1`)

The review notes and support page make similar claims (`fastlane/metadata/review_information/notes.txt:1-4`, `docs/support.html:47-49`). The marketing site goes further, saying there are no third-party SDKs and no network requests (`docs/index.html:566-574`).

The binary configures RevenueCat and sends subscriber attributes and custom paywall impressions (`Shared/Services/StoreService.swift:495-510`, `Shared/Services/StoreService.swift:520-548`). The privacy policy correctly says RevenueCat may process an anonymous app user ID, purchase and entitlement information, and limited technical context, and does not receive HealthKit data (`docs/privacy-policy.html:108-118`).

The live listing currently reports “Data Not Collected,” while also displaying the Vitals+ purchase catalog. See the [live App Store listing](https://apps.apple.com/us/app/total-calories-daily-tracker/id6761743504).

The narrow, supportable claim is that HealthKit health data and reports stay on-device and are not sent to RevenueCat. The broader “no network” and “no analytics” claims create an avoidable trust break when a user reaches a trial or purchase surface.

## P1 activation and first-value findings

### P1.1 The trial is before the user's first personal result

The current first-launch sequence is:

```text
Welcome
  -> HealthKit request
  -> calorie and step goals
  -> food logging question
  -> optional dietary HealthKit authorization
  -> Vitals+ trial pitch
  -> dashboard
```

The sequence is implemented in `Vitals/Views/DashboardView.swift:2336-2946`. The user can spend the whole first session answering setup questions and evaluating a subscription before seeing their own calorie or step numbers.

The passive trial path takes the opposite approach: it waits for real, nonzero dashboard data (`Vitals/App.swift:507-539`). That makes the product's own retention logic evidence for a useful experiment: compare a pre-value trial pitch with a post-first-data pitch.

Measure the complete funnel, not just trial starts:

- HealthKit prompt shown and authorization result.
- First real-data paint and time to first data.
- Completion or abandonment at each onboarding step.
- Trial offer shown after data versus before data.
- Trial start per install, per onboarding completer, and per eligible offer view.
- Day-1 return and widget or watch activation as guardrails.

### P1.2 Onboarding has four steps but no visible progress or Back control

The onboarding step enum contains `welcome`, `goals`, `food`, and `trial` (`Vitals/Views/DashboardView.swift:2336-2342`). The flow advances forward and the code has no visible progress indicator or Back action in the reviewed path.

HealthKit authorization begins asynchronously when the user leaves Welcome (`Vitals/Views/DashboardView.swift:2438-2453`, `2602-2608`). A food-logging “Yes” answer can lead to a second dietary permission request later in the flow (`Vitals/Views/DashboardView.swift:2663-2785`).

This is not inherently wrong, but the cost is hidden. The highest-value question is whether food logging is the acquisition intent for this install. For Watch and widget users, the extra question likely delays the core value. For macro or deficit users, it may improve feature relevance. That is an audience-segmentation experiment, not a universal onboarding rule.

### P1.3 Empty, denied, loading, and stale HealthKit states can look alike

The dashboard explicitly maps `.unnecessary` authorization status to `.accessBlocked`, while acknowledging that the API cannot distinguish granted-but-empty from denied (`Vitals/Views/DashboardView.swift:1665-1686`). A new user with no HealthKit samples can therefore be sent toward Settings rather than being told that data has not arrived yet.

On a cold launch with no cache, a one-second fail-safe applies literal zero values and exits the loading state (`Vitals/Views/DashboardView.swift:1702-1710`). When a live fetch fails, cached values are applied and the error notice is cleared. The only visible clue is that the timestamp does not advance (`Vitals/Views/DashboardView.swift:1822-1840`).

The core product depends on trust in the number. A user who sees zeroes, stale numbers, or a permission detour before understanding the data source may not reach the trial surface.

Recommended measurement states:

- Permission prompt not yet requested.
- Permission request completed, data available.
- Permission request completed, no samples yet.
- HealthKit unavailable or restricted.
- Query failed with cached data.
- Query failed with no cache.
- Data loaded but stale beyond a defined freshness window.

### P1.4 Passive trial exposure is over-gated

The launch trial requires setup completion, a non-Pro state, a 14-day passive-offer cooldown, yearly trial eligibility, Today-tab selection, no covering sheet, and real nonzero dashboard data (`Vitals/App.swift:507-539`, `Shared/Services/GoalSettings.swift:195-228`). It then waits another 1.8 seconds before presenting.

The design protects the first value moment, but it also creates several ways for an eligible user never to see the offer. New users who finish onboarding are suppressed for the rest of that session (`Vitals/App.swift:870-877`), and users who skip or dismiss a passive pitch may wait 14 days before another passive encounter.

Test the current policy against shorter cooldowns and a single post-value opportunity. Record eligible users separately from exposed users so a low trial-start rate is not mistaken for a weak paywall.

### P1.5 Default goal language may create the wrong mental model

The default calorie goal is 2,500 and the default step goal is 10,000 (`Shared/Services/GoalSettings.swift:598-612`). The onboarding title only says “Set your daily goals” (`Vitals/Views/DashboardView.swift:2488-2500`).

Because the product also discusses food energy, “calorie goal” can be read as calories eaten rather than calories burned. The first goal screen should be evaluated for comprehension, especially for users arriving from calorie-intake or macro searches.

## P1 trial and monetization findings

### P1.6 Eligibility is re-queried at the highest-intent moment

Product loading already refreshes introductory-offer eligibility (`Shared/Services/StoreService.swift:306-317`). The onboarding CTA refreshes eligibility again immediately before purchase (`Vitals/Views/DashboardView.swift:2931-2936`), and the focused trial sheet does the same (`Vitals/Views/TrialOfferPitch.swift:172-176`).

That extra request can add latency between the user's tap and Apple's purchase sheet. It also creates a failure point after the user has made the decision to trial. Compare cached eligibility with a bounded freshness window against the current immediate refresh, while preserving the rule that the displayed trial must match actual eligibility.

### P1.7 The experiment scope is narrower than the product funnel

The main Upgrade tab reads `upgrade_tab` offering metadata to select the catalog or feature-led layout (`Shared/Services/PaywallUIVariant.swift`, `Vitals/Views/PaywallView.swift:253-258`). Focused feature paywalls force the catalog layout and therefore bypass the same variant assignment.

This is acceptable as a placement-specific experiment, but the measurement must include placement. Do not combine Upgrade-tab impressions with History, Settings, dashboard, or onboarding pitches when comparing trial starts. The primary result should identify:

- Placement.
- Offering identifier and variant.
- Product and plan selection.
- Trial eligibility.
- Purchase state.
- App version and build.

The current on-device diagnostics store pitch views, last surface, first seen date, plan, and a first conversion snapshot (`Shared/Services/ConversionDiagnostics.swift:33-137`). It does not capture the full event sequence.

### P1.8 Pricing is a test variable, but not the first suspected failure

The current local StoreKit fixture and live App Store listing show US prices of $6.99 monthly, $29.99 yearly, and $59.99 lifetime (`Vitals.storekit:4-99`, App Store listing). The local subscription benchmark reference reports:

- Health and Fitness sells mostly annual subscriptions, at 68% of subscriptions in the cited category data.
- Yearly renewal is materially higher than monthly renewal in the cited fleet benchmark.
- The market mode is approximately $10 monthly and $30 yearly.
- Seven-day trials sit in the reported 5 to 9 day sweet spot.
- Higher price bands correlated with more download-to-trial starts in the cited report, so lowering price is not a safe default assumption.

The current yearly price is near the market mode. The monthly price is below the mode, and lifetime is only 2x annual, which is at the low end of the common 2.5x to 4x lifetime-to-annual relationship cited in the benchmark reference. These are hypotheses to test only after the path can reliably expose, start, and measure trials.

Pricing experiments should include guardrails for:

- Trial start per eligible paywall view.
- Trial-to-paid conversion after a mature cohort.
- Refunds, cancellations, and renewal.
- Lifetime share of revenue.
- Revenue per install and revenue per trial start.

### P1.9 StoreKit, product IDs, and commercial documentation are inconsistent

The runtime identifiers are:

```text
com.jackwallner.vitals.monthly
com.jackwallner.vitals.yearly
com.jackwallner.vitals.plus.lifetime
```

The fixture uses those identifiers and the current $6.99, $29.99, and $59.99 prices (`Shared/Services/StoreService.swift:8-18`, `Vitals.storekit:45-90`). The operational documentation still describes older IDs and $1.99, $14.99, and $29.99 prices (`docs/app-store-metadata.md:383-418`, `_handoffs/revenuecat-paywall-handoff.md:39-51`). Several native locale source files also embed the older prices.

This creates price shock, weakens localization trust, and makes it difficult to know which product configuration a test result represents.

### P1.10 The local StoreKit fixture is bundled but not active in shared schemes

`project.yml` includes `Vitals.storekit` as a resource (`project.yml:53-61`). Neither `Vitals.xcscheme` nor `VitalsUITests.xcscheme` contains a `StoreKitConfigurationReference`.

The documentation claims the fixture is wired to the Vitals scheme (`docs/app-store-metadata.md:444-447`), but the scheme XML does not support that claim. Trial, restore, pending, cancellation, renewal, and price-display flows are therefore not covered by the described local testing path.

One Luna audit also reported that a current test attempt stopped while building the checked-out RevenueCat package because `PrivacyInfo.xcprivacy` was missing. `project.yml` requests RevenueCat from 5.14.0 while `Package.resolved` resolves 5.71.0. This was recorded as an environment or dependency integration blocker, not treated as a universal source failure. The prior `AUDIT822.md` run had 101 unit tests pass and four UI assertions fail on an earlier state, so those results should not be used as current branch proof.

## P1 retention, watch, and widget findings

### P1.11 Watch premium gating is weaker than iPhone gating

The iPhone widget now combines `showNetCalories` with the cached Pro flag (`VitalsWidget/VitalsWidget.swift:15-23`). The watch app and watch complication read `showNetCalories` directly (`VitalsWatch/Views/TodayView.swift:61`, `VitalsWatchWidget/WatchComplication.swift:101-110`, `598-614`).

A lapsed subscriber can therefore continue seeing Net Deficit on the watch until another phone-side preference write occurs. This damages the credibility of the most differentiated surface, especially if a user returns after a subscription change.

### P1.12 Running watch apps can show stale goals

The watch application receives goal context and writes values to defaults, but the reviewed handoff updates only some in-memory display flags. A watch Today screen that remains open while goals change on iPhone may show stale target values until relaunch (`VitalsWatch/App.swift:41-60`).

The conversion impact is indirect. Stale goal rings weaken the daily habit loop and can reduce the positive moments that later support trial, review, and retention.

### P1.13 Watch refresh work may be expensive

The watch refresh performs multiple sequential 30-day history loads plus dietary history (`VitalsWatch/Views/TodayView.swift:401-460`). HealthKit query continuations do not show clear cancellation handling (`Shared/Services/HealthKitService.swift:1199-1237`).

This is a performance hypothesis, not a measured defect. The relevant evidence is time to usable Today data, refresh battery cost, and whether a user backgrounds or abandons the watch app before the first screen becomes useful.

### P1.14 Widget and watch activation are not part of the conversion funnel

The product's strongest differentiator is persistent data on the Apple Watch face, Home Screen, and Lock Screen. The current diagnostics do not record whether a user installs a widget or complication, reaches the watch app, or returns after seeing a background refresh.

Evaluate a post-first-data activation prompt against no prompt, with day-1 return and trial start as guardrails. Do not interrupt the first data moment with setup instructions.

## P2 purchase surface and accessibility findings

### P2.1 Focused trial surfaces omit Restore

The full paywall includes Restore, Terms, and Privacy (`Vitals/Views/PaywallView.swift:455-474`). The focused trial surface provides Terms and Privacy but no Restore (`Vitals/App.swift:1858-1871`).

The onboarding Restore action also starts an unobserved task with no visible success, failure, or no-purchase result (`Vitals/Views/DashboardView.swift:2811-2821`). Returning subscribers have less recovery confidence exactly where the app asks them to buy.

### P2.2 Fixed and truncated paywall text is fragile

The paywall disclosure and error areas use three-line limits and a fixed 62-point frame (`Vitals/Views/PaywallView.swift:403-433`). The trial surface uses similar three-line constraints (`Vitals/App.swift:1820-1834`).

Long localized prices, purchase errors, Dynamic Type, and VoiceOver sizes can clip or compress the legal and CTA context. This affects trust and actionability, not only polish.

### P2.3 Runtime localization is effectively absent

No runtime `.lproj`, `.xcstrings`, `.strings`, or `.stringsdict` resources were found. User-visible dates use hardcoded formats in several views, including `MMM d` in `Vitals/Views/SummaryReportView.swift:18` and `Vitals/Views/HistoryView.swift:2691`.

The App Store listing currently exposes English only. The repository contains many locale metadata inputs, but those are not equivalent to a localized runtime experience.

### P2.4 Accessibility gaps can block nonvisual conversion

Source-level gaps include:

- Icon-only paywall close control without an explicit label (`Vitals/Views/PaywallView.swift:612`).
- History export control requiring runtime verification of its accessible label (`Vitals/Views/HistoryView.swift:505`).
- Custom tab buttons that visually track selection but do not clearly expose selected state (`Vitals/App.swift:2239-2262`).
- A settings toggle with an empty visual label (`Vitals/Views/DashboardView.swift:3097`).
- Watch calorie cards that use tap gestures rather than button semantics (`VitalsWatch/Views/TodayView.swift:94-116`).

Add runtime coverage for VoiceOver, Dynamic Type, keyboard focus, and reduced motion before considering the conversion funnel accessible.

## P1 acquisition findings

### P1.5 The live acquisition wedge is stronger than the current site story

The live listing title is `Total Calories - Daily Tracker` and the subtitle is `TDEE Burn on Watch & Widget`. It reports 8 ratings at 5.0, English as the only listed language, and Vitals+ prices of $29.99 yearly, $6.99 monthly, and $59.99 lifetime. See the [live listing](https://apps.apple.com/us/app/total-calories-daily-tracker/id6761743504).

This reinforces the best positioning: total burn on Apple Watch, widgets, and Lock Screen. The repository ASO strategy also recommends leading the first screenshot frames with Watch, widgets, and daily burn (`docs/aso-keyword-strategy.md:102-114`).

The active keyword field instead emphasizes `bmr`, `complication`, `resting`, `active`, `calculator`, `deficit`, `net`, `energy`, `steps`, `macro`, `bmi`, `body`, `fat`, `protein`, and `carb` (`fastlane/metadata/en-US/keywords.txt:1`). The keyword field and screenshot order should be tested against the actual acquisition wedge, not optimized as a generic calorie tracker.

### P1.6 The marketing site contradicts the current onboarding

The site says “Zero-config setup” and “No onboarding flow” (`docs/index.html:611-616`). The binary currently has four onboarding steps and may request two separate HealthKit permission groups (`Vitals/Views/DashboardView.swift:2336-2946`).

That mismatch raises expectation failure before a trial is even considered. Test acquisition-specific onboarding paths:

- Watch and widget intent: show burn quickly, defer food setup.
- Macro and deficit intent: explain the food-data requirement before asking for it.
- General calorie intent: show first burn and steps result before the Vitals+ pitch.

### P1.7 Site and structured metadata are stale

The site structured data reports software version 1.7.8 and one rating (`docs/index.html:23-65`), while the live listing reports version 1.8.2 and eight ratings. The site screenshot order leads with older Net Deficit and History assets (`docs/index.html:495-511`), while the repository's current screenshot set has a separate Watch and total-burn story.

This can reduce qualified installs and create a mismatch between ad or search intent and the first in-app experience.

### P1.8 Attribution starts too late

The code records paywall views and a conversion snapshot, but not install source, landing-page source, onboarding-step drop-off, HealthKit outcome, first-data latency, product-load failure, free exit, or trial CTA readiness (`Shared/Services/ConversionDiagnostics.swift:33-137`).

The marketing site uses hardcoded App Store links without campaign-specific measurement (`docs/index.html:484-492`, `622-626`). No acquisition funnel was found that connects:

```text
source or custom product page
  -> install
  -> first open
  -> HealthKit result
  -> first data
  -> onboarding completion
  -> trial offer
  -> trial start
```

Without that chain, a paywall experiment can improve trial-start rate among exposed users while total user conversion gets worse because fewer users reach the paywall.

## Measurement contract

The minimum event taxonomy for a trustworthy optimization loop is:

| Stage | Events |
|---|---|
| Acquisition | source, custom product page, App Store view, install, first open |
| Activation | HealthKit prompt shown, authorization outcome, onboarding step viewed, step completed, free exit, first data paint, first-data latency |
| Monetization | paywall impression, offering and variant assignment, package viewed, package selected, CTA ready, purchase initiated, purchase pending, purchase cancelled, purchase failed |
| Entitlement | trial active, paid active, restore started, restore result, entitlement lost, billing issue |
| Retention | day-1 return, day-7 return, widget installed, watch app opened, complication present, positive moment, review prompt eligible |

Do not send calorie values, step values, dietary values, macro values, or PDF contents as conversion attributes. The privacy boundary should remain that HealthKit data is processed locally and is not part of RevenueCat conversion measurement.

Primary metrics:

- First real-data rate per install.
- Onboarding completion per first open.
- Trial offer exposure per eligible user.
- Trial start per eligible offer view.
- Trial start per install.
- Trial-to-paid conversion after a mature cohort.
- Day-1 return and widget or watch activation as guardrails.

## Recommended experiment backlog

Order is by information value and risk reduction, not implementation size.

1. **Purchase-state truth experiment**: separate pending, active trial, paid, cancelled, failed, and restored. Exclude pending from trial-start and conversion numbers.
2. **Product-load resilience experiment**: compare the current spinner-only state with an actionable retry and plan-picker route. Fault-inject RevenueCat failure and measure recovered trial starts.
3. **First-value timing experiment**: compare trial before personal data against trial immediately after first data paint.
4. **Intent-specific onboarding experiment**: compare the current food question for everyone against deferring food setup for Watch/widget and general burn intent.
5. **Passive exposure experiment**: compare the current 14-day cooldown and 1.8-second delay against a shorter post-value opportunity. Track eligible versus exposed separately.
6. **Paywall placement experiment**: keep Upgrade-tab variants separate from focused feature paywalls. Compare trial start, trial-to-paid, refund, and revenue per eligible user.
7. **Pricing experiment**: only after the funnel is measurable. Test the annual anchor and monthly price independently, with lifetime cannibalization and renewal as guardrails.
8. **Acquisition creative experiment**: use Watch/widget/daily-burn first frames for that intent, while keeping macros and deficit creative for food-intent traffic.
9. **Trust-copy experiment**: replace broad no-network claims with precise HealthKit-locality and purchase-service disclosure. Track HealthKit authorization, trial starts, and support contacts.
10. **Retention activation experiment**: test a post-first-data widget or watch setup nudge against no nudge, measuring day-1 return and trial starts.

## Strengths to preserve

- The free core is differentiated: total burn, steps, Apple Watch complications, and widgets.
- The listing subtitle clearly identifies the Watch and widget wedge.
- HealthKit is read-only and health data is intended to stay on-device.
- RevenueCat products provide localized price strings rather than hardcoded in-app prices.
- Yearly is selected by default and plans are ordered yearly, monthly, lifetime (`Shared/Services/StoreService.swift:211-228`, `Vitals/Views/PaywallView.swift:662-680`).
- The full paywall includes pricing, trial disclosure, Restore, Terms, and Privacy.
- The iPhone widget now checks cached Pro state before showing Net Deficit.
- Passive trial presentation waits for real data rather than appearing over a blank dashboard.
- The feature-led paywall arm renders an illustrative macro card instead of showing an empty premium state (`Vitals/Views/PaywallView.swift:509-573`, `808-871`).

## Audit limitations

- No real Apple sandbox purchase, restore, refund, renewal, cancellation, or entitlement-revocation flow was executed.
- No App Store Connect or RevenueCat configuration was changed.
- Full device, watch-size, VoiceOver, Dynamic Type, RTL, pseudo-localization, and physical-device coverage was not run.
- The current branch was not accepted as test-green. One Luna audit reported a RevenueCat package privacy-resource build failure; the prior `AUDIT822.md` test results were from an earlier state.
- Live App Store facts are time-sensitive and should be rechecked before any acquisition experiment is launched.

## Bottom line

The product concept is clear and the acquisition wedge is promising. The next optimization decision should be about funnel integrity and timing, not a broad feature expansion or reflexive price cut. Until pending purchases, product-load failures, first-value timing, and event taxonomy are measurable, trial-start rate will mix real demand with reachability and instrumentation artifacts.

---

# 2026-08-23 Max-Reasoning Addendum: Total Calories / Vitals

This addendum is appended to the prior `AUDIT823.md` audit. The preceding audit is preserved in full. This section is a second pass over the current Vitals repository and the current authenticated ASC and RevenueCat views available on 2026-08-23.

## Scope, method, and evidence rules

This pass covers the complete requested Vitals scope:

- App Store Connect metadata, acquisition surfaces, downloads, and release state.
- Trial exposure, trial starts, paid conversion, revenue, and the native paywall.
- Onboarding, first value, HealthKit states, ratings, review acquisition, and retention surfaces.
- RevenueCat offerings, packages, experiments, custom attributes, and exact insertion points.
- Website, terms, privacy, metadata, subscription copy, and other non-RevenueCat consistency.
- Crash, hang, watchdog, release-regression, stale-data, and degraded-purchase signals.
- Cursor, Claude, Codex, and general agent-documentation hygiene.

No source code, configuration, ASC record, RevenueCat record, purchase, browser account state, or notification channel was changed. This addendum changes only this existing file.

Evidence labels used below:

- **Confirmed local:** directly observed in repository source, configuration, metadata, or documentation. Paths and symbols are included so an implementation agent can re-check the claim.
- **Confirmed live snapshot:** observed in the authenticated ASC or RevenueCat UI, or on the public App Store listing, on 2026-08-23. These values are time-sensitive.
- **Inference:** a plausible conversion, retention, or trust effect derived from confirmed behavior. It needs a controlled test or telemetry before being treated as causal.
- **Unknown:** not available from the inspected sources. It is a measurement requirement, not a fabricated result.

### Explicit exclusion

Do not report or act on an inconsistency whose only subject is the app's RevenueCat tracking or data-collection disclosure. The owner will handle that separately. This addendum still records non-RevenueCat consistency such as version, price, product, metadata, legal-link, feature, accessibility, and storefront differences. It also uses RevenueCat operational data for funnel analysis, as requested.

## Executive decision

Vitals has a clear free acquisition wedge: total calories burned and steps on Apple Watch, widgets, and the Lock Screen. The current product work has already improved several purchase failure states, but the measurement layer still cannot answer the most important question: did an install reach a trustworthy first result and then start a real trial, or did a paywall impression or unresolved StoreKit state merely look like conversion?

The highest-leverage sequence is:

1. Reconcile the production RevenueCat paywall catalog, local StoreKit fixture, site JSON-LD, metadata guide, and ASC product catalog before running a price or savings experiment.
2. Fix the conversion snapshot schema and add a durable funnel state machine. The existing `converted_on` key is currently populated with the last surface name rather than a conversion timestamp.
3. Re-run the native paywall experiment only after the experiment has enough duration and actual trial or paid events. The observed one-day experiment has zero conversions in both arms and cannot select a winner.
4. Compare pre-value onboarding trial timing with a post-first-data offer, while measuring trial starts per install and per eligible offer view separately.
5. Add release-window monitoring for crash, hang, HealthKit freshness, product-load, purchase-state, widget, watch, and rating regressions. Vitals currently has useful OSLog coverage but no confirmed crash or hang reporting integration.

Do not make a price cut or broad paywall redesign the first move. The live commercial configuration and event denominator are not yet stable enough for that decision.

## Current evidence register

### Local binary and repository state

| Item | Evidence | Interpretation |
|---|---|---|
| Repository | `/Users/jackwallner/vitals` | In-scope Vitals repository. |
| Branch | `fix/audit822-polish` | Current branch at audit time. |
| Local marketing version | `1.8.3` in `project.yml:15` | Local source targets a newer build than the live public listing snapshot. |
| Local build | `173` in `project.yml:16` | Use this build as the release-watch candidate key. |
| iPhone bundle | `com.jackwallner.vitals` in `project.yml:64` | ASC and crash data must be joined to this bundle. |
| Watch bundle | `com.jackwallner.vitals.watch` in `project.yml:84` | Watch regressions need a separate target dimension. |
| iOS widget bundle | `com.jackwallner.vitals.widget` in `project.yml:102` | Widget failures should not be hidden inside host-app metrics. |
| Watch widget bundle | `com.jackwallner.vitals.watch.widget` in `project.yml:117` | Complication regressions need a separate target dimension. |
| App Group | `group.com.jackwallner.vitals` in `CLAUDE.md:34` and shared sources | Joins app, widget, and local conversion state. |
| Existing audit | `/Users/jackwallner/vitals/AUDIT823.md` | Prior work retained, this section is appended. |

### Confirmed live App Store and ASC snapshot

The authenticated ASC app list and public listing were inspected on 2026-08-23.

| Surface | Observed value | Evidence or follow-up |
|---|---|---|
| ASC app | `Total Calories - Daily Tracker` | App ID `6761743504`. ASC page: `https://appstoreconnect.apple.com/apps/6761743504/analytics` |
| ASC app-list version | `1.8.2`, Ready for Distribution | Confirmed in the ASC app list snapshot. Recheck the version page before any upload. |
| Public title | `Total Calories - Daily Tracker` | `https://apps.apple.com/us/app/total-calories-daily-tracker/id6761743504` |
| Public subtitle | `TDEE Burn on Watch & Widget` | Confirms the current Watch and widget positioning is live. |
| Public price | Free with in-app purchases | Strong free-to-paid acquisition structure. |
| Public ratings | 8 ratings, 5.0 shown | Very small sample. Do not optimize against the average without volume and review-text context. |
| Public screenshots | Four visible iPhone screenshots in the inspected listing | Recheck order, first-frame promise, and whether the Watch/widget wedge appears early enough. |
| Public languages | English shown in the inspected listing | Local metadata has a much larger locale set. Verify which locales are actually active in ASC. |
| Public release note | Version 1.8.2, updated roughly 15 hours before the snapshot | The timestamp is a live snapshot, not a durable fact. |
| Accessibility listing | No accessibility features indicated in the inspected listing | This is a storefront discoverability gap or missing declaration, not proof that the binary lacks accessibility support. |

The local `project.yml` version `1.8.3` and the public `1.8.2` are not inherently a bug. They do prove that the repository and live storefront are on different release candidates, so every acquisition or conversion comparison must be keyed by app version and build.

### Confirmed RevenueCat production snapshot

The RevenueCat project is `d0d314f5`, reached through the authenticated project UI. Project URL: `https://app.revenuecat.com/projects/d0d314f5/`.

| Metric or configuration | Snapshot | Interpretation |
|---|---|---|
| Project | Total Calories / Vitals | Matches the local Vitals product identifiers and ASC app. |
| Active trials | 22 to 23 while the page was observed | Dynamic production snapshot. Use the timestamp and export window, not a fixed count. |
| Active subscriptions | 56 | Dynamic production snapshot. Join to app version and product in a real export. |
| MRR | `$87` | RevenueCat project snapshot for the displayed last-28-day view. |
| Revenue | `$551` | RevenueCat project snapshot for the displayed last-28-day view. |
| New customers | `586` | Customer count, not installs or trial starts. Do not use as a download proxy. |
| Active customers | `1,089` | Customer count, not active users or retention. |
| Default paywall | `Vitals+`, published | Paywall page: `https://app.revenuecat.com/projects/d0d314f5/paywalls` |
| Paywall headline | `See your real calorie deficit, burn minus food from Apple Health` | Strong feature-led intent copy for food-logging users. It may be weak for Watch-only users. |
| Paywall feature copy | `Monthly + Custom PDFs`, `Deep Trends`, `Stays Private` | The production paywall presents a narrower promise than the local `PlusFeature` catalog. Compare the actual selected layout and version. |
| Paywall package snapshot | Yearly `$29.99`, Monthly `$6.99`, Lifetime `$29.99` | Confirm against ASC localized product prices. The lifetime value differs from the local fixture and site. |
| Yearly badge | `Save 38%` | Mathematically inconsistent with `$6.99 * 12` versus `$29.99`, which is about 64% savings. It matches an older `$1.99` and `$14.99` price pair instead. |
| Footer | Restore, Terms of Use, Privacy Policy | Confirm the production hosted or native rendering uses the same URLs in every placement. |

### Confirmed RevenueCat experiment snapshot

Experiment page: `https://app.revenuecat.com/projects/d0d314f5/experiments/exp22966addbd/report?range=Last+90+days%3A2026-05-26%3A2026-08-23`.

| Field | Observed value | Decision implication |
|---|---|---|
| Experiment | `Upgrade tab: timeline vs catalog` | Tests a native Upgrade-tab presentation, not the full funnel. |
| Status | Completed | Do not treat the status as proof of a winning arm. |
| Enrollment | 100% | Does not establish adequate sample size. |
| Duration | Aug 22 to Aug 22, effectively zero days | Too short for a durable conversion decision. |
| Variant A | `Upgrade tab - catalog (A/B control)` | Control. |
| Variant B | `Vitals+` | Treatment label needs to be mapped to the layout the binary actually renders. |
| Customers | 1 versus 0 | Insufficient sample. |
| Initial conversions | 0 versus 0 | No evidence of a winner. |
| Trials started | 0 versus 0 | No trial-start result. |
| Trial conversions | 0 versus 0 | No trial-to-paid result. |
| Paid, revenue, and MRR metrics | 0 versus 0 | No commercial result. |

This is a measurement-quality finding, not a product-performance finding. Keep the experiment as a historical record, but re-run it only with a stated sample-size rule, a minimum duration, version gating, placement labels, and a primary metric such as trial start per eligible Upgrade-tab impression.

## Prioritized findings for an implementation agent

| ID | Priority | Finding | Confidence | Primary surface |
|---|---|---|---|---|
| V-P0-01 | P0 | `converted_on` stores the last paywall surface, not a conversion timestamp. | Confirmed local | `Shared/Services/ConversionDiagnostics.swift:83-101` |
| V-P0-02 | P0 | Production paywall price and savings copy conflict with the local catalog and arithmetic. | Confirmed live snapshot plus confirmed local | RC paywall, `Vitals.storekit:4-91`, `docs/index.html:23-54` |
| V-P0-03 | P0 | The observed RevenueCat experiment ended with zero trial and paid conversions, so it has no decision value. | Confirmed live snapshot | RevenueCat experiment `exp22966addbd` |
| V-P1-01 | P1 | Downloads, first opens, HealthKit outcomes, onboarding exits, eligible offers, trial starts, and trial-to-paid conversion are not joined into one observable funnel. | Confirmed gap | `Shared/Services/ConversionDiagnostics.swift:33-159`, ASC Analytics |
| V-P1-02 | P1 | Purchase states are now distinguished in source, but pending, entitlement activation, trial start, restore, and later resolution still need end-to-end production validation. | Confirmed local, validation gap | `Shared/Services/StoreService.swift:586-617` |
| V-P1-03 | P1 | Product-load recovery is better than the prior audit, but only the full paywall has a visible retry path. Onboarding's six-second fallback needs a live degraded-network test. | Confirmed local, runtime impact unknown | `Vitals/Views/DashboardView.swift:2393-2403`, `2973-2992` |
| V-P1-04 | P1 | The main trial offer still arrives before the user sees a personal dashboard result, while the passive offer waits for real data and is heavily gated. | Confirmed local, conversion effect inference | `Vitals/Views/DashboardView.swift:2336-2969`, `Vitals/App.swift:514-547` |
| V-P1-05 | P1 | Local build/version and local commercial guides are ahead of or inconsistent with the live listing and current paywall snapshot. | Confirmed local and live snapshot | `project.yml:15-16`, `docs/app-store-metadata.md:9-21`, ASC/listing |
| V-P1-06 | P1 | The rating funnel opens a direct App Store write-review URL but has no reliable prompt-to-rating outcome measurement. | Confirmed local | `Shared/Services/ReviewPromptTracker.swift:34-253`, `Vitals/Views/ReviewPromptSheet.swift:111-209` |
| V-P1-07 | P1 | Empty, denied, loading, cached, and stale HealthKit states can still be hard to distinguish at the first-value boundary. | Confirmed local, user impact inference | `Vitals/Views/DashboardView.swift:1665-1840`, `Shared/Services/HealthKitService.swift` |
| V-P1-08 | P1 | Watch and widget surfaces have meaningful stale-data and watchdog risk, but no joined retention or degraded-surface telemetry. | Confirmed local, incident rate unknown | `VitalsWidget/VitalsWidget.swift:37-105`, `VitalsWatch/App.swift:117-159` |
| V-P2-01 | P2 | Dynamic Type, VoiceOver, small watch layouts, and fixed paywall footer limits need a complete conversion-path accessibility run. | Confirmed validation gap | `Vitals/Views/PaywallView.swift:370-474`, `Vitals/Views/ReviewPromptSheet.swift:89-180` |
| V-P2-02 | P2 | Agent documentation is structurally healthy at the root but stale archive pointers and old handoffs can mislead coding agents. | Confirmed local | `AGENTS.md`, `CLAUDE.md`, `archive/README.md`, `_handoffs/revenuecat-paywall-handoff.md` |

## ASC metadata, downloads, and acquisition

### Current local metadata

The current en-US metadata files are:

| Field | File | Current local value or shape |
|---|---|---|
| Name | `fastlane/metadata/en-US/name.txt:1` | `Total Calories - Daily Tracker` |
| Subtitle | `fastlane/metadata/en-US/subtitle.txt:1` | `TDEE Burn on Watch & Widget` |
| Keywords | `fastlane/metadata/en-US/keywords.txt:1` | `bmr,complication,resting,active,calculator,deficit,net,energy,steps,macro,bmi,body,fat,protein,carb` |
| Promotional text | `fastlane/metadata/en-US/promotional_text.txt:1` | Leads with Macros and Apple Health. |
| Description | `fastlane/metadata/en-US/description.txt:1-70` | Watch, widgets, dashboard, body profile, macros, Vitals+, privacy, and subscription copy. |
| Release notes | `fastlane/metadata/en-US/release_notes.txt:1-7` | Macros, all plans, pending purchase handling, slow product-load handling, and widget entitlement behavior. |
| Review notes | `fastlane/metadata/review_information/notes.txt` | Must be pulled and checked against the current product set before the next review submission. |

The local repository scan found 51 locale directories under `fastlane/metadata`. The public listing snapshot showed English, so the acquisition team must distinguish local files from live ASC localizations. A directory count is not proof that ASC has each locale active or that each locale has current copy.

### Metadata consistency findings

1. `docs/app-store-metadata.md:9-21` still describes the subtitle as `Burned Calories & Step Count`, while the local fastlane subtitle and public listing use `TDEE Burn on Watch & Widget`.
2. `docs/app-store-metadata.md:63-76` has an older Vitals+ feature list and broad privacy wording. It does not reflect the current Macros and body-profile copy in `fastlane/metadata/en-US/description.txt:23-55`.
3. `docs/app-store-metadata.md:409-413` says the local US prices are Monthly `$6.99`, Yearly `$29.99`, and Lifetime `$59.99`. Those values match the local StoreKit fixture but must be checked against ASC and the production RevenueCat package response before the next submission.
4. `docs/index.html:23-70` hardcodes a software version of `1.8.3`, rating count `8`, rating value `5`, and the same three local prices. The public listing snapshot is version `1.8.2` and the rating count is time-sensitive. JSON-LD is not a live ASC feed.
5. `docs/index.html:484-492` uses hardcoded App Store links without campaign identifiers. This makes site-to-install attribution weaker than it needs to be.
6. The current site first screen leads with total burn, while the production RC paywall leads with Net Deficit. That is a useful segmentation opportunity, not a contradiction by itself. Watch/widget acquisition should land on the free wedge; food-logging acquisition should land on Net Deficit and Macros.

### Download measurement requirements

ASC Analytics exposes Acquisition Sources, Product Pages, Campaigns, Monetization, Retention, App Usage, and Metrics for this app. The inspected page exposed the surfaces, but no trustworthy downloads or source-level conversion numbers were captured in this audit snapshot. Treat the following as unknown until exported:

- Impressions, product-page views, conversion rate, and downloads by source.
- Downloads by custom product page, campaign, territory, device, and app version.
- First-day and seven-day retention after an install.
- Download-to-onboarding-completion and download-to-trial-start.
- Download-to-paid conversion and revenue per download.
- Whether the recent `1.8.2` release changed the acquisition mix or only the version distribution.

The implementation agent should pull a fixed 7-day, 28-day, and 90-day window and record the extraction timestamp. Use the same windows in RevenueCat, then join on app version, country, and date. Never use RevenueCat new customers as a download count.

### Acquisition tests

Prioritize tests that isolate intent:

| Test | Control | Treatment | Primary metric | Guardrails |
|---|---|---|---|---|
| Watch wedge | Current listing | First screenshot and subtitle lead with the Watch complication and widget outcome | Product-page-to-download | First-day retention, HealthKit authorization |
| Burn wedge | Current listing | First frame leads with total burn and active plus resting context | Product-page-to-download | Onboarding completion, trial starts per install |
| Food wedge | Current listing | Custom product page leads with Net Deficit and Macros | Product-page-to-download | Empty-food-state exits, refund rate |
| Site attribution | Hardcoded App Store link | Campaign-specific App Store link and source parameter | Site click-to-download | Link integrity, regional routing |
| Screenshot ordering | Current four-image order | Watch/widget first or Net Deficit first by intent | Product-page conversion | Rating, retention, trial-to-paid |

Do not infer a winning creative from a short-lived rating or a single ASC day. The public rating sample is only eight ratings in the captured snapshot.

### Useful external leads from the user's likes

These are leads, not Vitals evidence:

- App Store screenshot workflow lead: `https://github.com/ParthJadhav/app-store-screenshots`. Use it to produce versioned, locale-aware screenshot variants with a manifest and QA step. The relevant test is still ASC conversion by custom product page.
- Apple Search Ads and search-term-popularity CLI lead: `https://github.com/rorkai/App-Store-Connect-CLI`. Use only for read-only keyword and campaign analysis until a deliberate metadata decision is made.
- Navigation simplification experiment lead: `https://x.com/carlmonkft/status/2091037062971412944`. The claimed lift is unverified. It supports testing a focused first feature, not copying a claimed percentage.
- Apple Retention Messaging API lead: `https://x.com/MarioSaputra/status/2089407941644534062`. Consider a reactivation test only after the retention baseline and user-consent constraints are clear.

## Trial, conversion, and live user flow

### Current onboarding path

The source-defined path is:

```text
Welcome
  -> core HealthKit authorization request
  -> calorie and step goals
  -> food logging choice
  -> optional dietary HealthKit authorization
  -> Vitals+ trial step
  -> Get Started or purchase
  -> Today dashboard
```

Exact source locations:

- Step enum and state: `Vitals/Views/DashboardView.swift:2336-2364`.
- HealthKit request when leaving Welcome: `Vitals/Views/DashboardView.swift:2452-2466`.
- Goal persistence: `Vitals/Views/DashboardView.swift:2624-2643`.
- Food intent and optional dietary permission: `Vitals/Views/DashboardView.swift:2677-2764`.
- Trial copy by food intent: `Vitals/Views/DashboardView.swift:2840-2894`.
- Trial CTA, direct purchase, error recovery, and free exit: `Vitals/Views/DashboardView.swift:2781-2836`, `2935-2992`.

Confirmed strengths:

- A free `Get Started` route remains available at `Vitals/Views/DashboardView.swift:2808-2820`.
- The food question avoids selling Net Deficit or Macros to users who say they do not log food.
- Legal links and Restore are adjacent to the onboarding trial CTA at `Vitals/Views/DashboardView.swift:2822-2836`.
- The CTA becomes `See Vitals+ Plans` after a six-second product-load wait, so the user can reach the full plan-picker route.
- Pending, cancelled, unavailable, and thrown purchase errors have distinct handling in the current source.

Conversion risks to validate:

- The user is asked to make a subscription decision before seeing a personal dashboard result in the main onboarding path. This is confirmed source behavior. The effect on trial starts is an inference.
- There is no visible progress indicator or Back action in the reviewed onboarding step implementation. This is confirmed source behavior. The effect on completion is an inference.
- The passive offer waits for `dashboardShowedRealData`, but requires setup completion, yearly eligibility, a cooldown, Today-tab selection, no covering sheet, and a 1.8-second delay at `Vitals/App.swift:514-547`. The offer may be well-timed for exposed users and under-exposed for eligible users.
- `startTrial()` rechecks eligibility immediately before purchase at `Vitals/Views/DashboardView.swift:2948-2953`. This protects offer honesty but can add latency at the highest-intent tap.

### Required trial state machine

The next implementation should produce one immutable event or local record for each state transition:

```text
eligible_unknown
  -> eligible
  -> ineligible
offer_eligible
  -> offer_impression
  -> plan_selected
  -> purchase_initiated
  -> apple_sheet_presented
  -> pending
  -> entitlement_active_trial
  -> entitlement_active_paid
  -> cancelled
  -> failed
  -> restored
  -> entitlement_lost
```

Do not count `purchase_initiated`, `pending`, or `offer_impression` as a trial start. RevenueCat and ASC should be the source for actual entitlement and transaction outcomes; local diagnostics should explain how the user reached them.

### RevenueCat insertion points and current state

| Concern | Current location | Current behavior | Recommended implementation point |
|---|---|---|---|
| Configure RC | `Shared/Services/StoreService.swift:678-689`, `configureIfNeeded()` | Debug uses a test key, release uses the production key. | Keep production key out of simulator runs. Add a config assertion to release-watch documentation, not to the audit. |
| Load offering | `StoreService.fetchProducts():321-345` | Loads the Vitals offering and sorted packages, then eligibility. | Record load start, success, empty-offering, and error latency with a bounded reason code. |
| Resolve trial eligibility | `StoreService.refreshIntroEligibility():347-384` | Uses StoreKit eligibility and hides trial copy until resolved. | Record `eligibility_state` and `eligibility_latency_bucket`, not health values. |
| Paywall impression | `StoreService.trackPaywallImpression():556-584` | Writes local pitch count and calls `trackCustomPaywallImpression`. | Add a placement and app-build attribute before the call, while keeping non-paywall funnel steps out of RC impressions. |
| Purchase | `StoreService.purchase():586-617` | Applies customer info, distinguishes cancellation and missing entitlement, and records first conversion after entitlement. | Emit state transitions and package metadata. Correct the conversion snapshot schema first. |
| Restore | `StoreService.restorePurchases():641-652` | Applies customer info and surfaces no-active-purchase or retry copy. | Record restore started, success, no-match, and failure. |
| Native layout variant | `StoreService.upgradeTabVariant`, `Shared/Utilities/PaywallUIVariant.swift:16-27` | Offering metadata `upgrade_tab` maps to catalog or feature-led; unknown values fall back to catalog. | Record the rendered layout separately from RC offering assignment. |
| Full paywall | `Vitals/Views/PaywallView.swift:199-735` | Native plan picker with all packages, Restore, Terms, Privacy, and fixed checkout footer. | Keep the experiment scoped to the generic Upgrade tab and label other placements separately. |
| Focused pitch | `Vitals/Views/TrialOfferPitch.swift:49-197` | Intent-specific feature pitch; used-trial accounts get a plan ladder. | Measure intent, feature, placement, and whether the user selected a plan. |
| Passive offer | `Vitals/App.swift:514-547` | Value-gated launch offer with cooldown and covering-sheet guards. | Record eligible versus exposed before changing cooldowns. |

### Conversion snapshot defect

`ConversionDiagnostics.recordConversion()` guards on `Key.convertedOn` but writes `Key.lastSurface` into that key at `Shared/Services/ConversionDiagnostics.swift:89-96`:

```swift
d.set(d.string(forKey: Key.lastSurface) ?? "unknown", forKey: Key.convertedOn)
```

`subscriberAttributes` then exports that value under `converted_on` at lines 146-157. The field is therefore a surface identifier such as `onboarding_trial`, not an ISO timestamp. This causes three problems:

1. `converted_on` is semantically false.
2. The sentinel and the timestamp are conflated, which makes later schema changes risky.
3. RevenueCat customer inspection cannot answer when the first conversion occurred from this attribute.

Validation requirement:

- Preserve the surface as `converted_surface`.
- Add a separate `converted_at` value with a documented ISO-8601 or epoch format.
- Add a test that asserts the two values are different fields and that `days_to_convert` is calculated from the first pitch timestamp.
- Backfill nothing from old values. Mark old records as legacy or unknown.

### RevenueCat custom attributes to add

The current implementation already mirrors `ConversionDiagnostics.subscriberAttributes` from `StoreService.syncConversionAttributes()` at `Shared/Services/StoreService.swift:518-542`. Existing keys include `pitch_views_total`, per-surface pitch counts, `pitch_last`, `pitch_first_seen`, `days_since_first_pitch`, `converted_on`, `pitch_views_at_convert`, `days_to_convert`, `converted_plan`, `converted_with_trial`, `converted_variant`, `converted_offering`, and `paywall_variant`.

Recommended additions use small, bounded strings and booleans. Do not send calorie values, step values, macro values, dietary values, body measurements, PDF contents, or raw HealthKit records.

| Attribute | Values | Exact insertion point | Why it matters |
|---|---|---|---|
| `app_version` | `1.8.3` | `StoreService.syncConversionAttributes()` | Separates releases in customer-level inspection. |
| `build_number` | `173` | Same function | Joins a customer issue to an exact release candidate. |
| `offer_placement` | `onboarding`, `upgrade_tab`, `history`, `settings`, `dashboard`, `passive_launch` | Pass placement into `trackPaywallImpression` and retain in `ConversionDiagnostics` | Prevents cross-placement conversion mixing. |
| `offer_intent` | `generic`, `net_deficit`, `macros`, `deep_trends`, `pdf`, `watch`, `body_profile` | `TrialPitchRequest` and `TrialOfferPitchSheet` before impression | Identifies feature-led demand. |
| `food_logging_intent` | `yes`, `no`, `unknown` | After `commitFoodAnswerAndContinue()` at `DashboardView.swift:2748-2764` | Enables a clean food-led versus Watch-led trial comparison without raw food data. |
| `healthkit_core_state` | `not_requested`, `authorized_data`, `authorized_empty`, `denied_or_unavailable`, `error`, `stale_cache` | After authorization and first data state in `DashboardView` and `HealthKitService` | Explains activation loss without sending health values. |
| `first_data_state` | `not_ready`, `real_data`, `zero_or_empty`, `cached`, `failed` | On `vitalsDashboardDidLoadData` handling in `Vitals/App.swift:898-900` and the dashboard load path | Separates value exposure from install count. |
| `first_data_latency` | bucket such as `0_2s`, `2_5s`, `5_15s`, `15s_plus`, `never` | Start at first dashboard load, finalize at first real data | Identifies slow HealthKit or cache paths. |
| `eligibility_state` | `unknown`, `eligible`, `ineligible`, `error` | After `refreshIntroEligibility()` at `StoreService.swift:351-384` | Prevents used-trial accounts from entering the eligible denominator. |
| `purchase_state` | `initiated`, `pending`, `active_trial`, `active_paid`, `cancelled`, `failed`, `unavailable`, `restored` | `StoreService.purchase()` and `restorePurchases()` | Makes customer-level support investigation possible. |
| `selected_package` | `yearly`, `monthly`, `lifetime` | `PaywallView.startPurchase()` and `TrialOfferPitchSheet.startPurchase()` | Connects intent and price choice to outcome. |
| `trial_copy_version` | a short semantic copy ID | At each trial surface before impression | Allows copy tests without relying on release notes. |
| `review_prompt_outcome` | `not_now`, `feedback`, `write_review_opened` | `ReviewPromptSheet.finish()` and tracker outcome methods | Measures the in-app handoff, not the Apple rating itself. |
| `watch_widget_intent` | `watch`, `widget`, `iphone`, `unknown` | At acquisition deep link or first relevant surface | Separates the free acquisition wedge from general dashboard intent. |

Keep the authoritative funnel in a local event schema or exportable first-party store if the product needs population-level analysis. RevenueCat attributes are customer-level context, not a replacement for ASC acquisition data or an event warehouse.

## Paywall and A/B test opportunities

### Native paywall surfaces

The code has several native paywall entry points:

- Generic Upgrade tab: `Vitals/App.swift:824-865` and `PaywallView` with `focus == nil`.
- Focused feature pitches: `Vitals/Views/TrialOfferPitch.swift:4-46` and the `PlusFeature` intent map in `Vitals/Views/PaywallView.swift:17-197`.
- History Deep Trends: `Vitals/Views/HistoryView.swift:2254-2429`.
- Onboarding trial: `Vitals/Views/DashboardView.swift:2838-2969`.
- Settings and dashboard locked-feature surfaces through `TrialOfferCoordinator`.

The generic Upgrade tab reads the `upgrade_tab` offering metadata. Focused paywalls intentionally force `.catalog` at `Vitals/Views/PaywallView.swift:253-258`, so a generic Upgrade-tab experiment must not be reported as a whole-app paywall experiment.

### Recommended experiment order

1. **Commercial truth test:** reconcile price and savings copy first. A false savings badge invalidates any pricing result.
2. **Measurement control:** catalog versus feature-led generic Upgrade tab, seven to 28 days minimum, with trial start per eligible impression as the primary metric.
3. **Placement test:** generic Upgrade tab versus focused intent pitch, measured per eligible feature request and per install.
4. **First-value timing:** onboarding offer before first data versus after first real dashboard data.
5. **Food-intent segmentation:** Macros and Net Deficit pitch for `food_logging_intent=yes` versus burn, trends, and reports for `no`.
6. **Offer exposure:** current passive cooldown versus one post-first-data opportunity and a shorter cooldown. Track eligible, exposed, dismissed, and converted separately.
7. **Plan presentation:** yearly-first cards versus feature-specific monthly choice, with trial-to-paid, refund, renewal, and revenue-per-install guardrails.
8. **Feature-led hero:** current Net Deficit hero versus Watch/widget free-wedge hero for the relevant acquisition source. Never force one hero across all sources.
9. **Recovery path:** spinner-only or disabled product state versus explicit retry and plan-picker path under a simulated RevenueCat failure.
10. **Retention handoff:** post-first-data widget or Watch setup prompt versus no prompt, measuring day-1 return and trial starts.

Every test needs an exposure denominator, a version/build key, an offering identifier, a placement, a package selection, and a guardrail for crashes, refunds, cancellations, and day-1 retention.

## Ratings and review funnel

### Confirmed current implementation

- `ReviewPromptTracker` requires at least three launches, three days since first open, and two positive moments before passive presentation (`Shared/Services/ReviewPromptTracker.swift:34-54`, `198-221`).
- Positive moments include goal or habit milestones and a subscriber who has retained Vitals+ for 30 days (`ReviewPromptTracker.swift:116-159`).
- A hard `Not now` cooldown is 60 days and a soft defer cooldown is 30 days (`ReviewPromptTracker.swift:49-54`, `223-243`).
- `ReviewPromptSheet` presents a direct `Yes, rate on the App Store` button and opens `AppStoreReviewLinks.writeReviewURL` (`Vitals/Views/ReviewPromptSheet.swift:111-145`).
- The destination uses the active storefront country and app ID `6761743504` (`Shared/Utilities/AppStoreReviewLinks.swift:4-45`).
- Negative or uncertain users are routed to private email feedback rather than the public review path (`ReviewPromptSheet.swift:150-225`).
- No `SKStoreReviewController.requestReview` call was found in the non-archive source scan. The current path is an explicit App Store handoff, not Apple's in-app review sheet.

### Review growth opportunities

The funnel is ethically better than asking at launch or after a permission denial, but its actual yield is unknown. Add local counters for:

```text
review_eligible
review_prompt_presented
review_not_now
review_feedback_started
review_feedback_submitted
review_write_review_opened
```

Use the App Store rating count and review text as the outcome. Do not claim that `write_review_opened` equals a rating. The eight-rating snapshot is too small for a reliable average guardrail, so use count growth, review sentiment, and support contacts together.

Test eligible moments in this order:

1. A second or third real-data day with a completed dashboard.
2. A goal or habit milestone after the user has seen the result persist.
3. A successful report export or meaningful History visit.
4. A subscriber who has held access for 30 days.

Avoid asking immediately after a trial purchase, a failed purchase, a HealthKit denial, a stale-data banner, or a crash recovery. These are poor moments even if they are technically high engagement.

## UX, accessibility, and degraded states

### Onboarding

The onboarding uses a `ScrollView` for non-trial pages and a fixed bottom bar for CTA stability (`DashboardView.swift:2374-2421`, `2555-2610`). This protects layout stability but should be tested with Dynamic Type sizes where the content may scroll while the CTA remains pinned. The lack of visible progress or Back is a usability hypothesis worth testing, not a reason to add navigation without measuring completion.

Validation cases:

- Fresh install with HealthKit already populated.
- Fresh install with no HealthKit samples.
- User denies core HealthKit access.
- User grants core access but declines dietary access.
- RevenueCat product load delayed beyond six seconds.
- RevenueCat product load fails.
- User selects `Get Started` without trial.
- User returns with an active entitlement during onboarding.
- User selects each plan from the full paywall.
- User taps Restore before and after a purchase.

### Paywall

The native paywall has good structural safeguards:

- Package prices come from RevenueCat localized package data in `StoreService.swift:92-155`.
- Trial badges are gated by resolved eligibility in `StoreService.swift:386-408`.
- Yearly, monthly, and lifetime package cards are rendered in `PaywallView.swift:603-617`.
- The CTA, error, disclosure, Restore, Terms, and Privacy share a pinned footer at `PaywallView.swift:364-474`.
- Plan cards combine accessibility children and expose selected and button traits at `PaywallView.swift:824-828`.

Remaining validation risks:

- The fixed 62-point disclosure/footer slot and three-line limit at `PaywallView.swift:403-433` may clip or over-compress under large text, localization, or VoiceOver settings.
- The CTA has a minimum scale factor and may become visually small while still technically fitting (`PaywallView.swift:372-398`).
- The footer uses small `caption2` links, which need a minimum effective hit target and VoiceOver order check.
- Focused pitch and onboarding footers use different copy and layout constraints, so a compliance fix in the full paywall may not reach every purchase path.
- `ReviewPromptSheet` uses a fixed minimum editor height and autofocuses the feedback field at `ReviewPromptSheet.swift:150-180`; test keyboard, VoiceOver focus, and large text.

### HealthKit, cache, widget, and watch

- Dashboard data failure can retain cached values or settle to zero at `DashboardView.swift:1702-1710`, `1772-1840`. The user needs an explicit freshness state, not just a number.
- The widget uses the most recent prior day when no same-day cache exists at `VitalsWidget/VitalsWidget.swift:77-105`. The stale label helps, but test a one-day, seven-day, timezone-change, and daylight-saving boundary.
- The widget gates Net Deficit on the cached Pro flag at `VitalsWidget/VitalsWidget.swift:15-23`. Validate entitlement loss while the host app is not open.
- Watch background refresh intentionally cancels work after eight seconds at `VitalsWatch/App.swift:117-149`, because the source comments identify the watchOS CAROUSEL watchdog code `0xc51bad02`. This is a useful operational guard, but it needs a count of cancellations, elapsed buckets, and refresh failures.
- HealthKit observer and background-delivery errors are logged in `Shared/Services/HealthKitService.swift:711-755`. Logs alone do not establish population impact.

## Website, terms, privacy, and storefront consistency

The non-RevenueCat consistency review found the following:

| Topic | Local evidence | Risk or action |
|---|---|---|
| Version | `project.yml:15` says `1.8.3`; site JSON-LD `docs/index.html:65` says `1.8.3`; public listing snapshot says `1.8.2` | Label site and repository as next release or update them after release. Do not let the site imply a feature is live before ASC. |
| Subtitle | `docs/app-store-metadata.md:11-12` differs from `fastlane/metadata/en-US/subtitle.txt:1` and the public listing | Mark the guide as stale or regenerate it from the current metadata source. |
| Prices | Local fixture and docs say Lifetime `$59.99`; RC paywall snapshot displayed Lifetime `$29.99` | Verify ASC product prices and RC package mapping before changing copy. |
| Savings | RC paywall displayed `Save 38%` beside `$6.99` monthly and `$29.99` yearly | Recalculate from the actual localized prices, or remove the badge until truth is confirmed. |
| Site structured data | `docs/index.html:23-70` hardcodes rating, price, version, and download URL | Treat as a release artifact with an extraction date, not a permanent source of truth. |
| Site links | `docs/index.html:484-492`, `622-626` hardcode US App Store URLs | Add tested campaign variants only after a source taxonomy exists. |
| Terms | `docs/terms.html:86-115` describes purchases, renewal, refunds, and restore | Recheck wording against the current CTA and package prices. |
| Privacy | `docs/privacy-policy.html:86-125` has a dated policy and purchase section | Verify that non-purchase claims remain accurate, but do not add the excluded RevenueCat disclosure inconsistency as a finding. |
| Support | `docs/support.html:40-49` has HealthKit and widget troubleshooting | Add a clear stale-data and purchase-pending recovery path to the support checklist. |
| App Review notes | `fastlane/metadata/review_information/notes.txt` is version-sensitive | Ensure the notes describe the current Macros, Watch, widget, trial, and Restore paths. |

The landing page currently has good content for Watch, widgets, burn, Net Deficit, reports, and trends. The main growth improvement is measurement and intent-specific landing, not more copy. Keep a single source table for product IDs, localized prices, live version, screenshot set, and feature availability.

## Release crash and regression watchdog requirements

### Existing signal sources

The repository has useful local logging but no confirmed crash analytics or MetricKit integration in the inspected source. Relevant locations:

- `Shared/Services/DataService.swift:35-47` logs an in-memory model-container failure and calls `fatalError` if that test or fallback container cannot be created. Confirm target usage before treating it as a production crash source.
- `Shared/Services/StoreService.swift:341-344`, `635-650` logs product-load, customer-info, and Restore errors.
- `Vitals/Views/DashboardView.swift:1822-1835` logs Today HealthKit failures and retains cache when possible.
- `Shared/Services/HealthKitService.swift:638-640`, `711-755`, `793-802`, `1191-1226` logs query, observer, refresh, and optional-data failures.
- `VitalsWatch/App.swift:125-149` logs background duration and failure after the eight-second cancellation boundary.
- `VitalsWidget/VitalsWidget.swift:37-105` has data-available and stale-date branches that can be checked in screenshots or UI tests.
- `Vitals/Views/HistoryView.swift:1918-2053` logs History fetch and CSV export failures.

### Release-window monitoring contract

For every TestFlight or App Store release, capture a baseline for the previous 14 or 28 days and compare release cohorts at 1 hour, 6 hours, 24 hours, 72 hours, and 7 days. Join every signal by:

```text
app ID
bundle ID
marketing version
build number
target
OS version
device class
territory
release channel
```

Minimum signals:

| Signal | Source | Provisional alert rule |
|---|---|---|
| Crash-free users and sessions | ASC crash data, Xcode Organizer, or a connected crash provider | Alert on a meaningful absolute drop or 2x the version baseline. Calibrate thresholds from fleet history. |
| Launch failure or immediate exit | Crash logs and support reports | Any clustered signature in the first 24 hours is urgent. |
| Main-thread hang or watchdog termination | ASC/Xcode diagnostics, MetricKit if later connected | Alert on new signature or 2x baseline. |
| Watch CAROUSEL termination | Watch diagnostics and `0xc51bad02` log correlation | Alert on any new release spike, especially if refresh completion falls. |
| Product-load failure | Store logs, RC offerings availability, support reports | Alert if failed or empty offerings exceed 5% of paywall attempts or 2x baseline. |
| Purchase pending unresolved | RC customer state plus local purchase-state record | Alert when pending persists beyond a documented resolution window. Never count it as a trial. |
| Restore failure | Store logs and support reports | Alert on a new error cluster or a large rise after a release. |
| HealthKit no-data or stale-cache rate | Local debug fixtures, support reports, optional privacy-safe counters | Alert when first-data completion or freshness falls materially versus baseline. |
| Widget and complication freshness | Snapshot/UI probes and support reports | Alert on stale fallback rates, missing timelines, or entitlement-gated content mismatch. |
| Trial starts per install | ASC downloads joined to RC trial starts | Alert on a sustained drop after controlling for source, territory, and eligibility. |
| Trial-to-paid conversion | RC mature cohorts | Do not alert on immature trials. Use cohort age and renewal maturity. |
| Rating and review velocity | ASC ratings and review feed | Alert on new low-rating clusters, but suppress average-based alerts until sample size is meaningful. |

The MacBook watchdog requested elsewhere should consume exported ASC, RC, crash, hang, and local probe data. It should default to report-only and keep email scaffolding disabled until explicitly configured.

### Vitals release regression matrix

The release gate should run these paths on a headless leased simulator and a TestFlight sandbox device where platform state matters:

1. Cold launch with empty HealthKit, authorized HealthKit, denied HealthKit, and stale cache.
2. Onboarding CTA with fast, delayed, failed, and recovered product load.
3. Eligible seven-day trial, used-trial account, monthly purchase, yearly purchase, lifetime purchase, cancellation, pending, failed, and Restore.
4. Generic Upgrade-tab catalog and feature-led variants, plus each focused feature route.
5. Free exit from onboarding and later passive offer at first real-data moment.
6. Widget same-day, prior-day, seven-day stale, Pro, and lapsed-entitlement states.
7. Watch first launch, permission denial, background refresh under eight seconds, and a forced slow refresh.
8. VoiceOver, Dynamic Type at accessibility sizes, dark mode, RTL or pseudo-localization, and narrow watch display.
9. History trend, Deep Trends empty comparison, PDF export, CSV export, and share destinations.
10. Review prompt after a positive moment and after a negative or stale-data path to ensure it does not appear at the wrong time.

## Cursor, Claude, Codex, and agent-documentation hygiene

### Confirmed healthy structure

- `AGENTS.md` is a symlink to `CLAUDE.md`, so the root guide has one canonical source for the current agent rules.
- `.agents/skills/vitals-architecture/SKILL.md` and `.claude/skills/vitals-architecture/SKILL.md` are byte-identical in the inspected repository scan.
- `.codex/config.toml` is small and points to the Astro MCP server. It does not duplicate the root guide.
- The root guide identifies the four targets, App Group, review funnel, ASC privacy-policy URL, privacy manifests, simulator owner, and Astro ASO tooling.

### Confirmed hygiene risks

1. There is no root `README.md`, but `archive/README.md:7-9` tells agents to use the top-level README for current state. This is a broken current-state pointer.
2. `docs/localization-aso.md:1-14` describes a May 2026 draft `1.5.3` and an old `IN_REVIEW` block. It is useful history but can be mistaken for current release state.
3. `docs/archive/aso/2026-05/astro-phase-b-report.md` is correctly dated but contains old ASC upload state and locale counts. Keep it archived and make the archive status obvious to agents.
4. `_handoffs/revenuecat-paywall-handoff.md:1-7` says it is superseded, but the remainder contains old product IDs and prices. A coding agent that starts reading at the middle can still copy obsolete commercial values.
5. `docs/app-store-metadata.md` is presented as a current source of truth while its subtitle and some feature and price instructions differ from the current fastlane metadata and live RC snapshot.
6. `archive/README.md` is historically clear but depends on the missing top-level README. This makes the intended separation between human history and agent-operational truth less reliable.

### Recommended agent-facing layout

Do not implement this during the read-only audit, but use this target structure in the next maintenance pass:

```text
CLAUDE.md                 canonical agent guide
AGENTS.md -> CLAUDE.md    compatibility symlink
README.md                 short human and agent entry point
docs/agent/
  current-state.md        version, targets, source-of-truth links, last verified
  release-checklist.md    ASC, TestFlight, RC, simulator, and watchdog steps
  metadata-source.md      generated or clearly dated metadata source
docs/audits/
  AUDIT823.md             current audit, if retained here in a future migration
docs/handoffs/
  active/                  only active handoffs
  archive/                 superseded handoffs with status headers
docs/archive/              dated historical plans and audits
.agents/skills/            shared agent skills
.claude/skills/            compatibility copy or symlink, with parity check
.codex/                    Codex-only configuration, no duplicated product truth
```

Every non-current document should begin with `Status`, `Last verified`, `Owner`, and `Source of truth`. Product prices, app version, ASC state, and RevenueCat offering IDs should be copied from one current table, not hand-maintained in multiple prose files.

## Validation plan for the implementation agent

### Commercial and metadata validation

1. Pull ASC app ID `6761743504` app information, the live version, editable draft version, localizations, product pages, acquisition sources, campaigns, and subscription products.
2. Pull the RevenueCat Vitals project offerings, packages, product identifiers, localized prices, intro offers, entitlement state, paywall metadata, and experiment assignment.
3. Compare all product IDs against `Shared/Services/StoreService.swift:8-18`, `Vitals.storekit:4-91`, `docs/app-store-metadata.md:405-425`, `docs/index.html:30-54`, and the public listing.
4. Recalculate annual savings from the actual localized monthly and yearly prices. Do not trust a hardcoded `Save 38%` label.
5. Verify each active locale in ASC against `fastlane/metadata`, then record the extraction date and source file hash.
6. Verify the site App Store URL, canonical URL, privacy URL, terms URL, version, screenshot files, structured rating, and prices.

### Funnel and purchase validation

1. Add or test the state machine before using trial-start rate as a decision metric.
2. Unit test `ConversionDiagnostics.recordConversion()` for surface, timestamp, plan, trial, variant, offering, and days-to-convert fields.
3. Test purchase success, cancellation, pending, failed, unavailable, Restore success, Restore no-match, entitlement loss, and used-trial eligibility.
4. Test an offline or failing RevenueCat offering load. Confirm onboarding reaches the full plan picker and has a retry path.
5. Run the onboarding sequence with seeded HealthKit data and without seeded data. Record time to first real data, step completion, trial exposure, and free exit.
6. Run the same matrix for generic Upgrade tab, focused feature pitch, History Deep Trends, and Settings.
7. Re-run the native paywall experiment for at least a predeclared duration and sample size, with a primary metric and guardrails. A one-day zero-conversion run is not sufficient.

### Accessibility and UX validation

1. Run VoiceOver through Welcome, HealthKit denial, goals, food choice, trial, plan selection, purchase error, Restore, and review prompt.
2. Run Dynamic Type through the largest accessibility sizes and verify that CTA, disclosure, Restore, Terms, Privacy, and error text remain reachable.
3. Check color contrast and non-color selection state in all paywall plans and widget metrics.
4. Test right-to-left layout, long localized prices, long localized trial text, and narrow watch displays.
5. Verify stale labels include enough date context and that entitlement-lapsed widgets do not expose premium metrics.

### Release-watch validation

1. Capture the pre-release baseline and the exact candidate build `1.8.3 (173)`.
2. After TestFlight or release, collect ASC crash and usage reports, RC customer and transaction cohorts, and local diagnostic exports at 1 hour, 6 hours, 24 hours, 72 hours, and 7 days.
3. Compare crash, hang, launch, HealthKit, product-load, pending, Restore, widget, Watch, trial, revenue, and rating signals by target and version.
4. Open an urgent incident when a new crash or watchdog signature clusters across multiple users, or when a conversion-critical failure rises above the calibrated threshold.
5. Keep notification delivery disabled until the owner explicitly configures an email destination and SMTP or relay credentials.

## Audit limitations

- ASC acquisition, download, retention, and crash counts were not exported into this file, so those numeric outcomes remain unknown.
- RevenueCat metrics are a live production snapshot and changed while the page was observed. They are not a cohort report.
- The RevenueCat experiment page showed zero conversions in both arms. That proves the run was not decision-ready, not that either layout is good or bad.
- No real Apple sandbox purchase, pending transaction, refund, renewal, cancellation, or entitlement-revocation flow was executed in this read-only pass.
- No physical Apple Watch, VoiceOver, Dynamic Type, RTL, or production crash session was run.
- The public rating average and count are too small for a stable experiment guardrail.
- The prior audit's existing content, including findings outside this addendum's explicit exclusion, was not rewritten. This addendum is the current scoped interpretation for implementation planning.

## Vitals addendum conclusion

The free Watch, widget, and total-burn wedge is strong enough to support more downloads, but Vitals needs commercial truth and funnel truth before optimizing harder. The most urgent implementation items are the `converted_on` schema defect, the live versus local price and savings reconciliation, the invalid zero-data experiment, and a joined install-to-entitlement measurement contract. Once those are fixed, test first value timing and intent-specific paywalls, then use ASC acquisition and mature RevenueCat cohorts to decide which surface actually improves revenue without degrading the free product experience.

## Activity and success context, 2026-08-23

Classification: **growing acquisition, monetizing, conversion softening**. Confidence: **high**. Trend: **acquisition growing, conversion softening**.

ASC release state: `iOS 1.8.2 Ready for Distribution`. ASC evidence: [Analytics Overview](https://appstoreconnect.apple.com/apps/6761743504/analytics/overview?dateSpec=d90), selected range `dateSpec=d90`.
RevenueCat evidence: [Project Overview](https://app.revenuecat.com/projects/d0d314f5/overview), production mode, selected range `Last 28 days, 2026-07-27 through 2026-08-23`.

### Observed activity

| Source | Metric | Value | Window or comparison |
| --- | --- | ---: | --- |
| ASC | First-time downloads | 1140 | 90-day Analytics Overview |
| ASC | Redownloads | 142 | 90-day Analytics Overview |
| ASC | Conversion rate | 5.88% | comparison -23.4% |
| ASC | Proceeds | $834 | 90-day Analytics Overview |
| ASC | In-app purchases | 228 | 90-day Analytics Overview |
| RevenueCat | New customers | 588 | last 28 days |
| RevenueCat | Active customers | 1092 | last 28 days |
| RevenueCat | Active trials | 22 | current total |
| RevenueCat | Active subscriptions | 56 | current total |
| RevenueCat | MRR | $87 | current total |
| RevenueCat | Revenue | $551 | last 28 days |

A missing value above means the source did not expose that metric in this read-only snapshot. It is not a zero.

### Interpretation and implementation focus

Vitals is the strongest current commercial engine in the fleet snapshot. ASC shows 1,140 first-time downloads, +330% versus the comparison, 5.88% conversion with a -23.4% comparison, $834 proceeds with +760%, and 228 in-app purchases. RevenueCat shows 588 new customers, 1,092 active customers, 22 active trials, 56 active subscriptions, $87 MRR, and $551 revenue in the last 28 days. The correct priority is conversion and cohort truth: keep the acquisition wedge, repair the known commercial and experiment instrumentation issues, and use mature trial cohorts to improve trial starts without damaging the free Watch and widget experience.

The deterministic classifier recommends: Prioritize first-value and trial-start instrumentation, then test the paywall or native purchase surface with mature conversion cohorts.

- Join ASC first-time download, first launch, first value, paywall shown, offer loaded, trial started, trial canceled, trial converted, entitlement active, restore, and purchase failure events with the app version and build.
- Keep ASC's 90-day acquisition and proceeds window separate from RevenueCat's 28-day customer and revenue window. Do not calculate a conversion rate by dividing values from different windows.
- Use a mature trial cohort and a minimum sample before choosing a native paywall or onboarding A/B winner. Record the offering identifier, package, placement, experiment variant, and build.
- Put the app's classification and the next baseline date in the release handoff so Cursor, Claude, and Codex do not optimize from an old qualitative audit.

### Boundary on success or death

This snapshot supports the label **growing acquisition, monetizing, conversion softening**, not a lifetime verdict. Acquisition or paid conversion is rising, while ASC conversion rate is moving down. A later decision should include a clean 28-day RevenueCat trend, ASC acquisition and conversion trend, ratings and review count, crash and hang evidence, and a release-specific cohort.
This dated section supersedes earlier statements in this file that per-app ASC or RevenueCat activity was unavailable as of 2026-08-23. Earlier statements remain historical evidence boundaries for their original audit pass.
