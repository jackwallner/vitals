# 625plan.md — Total Calories ASO Metadata Update + Rollout Plan

> Written 2026-06-25. Owner: Jack Wallner. App: **Total Calories – Daily Tracker** (App Store ID `6761743504`, bundle `com.jackwallner.vitals`, this repo = `~/vitals`).
> This plan captures a long working session that designed an ASO keyword strategy, cleaned the Astro tracking data, derived exact metadata edits for the US, and decided the rollout. A fresh agent should be able to implement from this doc alone. Companion strategy doc: `~/Desktop/aso.md`.

---

## 0. TL;DR / Current decision

- We designed **conservative metadata edits** for the US listing (subtitle + keyword field) and a rule-set to stage **all ~50 localizations**.
- **DO NOT SHIP YET.** Total Calories is in a **live download spike** (new customers 8 → 17 from Jun 24 → Jun 25, day still incomplete; 28-day avg ~9/day). Changing keywords/subtitle forces Apple to re-index and causes a few days of ranking volatility — an unforced risk mid-spike, for **marginal** keyword upside.
- **Plan: HOLD. Bundle the metadata changes with the next real build — ideally the BMI/body-fat feature build (§6) — and use MANUAL release timed AFTER the spike normalizes. Never auto-release.**
- Astro tracking data has already been cleaned + tagged (§7). That part is done.

---

## STEP 0 — Re-pull current state first (data drifts; trust the tools, not this doc)

Every number, keyword field, ranking, and competitor named in this doc is a **dated snapshot (2026-06-25) and WILL be stale.** Rankings shift daily, you may have edited metadata since, and competitors move. A fresh agent must re-pull live state before acting, then apply the durable rules (positioning, guardrails, transform logic, safeguards) to *that* data — not to anything pasted here.

| What you need | How to pull it fresh |
|---|---|
| Live name/subtitle/keywords, **all locales** | `scripts/pull-appstore-metadata.sh` → writes live values into `fastlane/metadata/<locale>/{name,subtitle,keywords}.txt`; then read those files. (Authoritative source for the edits.) |
| Same, via API | `scripts/asc_lib.py` helpers: name/subtitle = `appInfoLocalizations`, keywords = `appStoreVersionLocalizations`. |
| The locale list (~50) | `scripts/asc-supported-locales.json` |
| Current rankings / popularity / difficulty / tags / notes | Astro MCP `get_app_keywords(appId="6761743504", store="us")` (repeat per store). Cached snapshots: `scripts/astro-keywords-us.json`, `scripts/astro-keywords-by-store`; refresh with `scripts/astro-sync-all-stores.py`. **The deployed/target/wall tags + notes already encode the strategy — read them.** |
| Who ranks for a term + your own position | Astro MCP `search_app_store(keyword, store, appId="6761743504")`, or `scripts/astro-competitor-scan.py`. Re-derive competitor tiers from co-ranking (`~/Desktop/aso.md` §2) — they change. |
| ASC version / write state (before any push) | Check the live version is READY_FOR_SALE and whether a draft already exists (see §5). |

**Do this first, then proceed.** The rest of this doc is the durable decision-making; the data behind each example must be refreshed.

---

## 1. What this app is (positioning — load-bearing)

Total Calories is a **calories-BURNED / energy-expenditure** app: TDEE, active + resting energy, Apple Watch complications, lock-screen / home widgets, pacing. **It is NOT a food-logging calorie counter.** This distinction drives every keyword decision:

- The high-volume head terms (`calorie counter` pop 74, `calorie tracker` 74, `fasting` 58, `weight loss tracker` 61) are **food-logging intent owned by an unbeatable wall** (MyFitnessPal 2.3M ratings, Cal AI, Cronometer, Lose It 762k, MyNetDiary). Total Calories is #1000 on all and always will be. **Do not chase them.**
- The **one winnable lane** is the **TDEE / BMR / BMI calculator cluster**, whose competitors are tiny indies (TDEE/Apperitif 469★, Dynamic TDEE Tracker 1★, Delta 1★, Zolt 57★, BMI-BMR-BodyFat 333★). Total Calories already ranks #34 `tdee bmr`, #40 `tdee tracker`, #117 `tdee`.
- Secondary strength: **Apple Watch / widget energy** combos it already wins — `widget calories` #4, `smart watch calories` #10, `apple watch calories` #18, `net calories` #31, `active calories` #37.

