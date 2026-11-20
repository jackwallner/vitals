# Competitor reviews: what calories-burned and activity app users complain about and ask for

2026-11-20. 33,994 reviews and web notes on 13 apps that share Total Calories' searchers, ranked against Total Calories. 4,085 of them were read and tagged one by one (the decision sample); the rest carry keyword-rule tags. Rows: [2026-11-20-competitor-reviews.tsv](2026-11-20-competitor-reviews.tsv). Pull method, pricing, keyword counts and the full ask list: [2026-11-20-competitor-reviews-pull-notes.md](2026-11-20-competitor-reviews-pull-notes.md).

## Bottom line

- The category's loudest complaints are about numbers people can't trust or can't see in time: crashes and lost data, wrong step and calorie counts, and widgets or complications that only update when the app is opened. Total Calories reads Apple Health rather than counting, so most accuracy complaints land on Apple, not on it. Stale widgets do apply to it, and the code has a known bug that causes them (below).
- Paywall anger is the third-biggest theme, mostly at apps that moved free features behind a subscription (HealthView) or charged more than they advertised. Total Calories' free core plus a lifetime option is the answer users ask for. Its listing says so only in the description.
- The ask Total Calories exists for shows up across every competitor: total (active plus resting) calories on the watch, burn shown next to steps in pedometers, and burned calories offset against food in calorie counters. 124 decision-sample rows ask for something Total Calories already does.
- The two clear gaps in the code are a kJ (kilojoule) unit and weekly or rest-day-friendly goals. Both are small, and both have direct asks.
- Total Calories' own paying reviewer (5★, 2026-07) asked for a Net Deficit complication. It has existed since April as "Net Calories". The listing never mentions it.

## Competitors and why each made the list

Picked by their rank in US App Store search (iTunes Search API, top 25, 29 terms Total Calories ranks for or targets). Food loggers fill most of those results; only Cronometer and Calory were kept, because they rank top 5 for the burn terms themselves.

| App | Why | App Store rows | Play rows | 1-3★ share | US ratings (avg) |
|---|---|---|---|---|---|
| ActivityTracker Pedometer | #1 "calories burned" and "calories burned tracker", #7 "calories burned widget", #8 "activity rings" | 2,634 | 1,070 | 8% (Play 31%) | 102,914 (4.8) |
| Steps - Activity Tracker | "active calories" #10, "step counter widget" #6, "activity rings" #12 | 2,771 | 0 | 29% | 136,211 (4.8) |
| HealthView | "health widget" #1, "calorie complication" #7, "apple watch calories" #8 | 1,062 | not on Play | 65% | 14,413 (4.5) |
| Activity Tracker FitnessView | "activity rings" #5, "move ring" #9, widgets | 515 | 9 | 42% | 8,084 (4.6) |
| Calorie Counter - Calory AI | in the top 25 for 13 of the 29 terms; #2 "calorie widget" and "calories burned widget" | 986 | 373 | 38% | 8,154 (4.6) |
| Cronometer | the one big food logger near the top for burn terms: #1 "maintenance calories", #2 "resting calories" and "net calories", #4 "active calories" | 2,229 | 1,861 | 29% | 101,019 (4.8) |
| All the Rings | "move ring" #2, "activity rings" #7 | 126 | not on Play | 67% | 1,515 (4.6) |
| TDEE (Apperitif) | #1 "tdee" | 28 | 0 | 75% | 505 (4.7) |
| Pedometer++ | #1 "pedometer"; Total Calories targets steps and pedometer | 7,524 | not on Play | 23% | 185,590 (4.8) |
| Apple Fitness | #1 "activity rings" and "move ring"; its active-only Move number is what Total Calories corrects | 7,081 | n/a | 82% | 11,701 (2.9) |
| Google Fit, iTECH Wearables, Calorie Burn Plan | Play's top non-food-logger results for "active calories" and "total calories burned" (Android port context) | n/a | 3,656 / 1,743 / 268 | 76% / 50% / 14% | Play 688,069 / 61,418 / 2,833 |
| Total Calories (reference) | | 2 | | | 12 (4.7) |
| Web | Apple Community, MacRumors, Garmin and Cronometer forums, MacStories | | | 56 notes | |

