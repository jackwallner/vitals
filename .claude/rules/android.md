---
paths:
  - "android/**"
  - "scripts/play-*"
  - "scripts/android-pro.sh"
  - "scripts/make_android_icon.py"
  - "docs/android-*.html"
---

# Total Calories Android rules

## Product

- Native port in `android/`: Kotlin, Compose, Gradle Kotlin DSL, JDK 17, minSdk 26, target/compile 36.
  Package `com.jackwallner.vitals` (permanent), launcher label "Total Calories", Play title
  "Total Calories: Daily Tracker", version 1.8.9 (versionCode 1).
- Data source is Health Connect (`androidx.health.connect:connect-client:1.1.0`) through
  `aggregateGroupByPeriod`, never `readRecords`. Why this is viable and how resting energy is derived:
  `project-docs/android/health-connect-feasibility.md`. Rules live in `model/Energy.kt`
  (`EnergyResolver`): resting is marked estimated ("est.") when only active energy exists and is kept
  out of TDEE and BMR.
- History older than 30 days and background reads are separate Health Connect permissions that "Allow
  all" does not grant. The app degrades to a 30-day window and Settings offers the grant.
- Same paid boundary and product IDs as iOS. Free: onboarding, Today, History, Settings, widget, review
  prompt. Vitals+: Active/Resting, TDEE and BMR, projection, streaks, Net Deficit (+ Fasting Mode),
  Excluded Days (+ pause), Deep Trends, PDF reports (30 day and custom), Custom period.
- Left out of v1 on purpose: Macros, Body Profile, Weekly Recap, milestones, What's New, Coach promo,
  Wear OS, per-metric detail screens (folded into History), the iOS trial-pitch sheet (a full-screen
  paywall with a focus feature replaces it). iOS stays the spec; port changes when iOS changes.
- State mirrors iOS UserDefaults keys in `SharedPreferences` (`KeyValueStore`), so a key means the same
  thing on both platforms. The Glance widget reads a snapshot the repository writes at each refresh.
- Play In-App Review: called directly at the positive moment, no enjoyment question, never from a
  button. Thresholds ported from iOS (launch 2, tracked days 7, subscriber 30 days, cooldown 30 days).
- Light, dark and system appearance (iOS offers all three). Nunito stands in for SF Rounded.
- No `POST_NOTIFICATIONS` and no notifications: iOS only notifies for the Weekly Recap, which is not in v1.

## Billing

- RevenueCat project `projd0d314f5` (shared with iOS by decision, not a separate project). Play app
  `app459152e4e6` (package `com.jackwallner.vitals`, created 2026-10-15, **service-account credentials
  not configured yet**), Test Store app `app6302e748f4`. Entitlement `Total Calories - Daily Tracker
  Vitals+` (`entl05bb1ab663`) now also holds the three Play products. Offering `android`
  (`ofrng8ab09d37a4`, not current) with `$rc_annual`, `$rc_monthly`, `$rc_lifetime`. The app picks
  `offerings.all["android"] ?: current` and treats any active entitlement as Pro.
- Shared project risk: Android customers appear in iOS charts and in the offering experiments' customer
  counts. Keep `android` out of every experiment and never make it current.
- Play products (created and active 2026-10-17, `scripts/play-products.py`, idempotent): subscriptions
  `com.jackwallner.vitals.monthly` (base plan `monthly`) and `com.jackwallner.vitals.yearly` (base plan
  `yearly`), each with a 7-day free-trial offer `trial-7d`, and one-time `com.jackwallner.vitals.plus.lifetime`.
  Android US ladder about 20% under iOS ($6.99 / $29.99 / $59.99): $5.49 / $23.99 / $47.99, local prices
  from Play's conversion then the fleet PPP curve. Never put prices in listing copy.
- Debug uses the Test Store key (`REVENUECAT_TEST_KEY`), release uses `REVENUECAT_PLAY_KEY` (`goog_`),
  both in ignored `android/local.properties` with the upload keystore settings and
  `PLAY_REVIEW_CODE_SHA256`. The upload keystore is `~/.android/keystores/vitals-upload.p12` (alias
  `upload`, backup in `backups/`); passwords and the review code are in `~/.vitals_credentials`.
  `validateReleaseConfiguration` fails a release build when any of them is missing.
- Play reviewers unlock Vitals+ by long-pressing Settings > About > Version and entering the review
  code (hash-checked in release; never type the raw code in the Console, Jack pastes it).

## Release

- `PLAY_SERVICE_ACCOUNT_JSON=~/.config/google-play/mahj-service-account.json ./scripts/play-upload.sh
  internal-draft` tests, signs, verifies and uploads. Bump `versionCode` in `android/app/build.gradle.kts`
  before every upload. versionCode 1 is already uploaded (2026-10-17); the next upload needs 2.
- Listing text: `android/play-assets/metadata/android/en-US/` (title 29, short 68, full under 4000, no
  prices). Graphics: `android/play-assets/` (icon-512, feature-graphic-1024x500, screenshots/light and
  screenshots/dark from the real emulator build). Policy pages: `docs/android-privacy.html` and
  `docs/android-terms.html` (the Sober lesson: check they render in a browser, not just curl 200).
