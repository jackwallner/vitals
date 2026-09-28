# AUDIT822: Vitals release, polish, and RevenueCat audit

Date: 2026-08-22
Repository: `/Users/jackwallner/vitals`
Scope: read-only product and release audit for the next implementation agent
Change policy: this audit adds documentation only. No app source, project configuration, tests, metadata, RevenueCat configuration, or release state was changed by this audit.

## Executive decision

Current status: **NO-GO**.

The app has a solid core and the unit suite is green, but this snapshot is not ready for App Store submission or a confident TestFlight handoff. The most important reasons are:

1. App Store Connect version 1.8.2 is waiting for review with build 161 attached, while build 173 is a separate valid build. The reviewed build is therefore not the current local HEAD build.
2. The UI suite has four failures in two test cases: the seeded Settings gear is not hittable, and the History upgrade flow presents a blank or incomplete pitch.
3. A pending purchase is dismissed as if it succeeded from the trial pitch. The purchase path also records a conversion before distinguishing an active entitlement from a pending transaction.
4. Net-calorie widgets use a display preference without independently checking the cached Pro entitlement. Another widget already has a Pro gate, so entitlement behavior is inconsistent.
5. The RevenueCat entitlement check accepts any active entitlement, not a named Vitals entitlement. This is permissive and should be made explicit before relying on it for premium access.
6. The checked-in StoreKit fixture is stale and is not attached to either the app scheme or the UI-test scheme. The current local prices and trial behavior are consequently not covered by the existing automated purchase flow.
7. App Store and support copy says that no data leaves the device and that there are no third-party SDKs or network requests, while the app configures RevenueCat and sends conversion attributes. The privacy policy describes RevenueCat correctly, but the public and review copy is contradictory.
8. The cache recovery path deletes the local store, WAL, and SHM files on any open failure and then falls back to memory. This can silently erase the locally cached history and widget data.
9. The paywall and onboarding contain fixed-height or single-line areas that are high-risk under Dynamic Type, localization, accessibility sizes, and long RevenueCat product text. Summary PDF layout and the History period selector need dedicated rendering checks.

No reviewer can honestly call this snapshot perfect until the failures above are fixed or explicitly accepted with evidence. The ordered handoff at the end of this document is the recommended implementation sequence.

## Audit method and evidence

The audit combined:

- Three independent read-only Luna 5.6 reviews using `gpt-5.6-luna`, with separate focus on UI and accessibility, application correctness and monetization, and App Store/release readiness.
- Direct source review across SwiftUI views, shared services, widgets, watch targets, XcodeGen configuration, tests, scripts, privacy files, metadata, and local artifacts.
- A unit-test run and a full UI-test run on a leased headless simulator.
- Read-only App Store Connect inspection, including the submitted version to build relationship and current build status.
- Read-only RevenueCat inspection of offerings, experiment configuration, product identity, and result data.
- Review of the available local handoffs and historical audits for Cursor-adjacent context.

The three reviewers were instructed not to edit files, commit, push, upload, or change external state. Their findings were reconciled against the current source and against prior audits, because several historical findings are no longer current and one reviewer finding rests on an incorrect cross-device assumption.

### Commands and test results

Unit command:

```text
xcodebuild test -project Vitals.xcodeproj -scheme Vitals \
  -destination 'id=2C7A80C1-1228-411A-B9AD-A7DEED683F79' \
  -resultBundlePath /tmp/vitals-audit-unit.xcresult
```

Result: **101 tests passed, 0 failures, 0 unexpected failures**.

UI command:

```text
xcodebuild test -project Vitals.xcodeproj -scheme VitalsUITests \
  -destination 'id=2C7A80C1-1228-411A-B9AD-A7DEED683F79' \
  -resultBundlePath /tmp/vitals-audit-ui.xcresult
```

Result: **15 test cases, 4 failures, 0 unexpected failures**.

The simulator was leased as `agent-sim-1` for owner `vitals`. It must be checked in after all testing.

Release compile command started during the audit:

```text
xcodebuild -project Vitals.xcodeproj -scheme Vitals -configuration Release \
  -destination 'id=2C7A80C1-1228-411A-B9AD-A7DEED683F79' \
  -derivedDataPath /tmp/vitals-audit-release-dd build
```

Result: **BUILD SUCCEEDED** for the Release simulator targets. The build emitted existing warnings for an unused `nonZeroStepDays` value in `Shared/Services/SummaryReportGenerator.swift:106` and an `await` with no async operations in `Vitals/Views/DashboardView.swift:1802`. These warnings do not prevent compilation, but they should be cleaned up or explicitly accepted before the final release candidate.

### Audit limitations

This audit did not:

- Change source or configuration.
- Upload a TestFlight build. The explicit request was to document only.
- Execute a real App Store or sandbox purchase, restore, refund, renewal, cancellation, or entitlement revocation.
- Run the full UI matrix on every iPhone size, watch size, Dynamic Type category, VoiceOver state, right-to-left layout, pseudo-localization, or physical device.
- Render and visually inspect every Summary PDF data combination.
- Prove the RevenueCat experiment with enough real customers or mature trial cohorts.
- Replace the need for a final archive inspection and App Store Connect build association check.

## Current repository and release state

### Working tree

The worktree already contained unrelated user state before this audit:

```text
 M fastlane/report.xml
?? .agents/
?? .codex/
?? revenuecat-dashboard/
```

Those paths are not part of this audit and must remain untouched. The next agent must commit only `AUDIT822.md` for this task.

HEAD at audit time:

```text
9d2973b chore: stage pbxproj for build 173
```

Current local project configuration reports marketing version `1.8.2` and build `173`. The project declares RevenueCat package version `5.14.0`, while `Package.resolved` resolves `5.71.0`. That package-resolution drift should be made intentional and documented.

The project guide describes iOS 26 and watchOS 26, while `project.yml` currently declares iOS 17.0, watchOS 10.0, and Xcode 16.0. Xcode 26.6 and SDK 26.5 were used in this environment. Resolve whether the deployment targets and guide are intentionally different. Do not silently change deployment targets during a release fix.

### App Store Connect state

The live App Store Connect inspection showed:

| Item | Observed state | Release implication |
| --- | --- | --- |
| App | Total Calories - Daily Tracker, app id `6761743504` | Correct app record inspected |
| Version 1.8.2 | `WAITING_FOR_REVIEW` | Existing submission is already in review flow |
| Build attached to version 1.8.2 | Build id `4b44758c-5996-469f-ac9a-b4d3431f44b5`, build number `161` | This is not the current local build 173 |
| Build 173 | Build id `79676754-7d85-48be-9031-db25e2d96477`, `VALID`, `APP_STORE_ELIGIBLE` | It is uploaded and valid, but was not attached to the waiting version |
| Build 173 upload | 2026-08-22 12:22:33 -07:00 | Confirms a recent upload exists, not that it is submitted |
| Yearly product | `com.jackwallner.vitals.yearly`, `APPROVED` | Live product exists |
| Monthly product | `com.jackwallner.vitals.monthly`, `APPROVED` | Live product exists |
| Lifetime product | `com.jackwallner.vitals.plus.lifetime`, `APPROVED` | Live product exists |

Required next action: decide whether to continue the existing review submission or create a new version/build association. Do not upload another build and assume App Store Connect will attach it to the waiting version. Verify the exact build number on the version record after any release operation.

### Priority legend

- **P0**: release blocker or high risk of a rejected, misleading, or materially broken purchase experience.
- **P1**: must fix or produce explicit evidence before claiming production readiness.
- **P2**: important hardening or user-facing polish that should be completed before broad rollout.
- **P3**: follow-up improvement or test debt that does not justify blocking a narrowly scoped release if all P0 and P1 items are closed.

Each finding is labeled as confirmed, likely, or requiring runtime verification. A reviewer suggestion is not a confirmed defect until the source and behavior support it.

## P0 release blockers

### P0.1 Submitted App Store build does not match current build

**Status: confirmed.**

App Store Connect version 1.8.2 is waiting for review with build 161 attached. Build 173 is valid and eligible, but it is not attached to that version. A release reviewer would be reviewing the wrong binary if the current local changes are assumed to be in the submitted build.

Required evidence before sign-off:

1. A fresh archive with the intended marketing and build numbers.
2. Archive inspection proving the version, build, bundle identifiers, entitlements, privacy manifests, and embedded targets.
3. App Store Connect version relationship showing the intended build attached to the intended version.
4. TestFlight install from that exact build, not from the first IPA found under `build/`.

### P0.2 Existing UI regression: Settings gear is not hittable

**Status: confirmed by UI test.**

`SeededHealthFlowUITests.testSeededTodayHistorySettingsAndTimelinePaywall` failed at `VitalsUITests/SeededHealthFlowUITests.swift:100`. The test found the `gearshape` button with label `Settings` at approximately `{{337.2,78.0},{40.7,40.7}}`, but XCTest reported it as not hittable and returned a hit point of `{-1,-1}`.

Investigate the actual rendered hierarchy, safe-area placement, navigation transition state, overlay, and hit-testing region. A button that exists but cannot be tapped is a real user-flow failure. Check both the UI test and a physical-size device, because a hit region at the top-right edge can fail differently on different status-bar and Dynamic Island layouts.

Acceptance criteria:

- The button is hittable at default and accessibility text sizes.
- The entire visible control has a sufficiently large hit target.
- No overlay, toolbar transition, or safe-area inset blocks it.
- The test opens Settings without coordinate-based workarounds.
- VoiceOver identifies it as a button with a stable label.

### P0.3 Existing UI regression: History upgrade pitch can be blank

**Status: confirmed by UI test.**

`TrialOfferPresentationUITests.testHistoryUpgradeTapRendersARealPitchNotABlankSheet` reported three assertions for the Custom range path:

- The locked Custom range raised no pitch.
- The pitch rendered with no purchase button.
- The pitch rendered without the feature headline.

The three assertions are one behavioral failure, not three independent bugs. The resulting sheet is either absent or incompletely rendered. This is especially important because the History locked-feature path is a monetization surface and because focused-feature paywalls intentionally use a different variant path.

Acceptance criteria:

- Tapping a locked History feature always presents a nonblank, labeled pitch.
- The pitch contains the feature-specific headline, price/package choices, purchase CTA, Restore, Terms, Privacy, and required Apple subscription disclosure.
- Offering loading, no offering, package loading, purchase failure, and retry states are visible and actionable.
- The test asserts the correct sheet identity and content, not merely the existence of a sheet.
- The pitch does not silently fall back to an empty `current` offering.

### P0.4 Purchase state machine treats pending as success in the trial pitch

**Status: confirmed by source review.**

`Shared/Services/StoreService.swift:522-548` returns `.pending` when a transaction has not produced an active entitlement. `Vitals/Views/TrialOfferPitch.swift:165-187` handles `.purchased` and `.pending` together and calls `onDismiss()` for both. A pending transaction is not a completed purchase and must not dismiss a trial offer as though Pro is active.

The standard `PaywallView` path waits for `isPro` before dismissing, but it also needs a clear pending explanation and recovery action. The two paywall paths must share one state-machine contract.

Required behavior:

- Purchased and entitlement active: show success or dismiss after the entitlement update is confirmed.
- Pending: keep the UI open or move to an explicit pending state, explain that Apple is completing the transaction, and provide a way to retry status or close without claiming access.
- Cancelled: remain on the paywall with no misleading error if cancellation is expected.
- Failed: show a user-readable error and retry action.
- Restore: show restoring, restored, no purchases found, and failure states.
- Entitlement revoked or expired: remove premium content and refresh all surfaces.

### P0.5 StoreKit fixture is stale and not attached to test schemes

**Status: confirmed.**

`Vitals.storekit` is included as a resource in `project.yml`, but neither `Vitals.xcscheme` nor `VitalsUITests.xcscheme` contains a `StoreKitConfigurationReference`. Bundling a StoreKit file does not activate StoreKit local testing.

The fixture currently contains:

| Product | Local fixture price | Intro |
| --- | ---: | --- |
| `com.jackwallner.vitals.plus.lifetime` | $59.99 | none |
| `com.jackwallner.vitals.monthly` | $6.99 | 1-week intro |
| `com.jackwallner.vitals.yearly` | $29.99 | 1-week intro |