Sources and method:
- **App Store:** customer-reviews RSS, newest and most helpful, 20 storefronts: 10 English (us gb ca au nz ie za in sg ph) plus Total Calories' top non-English proceeds markets (de es fr it ch hk tw jp pl nl). The feed caps at 500 per sort per storefront; 44 of 440 feeds hit the cap (Pedometer++, Apple Fitness, Steps, ActivityTracker, Cronometer US).
- **Google Play:** google-play-scraper, us gb ca au in de, newest 1,500 plus most relevant 500. English countries return the same reviews, so nearly all Play rows count as US.
- **Web:** 56 notes from search excerpts (Apple Community pages are script shells and could not be read directly). Weak, one vote each.
- **Not covered:** Reddit (old.reddit 403, mirror 429). Version history past the current release (apps.apple.com loads it from an API that needs a web token).
- **Tagging:** 11,724 four- and five-star rows with no complaint or request words were auto-tagged as general praise. The decision sample (4,085 rows) was read one by one by Sonnet: every 2024+ complaint, ask or mixed review for the eight close competitors, a seeded random 300 each from Apple Fitness, Cronometer, Google Fit and Pedometer++ (150 iTECH), and 1,091 earlier rows on widget, complication and calorie wording. The other 18,185 rows have keyword-rule tags, which matched the hand tags only 53% of the time, so the ranking below uses the decision sample only. My own 14-row spot check of the hand tags agreed on every row. The TSV's `tag_method` column says which rows are which.
- **Caveats:** this is a 2024+ view weighted toward the close competitors, not market share. Apple Fitness and Google Fit reviews are mostly about Fitness+ classes and Fitbit migration, which inflates workouts and platform. Long reviews were tagged from their first 200 to 320 characters, so a late ask can be missing.

## Themes ranked

Decision sample only (4,085 rows). Score = sum of intensity (1 to 3) over negative or mixed mentions. Asks = reviews requesting something missing. Status is explained in the next section.

| # | Theme | Mentions | Neg/mixed | Strong (3) | Asks | Score | Mostly from | Total Calories |
|---|---|---|---|---|---|---|---|---|
| 1 | Bugs and stability (crashes, lost history, vanished app) | 919 | 877 | 348 | 114 | 1,980 | iTECH, Steps | covered by design |
| 2 | Step and distance accuracy | 1,054 | 790 | 257 | 133 | 1,617 | Steps, Google Fit | n/a (reads Health) |
| 3 | Price and paywall | 640 | 478 | 232 | 81 | 1,119 | Calory, HealthView | covered, under-marketed |
| 4 | Sync and refresh (stale widgets, complications, data) | 431 | 391 | 112 | 54 | 828 | Pedometer++, Google Fit | partly: known bug |
| 5 | Widgets and complications | 511 | 397 | 93 | 147 | 810 | Pedometer++, iTECH | covered, tinted mode unchecked |
| 6 | Watch app (breaks after updates, old watches dropped) | 428 | 369 | 120 | 97 | 762 | Pedometer++, iTECH | partly |
| 7 | Platform (Android, iPad, Garmin, Fitbit) | 440 | 344 | 134 | 94 | 741 | Google Fit, Apple Fitness | covered, not marketed |
| 8 | UI and design (incl. units) | 580 | 372 | 88 | 221 | 675 | Apple Fitness, Calory | gap on kJ |
| 9 | Workouts *(outside direction)* | 413 | 326 | 86 | 190 | 619 | Apple Fitness, Google Fit | n/a |
| 10 | Calorie accuracy | 257 | 216 | 80 | 43 | 467 | Apple Fitness, Google Fit | partly |
| 11 | Goals and rings (rest days, streaks, weekly goals) | 366 | 235 | 50 | 106 | 462 | Apple Fitness | partly |
| 12 | Food logging *(outside direction)* | 454 | 191 | 47 | 129 | 332 | Calory, Cronometer | n/a; net covered |
| 13 | Ads | 187 | 143 | 66 | 12 | 319 | Cronometer, Calory | covered (no ads) |
| 14 | History and trends | 227 | 149 | 39 | 73 | 290 | Steps, Google Fit | covered |
| 15 | Developer support | 144 | 109 | 70 | 8 | 280 | Steps, HealthView | covered |
| 16 | Privacy and account | 97 | 95 | 61 | 13 | 242 | Calory, iTECH | covered (no account) |
| 17 | Total vs active calories | 96 | 61 | 9 | 50 | 104 | Apple Fitness, Apple Community | covered (the core) |
| 18 | Localization | 75 | 63 | 9 | 56 | 104 | Apple Fitness | covered (36 languages) |
| 19 | Notifications | 78 | 47 | 15 | 28 | 92 | iTECH, Apple Fitness | covered |
| 20 | Net calories and deficit | 57 | 27 | 3 | 30 | 44 | Calory, FitnessView | covered (Vitals+) |
| 21 | TDEE and BMR | 23 | 15 | 6 | 6 | 32 | TDEE | covered |