- Last verified state 2026-10-15: signed AAB builds (`android/app/build/outputs/bundle/release/app-release.aab`),
  package `com.jackwallner.vitals`, versionCode 1, targetSdk 36, 16 KB aligned. Not uploaded.

## Play state (2026-10-17)

Staged, not sent for review. Play app id `4973808117865134124` (E3 Apps). versionCode 1 uploaded;
listing, graphics and screenshots committed by API (`~/docs/android/tools/play_stage.py`); draft
releases on internal and production, production targets all 178 countries; products active; every
App content answer below is entered. Publishing overview shows "Submit 11 changes for review".

Left for Jack: paste `VITALS_PLAY_REVIEW_CODE` from `~/.vitals_credentials` into App access >
Password, then Send for review when this app's pacing slot comes. Review codes: `~/docs/android/tools/play_handoff.py review-codes`. RevenueCat Play credentials
were uploaded with `play_handoff.py rc-credentials --apply` on  2026-10-17. The
RevenueCat service account already has account-wide Play permissions, so no per-app grant is needed.

## Play Console answers (entered 2026-10-16/17)

- App content > Health apps declaration: the app has health and fitness features. Functionality:
  activity and fitness tracking, nutrition and weight management (Net Deficit reads logged food
  energy). Not a medical device, no clinical use, no diagnosis, no treatment claims.
- Health Connect permissions declaration, one reason per permission, all read only:
  `READ_ACTIVE_CALORIES_BURNED` and `READ_TOTAL_CALORIES_BURNED` (today's burn, active/resting split,
  history), `READ_BASAL_METABOLIC_RATE` (measured resting burn for BMR and TDEE), `READ_STEPS` (steps
  and history), `READ_NUTRITION` (Net Deficit, optional), `READ_HEALTH_DATA_HISTORY` (history older
  than 30 days, optional), `READ_HEALTH_DATA_IN_BACKGROUND` (widget refresh, optional). Rationale
  screen: `HealthRationaleActivity` (action `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`, alias
  `ViewPermissionUsageActivity`).
- Data safety: Health info is read on device only and never sent off the device, so it is not
  "collected". Collected and shared with RevenueCat as a service provider: Purchase history (Financial
  info), Device or other IDs (anonymous app user ID), App interactions (counts of when the upgrade
  screen was shown). Purposes: app functionality and analytics. Encrypted in transit: yes. Not sold, not
  used for ads. Users can request deletion (email, listed in the privacy policy). No data is
  required to use the app beyond that.
- Privacy policy URL: `https://jackwallner.github.io/vitals/android-privacy.html`.
- Content rating (IARC): category Utility/Productivity or Reference; no violence, sexual content,
  language, controlled substances, gambling, user-generated content or location sharing. Expected
  Everyone / PEGI 3.
- Target audience: 18 and over (not directed to children). Ads: none. App access: no login; every
  feature works without an account and Vitals+ is unlocked for review with the review code above
  (Sign in details, Jack pastes the code). News app: no. Government app: no. Financial features: no.
- Store listing: category Health & Fitness, contact email `jackwallner+tc@gmail.com`, website
  `https://jackwallner.github.io/vitals/`.

## Emulator (remote Pro only)

- Never boot an emulator on this Mac. Pro is `jackwallner@192.168.4.25` (BatchMode, strict host key),
  SDK `/Users/jackwallner/Library/Android/sdk`. `small_phone` (port 5554) is the Play AVD with an
  account: never install debug builds on it or wipe it.
- Debug work uses a temporary config-only AVD `vitals_agent_test` on port 5562 (`emulator-5562`), made
  by copying `small_phone.avd/config.ini` as in `~/ironman/.claude/rules/android.md`, API 36 image (not
  36.1, instrumentation breaks there). Stop it with `adb -s emulator-5562 emu kill` on Pro, then delete
  only `~/.android/avd/vitals_agent_test.avd` and `.ini`.
- Pro has no JDK 17: build both APKs on this Mac (`./gradlew assembleDebug assembleDebugAndroidTest`,
  Temurin 17), then `scripts/android-pro.sh install | test [class] | shot <png> | adb <args>`.
- Unit tests: `cd android && ./gradlew testDebugUnitTest` (100 tests, JVM, in-memory store).
- Debug launch extras (debug build only, `DebugLaunchOptions.kt`): `resetAll` (wipes state and rebuilds
  the graph), `seedDemo` (90 days written into Health Connect, needs the HC write grants made once
  through `DebugPermissionActivity`), `completeSetup`, `demoPro`, `previewStore`, `appearance`
  (light|dark), `tab` (today|history|upgrade), `overlay` (settings|paywall|excluded), `onboardingStep`
  (welcome|goals|trial), `enable` (activeResting,tdee,projections,streaks,net).
- Screenshots: put the status bar in demo mode first (`com.android.systemui.demo`: clock 0941, wifi
  full, mobile hidden, notifications off).
