# Competitor review pull and tags, 2026-11-20

Run: fleet-run on imac, branch fleet/20261120-112808-3868-claude. Raw JSON stays in the run folder (`_raw/`, uncommitted). Row file: `2026-11-20-competitor-reviews.tsv` (33,994 rows).

Rows: 33,994 total = 24,958 App Store + 8,980 Google Play + 56 web. Sentiment: {'neg': 11756, 'mixed': 5634, 'pos': 16596, 'neutral': 8}.

## 1. Row counts

### App Store rows by app and storefront (deduped by review id)

| App | us | gb | ca | au | nz | ie | za | in | sg | ph | de | es | fr | it | ch | hk | tw | jp | pl | nl | total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ActivityTracker Pedometer | 929 | 618 | 137 | 211 | 14 | 32 | 9 | 50 | 9 | 5 | 241 | 93 | 67 | 97 | 20 | 3 | 0 | 9 | 5 | 85 | 2634 |
| Steps - Activity Tracker | 922 | 671 | 417 | 351 | 41 | 77 | 44 | 90 | 10 | 27 | 12 | 12 | 4 | 4 | 8 | 4 | 3 | 41 | 12 | 21 | 2771 |
| HealthView | 546 | 90 | 46 | 22 | 5 | 1 | 0 | 10 | 3 | 3 | 223 | 21 | 26 | 20 | 20 | 1 | 4 | 4 | 1 | 16 | 1062 |
| Activity Tracker FitnessView | 235 | 29 | 18 | 14 | 1 | 2 | 4 | 17 | 0 | 1 | 113 | 7 | 34 | 8 | 7 | 2 | 3 | 8 | 5 | 7 | 515 |
| Calorie Counter - Calory AI | 705 | 96 | 62 | 23 | 2 | 6 | 2 | 7 | 4 | 4 | 29 | 9 | 13 | 3 | 3 | 0 | 2 | 3 | 8 | 5 | 986 |
| Cronometer | 680 | 393 | 504 | 218 | 42 | 25 | 25 | 23 | 7 | 12 | 96 | 27 | 54 | 33 | 26 | 4 | 3 | 8 | 11 | 38 | 2229 |
| All the Rings | 86 | 18 | 11 | 5 | 1 | 0 | 0 | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 126 |
| TDEE | 15 | 9 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 28 |
| Pedometer++ | 961 | 846 | 352 | 622 | 99 | 113 | 63 | 598 | 59 | 61 | 911 | 501 | 777 | 617 | 453 | 41 | 29 | 155 | 53 | 213 | 7524 |
| Apple Fitness | 966 | 601 | 507 | 335 | 58 | 43 | 87 | 641 | 67 | 45 | 817 | 521 | 619 | 480 | 158 | 42 | 177 | 430 | 218 | 269 | 7081 |
| Total Calories (reference) | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 2 |

### Google Play rows by app and country (first-seen country after dedupe; us, gb, ca, au, in pulls in English mostly return the same reviews, so nearly all are attributed to us; the de pull uses German language and adds German-language reviews)

| App | us | gb | ca | au | in | de | total |
|---|---|---|---|---|---|---|---|
| ActivityTracker Pedometer | 939 | 0 | 0 | 0 | 0 | 131 | 1070 |
| Activity Tracker FitnessView | 8 | 0 | 0 | 0 | 0 | 1 | 9 |
| Calorie Counter - Calory AI | 367 | 0 | 0 | 0 | 0 | 6 | 373 |
| Cronometer | 1524 | 0 | 0 | 0 | 0 | 337 | 1861 |
| Google Fit | 1752 | 0 | 0 | 0 | 0 | 1904 | 3656 |
| iTECH Wearables | 1743 | 0 | 0 | 0 | 0 | 0 | 1743 |
| Calorie Burn Plan | 262 | 0 | 0 | 0 | 0 | 6 | 268 |

### Web rows: 56 (Apple Community, MacRumors, Cronometer forum, Garmin forum, MacStories, App Store review excerpts); source=web, rating blank, URL in ref.

## 2. 1-3 star share (App Store and Play rows pulled; web excluded)

| App | source | rows | 1-3 star | share | 1-2 star share |
|---|---|---|---|---|---|
| ActivityTracker Pedometer | appstore | 2634 | 222 | 8% | 6% |
| ActivityTracker Pedometer | play | 1070 | 336 | 31% | 23% |
| Steps - Activity Tracker | appstore | 2771 | 791 | 29% | 20% |
| HealthView | appstore | 1062 | 690 | 65% | 55% |
| Activity Tracker FitnessView | appstore | 515 | 216 | 42% | 31% |
| Activity Tracker FitnessView | play | 9 | 6 | 67% | 56% |
| Calorie Counter - Calory AI | appstore | 986 | 370 | 38% | 26% |
| Calorie Counter - Calory AI | play | 373 | 157 | 42% | 29% |
| Cronometer | appstore | 2229 | 655 | 29% | 20% |
| Cronometer | play | 1861 | 597 | 32% | 22% |
| All the Rings | appstore | 126 | 85 | 67% | 60% |
| TDEE | appstore | 28 | 21 | 75% | 71% |
| Pedometer++ | appstore | 7524 | 1697 | 23% | 15% |
| Apple Fitness | appstore | 7081 | 5773 | 82% | 63% |
| Total Calories (reference) | appstore | 2 | 0 | 0% | 0% |
| Google Fit | play | 3656 | 2780 | 76% | 66% |
| iTECH Wearables | play | 1743 | 867 | 50% | 38% |
| Calorie Burn Plan | play | 268 | 38 | 14% | 9% |

Note: the RSS feed returns at most 500 reviews per storefront per sort, so these are samples of the newest and most helpful reviews, not all ratings. The most-helpful sort skews to complaints.

## 3. Store pages: US rating counts, averages, pricing, IAPs

App Store US (iTunes lookup; star histogram from apps.apple.com page, 5 stars first):