The runtime product identifiers match these current fixture identifiers, but `docs/app-store-metadata.md:405-408` still lists legacy monthly and yearly IDs and legacy prices. `docs/app-store-metadata.md:446` claims StoreKit is wired, which is not true for the current schemes.

Required action:

1. Decide whether local StoreKit testing is part of the supported test workflow.
2. If yes, attach the fixture to the app and UI-test schemes and verify it in Xcode scheme data.
3. Test product loading, intro eligibility, purchase, pending, cancellation, restore, renewal, refund, and entitlement revocation.
4. Reconcile the fixture, App Store Connect products, RevenueCat products, app copy, and metadata.
5. Ensure simulator tests use the local fixture or a test RevenueCat configuration, never the production `appl_` key.

### P0.6 Privacy and review copy contradict the implemented RevenueCat integration

**Status: confirmed.**

The app imports and configures RevenueCat in `Shared/Services/StoreService.swift`, and `Shared/Services/ConversionDiagnostics.swift` sends conversion attributes. The privacy policy correctly explains that RevenueCat receives an anonymous app user ID, purchase and entitlement data, and limited technical or device context, and does not receive HealthKit data.

However, active metadata and support copy contain stronger claims:

- `fastlane/metadata/en-US/description.txt` says no data leaves the device.
- Review notes say no analytics, ads, servers, accounts, tracking, or network requests of any kind.
- `docs/support.html` repeats no-server, no-analytics, and no-tracking claims.
- `docs/index.html` says no third-party SDKs or network activity and has stale version/onboarding claims.

These statements are materially inconsistent with a RevenueCat purchase SDK. They can cause App Review questions, privacy label inconsistencies, and user distrust. Reconcile every customer-facing and reviewer-facing claim with actual runtime behavior. Keep the accurate HealthKit claim narrow: HealthKit health data remains local and is not sent to RevenueCat. Do not claim that the entire app makes no network requests.

### P0.7 Net-calorie premium content is not consistently entitlement-gated in extensions

**Status: confirmed by source review, runtime visibility still required.**

`VitalsWidget/VitalsWidget.swift:7-16` and `:42-66` load `showNetCalories` from shared defaults and build `VitalsEntry` without an `isProCached` check. `VitalsWatchWidget/WatchComplication.swift:101-110`, `:135-180`, and `:598-614` do the same for the watch complication path. `VitalsWidget/EnergyAveragesWidget.swift:63-82` does check the cached Pro key, so the extension behavior is inconsistent.

If a customer loses entitlement, changes account, has stale defaults, or has not reopened the app, a widget or complication may continue showing net-deficit content based only on a display preference. Premium visibility must be decided consistently in every extension process.

Required acceptance tests:

- Free user, Pro user, expired user, restored user, pending user, and signed-out or reset state.
- App not opened after entitlement change.
- Widget timeline reload before and after entitlement change.
- iOS widget families and watch complication families.
- Cached entitlement missing, malformed, and stale.
- No premium data in snapshot or placeholder entries for a free user.

### P0.8 Entitlement check accepts any active RevenueCat entitlement

**Status: confirmed permissive contract, impact depends on account configuration.**

`CustomerInfo.hasVitalsProEntitlement` in `Shared/Services/StoreService.swift:183-189` returns true when `entitlements.active` is nonempty. It does not require the expected Vitals entitlement identifier. If an account has another active entitlement, the app can treat it as Vitals Pro.

Use a named entitlement such as the configured Vitals entitlement, with an explicitly documented alias policy if multiple product-era entitlements must remain valid. Add tests for:

- Exact Vitals entitlement active.
- Unrelated entitlement active only.
- Multiple entitlements with Vitals inactive.
- Expired, revoked, billing retry, and grace-period states.
- Product purchase completed but entitlement delayed.

Do not call this an exploit without proving that unrelated entitlements can be present for the same customer in the production project. It is still too broad for a release gate.

## P1 correctness and monetization findings

### P1.1 Conversion diagnostics record pending purchases too early

In `Shared/Services/StoreService.swift:522-548`, conversion diagnostics are recorded before the code confirms an active entitlement. A pending transaction can therefore be reported as a conversion. The recorded attributes also need to identify the offering, placement, UI variant, package, trial eligibility, transaction state, and whether the event is first purchase, restore, renewal, or delayed entitlement activation.

Separate these concepts:

| Event | Meaning |
| --- | --- |
| Paywall impression | A user saw a specific placement and variant |
| Package selection | A user selected a package |
| Purchase initiated | StoreKit purchase call started |
| Purchase pending | Apple has not completed the transaction |
| Purchase completed | Transaction completed and entitlement active |
| Restore completed | Restore returned an active entitlement |
| Trial started | Entitlement entered an introductory period |
| Paid conversion | Trial converted to paid or direct purchase became paid |
| Entitlement lost | Expired, revoked, billing issue, or customer reset |

Do not use a single conversion event for all of these.

### P1.2 Focused paywalls bypass the RevenueCat layout experiment

`PaywallView.swift:260-265` forces focused feature paywalls to `.catalog`. The main Upgrade tab reads `currentOffering.metadata["upgrade_tab"]` through `PaywallUIVariant`, so the RevenueCat experiment controls the main Upgrade tab layout only. History and other feature-specific upsells are not part of the A/B test.

This is acceptable only if intentional and documented. The dashboard experiment name suggests the Upgrade tab, so it should not be interpreted as a whole-app paywall experiment. Add placement to every result and impression record, and make the scope explicit in the experiment handoff.

### P1.3 Offering selection can become stale

`StoreService` reads `offerings.current` and falls back to the offering named `default`. `PaywallView` selects packages from the loaded offering. If RevenueCat replaces an offering or changes packages while the view is alive, the selected package and displayed copy can become stale.

Add identity checks and request cancellation. A view should not purchase a package that is no longer part of the offering it rendered. Refresh offerings on foreground with a bounded throttle, not on every render, and surface a retry state when the selected package disappears.