## 2. The spike (why we hold)

RevenueCat New Customers (Total Calories), daily: Jun 22 = 5, Jun 23 = 6, Jun 24 = 8, **Jun 25 = 17** (incomplete). 28-day avg ≈ 9. Clear upward break tied to the recent 1.7.1 release. Recency + velocity are worth more than a marginal keyword tweak, so we protect it.

---

## 3. The exact US metadata change (researched, ready)

Current (live, from `fastlane/metadata/en-US/`):
- name.txt: `Total Calories - Daily Tracker`  *(unchanged)*
- subtitle.txt: `Daily Burn on Watch & Widget`
- keywords.txt: `tdee,bmr,complication,resting,active,ring,calculator,deficit,net,kcal,energy,steps,metabolic,pacing`

**Change to:**
- subtitle.txt → `TDEE Burn on Watch & Widget`
- keywords.txt → `bmr,complication,resting,active,ring,calculator,deficit,net,energy,steps,metabolic,pacing,bmi,burned`

### Per-edit rationale
- **Subtitle: drop "Daily", lead with "TDEE".** "Daily" only re-indexed the title's "Daily" (title is `…Daily Tracker`) — wasted. The subtitle is weighted *higher than the keyword field*, so it should carry the highest-value words you can actually rank for. `TDEE` = your winnable lane's head term (promoting it here should lift the whole tdee cluster). `watch` (pop 66) + `widget` (pop 70) stay — the two highest-pop on-strategy words you already rank for. This is the strongest subtitle available; higher-pop words (`calculator` 75, `ring` 77, `calorie counter` 74) are either covered via combos, unwinnable, or the food wall.
- **Keyword field: remove `tdee`** — it moved to the subtitle; never duplicate a word across fields (wasted characters).
- **Remove `kcal` from US** — redundant with "calories" in US usage, ranks 1000. NOTE: **keep `kcal` in all metric/non-US locales** — it's the native calorie term there (kcal↔ring mirror, §4).
- **Add `bmi`** — core term of the winnable cluster (every TDEE/BMR indie pairs bmi+tdee+bmr). **Caveat:** historically `bmi` stayed at 1000 because the app has no BMI feature to index against — it is **product-gated** (see §6). We add it now anyway (it sits inside a real metabolic cluster and is cheap); if it's still 1000 after a refresh, that confirms the gate and the BMI feature becomes the unlock. Watch it.
- **Add `burned`** — genuine vocab gap: the pool has `burn` but not `burned`, and Apple does NOT reliably stem them. Unlocks `calories burned` / `burned calories` / `energy burned` — the app's literal function, all currently 1000.
- **Keep `ring`** — pop 77 but it only forms pop-5 combos (`calorie burn ring` #34, `energy ring` #67 — verified, no real volume); still beats `kcal` for the US slot because `kcal` produces nothing. (`ring` is droppable later; it's the next-weakest US word after kcal/steps.)
- **Keep `steps`** — pop 58, off-strategy (pedometer SERP, diff 81, ranks 1000), but the app surfaces step/activity data and one word doesn't meaningfully dilute. Kept by owner preference.

Result: **100/100 chars, full. 2 words swapped of 14 (~14%)** — well under the 30%-per-update rule, so any ranking move stays attributable.

### Staged-vs-now note
We sequenced US as: this round = the swap above (`tdee`→subtitle, `kcal`/`ring` retained, +`bmi`+`burned`). A later cycle can drop `kcal` and reassess `bmi`/`burned`/`ring`. Keep each update ≤30% of the field.

---

## 4. Staging ALL ~50 locales (the per-locale rule-set)

The repo's metadata source of truth is `fastlane/metadata/<locale>/{keywords.txt,subtitle.txt,name.txt}`. Locale list = `scripts/asc-supported-locales.json` (~50: ar-SA, bn-BD, ca, cs, da, de-DE, el, en-AU, en-CA, en-GB, en-US, es-ES, es-MX, fi, fr-CA, fr-FR, gu-IN, he, hi, hr, hu, id, it, ja, kn-IN, ko, ml-IN, mr-IN, ms, nl-NL, no, or-IN, pa-IN, pl, pt-BR, pt-PT, ro, ru, sk, sl-SI, sv, ta-IN, te-IN, th, tr, uk, ur-PK, vi, zh-Hans, zh-Hant).

**First pull every locale's *current* field** (Step 0) — do not assume parity. The fields are **native-language** (e.g. de-DE keywords ≈ `grundumsatz,stoffwechsel,kalorienrechner,…`) and they are NOT uniform: as of 2026-06-25, en-GB/en-AU/en-CA carried `…,pace,pacing,…,move` (not `ring,kcal` like en-US), and the de/es/fr/it/nl fields are already custom-localized with no `pedometer,ring` prefix. So re-pull, then apply these rules per locale:

1. **English-listing locales (en-GB, en-AU, en-CA):** they share the English *language* but currently have their **own** keyword fields (verify via pull — they differ from en-US). After pulling, align them to the en-US *final* field + subtitle, and SERP-check any divergent words (e.g. `pace`/`move`) against the GB/AU/CA stores — they're likely the same false friends as US, but confirm.
2. **`tdee` → subtitle, everywhere it appears.** `tdee` and `bmr` are universal acronyms present in most localized fields. Promote `tdee` into that locale's subtitle (kept grammatical in-language) and remove it from the keyword field.
3. **Add `bmi`** — universal acronym, add to every locale's keyword field (subject to the product-gate caveat; harmless to include).
4. **Add the local word for "burned"** (calories-burned sense), only if it's a genuine gap vs the local pool. Best-effort table (MUST be SERP-validated, see safeguard §8.4):
   - de `verbrannt` · fr `brûlées` · es `quemadas` · it `bruciate` · pt `queimadas` · nl `verbrand` · ru `сожжённые` · pl `spalone` · tr `yakılan` · sv `förbrända` · ja `消費` · ko `소모` · zh `消耗`.
5. **Keep `kcal`** in metric/non-US locales (native calorie term).
6. **Drop `ring`-equivalents** in non-English locales — `ring` only forms English combos; the localized "ring" word (pt `anel`, ja `リング`, etc.) yields nothing locally. (kcal↔ring mirror: US drops kcal/keeps ring; locales keep kcal/drop ring.)
7. **Subtitle localization:** lead the subtitle with `TDEE` + the local "burn/watch/widget" phrasing, kept natural and conversion-friendly (subtitle drives installs, not just indexing). Do NOT machine-translate blindly.
8. **Honor the guardrails per locale** (see `~/Desktop/aso.md`): pop>5, difficulty ≤ ~50, and a SERP-intent check that the term returns calorie/burn/metabolic apps in *that* store, not a homograph. Owner has NOT yet done per-locale competitor research — so a fully rigorous pass means repeating the US method per market. The rule-set above is the safe structural minimum.

---

## 5. ASC mechanics — how metadata actually ships (verified 2026-06-25)

- **Write access: confirmed.** Both API keys (`9T82M4AZQ2` analytics-role and the `asc_env.sh` key `2RRT7V72N7`) returned a 409 *validation* error (not 403) on a write probe → authorized to write. Keys/issuer in `~/.appstoreconnect/` (see `aso.md` §tooling). The repo's `scripts/asc_lib.py` is the canonical JWT/ASC helper — use it, not ad-hoc scripts.
- **Version state:** live version is **1.7.1 / READY_FOR_SALE**; app-info is READY_FOR_SALE. **No editable version exists.**
- **Keywords + subtitle are version-bound.** They CANNOT be edited on a live version. Changing them requires a **new App Store version (1.7.2) + a build + App Review**. (Only *promotional_text* is editable on a live app — not keywords/subtitle.) So there is **no instant "metadata-only auto-release."**
- **Repo pipeline to use (do not hand-roll):**
  1. Edit `fastlane/metadata/<locale>/keywords.txt` + `subtitle.txt`.
  2. `scripts/asc-ensure-draft-version.py` — creates/ensures the editable draft version.
  3. `scripts/asc-upload-metadata.py` (or fastlane `deliver`) — pushes the metadata files to the draft version.
  4. `scripts/testflight.sh` — cut the build (bundle with the BMI feature, §6).
  5. Submit for review with **MANUAL release** (not auto), then release after the spike.
- Other relevant scripts: `apply-native-locales.py`, `aso-apply-locale-optimizations.py`, `pull-appstore-metadata.sh` (re-pull live to verify), `restore-appstore-metadata.sh` (rollback).

---

## 6. The real lever: build a BMI / Body Profile feature (product, not keywords)

The audit's honest conclusion: **the US keyword field is near-saturated for this niche; keyword gains are marginal.** Real organic growth needs (a) ratings/authority and (b) a real **BMI / body profile feature**:

- Every winnable-cluster competitor (TDEE/Apperitif "TDEE, BMR and BMI Calculator", BMI-BMR-BodyFat, Zolt) pairs **bmi + tdee + bmr**. Total Calories can't index `bmi` (pop 55, diff 49, competitors sub-500★ — winnable) because the app has no BMI feature. Apple won't reliably index a term the product doesn't support; field placement alone won't fix it (proven — `bmi` previously sat at 1000 in the field).
- **Important product framing:** BMI should **not** be jammed into the existing TDEE/BMR row as if it is another calorie-burn metric. TDEE/BMR answer "how many calories do I burn?" BMI/weight/body-fat answer "what are my body stats?" Keep those concepts separate so the app stays easy to understand.
- **Pitch:** Total Calories shows what you burn. **Body Profile** shows the body stats behind your calorie plan: height, weight, BMI, and (for Vitals+) body-fat / deeper context.
- **ASO reason:** basic BMI must be genuinely visible in the free app. People searching `bmi` usually want a quick calculator/readout, not a paywalled promise. Make the BMI number free; use Vitals+ for interpretation and richer body-composition context.
- This build is the natural carrier for the §3/§4 metadata changes — ship them together, manual-release after the spike.

### 6.1 Final product decision

Build a **Body Profile** section in **Settings**, not a default Today-dashboard card.

Why:
- The Today dashboard is already doing a focused job: calories burned, steps, pacing/projection, net deficit.
- BMI is useful, but it is more "profile/settings context" than "live today metric."
- Keeping it in Settings makes it discoverable without crowding the core daily-use surface.
- Free BMI in Settings satisfies real search intent and gives Apple a product surface to index.

V1 placement:
- `Settings` sheet gets a new top-level `Body Profile` section, preferably after the Vitals+ section and before Calories.
- Section row title: `Body Profile`
- Section row subtitle: `BMI, height, and weight`
- Tapping opens a dedicated `BodyProfileView` / detail screen.
- Do **not** show BMI on the Today dashboard by default in V1.
- Do **not** add BMI to iOS widgets, Lock Screen widgets, watch app, or watch complications in V1.

Optional future work:
- A user-enabled compact Body Profile card on Today.
- Weight/BMI trend charts if the app later stores historical body measurements.
- Watch readout only if users ask for it.

### 6.2 Free vs Vitals+ split

Free for everyone:
- Height
- Weight
- BMI number
- BMI category (e.g. Underweight / Healthy / Overweight / Obesity)
- Data source indicator: `Apple Health` or `Manual`
- Simple educational copy: "BMI is a height/weight reference, not a complete measure of health."

Vitals+:
- Body-fat percentage, if available from Apple Health or manually entered.
- Deeper "Body Profile context" card that ties the profile to the existing calorie features:
  - TDEE / BMR remain the calorie-burn readouts.
  - BMI and body-fat are the body-context readouts.
  - Copy should be informational, not medical/diagnostic.
- Potential Vitals+ card copy:
  - `Your calorie context`
  - `TDEE and BMR estimate your burn. BMI and body fat help frame your body profile.`
- Locked non-Pro state should show enough value to explain the upgrade without hiding the free BMI number.

Do **not** paywall the BMI number itself. The BMI number is the ASO/product unlock and the basic user promise.

### 6.3 User flows

First open:
1. User opens Settings.
2. User taps `Body Profile`.
3. App shows an explanation and source options.
4. If Apple Health already has height/weight and authorization is settled, show values from Health.
5. If Health values are missing or authorization has not been requested, show manual fields immediately so the feature still works.

Manual-only flow:
1. User enters height + weight.
2. App calculates BMI instantly.
3. Store manual values locally only.
4. Label source as `Manual`.
5. Do not write manual values to Apple Health in V1.

Apple Health flow:
1. User taps `Use Apple Health`.
2. Request HealthKit authorization for Body Profile types only.
3. Fetch most recent height and weight samples.
4. If both exist, calculate BMI and label source as `Apple Health`.
5. If one or both are missing, keep the manual fields visible and show a friendly message:
   - `Apple Health is missing height or weight. Enter them here to calculate BMI.`

Both sources exist:
- Default to Apple Health.
- Let the user switch source with a simple picker:
  - `Apple Health`
  - `Manual`
- Persist the preferred source.

Body-fat flow:
- If user is Pro and body-fat % is available from Apple Health or manual entry, show it.
- If user is Pro and body-fat is missing, show:
  - `Add body fat in Apple Health or enter it manually to include it here.`
- If user is not Pro, show a locked preview row:
  - `Body fat and calorie context are in Vitals+.`
  - Tap opens the existing trial/paywall flow with the Body Profile feature focused.

### 6.4 Data source and storage design

Keep HealthKit read-only. Do **not** write height, weight, BMI, or body-fat back to Apple Health in V1.

HealthKit reads:
- `HKQuantityType(.height)`
- `HKQuantityType(.bodyMass)`
- `HKQuantityType(.bodyFatPercentage)` for Vitals+ body-fat if available

Manual values:
- Store in App Group `UserDefaults`, normalized to metric units:
  - `bodyProfile.manualHeightMeters: Double`
  - `bodyProfile.manualWeightKilograms: Double`
  - `bodyProfile.manualBodyFatPercent: Double`
  - `bodyProfile.preferredSource: Int/String` (`appleHealth`, `manual`, maybe `automatic`)
  - `bodyProfile.unitSystem: Int/String` (`automatic`, `us`, `metric`)
- Keep manual storage out of SwiftData unless historical trends are added later.
- Do not add body profile fields to `DailyHealthRecord` in V1. BMI is a latest/profile value, not a daily cache metric.

Recommended new shared types:
- `Shared/Utilities/BodyProfileCalculator.swift`
  - pure BMI math
  - unit conversions
  - BMI category thresholds
  - formatting helpers if useful
- `Shared/Services/BodyProfileStore.swift`
  - `@MainActor ObservableObject`
  - App Group `UserDefaults`
  - stores manual values and preferred source
  - separate from `GoalSettings` so goals/settings do not become a catch-all for body measurements
- `Shared/Models/BodyProfile.swift` or local structs in the service:
  - `BodyProfile`
  - `BodyProfileSource`
  - `BodyProfileUnitSystem`
  - `BodyProfileInput`

If creating new Swift files, run `xcodegen generate` before building.

### 6.5 BMI calculation and categories

BMI formula:
- `BMI = weightKg / (heightMeters * heightMeters)`

Input validation:
- height: allow roughly `0.9...2.5` meters (about 3 ft to 8 ft 2 in)
- weight: allow roughly `25...350` kg (about 55 lb to 772 lb)
- body-fat: allow roughly `2...75` percent
- reject non-finite values.

BMI categories for adult display:
- `< 18.5` = `Underweight`
- `18.5..<25` = `Healthy`
- `25..<30` = `Overweight`
- `>= 30` = `Obesity`

Copy caveat:
- `BMI is a simple height/weight reference and is not a diagnosis. It may not reflect muscle mass, pregnancy, age, or individual health context.`

Avoid heavy medical language. This is a utility readout, not clinical advice.

### 6.6 HealthKit implementation notes

Current pattern:
- Core HealthKit authorization reads active energy, basal energy, and steps during onboarding.
- Optional Dietary Energy is requested separately when Net Deficit is enabled because mixing old/new read types can suppress the HealthKit sheet.

Follow that optional-type pattern for Body Profile.

In `Shared/Services/HealthKitService.swift`:
- Add body profile read types separately from `baseReadTypes`.
- Add something like:
  - `private let bodyProfileReadTypes: Set<HKObjectType> = [HKQuantityType(.height), HKQuantityType(.bodyMass), HKQuantityType(.bodyFatPercentage)]`
  - `func requestBodyProfileAuthorization() async throws`
  - `func authorizationRequestStatus(includeDietaryEnergy: Bool = false, includeBodyProfile: Bool = false) async -> HKAuthorizationRequestStatus?`
  - `func fetchBodyProfileFromHealth() async throws -> HealthBodyProfile`
- Use `HKSampleQuery` for most recent quantity samples rather than statistics collection:
  - sort by `HKSampleSortIdentifierEndDate` descending
  - `limit = 1`
  - height unit: `.meter()`
  - weight unit: `.gramUnit(with: .kilo)`
  - body-fat unit: `.percent()`; normalize display to percent and verify with a fixture/manual test because HealthKit percent values can be easy to mishandle.
- Do not register background delivery for height/weight/body-fat in V1. Settings can refresh on open / pull-to-refresh / button tap.
- Add verbose logs matching existing style:
  - requested type count
  - auth status before/after
  - which profile fields were found/missing
  - no sensitive values in logs unless needed for debugging; counts/source/missing flags are enough.

Important UX: HealthKit read authorization is opaque. A missing height/weight sample can mean not entered, not authorized, or genuinely absent. Avoid saying "permission denied" unless the API clearly supports it. Prefer:
- `Couldn’t find height and weight in Apple Health. You can enter them manually here.`

### 6.7 UI implementation notes

Recommended file:
- `Vitals/Views/BodyProfileView.swift`

Settings integration:
- In `DashboardView.swift`, `SettingsSheet` currently owns the form sections.
- Add a `NavigationLink` row in a new `Section("Body Profile")`.
- Present `BodyProfileView` via the existing `NavigationStack` inside Settings.

BodyProfileView layout:
- Header:
  - icon: `person.crop.circle` or `figure.stand`
  - title: `Body Profile`
  - subtitle: `Calculate BMI from Apple Health or manual height and weight.`
- Source card:
  - Picker/segmented control: `Apple Health` / `Manual`
  - Button: `Sync from Apple Health`
  - status text for missing Health values
- Free BMI card:
  - Big BMI number, one decimal place
  - Category chip
  - Height and weight row
  - Source label
- Manual entry card:
  - Unit picker: `US` / `Metric` / maybe default from locale
  - US: height feet + inches, weight pounds
  - Metric: height centimeters, weight kilograms
  - Values normalize into meters/kg in storage
  - Inline validation messages
- Education card:
  - short BMI caveat
- Vitals+ card:
  - Pro: body-fat %, source, and calorie-context copy
  - Non-Pro: locked preview row that calls `TrialOfferCoordinator.shared.request(.bodyProfileDetails)` or equivalent

Keep the Settings row short. Do not describe all caveats in the row; the detail view can carry that.

Accessibility:
- BMI card accessibility value should include BMI number, category, source, height, and weight.
- Manual fields need clear labels (`Feet`, `Inches`, `Pounds`, `Centimeters`, `Kilograms`).
- Locked Vitals+ row needs a clear button label, not just a lock icon.

### 6.8 Vitals+ / paywall integration

Update `Vitals/Views/PaywallView.swift`:
- Add or revise a `PlusFeature` for body profile details.
- Possible title: `Body Profile context`
- Detail: `Body fat and calorie context alongside your BMI, TDEE, and BMR.`
- Pitch headline: `Understand your body profile.`
- Pitch subheadline: `BMI stays free. Vitals+ adds body-fat and calorie context from your own data.`

Update `Vitals/App.swift`:
- Add a new `TrialOfferCoordinator.Intent`, e.g. `bodyProfileDetails`.
- Map it to the Body Profile PlusFeature.
- If there is no persistent Vitals+ toggle, no `pendingFeatureEnable` is required. After purchase, the Pro-only rows in `BodyProfileView` should appear automatically.

Do not rename the existing `showEnergyAverages` setting unless needed. TDEE/BMR can remain a separate Vitals+ toggle under Calories.

### 6.9 App metadata / privacy / review notes

Update HealthKit usage strings:
- `Vitals/Info.plist`
- `VitalsWatch/Info.plist` if the shared HealthKit service / watch target can request or mention the expanded types. If watch does not surface Body Profile in V1, keep watch copy accurate and avoid implying watch uses body profile.

Suggested iPhone usage string direction:
- `Total Calories reads Active Energy, Basal Energy, Step Count, optional Dietary Energy, and optional height/weight/body-fat data from Apple Health to display your daily progress, BMI, and body profile. Total Calories never writes Health data.`

Update docs before release:
- `docs/app-store-metadata.md`
- App review notes: mention Body Profile is in Settings, BMI can use manual input if Health lacks height/weight.
- Privacy language remains local/read-only. Manual values are stored locally only.

### 6.10 Tests and verification

Add unit tests:
- `VitalsTests/BodyProfileCalculatorTests.swift`
- Cover:
  - BMI formula
  - one-decimal formatting expectations if formatting lives in utility
  - category boundaries: 18.5, 25, 30
  - US/metric conversions
  - invalid height/weight/body-fat rejected
  - source resolution: Apple Health preferred when complete, manual fallback when Health missing

Build/test:
1. If new Swift files are added, run `xcodegen generate`.
2. Build with the dedicated headless simulator:
   - `UDID=$(agent-sim boot vitals)`
   - `xcodebuild -project Vitals.xcodeproj -scheme Vitals -destination "id=$UDID" build`
3. Run tests:
   - `xcodebuild test -project Vitals.xcodeproj -scheme Vitals -destination "id=$UDID"`
4. Use accessibility inspection to verify Settings → Body Profile is reachable:
   - `axe describe-ui --udid "$UDID"`

Manual QA checklist:
- [ ] Fresh install still only asks for core HealthKit types during onboarding.
- [ ] Settings shows `Body Profile` for free and paid users.
- [ ] Manual height/weight calculates BMI without HealthKit.
- [ ] Apple Health sync requests body profile authorization only after user action.
- [ ] Missing Apple Health height/weight falls back gracefully to manual entry.
- [ ] BMI number is visible to non-Pro users.
- [ ] Non-Pro users see locked Vitals+ body-fat/context row, and tapping it opens the focused trial/paywall flow.
- [ ] Pro users see body-fat/context when data exists, and a helpful missing-data state when it does not.
- [ ] Today dashboard layout is unchanged unless a future explicit toggle/card is added.
- [ ] No body profile values are written to Apple Health.
- [ ] HealthKit usage description matches the new optional reads.

### 6.11 Acceptance criteria for another agent

The BMI feature is done when:
- A free user can open Settings → Body Profile, enter height/weight manually, and see a BMI number + category.
- A user with height/weight in Apple Health can sync those values and see BMI sourced from Health.
- Vitals+ users get at least one meaningful deeper body-profile row (body-fat if available/manual, plus calorie-context copy).
- Non-Pro users can see the BMI number but are upsold for body-fat/context, using the existing Vitals+ trial/paywall system.
- The feature does not add clutter to the Today dashboard.
- Tests cover BMI math and source fallback.
- App Store metadata can honestly claim `BMI` support before adding `bmi` to the keyword field.

---

## 7. Astro state — already done (2026-06-25)

Astro MCP is now the source of truth for the report/recommend loop. For Total Calories US:
- **Removed 128 keywords** (113 + 7 + 8 verification adds): pop-5 noise, off-strategy (steps-counter/weight-loss/fasting/generic widget-health), homograph false-friends, and aspirational pop-5 targets we don't rank.
- **~40 keywords kept**, tagged on three axes:
  - `deployed` (blue, renamed from `asc-field`) = the live keyword-field words.
  - `target` (green, renamed from `winnable`) = pop>5 winnable gaps (`bmi`, `bmi calculator`, `bmr calculator`, `tdee calculator`, `total energy`, `tdee`) + the two climbing positions (`tdee tracker` #40, `tdee bmr` #34).
  - `wall` (gray, new) = the 5 unbeatable food-logger terms, tracked only to watch the ceiling.
- Strategy captured in keyword **notes** on `bmi` (product-gated) and `tdee tracker` (lane anchor).
- Rule enforced: don't host pop≤5 keywords EXCEPT deployed words or positions you already hold.
- The repo also has `scripts/astro_mcp.py`, `astro-sync-all-stores.py`, `astro-competitor-scan.py`, `astro-build-keywords.py` for batch Astro work across stores.

---

## 8. Safeguards (do not skip)

1. **Never ship metadata during a download spike.** Re-indexing causes days of volatility. Wait for normalization.
2. **Manual release only.** Auto-release lands at a random post-approval time, possibly mid-spike. Control the timing.
3. **≤30% keyword-field change per update** — else ranking moves are unattributable. Stage larger changes across cycles.
4. **No machine-translated metadata pushed live unverified.** For each non-English locale, validate the subtitle phrasing reads naturally and that each new keyword passes the SERP-intent check in that store (returns calorie/burn/metabolic apps, not a homograph). Owner has only researched US so far.
5. **Verify the change landed.** After upload, re-pull live metadata (`pull-appstore-metadata.sh` or read it back via ASC API) and **confirm subtitle.txt actually changed** in ASC, not just in the local file. (Owner explicitly flagged this — local file edits don't always propagate.)
6. **Keep the live app up.** Submitting is safe (1.7.1 stays live through review); only the *release* swaps metadata.
7. **`bmi` watch:** if it stays 1000 after release, that's the product-gate — do §6.

## 9. Verification checklist (post-release)
- [ ] `pull-appstore-metadata.sh` shows new subtitle + keywords for en-US (and each edited locale).
- [ ] Subtitle in App Store Connect UI reads `TDEE Burn on Watch & Widget` for en-US.
- [ ] Astro `tdee tracker` / `tdee bmr` / `bmi` rankings tracked for ~2 weeks post-release.
- [ ] Download velocity not harmed vs the pre-change spike baseline.
- [ ] `bmi` rank checked — if still 1000, schedule the BMI feature.

## 10. Open decisions for the implementer
- Sequence: confirm bundling metadata with the BMI-feature build vs a standalone metadata-only version (the latter still needs a build).
- Whether to do a full rigorous per-locale ASO pass (repeat US method per market) or ship the structural rule-set in §4 first.
- Exact release timing (after spike normalizes — watch RevenueCat New Customers for Total Calories).