| App | ratings | avg | 5 | 4 | 3 | 2 | 1 | price | version | last release |
|---|---|---|---|---|---|---|---|---|---|---|
| ActivityTracker Pedometer | 102,914 | 4.78 | 88,053 | 10,208 | 2,783 | 714 | 1,156 | Free | 4.4 | 2026-11-05 |
| Steps - Activity Tracker | 136,211 | 4.77 | 117,948 | 11,268 | 3,161 | 1,180 | 2,663 | Free | 1.7.70 | 2026-10-09 |
| HealthView | 14,413 | 4.54 | 11,218 | 1,547 | 657 | 275 | 720 | Free | 4.3.1 | 2026-09-29 |
| Activity Tracker FitnessView | 8,084 | 4.62 | 6,719 | 598 | 243 | 120 | 410 | Free | 3.3 | 2026-10-29 |
| Calorie Counter - Calory AI | 8,154 | 4.60 | 6,509 | 839 | 331 | 140 | 335 | Free | 5.2.8 | 2026-11-06 |
| Cronometer | 101,019 | 4.77 | 85,261 | 11,492 | 2,493 | 651 | 1,143 | Free | 4.60.5 | 2026-11-18 |
| All the Rings | 1,515 | 4.61 | 1,241 | 131 | 40 | 25 | 78 | Free | 2.2.3 | 2022-12-28 |
| TDEE | 505 | 4.71 | 439 | 30 | 13 | 4 | 19 | Free | 5.1.1 | 2026-07-30 |
| Pedometer++ | 185,590 | 4.79 | 161,644 | 15,484 | 4,093 | 1,681 | 2,707 | Free | 8.2.1 | 2026-10-23 |
| Apple Fitness | 11,701 | 2.86 | 3,226 | 1,279 | 1,680 | 1,712 | 3,804 | Free | 8.5 | 2026-09-14 |
| Total Calories (reference) | 12 | 4.67 | 11 | 0 | 0 | 0 | 1 | Free | 1.9.5 | 2026-11-17 |

Google Play (google-play-scraper, us):

| App | package | rating count | avg | installs | version | IAP range |
|---|---|---|---|---|---|---|
| ActivityTracker Pedometer | com.bitscoffee.ActivityTracker | 6121 | 4.01 | 500,000+ | 4.0 | $4.99 - $29.99 per item |
| Steps - Activity Tracker | com.yoc.steps | n/a | n/a | 100+ | Varies with device | $3.99 per item |
| FitnessView: Activity Tracker | com.funnmedia.fitnessview | 34 | 3.33 | 5,000+ | 1.2.1 | $1.99 - $29.99 per item |
| Calory - AI Calorie Counter | com.funnmedia.calory | 1293 | 4.22 | 100,000+ | Varies with device | $0.99 - $39.99 per item |
| Cronometer: Calorie Counter | com.cronometer.android.gold | 60312 | 4.54 | 5,000,000+ | Varies with device | $2.99 - $89.99 per item |
| TDEE - Your Diet Companion | com.apperitif.tdee | n/a | n/a | 500+ | Varies with device | $10.99 per item |
| Google Fit: Activity Tracking | com.google.android.apps.fitness | 688069 | 3.46 | 100,000,000+ | Varies with device | none |
| iTECH Wearables | itech.wearables | 61418 | 4.62 | 1,000,000+ | 7.5.0 | none |
| Burned Calories By Exercise | com.apep.burnedcalories | 306 | 4.78 | 100,000+ | Varies with device | none |
| Exercise Calorie Calculator | com.firstcenturythinking.exercisecalculator | 736 | 4.32 | 100,000+ | Varies with device | none |
| Calorie Burn Plan: Fat Gone | com.creamsoft.burnthemdown | 2833 | 4.38 | 100,000+ | 3.1.6 | $0.99 - $34.99 per item |
| Calories Burned Calculator | com.appsoup.calories.burned.calculator | n/a | n/a | 500+ | Varies with device | $3.99 per item |
| Calories Burned Running | air.com.intemodino.caloriesburnedwhilerunning | n/a | n/a | 1,000+ | Varies with device | none |
| Calories Burned Calculator | com.appnextdoor.caloriesburnedcalculator | n/a | n/a | 100+ | Varies with device | none |
| TDEE Calculator Calorie Intake | com.calculators.tech.tdee | 239 | 3.73 | 10,000+ | 1.4.9 | $4.99 - $74.99 per item |
| Calorie Deficit Calculator | com.oatsy | 236 | 3.53 | 100,000+ | 1.29 | $19.99 - $39.99 per item |
| Activity action tracker | com.sakar.actiontracker | 330 | 2.75 | 100,000+ | 1.0.24 | none |

Not on Play (name search found no match): HealthView (Kodeon; the Play app named Health View is a different developer), All the Rings, Pedometer++, Apple Fitness. Steps and TDEE (Apperitif) are on Play but have no rating count and returned 0 reviews.

Play non-food-logger additions (most ratings among results for the three queries, not food loggers): Google Fit (688,069 ratings, from 'active calories'), iTECH Wearables (61,418, from 'active calories'), Calorie Burn Plan: Fat Gone (2,833, from 'total calories burned'). Note Calorie Burn Plan is a fat-loss workout plan app and Google Fit and iTECH Wearables are general activity or smartwatch companions, so none is a pure burn tracker. Next in line if swapping: Exercise Calorie Calculator (736), Burned Calories By Exercise (306).

### Pricing and in-app purchases (App Store US page, price per SKU as listed; the page lists several SKUs of the same name at different price points)

- **ActivityTracker Pedometer** (Free to download): ActivityTracker PRO $29.99; ActivityTracker PRO $4.99
- **Steps - Activity Tracker** (Free to download): Pro Upgrade $3.99
- **HealthView** (Free to download): Premium Monthly Subscription $0.99; 14 Days Free Trial $0.00; Premium Yearly Subscription $4.99; Growth Bundle: Monthly $4.99; HealthView Premium $29.99; HealthView Premium $59.99; HealthView Premium $29.99; One time purchase $9.99; HealthView Premium $59.99; Annual Subscription $29.99
- **Activity Tracker FitnessView** (Free to download): FitnessView Premium Yearly $14.99; FitnessView Premium Monthly $1.99; FitnessView Premium Yearly $29.99; FitnessView Premium One Time $29.99; FitnessView Premium Yearly $9.99; FitnessView Premium Yearly $19.99; FitnessView Premium Yearly $7.49; FitnessView Lifetime Offer $14.99; FitnessView Premium Yearly $39.99; Premium Plus Bundle $59.99
- **Calorie Counter - Calory AI** (Free to download): Calory Monthly Subscription $4.99; Calory Monthly Subscription $2.99; Calory Premium 1 Year $17.99; Calory Premium 1 Year $16.99; Premium Plus Yearly $39.99; Premium Plus Monthly $5.99; Calory Premium Lifetime! $34.99; Calory Premium Yearly $14.99; Premium Plus Yearly $29.99; Calory Premium Lifetime! $34.99
- **Cronometer** (Free to download): Gold Monthly $10.99; Gold Annual $59.99; Gold Monthly $10.99; Gold Annual $59.99; Gold Subscription $10.99; Gold Annual $59.99; Gold Annual $59.99; Gold Monthly $10.99; Gold Annual $59.99; Cronometer Gold $10.99
- **All the Rings** (Free to download): 1 Month $2.99; 12 Months $9.99; Forever Fit $24.99; 3 Months $4.99; Remove Ads Forever $2.99; 6 Months $6.99
- **TDEE** (Free to download): TDEE Pro $14.99
- **Pedometer++** (Free to download): Pedometer++ Premium $1.99; Pedometer++ Premium $3.99; Pedometer++ Premium $29.99; Pedometer++ Premium $19.99; Pedometer++ Premium $3.99; Pedometer++ Premium $39.99; Pedometer++ Premium $5.99; Pedometer++ Premium $5.99
- **Apple Fitness** (Free to download): none listed (free, no IAP)
- **Total Calories (reference)** (Free to download): Vitals+ Yearly $29.99; Vitals+ Monthly $6.99; Vitals+ Lifetime $59.99; Vitals+ Yearly $14.99