### P1.4 Intro eligibility in DEBUG is not production eligibility

`Shared/Services/StoreService.swift:303-340` marks simulator products eligible for introductory offers when the test key is present. This is useful for deterministic UI previews, but it can hide the real eligibility path and produce false confidence about trial copy and pricing.

Keep the shortcut isolated behind an obvious test-only flag. Add at least one test against real StoreKit eligibility and one test for the ineligible state. Never use a production RevenueCat key in a simulator run.

### P1.5 UI tests force A/B branches rather than exercising RevenueCat assignment

`VitalsUITests/DebugLaunchConfig.swift:3-29` and the seeded UI tests set `VITALS_UPGRADE_TAB`. This proves that both local branches can render, but it does not prove that RevenueCat assigns a customer, keeps assignment sticky, returns the intended offering metadata, or reports the correct treatment.

Maintain deterministic branch tests, then add a separate integration layer with a non-production RevenueCat project or StoreKit fixture. The latter must verify the offering metadata to UI variant mapping. Do not make UI tests depend on a live production experiment.

## RevenueCat paywall A/B test: what it means and what is missing

### Observed configuration

The read-only RevenueCat inspection found project `projd0d314f5` with:

| Offering | Metadata | Products |
| --- | --- | --- |
| `default` | `{"upgrade_tab":"timeline"}` | `$rc_monthly`, `$rc_annual`, `$rc_lifetime` |
| `upgrade_catalog` | `{"upgrade_tab":"catalog"}` | `$rc_monthly`, `$rc_annual`, `$rc_lifetime` |

The app's product identifiers behind those packages are the same monthly, yearly, and lifetime products. The observed experiment was:

| Field | Observed value |
| --- | --- |
| Experiment | Upgrade tab: timeline vs catalog |
| Status | Running |
| Enrollment | 100% of eligible new customers observed in the dashboard configuration |
| Control | Catalog offering in the observed configuration |
| Treatment | Timeline offering in the observed configuration |
| Snapshot result | Control customers 1.0, treatment customers 0.0 |
| Snapshot conversions, trials, revenue | 0 |

The result snapshot is insufficient data, not a winning or losing result. It does not establish that catalog is better, that timeline has no users, or that the experiment is balanced. Confirm the live allocation percentage and audience rules in the RevenueCat dashboard before making any product decision.

### Correct interpretation

Enrollment and allocation are different:

- Enrollment at 100% means all customers who satisfy the experiment audience can enter the experiment.
- The allocation split determines how those enrolled customers are distributed between control and treatment. It is normally a separate setting.
- Assignment is customer-scoped and should be sticky. A customer should not switch layout on every launch.
- A customer can be enrolled but not yet have a meaningful purchase outcome.
- A one-customer snapshot cannot answer a conversion question.
- Because the products and introductory offers are the same, this experiment primarily tests information architecture, ordering, visual hierarchy, and pitch framing. It does not test price, trial length, or product availability.

### App behavior today

The current flow is approximately:

1. `StoreService` configures RevenueCat.
2. `offerings.current` is read, with a fallback to offering identifier `default`.
3. The app reads `upgrade_tab` metadata.
4. A DEBUG launch override can replace the metadata result.
5. The main Upgrade tab renders the timeline or catalog layout.
6. Focused feature paywalls force catalog and bypass the experiment.
7. Purchase handling maps the result to app state, but currently mishandles pending in `TrialOfferPitch`.

This means the experiment can be useful, but only for the main Upgrade tab and only after the purchase state machine and measurement contract are corrected.

### Measurement contract needed before trusting results

Every impression and purchase-related event should carry:

- Customer or anonymous experiment subject identifier, without sending HealthKit data.
- Experiment identifier and revision if available.
- Offering identifier and offering metadata.
- Resolved UI variant.
- Placement, such as Upgrade tab, History Custom range, dashboard, onboarding, or settings.
- Package identifier and product identifier.
- Price, currency, and trial or introductory eligibility as displayed.
- Purchase state, including initiated, pending, completed, failed, restored, and entitlement active.
- App version and build.
- Timestamp and a session or impression identifier for deduplication.

Do not use HealthKit values, daily calorie totals, or step totals as RevenueCat conversion attributes. The privacy policy should remain clear that health data is not sent to RevenueCat.

### Experiment quality gates

Before deciding a winner:

1. Verify the actual control/treatment allocation and audience in the RevenueCat dashboard.
2. Verify that fresh test customers receive sticky assignments.
3. Verify that each variant renders the same products, price, trial, Restore, Terms, Privacy, and Apple disclosure.
4. Verify impression and package-selection counts are not duplicated by SwiftUI view recreation.
5. Separate direct paid purchases, trial starts, trial-to-paid conversions, refunds, and restores.
6. Exclude internal testers, debug customers, StoreKit local-test customers, and failed or pending transactions from conversion denominators.
7. Wait for enough exposed customers and mature trial cohorts. A one-week trial requires at least the full trial duration plus a reasonable observation window before trial conversion is compared.
8. Define a minimum sample, primary metric, guardrail metrics, and stop rule before looking at the result.
9. Monitor refund rate, cancellation rate, revenue per eligible customer, and support complaints, not only initial purchase rate.
10. Keep a rollback offering ready and document which offering is the safe default.

Useful official RevenueCat references:

- [Offerings overview](https://www.revenuecat.com/docs/offerings/overview)
- [Experiments overview](https://www.revenuecat.com/docs/tools/experiments-v1/experiments-overview-v1)
- [Configuring experiments](https://www.revenuecat.com/docs/tools/experiments-v1/configuring-experiments-v1)
- [Creating offerings to test](https://www.revenuecat.com/docs/tools/experiments-v1/creating-offerings-to-test)
- [Experiment results](https://www.revenuecat.com/docs/tools/experiments-v1/experiments-results-v1)

## P1 data, HealthKit, and resilience findings

### P1.6 Cache open failure destructively deletes local history

`Shared/Services/DataService.swift:12-47` catches a persistent-store failure, removes the SQLite store, WAL, and SHM files, and falls back to an in-memory container. The final fallback uses `try!`.

This does not delete HealthKit's source data, but it can delete the local cache that powers history and widgets. The user receives no clear recovery state, backup, export, or diagnostic explanation. A transient migration, file-lock, disk, or corruption issue can become irreversible cache loss.

Recommended design:

- Preserve the failed store files before attempting recovery, using a versioned quarantine name and bounded storage policy.
- Record a visible recovery state and offer a HealthKit resync.
- Rebuild from HealthKit only after preserving the original evidence.
- Avoid `try!` in the recovery path.
- Add tests for corrupt store, migration failure, permission failure, disk-full behavior, WAL-only corruption, and successful rebuild.
- Verify that widgets receive a consistent empty/loading state during recovery.

### P1.7 All-zero HealthKit results can preserve stale nonzero values

`Shared/Services/HealthKitService.swift:831-852` skips replacing an existing nonzero value when a refresh returns zero. This may protect against a transient query result, but it also prevents a true zero, authorization change, source change, or corrected HealthKit day from being represented.

Replace the implicit zero rule with explicit freshness and knowledge state:

- Unknown or query failed: retain prior value and mark stale.
- Query succeeded with known zero: write zero and mark fresh.
- Query succeeded with data: write value and mark fresh.
- Authorization denied or restricted: show authorization state, not stale health data as current.

Add tests for a known zero day, a failed query, a denied query, a late-arriving sample, and a day crossing local midnight.

### P1.8 Steps-only cached entries need a clear merge contract

The history merge logic around `HealthKitService.swift:489-508` gives cached priority based on energy values. A cached entry with steps but no energy can be discarded or merged incorrectly.

Define field-level merge behavior rather than entry-level priority. Test combinations of:

- Cached steps only and fresh energy only.
- Cached energy only and fresh steps only.
- Fresh zero plus cached nonzero.
- Duplicate day keys with different timestamps.
- Partial data from phone and watch.

### P1.9 Date and calendar boundaries need explicit tests

The app uses a private Gregorian calendar for `DailyHealthRecord` key generation while other views and services use `Calendar.current`. Historical audits did not prove a current corruption bug, but timezone transitions, user timezone changes, DST, and local midnight boundaries remain a release risk.

Test fixed dates around:

- 23:59 to 00:01 local time.
- DST spring forward and fall back.
- Travel across timezones.
- Device timezone change while the app is suspended.
- HealthKit samples whose source timezone differs from device timezone.

The persisted day key and every query predicate must agree on the intended user-local day.

### P1.10 HealthKit authorization presentation is intentionally conservative but ambiguous

HealthKit read authorization status is not fully observable for this app's read-only use, and the code treats `.unnecessary` as effectively authorized in places. That avoids an impossible permission claim, but it can show a user a blank or stale dashboard without telling them whether data is unavailable, denied, or still loading.

Define visible states for requesting, authorized with data, authorized with no data, denied or restricted, unavailable, and query failed. Add a Settings link where the system permits it. Do not claim that the app knows read permission when HealthKit does not expose that information.

### P1.11 Query cancellation and startup races

`HealthKitService.swift:1199-1237` uses continuations without clearly stopping the underlying query on task cancellation. `StoreService` also starts unstructured work for configuration, customer status, offerings, and eligibility. These can race with view disappearance, account changes, or a second offering request.

Add cancellation handlers, stop queries when tasks are cancelled, and give each load request an identity. A stale offering or HealthKit result must not overwrite newer state. Test rapid tab changes, backgrounding, foregrounding, repeated paywall presentation, and customer status changes.

### P1.12 Swift concurrency escape hatches need focused tests

`@preconcurrency` RevenueCat imports and `nonisolated(unsafe)` global singleton state reduce compiler protection. This is not by itself a runtime defect, but it increases the chance of races around StoreService, PhoneGoalSyncService, WatchGoalSyncService, and ConversionDiagnostics.

Add actor-isolation tests and ensure all state mutations are serialized. Avoid global mutable state where an actor or injected service can express ownership.

### P1.13 Watch cache finding correction

One independent reviewer flagged `VitalsWatch/Views/TodayView.swift:344-376`, where the watch calls `HealthKitService.refreshCache`, as if it could overwrite the iPhone's SQLite cache. That conclusion is not valid for separate physical devices. The iPhone and Apple Watch have separate local containers even when their targets use the same App Group identifier. The call writes the watch device's local cache.

Do not implement a cross-device cache rewrite based on this claim. Still test the actual watch behavior:

- Watch cache refresh after a successful HealthKit query.
- Watch cache behavior while offline from the phone.
- WatchConnectivity goal synchronization.
- Repeated watch refreshes and midnight boundaries.
- Widget or complication reads from the watch's local container.

## P1 UI, accessibility, and layout findings

These are source-backed risks from the UI review. They need runtime evidence across the matrix below.

### P1.14 Onboarding trial page can clip at large Dynamic Type

`Vitals/Views/DashboardView.swift:2367-2421`, `:2689-2703`, and `:2710-2765` use a trial step with fixed footer behavior, spacers, and content that is not clearly scrollable. At accessibility sizes, the headline, trial timeline, legal text, and CTA can exceed the available height.

Use a scrollable content region and a pinned, safe-area-aware footer. Test the smallest supported iPhone and every accessibility size. The CTA must remain reachable without requiring a user to discover an invisible scroll region.

### P1.15 Paywall legal and error areas are not robust to long text

`Vitals/Views/PaywallView.swift:378-488` contains fixed or tightly constrained disclosure, error, Restore, Terms, and Privacy areas. `:417-447` and `:472-488` are particularly sensitive to RevenueCat price text and localization. The onboarding paywall footer around `DashboardView.swift:2689-2703` has the same risk.

Allow text to wrap vertically, stack legal actions when needed, and keep the purchase CTA visible. Test long product names, missing prices, currency symbols, right-to-left text, large text, and a failed purchase message longer than one line.

### P1.16 Toggle label is not reliably exposed

`DashboardView.swift:2877-2897` uses `Toggle("", isOn:)` with labels hidden while a visible sibling supplies the title. VoiceOver may announce an unlabeled or ambiguous control. Give the Toggle an explicit accessible label, value, and hint, or place the visible label inside the Toggle's label.

### P1.17 Summary PDF is a fixed one-page layout

`Vitals/Views/SummaryReportView.swift:6-46`, `:76-283`, and `:432-455` render a fixed 612 by 792 page while the content includes charts, highlights, macros, goals, and variable text. There is no clear pagination or measured overflow handling.

Render and inspect combinations for no data, one day, seven days, custom range, long date range, large values, missing sections, and long localized strings. Confirm that no chart, footer, disclaimer, title, or goal summary is clipped. If one page cannot fit, implement pagination or a deliberate section omission policy with tests.

### P1.18 History range selector can overflow

`HistoryView.swift:520-543` and `:1423-1446` force five period options into a horizontal layout. Captions, lock indicators, Dynamic Type, localization, and right-to-left ordering can compress or clip the controls.

Use a horizontally scrollable control, a menu, or `ViewThatFits` with a tested fallback. Every option must remain discoverable and accessible. A locked Custom option must announce both the range and its locked state.

### P1.19 Icon-only controls need explicit accessibility labels

Review identified:

- Paywall close control at `PaywallView.swift:570-586`.
- History export control at `HistoryView.swift:505-515`.
- Settings info controls around `DashboardView.swift:2077-2115` and `:3148-3169`.

Give each control an explicit label, hint where useful, stable identifier, and a sufficiently large hit target. Do not depend on the icon name or adjacent text.

### P1.20 Tap gestures are not equivalent to accessible buttons

The calorie breakdown in `DashboardView.swift:532-543` and the watch equivalent in `VitalsWatch/Views/TodayView.swift:94-116` use tap gestures. A gesture may not expose the button trait, action name, focus order, or hint. Use a Button or add equivalent accessibility actions and traits.

### P1.21 History charts need a nonvisual data representation

`HistoryView.swift:1075-1315` presents charts without a clearly verified accessible table or summary. VoiceOver users should be able to obtain the date, calorie, step, and goal values represented by the chart, not just hear a decorative chart label.

Provide a concise summary plus an expandable data table or per-point accessibility elements. Test with VoiceOver and large text.

### P1.22 Review prompt can hide content behind the keyboard

`Vitals/Views/ReviewPromptSheet.swift:150-180` uses a fixed vertical layout with an autofocus TextEditor. The keyboard can cover the submit button or the text field. The editor also needs an explicit label and prompt.

Use keyboard-aware scrolling, a safe-area inset, or a focused field layout. Verify submit, cancel, dismissal, and rotation with the keyboard visible.

### P1.23 Custom tab semantics and state retention

`App.swift:830-859` and `:2245-2262` implement custom tab behavior. Verify that the selected tab exposes selected state to VoiceOver, that tab labels remain stable under localization, and that switching tabs does not duplicate paywall loads or lose unsaved state.

Test deep links, repeated selection, sheet dismissal, background/foreground, and a paywall presented from each tab.

### P1.24 Watch fixed sizes and complications

`VitalsWatch/Views/TodayView.swift:84-241`, `:510-525`, and `VitalsWatchWidget/WatchComplication.swift:238-345` use many fixed font sizes and constrained layouts. Test all supported watch families, corners, extra-large sizes, accessibility text sizes, dark mode, long values, no data, and stale data.

### P1.25 Widget calorie abbreviation and accessibility value

`VitalsWidget/VitalsWidget.swift:374-399` divides calories by 1000 for the circular display. Confirm that the visible unit and accessibility value are unambiguous for values such as 999, 1000, 1240, and 9999. A display such as `1.2K` needs an accessible spoken value such as `1,240 calories`.

### P1.26 Loading, error, and retry states

Verify visible state and announcements for:

- HealthKit authorization pending, denied, unavailable, query failure, and zero data.
- RevenueCat loading, no offerings, package missing, purchase pending, purchase failure, restore states, and customer status refresh.
- History loading, empty, stale, error, and retry. `HistoryView.swift:583-609` currently lacks an obvious retry or Health Settings action in the error presentation.
- Widget timeline unavailable or entitlement stale.

Loading states should not be silent under VoiceOver. Errors should explain what the user can do next.

## P2 and P3 polish findings

### P2.1 Localization is effectively absent

No `.lproj`, `.strings`, `.stringsdict`, or `.xcstrings` resources were found. Approximately 300 user-visible string call sites are hardcoded in Swift sources. English-only text is a product decision, but it creates immediate risk for long strings, dates, numbers, pluralization, currency, and right-to-left layout.

At minimum, use localized string resources for all paywall, legal, purchase-state, error, accessibility, and date text. Add pseudo-localization with 30 to 100 percent expansion before claiming layout readiness. If localization is intentionally deferred, explicitly test the English accessibility matrix and do not claim international readiness.

### P2.2 Dates and numbers are hardcoded in places

History cards around `HistoryView.swift:2635-2656` and `:2834-2856`, and WeeklyRecap dates around `:13-17`, need locale-aware formatting and width tests. Avoid fixed date strings and manual decimal formatting in user-visible views.

### P2.3 Dark and light contrast

Verify theme colors, paywall error banners, locked states, chart labels, disabled buttons, and widget text in both appearances. Test increased contrast and reduced transparency where supported.

### P2.4 Nested sheets and interactive dismissal

Test paywall, settings, review prompt, export, and body profile sheets in every presenting context. Verify interactive dismissal, back navigation, state restoration, and edge-swipe behavior. `InteractivePopGestureEnabler.swift` needs an explicit regression test.

### P2.5 Data export and privacy wording

Confirm that every export path is user initiated, contains only the intended date range, does not include hidden identifiers, and presents an accurate sharing warning. The export control should report completion and failure clearly.

### P2.6 Stale marketing site and metadata

`docs/index.html` reports version 1.7.8 and contains claims about no SDKs and no network activity that do not match the current RevenueCat integration. `docs/support.html` and `docs/app-store-metadata.md` contain stale pricing or product identity. Active Fastlane metadata also needs reconciliation with the privacy policy.

### P2.7 App Store screenshots

The screenshot artifact audit passed dimensions, opacity, uniqueness, and overall format. It produced one OCR warning for `08-go-further.png`, where thumbnail OCR did not find the word “further” in the expected header. Recheck that image at full resolution and confirm that the intended header is legible. Do not submit based only on a thumbnail OCR warning.

## Functional strengths to preserve

The audit also found meaningful strengths. Do not regress them while addressing the blockers:

- All 101 unit tests passed.
- The app has separate iOS, iOS widget, watchOS, and watch complication targets with embedding configured in the generated project.
- HealthKit usage descriptions and required device capabilities are present for the app and watch targets.
- Privacy manifests exist in the main app and watch app, and the current archive inspection found the RevenueCat SDK privacy manifest included in the SDK bundle.
- The paywall includes Restore, Terms, Privacy, price, auto-renewal, and cancellation-related copy. Recheck wrapping and localization rather than removing it.
- `TrialTimeline` combines related content into an accessible element and exposes details through a vertical expansion pattern.
- HealthKit is the source of truth and app health data is intended to remain local. Keep this privacy boundary intact while accurately describing RevenueCat purchase-service traffic.
- The old dietary authorization gate issue identified in a historical audit appears fixed in current `DashboardView.loadDietaryEnergy`, which treats a successful zero result as a valid result.
- The old actor-isolation issue around `HealthKitService.queryStatisticsCollection` is not present in the current source.
- Screenshot assets are unique, opaque, and at expected iPhone and Apple Watch dimensions.
- Active App Store metadata lengths were within platform limits at audit time.

## Release tooling and artifact audit

### TestFlight script safety

`scripts/testflight.sh:14-47` currently:

- Bumps the build number.
- Runs `xcodegen`.
- Commits and pushes before archive completion.
- Masks commit and push failures with `|| true`.
- Removes the archive path before archiving.
- Uploads immediately after the archive step.

This sequence makes it possible to push a build-number commit before a failed archive or failed validation is known. It also makes the release script mutate the repository during what should be a gated release operation.

Before the next release:

- Require tests, archive, export, inspection, and upload validation before pushing release metadata.
- Fail fast on commit and push errors.
- Validate that the archive contains the intended version and build.
- Use an explicit archive and IPA path for upload.
- Do not select an arbitrary first IPA from a build directory.
- Keep a recoverable archive until App Store Connect accepts the upload.

### Stale IPA selection risk

`build/export/Total Calories.ipa` exists as an old artifact. Inspection identified version 1.1.0 build 8 inside that IPA. `scripts/upload-testflight-api.sh:14-16` uses `find "$ROOT/build" -name '*.ipa' -print -quit` when no IPA is provided, so it can select an old IPA instead of the freshly exported one.

This is a release blocker until the upload path requires an explicit artifact or validates version/build and rejects stale artifacts.

### Archive inspection checklist

For every release archive, inspect:

- `CFBundleShortVersionString` and `CFBundleVersion` for all four runtime targets.
- Main app, widget, watch app, and watch complication bundle identifiers.
- HealthKit entitlements and usage descriptions.
- App Group entitlement consistency.
- Privacy manifests in every applicable target and embedded SDK.
- RevenueCat SDK version and configuration environment.
- Absence of production RevenueCat keys in simulator or debug artifacts.
- StoreKit configuration not accidentally shipped as a production dependency.
- No stale debug flags, seeded data, test product identifiers, or UI-test environment variables.
- Exported IPA path and checksum recorded with the build number.

### Privacy manifest scope

Source privacy manifests were found for `Vitals` and `VitalsWatch`, but not as separate source files in the widget target directories. The current archive included the SDK manifest and the app/watch manifests. Verify the final archive against Apple's current privacy-manifest requirements for app extensions and embedded SDKs. Do not assume the main app manifest covers every extension target.

## Cursor and historical audit context

No raw Cursor conversation transcript was found in the repository search. The available local materials are evidence of prior work, not a complete chat log:

- `_handoffs/revenuecat-paywall-handoff.md`: a handoff about a RevenueCat-hosted paywall v3 and the prior native paywall. It describes old v2 problems such as hardcoded prices, missing Apple disclosure, missing lifetime product, placeholder dots, and no A/B test. It also says A/B variants were out of scope at that time. Current source and RevenueCat configuration now contain a native Upgrade-tab A/B test, so the old handoff is historical and must not override current source truth.
- `ios27Vitals.md`: a historical simulator launch audit. Its RevenueCat simulator launch blocker is not current because `StoreService.configureIfNeeded` now permits a test-key simulator configuration in DEBUG and the current UI tests launch.
- `archive/claudefinds.md` and `archive/gptfinds.md`: prior findings and resolutions. They are useful for regression context but contain stale or explicitly rejected hypotheses.

### Sensitive material in the local handoff

The RevenueCat handoff contains a literal old production-style `appl_` key. This audit intentionally does not reproduce it. Treat it as sensitive and potentially compromised if the file exists in shared repository history or any public location. Rotate the key in RevenueCat if its exposure has not already been handled, remove the literal from documentation, and search history and backups for copies. Store secrets only through the approved credential mechanism.

### Historical findings that must not be reimplemented blindly

- The old dietary read gate was a real issue and appears fixed. Re-test it, but do not restore the old gate.
- The old HealthKit actor-isolation complaint was fixed in current source.
- The old iOS 27 simulator SIGTRAP report is not current evidence.
- The claim that a watch writes the iPhone's local SQLite cache is a false cross-device premise. Test watch behavior, but do not change the storage architecture based on that claim.
- Prior timezone, stale-widget, and cache race claims were not all proven. Keep boundary tests, but distinguish a test gap from a confirmed bug.

## Required implementation sequence for the next agent

### Phase 0: establish the release candidate

1. Preserve unrelated worktree state.
2. Confirm the intended version and build number.
3. Resolve App Store Connect version/build association.
4. Fix the release script's stale-IPA and pre-validation push behavior.
5. Reconcile RevenueCat product IDs, StoreKit fixture, app metadata, privacy policy, support page, and review notes.
6. Rotate and redact the exposed handoff key if not already done.

### Phase 1: close functional blockers

1. Fix Settings hit testing.
2. Fix the blank History upgrade pitch.
3. Implement an explicit purchase state machine, especially pending, restore, cancellation, failure, and delayed entitlement.
4. Record conversions only after the intended entitlement condition is true.
5. Gate net-calorie content in every widget and complication.
6. Replace the broad entitlement check with an exact entitlement contract.
7. Make DataService recovery non-destructive and test corruption/migration recovery.
8. Add HealthKit zero, stale, steps-only, date-boundary, and cancellation tests.

### Phase 2: make the A/B test interpretable

1. Document experiment audience, allocation, control, treatment, placement, and rollback offering.
2. Keep focused feature paywalls explicitly out of scope or include them intentionally in a separate experiment.
3. Add impression, assignment, package, purchase-state, entitlement, trial, conversion, and refund measurement.
4. Test sticky assignment with clean non-production customers.
5. Verify both variants use identical products and legal disclosures.
6. Define sample-size, cohort-maturity, guardrail, and stop criteria before reading the result.

### Phase 3: polish the actual user experience

1. Remove fixed-height clipping risks from onboarding and paywalls.
2. Make Summary PDF layout measured and paginated or deliberately constrained.
3. Make History range controls adaptive.
4. Add labels, traits, hints, values, and hit targets to all controls.
5. Provide chart data to VoiceOver.
6. Make review input keyboard safe.
7. Test watch, widgets, themes, and loading/error states.
8. Add localization resources or explicitly document the supported English-only boundary and run pseudo-long-string tests.

### Phase 4: evidence and ship gate

1. Regenerate the Xcode project after any Swift file or `project.yml` change.
2. Run unit tests and all UI tests on a clean leased simulator.
3. Run the StoreKit fixture tests with the scheme actually attached.
4. Run a physical-device or TestFlight purchase and restore pass using a sandbox account.
5. Run accessibility, Dynamic Type, dark mode, RTL or pseudo-localization, watch, widget, PDF, and keyboard checks.
6. Archive Release and inspect every target.
7. Export and upload the exact inspected IPA.
8. Verify App Store Connect build association, processing, and TestFlight install.
9. Run the installed build through onboarding, dashboard, history, settings, upgrade, restore, widgets, watch, export, and review flows.
10. Only then push the release commit and submit or continue the review workflow.

## Full verification matrix

| Area | Required states | Evidence to capture |
| --- | --- | --- |
| Launch | First launch, returning user, no HealthKit, denied HealthKit, no network, RevenueCat unavailable | Screenshots, logs, no crash, actionable state |
| Onboarding | Calories, steps, goal errors, keyboard, large text, trial offer, pending | UI test plus manual accessibility pass |
| Dashboard | Zero, partial, stale, large values, dark mode, tap breakdown, review trigger | Screen recording or screenshots at smallest phone and large text |
| History | Empty, one day, range selector, locked Custom, unlocked Custom, query error, retry, chart VoiceOver | UI test for every branch and rendered layout inspection |
| Paywall | Timeline, catalog, focused feature, loading, no offering, package missing, purchase, pending, cancel, fail, restore, revoke | State-machine test and sandbox run |
| A/B | Clean customer control, clean customer treatment, sticky assignment, app restart, foreground refresh | Offering id, metadata, variant, placement logs |
| Entitlement | Exact Pro, unrelated entitlement, expired, revoked, billing retry, grace, pending | App, widget, watch, and complication outputs |
| Widgets | Small, medium, large, accessory, circular, rectangular, inline, no data, free, Pro | Rendered snapshots and spoken accessibility values |
| Watch | Small and large layouts, no phone, offline, stale cache, goals sync, complication families | Watch screenshots and connectivity logs |
| PDF | No data, normal range, long range, large values, all sections, missing sections, long strings | Rendered PDF pages with no clipping |
| Accessibility | VoiceOver, Dynamic Type default through largest, bold text, increased contrast, reduce motion | Manual checklist and stable identifiers |
| Localization | Pseudo-long English, currency expansion, dates, RTL if supported | Screenshot set and no truncation |
| Recovery | Corrupt store, migration failure, query failure, RevenueCat failure, retry, reinstall | Preserved cache, visible status, successful rebuild |
| Release | Archive, export, upload, processing, exact build association, TestFlight install | Archive inspection and ASC record |

## Final release gate checklist

The next agent should not mark the build ready until every applicable item is checked with evidence:

- [ ] App Store Connect submitted version points to the intended build.
- [ ] No stale IPA can be selected by the upload script.
- [ ] Release script does not push a commit before validation.
- [ ] Unit suite is green.
- [ ] UI suite is green, including Settings and History pitch tests.
- [ ] StoreKit configuration is attached to the intended schemes, or the deliberate alternative test setup is documented.
- [ ] Real sandbox purchase, pending, cancellation, restore, renewal, and entitlement revocation behavior is verified.
- [ ] Pending never dismisses as success.
- [ ] Conversion diagnostics distinguish purchase state and do not count pending as conversion.
- [ ] Exact entitlement identifier is enforced.
- [ ] All widgets and complications independently enforce premium visibility.
- [ ] DataService recovery preserves evidence and does not silently destroy the cache.
- [ ] HealthKit zero, stale, steps-only, timezone, and cancellation tests pass.
- [ ] Onboarding and paywall content fit at the largest supported Dynamic Type size.
- [ ] History controls and Summary PDF have no clipping or overflow.
- [ ] Every interactive icon has an accessible label, trait, hint where needed, and hit target.
- [ ] Charts have a nonvisual data representation.
- [ ] Review prompt is keyboard safe.
- [ ] Watch and widget families are checked in light and dark mode.
- [ ] Privacy policy, App Store description, support page, review notes, screenshot claims, and privacy labels agree with actual RevenueCat and network behavior.
- [ ] Sensitive keys are rotated or removed from handoffs and history as appropriate.
- [ ] Archive contains the expected targets, versions, entitlements, manifests, and SDK configuration.
- [ ] TestFlight install from the exact uploaded build passes the end-to-end smoke test.
- [ ] Simulator lease is checked in after testing.

This document is an audit and handoff, not a release approval. The current evidence supports a focused implementation pass followed by independent re-review and a fresh release-candidate test run.