Keyword counts across all 33,994 rows (any sentiment): widget 568, complication 285, watch face 252, burned 272, burnt 89 (GB 20, IN 20, AU 8: British and Indian users write "burnt"), calorie counter 106 (mostly about food loggers), total calories 61, resting 40, active calories 30, kJ or kilojoule 16 (10 from Australia), Garmin, Fitbit, Oura or Whoop 1,073, subscription 842, lifetime or one-time 233, ads 946.

### Quotes (under 15 words)

1. **Bugs:** "For no reason all my previous records are gone." (1★ Pedometer++, 2024-08); "Two days of walking since the upgrade not one step counted." (1★ Steps, 2024-04)
2. **Steps:** "My watch shows 6,000+ steps and the app only records 1,400." (1★ Steps, 2026-07)
3. **Price:** "Features that used to be free now behind paywall" (1★ HealthView, 2022-08); "advertise in the app for “$5.99 Annually” but charge $59.99" (1★ HealthView, 2024-09)
4. **Sync and refresh:** "you have to open the app for the widget to refresh" (3★ Pedometer++, 2025-10); "I have to open the complication to get it to refresh" (3★ Steps, 2025-09)
5. **Widgets:** "the widgets are blank when I use monochrome tint" (1★ HealthView, 2024-09); "Pls add Lock Screen widget support" (4★ HealthView, 2024-05)
6. **Watch app:** "Updated the app and now it no longer works with my Apple watch." (1★ Pedometer++, 2025-10)
7. **Units:** "Why can’t I remove kj/cal tracking" (2★ Apple Fitness, 2023-04); a Cronometer reviewer can't use the app without kilojoules (R11431)
8. **Calorie accuracy:** "I have burned 838 calories whilst on fitness app only showing 354" (2★ Apple Fitness, 2026-01)
9. **Goals:** "You should be able to set your own end of day" (3★ Apple Fitness, 2025-09); a 94-day streak lost on vacation by 2 calories (R05338)
10. **Total vs active:** "I wish that the app showed total calories burned for the day" (4★ ActivityTracker); "good app, just wish you could see the total calories burned (without paying)" (4★ Steps)
11. **Net:** "Great app just wish there was a way to remove calories" (5★ Calory, 2026-10); Total Calories' own reviewer: "The one complication I'm really missing is Net Deficit" (5★, 2026-07)

## Where Total Calories stands on each top theme

Checked against `main` at `cc62681` (origin fetched 2026-11-20).