Play IAP price ranges are in the Play table above. Total Calories (Vitals+): monthly $6.99, yearly $29.99 (and a $14.99 yearly SKU), lifetime $59.99. Closest comparators on price: HealthView Premium $29.99 yearly or $59.99 and a $9.99 one-time SKU, FitnessView Premium $29.99 yearly or one time and a $14.99 lifetime offer, Calory $14.99 to $39.99 yearly and $34.99 lifetime, Pedometer++ Premium $19.99 to $39.99, ActivityTracker PRO $29.99 and $4.99, All the Rings Forever Fit $24.99, TDEE Pro $14.99, Steps Pro $3.99, Cronometer Gold $10.99 monthly and $59.99 annual.

## 4. What's New since 2025-06

**Gap: full 18-month version history could not be pulled.** The apps.apple.com page (desktop User-Agent, redirects followed) returns a server-rendered shell with rating histogram, IAP list and info, but version history and release notes load from amp-api.apps.apple.com, which returns 401 without a web token that the page does not embed. The iTunes lookup returns only the current version's notes. What is available is below (current release per app, dated), plus review-derived signals.

- **ActivityTracker Pedometer** 4.4 (2026-11-05): • Updated for iPhone Duo! • Activities (GPS workouts) with voiceover on iPhone and Apple Watch • Additional bug-fixes and improvements
- **Steps - Activity Tracker** 1.7.70 (2026-10-09): We're continuously working on improving Steps by fixing bugs and adding new features. As part of these updates, Steps now requires iOS 17 or newer, and our Apple Watch app requires watchOS 10 or newer.  If Steps has been helpful to you, please consider leaving a rating or review - it means the world to us.
- **HealthView** 4.3.1 (2026-09-29): New: • The Workouts Year view now tells you when Apple Health data couldn't be loaded, instead of showing a blank chart • Fixed several crashes, including one when switching dates quickly on a chart and one with some Blood Pressure records • Other bug fixes and performance improvements  Still new from 4.3: ask Siri for any health stat, or find it straight from Spotlight.
- **Activity Tracker FitnessView** 3.3 (2026-10-29): What's New in FitnessView 3.3  • Made for iPhone Duo: Home, Stats, Workouts, Challenges and Settings adapt when you unfold your device, with multi-column layouts and controls in the side toolbar. • More Liquid Glass: rings, goal gauges, icons, Quick Add tiles and sharing previews have a fresh glass look on iOS 26 and later. • Many small improvements.
- **Calorie Counter - Calory AI** 5.2.8 (2026-11-06): What's New in Calory!  This update brings a smoother, more reliable experience with bug fixes and performance improvements throughout the app.  * Improved iPad Experience * Refined layouts, better screen resizing, and improved support for different window sizes and orientations.  * Smarter AI Food Scanning *  Improved photo loading from your gallery, with better error handling and more reliable scanning.  * More Accurate Tracking *  Fixed issues with food logs, fasting, water, weight, exercise calories, and GLP-1 dose entries.  * Better History & Logging *  Improved date and time accuracy when logging entries for previous days.  * Enhanced Stability *  Fixed crashes and improved overall app 
- **Cronometer** 4.60.5 (2026-11-18): - Bug fixes and polish for improved user experience
- **All the Rings** 2.2.3 (2022-12-28): This app has been updated by Apple to prepare for watchOS 27 compatibility. No new features are included.  • Bug fixes and performance improvements for iOS 16
- **TDEE** 5.1.1 (2026-07-30): Bug fixes and improvements.
- **Pedometer++** 8.2.1 (2026-10-23): Support for the iPhone Duo.
- **Apple Fitness** 8.5 (2026-09-14): Bug Fixes and Feature Enhancements
- **Total Calories (reference)** 1.9.5 (2026-11-17): iPad install compatibility is fixed.

Highlights from the notes above and from the reviews (dated by review date, not by release):
- 2026-11-05 ActivityTracker 4.4: iPhone Duo support, voiceover GPS workouts on iPhone and Watch.
- 2026-10-29 FitnessView 3.3: iPhone Duo layouts and more Liquid Glass (rings, gauges, Quick Add tiles).
- 2026-10-23 Pedometer++ 8.2.1: iPhone Duo support. Pedometer++ 8.x redesign drew watch-complication complaints from 2026-05 (rows 'Major Upgrade Flaw', 'New watch complication has ruined it'); widget, complication and watch-face complaint rows peak in 2025-09 (11 rows) and 2026-09 (11 rows); many cite iOS 26 or iOS 27 watch updates.
- 2026-11-06 Calory 5.2.8: improved iPad experience, smarter AI food scan.
- 2026-10-09 Steps 1.7.70: now requires iOS 17 and watchOS 10. 2026-09-29 HealthView 4.3.1: crash fixes, Workouts Year view load message; 4.3 added Siri and Spotlight access to any health stat (the only Siri launch among the set).
- 2026-11-17 Total Calories 1.9.5: iPad install compatibility fixed (reference).
- All the Rings 2.2.3 last released 2022-12-28; the listed note says Apple updated it to prepare for watchOS 27. Its recent reviews are crash-on-launch reports from 2023 to 2025.
- Apple Fitness 8.5 (2026-09-14): reviews mention iOS 26 (16 rows) and iOS 27 (27 rows, first on 2026-09-16) changes to move rings and calories (e.g. 'over-corrected' treadmill distance and active calories on iOS 27).
- Price changes: not dated; HealthView moved features behind a subscription (Growth Bundle) around the 3.1 update, 2021 to 2022, still the top complaint in its reviews; Cronometer Play IAP tops at $89.99, App Store annual $59.99.

## 5. Failures and gaps

- App Store RSS: 0 HTTP 403 or 429 responses across 440 feed files (11 apps x 20 storefronts x 2 sorts, 1.2 s between calls, 4 parallel workers). The feed hard-caps at 10 pages (500 reviews) per storefront per sort; 44 feed files hit the cap: Pedometer++ 16 files (au, de, es, fr, gb, in, it, us), Apple Fitness 13 (us, ca, in, de, fr, es, gb), Steps 4 (us, gb), ActivityTracker 4 (us, gb), Cronometer 3 (us, ca), HealthView 2 (us), Calory 2 (us). Older reviews in those storefronts are not retrievable here.
- Total Calories itself has only 2 written reviews across all 20 storefronts (12 ratings in the US). All other App Store apps: TDEE 28 rows, All the Rings 126 rows (small storefront footprints).
- Store pages: version history and release notes beyond the current version unavailable (see section 4). IAP lists come from the page's In-App Purchases block; Apple Fitness has none.
- Google Play: HealthView, All the Rings, Pedometer++, Apple Fitness not on Play. Steps (com.yoc.steps, 100+ installs) and TDEE (com.apperitif.tdee, 500+ installs) returned 0 reviews. Pulls come back in 200-review pages, so results were trimmed to 1,500 newest plus 500 most relevant per app per country; the English-language country pulls (us, gb, ca, au, in) mostly return the same reviews, so after dedupe nearly all rows are attributed to us (the first pulled); gb, ca, au, in added 0 unique rows. Play search results gave no rating counts directly; counts come from the app detail call.
- Reddit: old.reddit.com returned HTTP 403; one public mirror (redlib) returned 429; skipped as instructed.
- Web: Apple Community pages are JavaScript shells (curl returns the generic page, the -prz mirrors return 502, WebFetch redirects to support.apple.com), so threads could not be read directly. The 56 web rows are built from WebSearch result excerpts: thread titles and quoted user wording as the search tool returned them, with dates approximate (year, or year-month where the excerpt gave it). Rows marked source=web are therefore short or paraphrased excerpts, not verbatim reviews; they are tagged by hand. MacRumors row 2020 is from the fetched page. The 'web: App Store review' rows come from search excerpts of App Store reviews and listings. Fewer 2025 to 2026 first-person complaint threads surfaced than hoped; 56 rows is inside the 40 to 100 target.
- Ratings in the TSV: the RSS gives integers; Play gives integers. Web rows have blank rating. Em dashes in user text were replaced with commas in the TSV (house style); all other text is unchanged apart from tab and newline replacement.
- Language detection was used only to choose the gist style for rule-tagged non-English rows.

## 6. How rows were tagged (read this before trusting theme counts)

- 11,724 rows (4 to 5 stars with none of the complaint or request words) are auto-tagged praise_general, pos, intensity 1, request 0, gist 'general praise', exactly as specified.
- 1,104 rows are hand-tagged by reading each one: all 56 web rows, plus 1,048 non-praise rows that match the core-term regex below or belong to Total Calories, TDEE, All the Rings or the FitnessView Play app. Core regex: `total calor|total burn|total energy|resting|basal|active calor|active energy|move ring|complication|watch face|lock screen|tdee|\bbmr\b|net calor|deficit|maintenance|calories burned|calorie burn|burned calor|kj\b|kilojoule|grundumsatz|verbrannt|kalorienverbrauch|brûlé|dépense|quemad|gasto|bruciat|消費カロリー|安静時|消耗|卡路里`.
- 21,166 remaining non-praise rows are rule-tagged (keyword and rating rules in a multilingual regex tagger), not read one by one. That is a departure from 'tag every other row yourself': 21k rows was not feasible by hand in one run. Rule-tagged gists are the first complaint-bearing sentence of the review truncated to 15 words (English) or a fixed theme phrase (non-English), not a written summary. Rows with tagged=rule are in the run folder's `_raw/rows_tagged.json`; the TSV has no method column.
- Rule quality, measured against the 1,048 hand tags (a set biased toward widget, complication and calorie reviews, so treat as an upper bound on the rest): top hand theme found in the rule's themes 65%, mean theme set overlap (Jaccard) 0.42, sentiment 79%, intensity 77%, request flag 69%. Weakest themes: calorie_accuracy, bugs_stability, ui_design (rules miss many), total_vs_active and watch_app (over-trigger or under-trigger). Use rule-tagged theme counts as directional only; use hand-tagged rows and the quotes below for decisions.
- Sentiment: 1 to 2 stars neg; 3 stars mixed; 4 to 5 mixed only if a defect word appears. Intensity: 3 for 1 star, or 2 star with quit/refund/rage words; 2 for 2 to 3 stars with defects.

## 7. Theme row counts (all tagged rows, praise_general excluded from top list)

| theme | rows | of which hand-tagged |
|---|---|---|
| praise_general | 11,724 | 0 |
| other | 4,698 | 2 |
| steps_distance | 3,677 | 140 |
| bugs_stability | 3,271 | 180 |
| sync_refresh | 3,086 | 173 |
| price_paywall | 3,069 | 84 |
| workouts | 2,426 | 76 |
| food_logging | 2,220 | 61 |
| ui_design | 2,090 | 96 |
| goals_rings | 2,090 | 113 |
| platform | 1,776 | 60 |
| calorie_accuracy | 1,502 | 161 |
| history_trends | 1,349 | 47 |
| ads | 1,027 | 24 |
| widgets_complications | 944 | 397 |
| support_dev | 907 | 34 |
| privacy_account | 860 | 24 |
| notifications | 502 | 29 |
| weight_body | 479 | 21 |
| localization | 335 | 11 |
| watch_app | 258 | 71 |
| deficit_net | 250 | 52 |
| total_vs_active | 204 | 96 |
| siri_shortcuts | 44 | 0 |
| tdee_bmr | 25 | 21 |

## 8. Keyword counts (rows whose title or text matches; any sentiment; cell = rows / negative rows)

App columns combine App Store and Play. TC = Total Calories reference, web = all web rows.