- **Bugs and stability: covered by design.** History lives in Apple Health, so a reinstall or update can't lose it, which is the strongest 1-star driver at Pedometer++ and Steps. No account, no server.
- **Step and distance accuracy: not Total Calories' problem.** It reads Apple Health's steps rather than counting, so its number matches the Health app. The manual step entry asks belong in Health, which already allows it.
- **Price and paywall: covered, under-marketed.** Complications, widgets, Today and History are free with no expiry; Vitals+ has a lifetime option ($59.99 US). That answers the category's asks (lifetime 233 mentions, "total calories without paying"). The subtitle and promo text don't say "free" or "lifetime". The rule worth keeping: never move a free feature behind Vitals+, since that is exactly what made HealthView 65% 1-3★.
- **Sync and refresh: partly, with a known bug.** Background delivery is hourly and widget timelines reload hourly (`VitalsWidget.swift:44`, `WatchComplication.swift:130`). On iOS the observer calls `completionHandler()` before running `refreshCache()` (`HealthKitService.swift:730`), so iOS can suspend the app before the cache write and widget reload happen. The 2026-11-20 bug catalog lists this as medium. This is the exact failure competitors' users complain about.
- **Widgets and complications: covered.** Small, medium and large Home Screen widgets, Lock Screen circular and rectangular, a Maintenance (TDEE) widget, and Calories, Steps and Net Calories complications in all four watch families. Only a few views use `.widgetAccentable()`, and nothing checks `widgetRenderingMode`, so tinted and clear iOS 26 widgets are unverified; HealthView's blank tinted widgets drew 1-stars.
- **Watch app: partly.** watchOS 10+. The Pedometer++ lesson: a complication that disappears after a watchOS update is a 1-star. Nothing in the release checklist checks complications on a watchOS beta.
- **Platform: covered, not marketed.** Anything that writes to Apple Health counts (Garmin, Oura, Whoop, Fitbit through a sync app); there is an Android port on Health Connect, plus iPad and Duo layouts. The listing never names Garmin or Oura, and 1,073 rows mention those brands.
- **UI and units: gap on kJ.** No kilojoule option anywhere in the code; every value is kcal. 10 of 16 kJ mentions are Australian, and Australia is an English storefront Total Calories sells in.
- **Calorie accuracy: partly.** Totals use `HKStatisticsCollectionQuery` with `.cumulativeSum`, so Health removes double counting across sources (Cronometer's "duplicating my Active Energy" can't happen). What it can't fix is a source that writes no resting energy: then the total looks too low, and nothing tells the user why (a Garmin forum note says Garmin resting calories weren't syncing to Health; HealthView reviewers complain resting energy was missing).
- **Goals and rings: partly.** Excluded Days and a running pause (Vitals+) take sick days out of averages and keep streaks intact, which is what the "forgiveness" asks want. Missing: weekly goals (the most common goals ask, and ActivityTracker is praised for one), and a custom end of day (one or two asks, night shifts).
- **Total vs active, net, TDEE: covered.** These are the core. The Net Calories complication exists (since build 19, 2026-04-14), but a paying user didn't find it three months later, and the description doesn't mention it.
- **Ads, privacy, support, notifications, history, localization: covered.** No ads, no account, in-app feedback, a free goal-reached alert, 7D to 1Y history with CSV, 36 languages.

## Demand outside the current direction

| Theme | Mentions | Notes |
|---|---|---|
| Workouts | 413 | Mostly Apple Fitness (missing workout types, adding a workout after the fact) and Google Fit. Total Calories counts workout burn through Health already. |
| Food logging | 454 | Mostly Calory and Cronometer. Their top ask is a way to log or import burned calories and see the net, which Total Calories' Net Deficit already does for anyone who logs food elsewhere. |
| Manual burn entry | ~20 asks | Calory users want a minus button for exercise calories. Total Calories is read-only by design; Health takes manual entries. |

Shipping signals (current releases): ActivityTracker 4.4 (Nov 5) and Pedometer++ 8.2.1 (Oct 23) added iPhone Duo support; FitnessView 3.3 (Oct 29) added Duo layouts and Liquid Glass rings; HealthView 4.3 added Siri for any health stat; Calory 5.2.8 (Nov 6) improved iPad. Total Calories already has Duo, iPad and Siri. All the Rings hasn't shipped since 2022 and is crashing on launch, so its "move ring" searchers are up for grabs.

## Opportunities for Total Calories, best first

Effort: S = days, M = 1 to 2 weeks, L = 3+ weeks.

1. **Make widgets and complications stay current without opening the app (S).** *Evidence:* sync and refresh ranks 4th (391 negative), widgets 5th; "you have to open the app for the widget to refresh" recurs at Pedometer++, HealthView and Steps. *Build:* run `refreshCache()` and the widget reload before calling the observer's `completionHandler()` on iOS (inside a background task with a time limit), then measure on a real phone how stale the widget gets over a day with the app closed. Test `.immediate` delivery for active energy where HealthKit allows it. *Why first:* it's a known bug, it's cheap, and it's the failure that would cost a burn tracker its ratings.