| keyword | TOTAL | ActivityTracker | Steps | HealthView | FitnessView | Calory | Cronometer | AllRings | TDEE app | Ped++ | AppleFit | TC | GoogleFit | iTECH | BurnPlan | web |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| total calories | 57/21 | 2/0 | 2/0 | 10/3 | 5/2 | 3/0 | 11/1 | 1/1 | 0/0 | 1/0 | 4/1 | 1/0 | 1/0 | 0/0 | 1/0 | 15/13 |
| resting | 101/34 | 5/0 | 10/1 | 8/2 | 3/1 | 2/0 | 8/1 | 0/0 | 0/0 | 21/2 | 20/8 | 1/0 | 3/1 | 0/0 | 1/0 | 19/18 |
| basal | 3/1 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 1/0 | 0/0 | 2/1 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| active calories | 29/13 | 1/0 | 0/0 | 1/0 | 0/0 | 3/0 | 3/1 | 0/0 | 0/0 | 2/0 | 10/4 | 0/0 | 0/0 | 0/0 | 0/0 | 9/8 |
| move ring | 38/23 | 0/0 | 0/0 | 1/1 | 0/0 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 35/21 | 0/0 | 0/0 | 0/0 | 0/0 | 1/1 |
| rest day | 46/7 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 29/1 | 17/6 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| pause | 150/77 | 3/0 | 8/5 | 0/0 | 3/2 | 0/0 | 5/2 | 1/0 | 0/0 | 11/0 | 108/62 | 0/0 | 10/6 | 0/0 | 0/0 | 1/0 |
| complication | 285/96 | 27/13 | 20/6 | 60/26 | 31/9 | 12/1 | 0/0 | 5/1 | 0/0 | 121/36 | 6/2 | 1/0 | 0/0 | 0/0 | 0/0 | 2/2 |
| widget | 568/190 | 21/6 | 53/15 | 67/33 | 46/11 | 54/9 | 37/7 | 2/0 | 0/0 | 169/38 | 62/40 | 0/0 | 50/27 | 2/0 | 0/0 | 5/4 |
| watch face | 252/110 | 12/5 | 11/3 | 13/6 | 8/3 | 2/0 | 0/0 | 1/0 | 0/0 | 80/41 | 8/2 | 0/0 | 3/2 | 112/47 | 0/0 | 2/1 |
| lock screen | 47/17 | 6/2 | 4/2 | 3/0 | 0/0 | 2/0 | 1/1 | 0/0 | 0/0 | 21/8 | 9/4 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 |
| tdee | 8/5 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 4/1 | 0/0 | 2/2 | 0/0 | 1/1 | 0/0 | 0/0 | 0/0 | 0/0 | 1/1 |
| bmr | 13/5 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 9/2 | 0/0 | 1/1 | 0/0 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 2/2 |
| maintenance | 19/3 | 0/0 | 1/0 | 0/0 | 0/0 | 3/1 | 7/0 | 0/0 | 1/0 | 3/1 | 4/1 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| burned | 272/76 | 45/3 | 25/2 | 13/6 | 2/0 | 36/4 | 20/2 | 0/0 | 0/0 | 5/1 | 66/39 | 2/0 | 18/10 | 9/1 | 20/0 | 11/8 |
| burnt | 89/25 | 9/0 | 6/0 | 3/1 | 0/0 | 7/0 | 9/1 | 0/0 | 0/0 | 12/0 | 31/17 | 0/0 | 8/6 | 0/0 | 4/0 | 0/0 |
| calorie counter | 106/18 | 0/0 | 24/6 | 0/0 | 2/0 | 36/4 | 27/3 | 0/0 | 0/0 | 3/0 | 7/4 | 0/0 | 0/0 | 5/1 | 2/0 | 0/0 |
| net calories | 10/2 | 0/0 | 0/0 | 4/1 | 3/0 | 2/0 | 1/1 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| deficit | 37/4 | 1/0 | 0/0 | 1/0 | 3/1 | 5/0 | 24/3 | 0/0 | 1/0 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 0/0 | 1/0 |
| kj / kilojoule | 16/5 | 1/0 | 3/0 | 0/0 | 0/0 | 3/1 | 2/0 | 0/0 | 0/0 | 1/0 | 5/3 | 0/0 | 1/1 | 0/0 | 0/0 | 0/0 |
| inaccurate | 345/235 | 27/17 | 59/36 | 3/2 | 1/0 | 10/4 | 23/5 | 2/1 | 2/2 | 62/38 | 105/87 | 0/0 | 43/38 | 7/4 | 0/0 | 1/1 |
| wrong | 343/206 | 13/5 | 26/14 | 15/9 | 4/3 | 25/7 | 43/11 | 4/1 | 2/2 | 44/18 | 83/73 | 0/0 | 63/53 | 19/8 | 0/0 | 2/2 |
| accurate | 1616/421 | 310/36 | 340/80 | 16/8 | 6/1 | 39/9 | 159/8 | 3/1 | 5/3 | 406/72 | 159/106 | 0/0 | 120/76 | 39/17 | 10/0 | 4/4 |
| inaccurate/wrong/accurate (any) | 2180/784 | 342/53 | 400/115 | 32/17 | 11/4 | 70/18 | 213/24 | 9/3 | 8/6 | 491/120 | 312/236 | 0/0 | 212/154 | 63/27 | 10/0 | 7/7 |
| sync/update/refresh | 3723/2099 | 176/53 | 225/82 | 185/95 | 48/22 | 154/35 | 352/120 | 21/10 | 2/0 | 645/281 | 965/675 | 0/0 | 694/546 | 238/169 | 5/0 | 13/11 |
| subscription | 842/453 | 14/4 | 17/3 | 138/112 | 36/20 | 152/67 | 230/82 | 4/1 | 1/0 | 43/17 | 198/141 | 0/0 | 3/3 | 2/0 | 1/0 | 3/3 |
| lifetime/one-time | 233/65 | 6/0 | 23/1 | 17/9 | 19/6 | 103/28 | 26/9 | 1/0 | 0/0 | 24/6 | 10/3 | 0/0 | 3/2 | 1/1 | 0/0 | 0/0 |
| free | 1329/376 | 86/11 | 112/21 | 52/39 | 26/19 | 95/50 | 661/101 | 1/0 | 2/1 | 125/17 | 147/107 | 0/0 | 10/4 | 8/3 | 4/3 | 0/0 |
| ads | 946/418 | 40/12 | 54/20 | 32/27 | 3/3 | 66/28 | 552/243 | 3/0 | 6/5 | 103/30 | 68/42 | 0/0 | 12/5 | 3/2 | 4/1 | 0/0 |
| garmin/fitbit/oura/whoop | 1073/465 | 91/6 | 90/9 | 46/10 | 2/1 | 15/3 | 111/17 | 0/0 | 0/0 | 190/16 | 282/204 | 0/0 | 224/191 | 19/6 | 1/0 | 2/2 |
| android | 119/63 | 11/4 | 1/0 | 1/1 | 1/0 | 16/4 | 12/5 | 0/0 | 0/0 | 1/0 | 5/2 | 0/0 | 54/37 | 16/9 | 1/1 | 0/0 |
| ipad | 318/201 | 4/0 | 4/1 | 10/4 | 14/6 | 10/6 | 10/4 | 0/0 | 0/0 | 7/0 | 259/180 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| DE verbrannt | 21/13 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 0/0 | 5/2 | 0/0 | 14/11 | 0/0 | 0/0 | 0/0 |
| DE Kalorienverbrauch | 29/18 | 2/1 | 0/0 | 2/1 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 3/0 | 7/6 | 0/0 | 14/10 | 0/0 | 0/0 | 0/0 |
| DE Kalorienzähler | 1/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 0/0 |
| DE Grundumsatz | 3/2 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 3/2 | 0/0 | 0/0 | 0/0 |
| FR brûlées | 19/7 | 0/0 | 0/0 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 0/0 | 9/1 | 9/6 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| FR dépense | 24/11 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 8/0 | 15/11 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| ES quemadas | 6/2 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 4/0 | 2/2 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| ES gasto | 3/1 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 1/0 | 0/0 | 0/0 | 0/0 | 2/1 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| IT bruciate | 12/3 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 6/0 | 6/3 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| IT contacalorie | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| JA 消費カロリー | 16/10 | 0/0 | 3/3 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 1/0 | 12/7 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| JA 安静時 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| ZH 消耗 | 6/3 | 0/0 | 1/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 5/3 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| ZH 卡路里 | 6/5 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 6/5 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |

Row counts per app for reference: ActivityTracker 3,704, Steps 2,771, HealthView 1,062, FitnessView 524, Calory 1,359, Cronometer 4,090, AllRings 126, TDEE app 28, Ped++ 7,524, AppleFit 7,081, TC 2, GoogleFit 3,656, iTECH 1,743, BurnPlan 268, web 56.

## 9. High-signal quotes (verbatim, under 15 words; app, stars, date)

Top themes by row count (excluding praise_general and other): steps_distance, bugs_stability, sync_refresh, price_paywall, workouts, food_logging, ui_design, goals_rings. Added the five themes closest to Total Calories: total_vs_active, calorie_accuracy, widgets_complications, deficit_net, tdee_bmr (few rows, mostly hand-tagged). Quotes were chosen by hand from English rows; web rows are not quoted.

### steps_distance

1. "The app does not record all steps, then randomly adds steps while being idle" (Pedometer++, 1 stars, 2018-02-19, R15031)
2. "My app says 12,000 steps and 226 calories burned" (Apple Fitness, 2 stars, 2024-03-12, R06363)
3. "This app can take 1,000 steps before it updates on the watch" (HealthView, 1 stars, 2016-08-25, R13596)
4. "Not super accurate - misses a lot of steps" (Google Fit, 3 stars, 2026-11-16, R32177)
5. "A really poor app that won’t measure steps, distance and calories burned consistently" (Apple Fitness, 1 stars, 2024-12-09, R07546)
6. "Stopped working today, actually takes AWAY steps" (Steps - Activity Tracker, 1 stars, 2017-10-19, R23014)
7. "My Activity App shows highly different steps and calories burned than this app" (ActivityTracker Pedometer, 2 stars, 2020-02-26, R00833)
8. "To add to that the step counts are off in this app" (HealthView, 1 stars, 2023-10-20, R14452)
9. "Counts only steps and time spent, and not distance or calories burned" (Google Fit, 2 stars, 2018-10-16, R28618)
10. "Does not count distance, steps, calories burned currectly" (ActivityTracker Pedometer, 2 stars, 2019-11-24, R25211)

### bugs_stability

1. "Installed, opened it, asks to access HealthKit, I allow, app crashes" (All the Rings, 1 stars, 2023-02-02, R03231)
2. "App installs fine and then crashes as soon as I open it" (All the Rings, 1 stars, 2023-10-11, R03246)
3. "As others have said, after allowing access to health data, app crashes" (All the Rings, 1 stars, 2025-10-17, R03273)
4. "Not worth the time since all the bugs prevent the complications from working" (HealthView, 1 stars, 2020-10-29, R13961)
5. "It crashes after displaying old data every time" (Pedometer++, 1 stars, 2017-11-13, R14885)
6. "Keeps crashing and not counting my steps" (Steps - Activity Tracker, 2 stars, 2019-12-27, R23483)
7. "The Fitness+ app is super buggy and unreliable on my iPad" (Apple Fitness, 3 stars, 2021-11-10, R03375)
8. "Just fix the super big widget bug where some complications don’t show" (Activity Tracker FitnessView, 5 stars, 2026-11-04, R00437)
9. "Used to be a great app, now doesn't work" (Google Fit, 1 stars, 2019-04-16, R28791)
10. "I just wish it wouldn’t crash" (Activity Tracker FitnessView, 3 stars, 2023-01-28, R00152)

### sync_refresh

1. "Your rewards are still not updating correctly" (Apple Fitness, 1 stars, 2024-09-01, R07164)
2. "Expenditure tracking is completely broken since the Google Health sync update" (Cronometer, 1 stars, 2026-10-02, R28199)
3. "The app on my phone and watch just don’t sync or tally right" (HealthView, 2 stars, 2020-10-25, R13957)
4. "However, the app on my watch DOES NOT update" (HealthView, 1 stars, 2016-11-18, R13607)
5. "It’s just that the app is never refreshing unless you’re actively forcing it" (Pedometer++, 2 stars, 2026-03-19, R21700)
6. "I have to open the complication to get it to refresh" (Steps - Activity Tracker, 3 stars, 2025-09-22, R24317)
7. "To see latest heart rate and steps count, i have to refresh healthview manually" (HealthView, 1 stars, 2017-10-03, R13725)
8. "Great app but serious Apple Health sync issue" (Cronometer, 3 stars, 2025-08-21, R12440)
9. "The tracking is delayed if it tracks at all" (Google Fit, 1 stars, 2026-06-05, R30774)
10. "This week, it has stopped syncing to the face" (Pedometer++, 1 stars, 2025-05-09, R21248)

### price_paywall

1. "Features that used to be free now behind paywall" (HealthView, 1 stars, 2022-08-07, R14331)
2. "Now after the update to 3.1 I’ve lost many features to subscription only" (HealthView, 3 stars, 2021-06-28, R14152)
3. "Need to pay for Apple Watch complications" (ActivityTracker Pedometer, 1 stars, 2024-06-04, R01418)
4. "I’d pay $9.99 one time and be done with it" (HealthView, 1 stars, 2021-12-04, R14265)
5. "App keeps forgetting I have made a lifetime purchase of the app" (Activity Tracker FitnessView, 2 stars, 2021-07-16, R00013)
6. "I paid for the lifetime subscription and it’s so worth it" (Calorie Counter - Calory AI, 5 stars, 2024-04-23, R10999)
7. "Maybe having cheaper plans with less features would reel in more subscribers" (Cronometer, 4 stars, 2025-02-01, R12193)
8. "Good app, just wish you could see the total calories burned (without paying)" (Steps - Activity Tracker, 4 stars, 2015-04-21, R22258)
9. "Longtime subscriber, but won’t be for much longer" (Pedometer++, 1 stars, 2023-10-28, R20805)
10. "Less expensive than My Fitness Pal, which I considered" (Calorie Counter - Calory AI, 5 stars, 2025-07-12, R11138)

### workouts

1. "I just cleaned my entire house & the app says 2 exercise minutes" (Apple Fitness, 1 stars, 2025-01-06, R07679)
2. "Checking the workout sections showed that they were no longer listed anywhere" (Apple Fitness, 4 stars, 2023-08-26, R05399)
3. "Did not record all my exercises for last few days" (All the Rings, 1 stars, 2022-06-26, R03213)
4. "Disaster, misses complete workouts, when it does record it is off by miles" (Google Fit, 1 stars, 2026-08-14, R31453)
5. "Can track exercise calories burned too" (Cronometer, 4 stars, 2023-07-26, R11772)
6. "Only thing it needs is exercise tracking" (Calorie Counter - Calory AI, 4 stars, 2021-04-02, R26314)
7. "I wish they made an app for cycling" (Pedometer++, 5 stars, 2019-09-22, R16195)
8. "Therefore it does not import exercise data" (Cronometer, 4 stars, 2021-09-19, R11562)
9. "In the same app it can do workouts with no added fee" (Steps - Activity Tracker, 5 stars, 2026-01-07, R24455)
10. "Workouts are great, needs work elsewhere" (Apple Fitness, 2 stars, 2026-01-20, R08994)

### food_logging

1. "Hoping that there are more food options aside from that of US" (Calorie Counter - Calory AI, 5 stars, 2022-12-01, R10773)
2. "It is the BEST app for tracking food" (Cronometer, 5 stars, 2025-02-21, R12207)
3. "I like the different options of logging in food, especially the barcode scanner" (Cronometer, 5 stars, 2026-09-22, R13305)
4. "The scanner for nutrition facts is awesome but needs to be improved" (Calorie Counter - Calory AI, 5 stars, 2024-07-05, R11029)
5. "The food database is incomplete, and I cannot reliably verify my macros" (Google Fit, 1 stars, 2026-05-27, R30611)
6. "App is useless for tracking food" (Google Fit, 1 stars, 2026-06-05, R30764)
7. "I can not log my meals to keep track of my calories" (Google Fit, 1 stars, 2026-05-30, R30666)
8. "Be more like my fitness pal and let us log foods" (Apple Fitness, 2 stars, 2026-09-05, R09964)
9. "I can’t add calories by meal" (HealthView, 3 stars, 2021-02-13, R14028)
10. "The app also supports UK barcodes and food database which is great" (Calorie Counter - Calory AI, 5 stars, 2021-03-04, R10561)

### ui_design

1. "Why can’t I remove kj/cal tracking" (Apple Fitness, 2 stars, 2023-04-01, R04847)
2. "Setting up up the energy tracker is also severely confusing" (Cronometer, 3 stars, 2022-10-20, R11675)
3. "Why can’t they be displayed larger with better contrasting colours" (Apple Fitness, 4 stars, 2024-02-19, R06231)
4. "The app itself seems buggy and the redesigned UI is a big nope" (Pedometer++, 1 stars, 2026-08-09, R21956)
5. "Learn how to program using different units" (TDEE, 1 stars, 2026-02-09, R24954)
6. "Add the really ugly and confusing UI and there's little reason to use this" (Cronometer, 1 stars, 2025-12-10, R26965)
7. "biggest issue so far is temperature units can't be changed" (Cronometer, 3 stars, 2026-09-03, R27952)
8. "Too many options it is confusing" (HealthView, 2 stars, 2022-06-23, R14321)
9. "I absolutely love the interface and the amount of customization" (HealthView, 5 stars, 2017-01-07, R13637)
10. "Need the ability to customize activity coupling" (Apple Fitness, 1 stars, 2026-06-17, R09621)

### goals_rings

1. "Sometimes the move ring doesn’t record activities" (Apple Fitness, 1 stars, 2026-07-22, R09771)
2. "I saw the activities logged but it rarely showed me closing my rings" (Apple Fitness, 2 stars, 2023-10-13, R05594)
3. "Cant change step goal on apple watch" (Pedometer++, 1 stars, 2023-11-03, R20812)
4. "I have lost a streak over this" (Pedometer++, 3 stars, 2026-09-06, R22005)
5. "I would rather have a step goal" (Apple Fitness, 3 stars, 2026-09-24, R10044)
6. "Make having a Home Screen tile for a goal optional" (Activity Tracker FitnessView, 3 stars, 2023-09-27, R00196)
7. "It was my favorite, but now it doesn’t show any ring data at all" (All the Rings, 1 stars, 2024-09-21, R03261)
8. "Perfect, but would love streak-specific widgets" (All the Rings, 5 stars, 2022-02-23, R03206)
9. "This all translates into calories burned which is the only way to set goals" (Apple Fitness, 3 stars, 2025-05-09, R08206)
10. "In fact I don't see any way of editing my goals anymore" (Google Fit, 1 stars, 2021-08-14, R29125)