2. **Weekly goals that allow rest days (M).** *Evidence:* the top goals asks are weekly goals and rest days (R07158, R07222, R07482), streak forgiveness (R05338, R21088), and ActivityTracker praise for a weekly goal that doesn't break a streak on a missed day (R01921). *Build:* an optional weekly calorie and step goal (sum of 7 days) with its own ring on Today and a widget option. Excluded Days already keeps streaks intact. Free or Vitals+ is Jack's call; the weekly ring fits Vitals+ next to streaks.

3. **kJ units, and the Australian keywords (S).** *Evidence:* 16 kJ mentions, 10 from Australia; "cannot use otherwise" (Cronometer). *Build:* an Energy unit setting (kcal or kJ, defaulting to kJ in Australia and New Zealand) applied to every number, widget and complication. Then add `kilojoules` and `kj` to the en-AU keyword field.

4. **Put the Net Calories complication and "works with your food app" in front of people (S).** *Evidence:* Total Calories' own paying reviewer asked for a complication that already exists. Calory has 38 net-calories asks; Cronometer users want "calories eaten and calories burned" in one view. *Build:* name the Net Calories complication in the description and on a screenshot, show it in the Vitals+ trial pitch for users who answered that they log food, and add a one-time Today tip pointing to it.

5. **Explain a missing resting burn (S).** *Evidence:* Garmin and other trackers sometimes write no resting energy to Health; HealthView reviewers complain resting is missing; 10 Garmin asks, 5 Fitbit, 1 Oura. *Build:* when a finished day has active energy but zero resting energy, show one line on Today and History saying no resting energy came from Apple Health and which app should write it. Add "Works with Garmin, Oura, Whoop and Fitbit through Apple Health" to the description.

6. **Check every complication and widget on each watchOS and iOS beta, including tinted and clear modes (S).** *Evidence:* watch app ranks 6th; Pedometer++ 1-stars after updates ("no longer works with my Apple watch"); HealthView's blank widgets in monochrome tint. *Build:* add complication and tinted-widget captures to the release check (the iOS 27 beta device exists), and fix any view that goes blank in accented rendering.

7. **Say "free" and "lifetime" where searchers see it (S, listing only).** *Evidence:* price is the 3rd theme (478 negative); "total calories burned (without paying)" (Steps), "I'd pay $9.99 one time and be done with it" (HealthView). *Build:* promo text and screenshot 1 lead with free complications and widgets, no account; the paywall screenshot shows the lifetime plan. Keep the no-moved-features rule in writing.

8. **Win the "move ring" searchers All the Rings is losing (S, listing).** *Evidence:* All the Rings ranks #2 for "move ring" with 1-stars for crashing on launch since 2023 and no release since 2022. *Build:* a screenshot caption and keyword test around the Move ring counting only active calories, the question behind 18 of the 56 web notes, 10 of them asking for total calories on the watch.

## Listing wording users use that the listing lacks

- **"burnt"**: 89 rows, half from GB, India and Australia. en-GB and en-AU keyword fields have `burned` but not `burnt` (the description has it, but descriptions aren't indexed).
- **"kilojoules" / "kJ"**: Australian users; absent from every field and from the app.
- **"Net Calories complication"**, **"watch face"**: in reviews and Apple Community asks; the description says "complications" but never names the Net Calories one.
- **"Garmin", "Oura", "Fitbit"**: 1,073 mentions; never named. A description line is safe, and a brand name in keywords is not (App Review 2.3.7).
- **"total calories on Apple Watch"**: the most common Apple Community question (10 web asks, 18 notes). The listing already says it; it's the strongest message to keep in the subtitle and screenshot 1.

**For the pending non-English title rename (calorie counter words to burn words):** these reviews back it. Users of burn and activity apps describe the number with burn or consumption words, almost never counter words: German Kalorienverbrauch 29 and verbrannt 21 against Kalorienzähler 1; French dépense 24 and brûlées 19; Italian bruciate 12 against contacalorie 0; Japanese 消費カロリー 16. In English, "calorie counter" (106) is nearly always about a food logger. The caveat: reviews show how people talk, not what they type into search, and counter terms have far more search volume. So the localization session's split holds: burn words in the name, counter words kept in the keyword field.

## Follow-ups not done here

- Reddit (r/AppleWatch, r/loseit, r/CICO) needs a Reddit API key or a signed-in export.
- Version history beyond each app's current release needs an apps.apple.com web token or a browser pull.