### total_vs_active

1. "The app keeps duplicating my Active Energy balance" (Cronometer, 3 stars, 2025-08-21, R12440)
2. "I wish that the app showed total calories burned for the day" (ActivityTracker Pedometer, 4 stars, 2017-05-16, R00531)
3. "App is taking whole calories from a day not active calories as it should" (Apple Fitness, 1 stars, 2022-10-06, R04025)
4. "Also consider showing active calories along with total calories" (Pedometer++, 5 stars, 2019-11-09, R16313)
5. "Why are total calories so hard to read" (Apple Fitness, 4 stars, 2024-02-19, R06231)
6. "It still logs all my activities, but the active calories don't update" (Apple Fitness, 1 stars, 2026-08-14, R09873)
7. "PHONE APP: Very nice, but Resting Energy isn't supported" (HealthView, 2 stars, 2016-07-04, R13585)
8. "How do I look my number for Active Calories burnt for a whole month" (Apple Fitness, 4 stars, 2024-02-08, R06159)
9. "Good app, just wish you could see the total calories burned (without paying)" (Steps - Activity Tracker, 4 stars, 2015-04-21, R22258)
10. "The app doesnt show total calories on the watch" (Apple Fitness, 1 stars, 2025-05-17, R08226)

### calorie_accuracy

1. "The calories burned each day are so different day to day it’s astounding" (Apple Fitness, 3 stars, 2026-04-13, R09312)
2. "Fairly Accurate On Steps, Horrifically Inaccurate In Calorie Count" (Apple Fitness, 3 stars, 2025-10-24, R08691)
3. "Calorie count is off by at least half" (Google Fit, 2 stars, 2018-09-20, R28556)
4. "The calorie count is way off base" (ActivityTracker Pedometer, 4 stars, 2019-11-17, R00791)
5. "The recent update caused the time, distance, and calorie data to be wildly inaccurate" (Apple Fitness, 1 stars, 2026-11-02, R10264)
6. "The problem is, the calories it exports to Fitbit seem to double or triple" (Cronometer, 2 stars, 2022-04-29, R11632)
7. "It sometimes doubles the dietary calories rather than take the information as is" (HealthView, 2 stars, 2018-11-03, R13793)
8. "It now adds back exercise calories even after I tuned that off" (Cronometer, 3 stars, 2026-09-09, R28011)
9. "Highly inaccurate in terms of calories burnt per step" (Google Fit, 2 stars, 2019-02-16, R28743)
10. "Great app but Kcal count is wrong" (Cronometer, 2 stars, 2022-12-30, R11697)

### widgets_complications

1. "Unfortunately the Apple Watch complication is broken since the newest update" (Pedometer++, 1 stars, 2023-10-29, R20807)
2. "I am frustrated that the widgets are never accurate, so far" (Steps - Activity Tracker, 2 stars, 2024-06-28, R24100)
3. "The step complication doesn't seem to update very often, if at all" (Steps - Activity Tracker, 3 stars, 2025-12-26, R24438)
4. "The lock screen widget no longer works" (ActivityTracker Pedometer, 1 stars, 2025-07-11, R01879)
5. "Especially love the complications and multitude of configurations" (Activity Tracker FitnessView, 5 stars, 2022-09-29, R00129)
6. "I'd happily replace the Total Calories complication with Net Deficit" (Total Calories (reference), 5 stars, 2026-07-20, R24957)
7. "Please kindly add the widget showing step count on lock screen" (Apple Fitness, 4 stars, 2026-08-30, R09942)
8. "Some today’s update there’s no ability to see steps on the lock screen" (Pedometer++, 1 stars, 2026-02-10, R21641)
9. "Also, steps on watch complication inexplicably changed to miles" (HealthView, 3 stars, 2016-12-23, R13618)
10. "Please add water complication for Watch" (Calorie Counter - Calory AI, 5 stars, 2022-06-20, R10697)

### deficit_net

1. "My only complaint is that they don't track calories burned or net calories" (Calorie Counter - Calory AI, 4 stars, 2022-07-12, R26391)
2. "Great app, but no ability to add calories burned" (Calorie Counter - Calory AI, 4 stars, 2021-07-10, R26330)
3. "I turned on “account for exercise” and it wouldn’t account for burned calories" (Calorie Counter - Calory AI, 4 stars, 2022-10-14, R10751)
4. "Deficit actually adding the intake and burn calories up instead of counting the balance" (Activity Tracker FitnessView, 3 stars, 2022-07-16, R00115)
5. "if it was able to calculate/display Net Calories" (HealthView, 4 stars, 2019-04-15, R13823)
6. "compare my total calories burnt against my total calories intake at a glance" (HealthView, 5 stars, 2018-10-11, R13784)
7. "total calories burned for the day vs dietary calories consumed" (HealthView, 4 stars, 2019-06-13, R13832)
8. "it had a burned calories thing and then have the net calories after that" (Calorie Counter - Calory AI, 4 stars, 2023-12-04, R10938)
9. "Net Deficit (burned − eaten)" (Total Calories (reference), 5 stars, 2026-07-20, R24957)
10. "I don’t know how add burned calories" (Calorie Counter - Calory AI, 4 stars, 2023-07-27, R10887)

### tdee_bmr

1. "told me that I need almost 8000 calories a day" (TDEE, 1 stars, 2023-04-10, R24949)
2. "gave me a full spreadsheet of my maintenance calories, deficit and surplus" (TDEE, 5 stars, 2026-07-14, R24955)
3. "Input your BMR into the app and your burnt calories are effortlessly tracked" (Cronometer, 3 stars, 2024-01-15, R11869)
4. "BMR results are obstructed by Ad placement & there is no method to scroll" (TDEE, 1 stars, 2019-08-30, R24934)
5. "Put my details in to calculate TDEE" (TDEE, 2 stars, 2019-01-22, R24931)
6. "the way I use it is by only considering the (BMR) and the (TEF)" (Cronometer, 5 stars, 2025-01-20, R12179)
7. "have it calculate my BMR from Apple Health stats" (Cronometer, 4 stars, 2020-06-29, R11475)
8. "cronometer adds the full bmr calorie burn on top of what it already estimates" (Cronometer, 4 stars, 2026-05-28, R27004)
9. "There is a learning curve with the energy settings and macro" (Cronometer, 5 stars, 2024-11-12, R12108)
10. "BMR sometimesly sinply disappears" (Google Fit, 3 stars, 2019-03-08, R28761)

