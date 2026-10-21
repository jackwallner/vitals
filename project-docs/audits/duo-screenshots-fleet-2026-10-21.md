# Fleet audit: APP_IPHONE_DUO screenshot sets (2026-10-21)

Read-only. Nothing was uploaded, deleted or changed in App Store Connect or any repo.

## Method

- Shared ASC key, serial requests with backoff on 429. All 35 apps in the account scanned, newest iOS version of each, every localization, every screenshot set whose display type contains DUO.
- Every Duo shot downloaded (61 files) and viewed, next to the same app's live `APP_IPHONE_67` set for style.
- App code grepped for `horizontalSizeClass`, `reservedRegions`, `NavigationSplitView`, `ViewThatFits`, `.sidebarAdaptable`.
- Raw data and downloads: `/private/tmp/claude-501/-Users-jackwallner-vitals/8d2440cb-1246-4768-b764-d97811f774d5/scratchpad/` (`data/scan.json`, `shots/<app>/<locale>/NN.png`, `sheets/`, `iph/`).

## Result

Five apps have a Duo set, the four from the earlier scan plus Vitals. The other 30 have none (Skat, Baseball/Hockey/Football/Basketball StatScout, Pickleball, Sheepshead, Cribbage, Baby Tracker, Deep Cuts, Plain Launcher, Recharge, IM Tri, Little Gestures, Sunset, Shoes On, Fitness Habit, Migraine, Trip Comfort, Sports Cheat Sheet, Desk Reset, Electrician, DreamCart, VO2 Max, Elderhub, Simple GLP, Quit Zyn, Sober, Next Cue, Baby Docs).

Three of the four older sets are the same thing: the folded outer display (466x678 pt, portrait, with the Duo side bar showing 9:41 and a back chevron) dropped into a portrait device outline. None pitches the unfolded display. Mahj's commit message says so outright: "outer display, same 8 frames as 6.9-inch".

| App | Version, state | Shots | Verdict | Problems (shot index) | Fix |
|---|---|---|---|---|---|
| Vitals (Total Calories) | 1.9.0, WAITING_FOR_REVIEW | 5 (en-US) | good | 2-4: floating tab pill overlaps the bottom of the steps and deficit card in the Today pane. 1 and 5 show an "Upgrade" lock tab, 2-4 show "Vitals+"; mixed states in one set. Shot 5 is the only folded frame. | reshoot only, optional polish (pick one tab state, nudge the pill). In review, so any change means pulling it. |
| Bridge Trainer | 1.2.5, PREPARE_FOR_SUBMISSION | 7 (en-US) | folded-only | All 7 are folded outer-display captures in a portrait outline; no unfolded or two-pane frame. 2-7: content is cut mid-row at the bottom of the frame, with the side bar chrome floating beside it. Headlines are bold condensed, while the live iPhone set uses light serif, so the style does not match. Shots 1 and 5 are onboarding and a mid-drill question, weak as a Duo pitch. | needs a real unfolded layout first, then reshoot. Until then, pull the Duo set. Draft version, so no review impact. |
| Vehicle Maintenance Log | 1.0, REJECTED | 7 (en-US) | folded-only | All 7 folded. 2: ghost of the previous screen showing through the nav bar (transition frame). 4: service-record PDF is unreadably small, with a clipped "Done" header. 5 and 6: modal sheets with clipped "Done" header, not the app's main surfaces. 1: "The Wallner garage" is a personal name on the hero shot. Style does match the live iPhone set (same headlines). Count equals the iPhone set (7), so it is a pure re-render. | needs a real unfolded layout first, then reshoot; pull the Duo set meanwhile. Rejection reason not checked (needs Resolution Center, not the API), so confirm it is not screenshots before resubmitting. |
| E3 Fitness | 1.0, PREPARE_FOR_SUBMISSION | 10 (en-US): 6 folded, 4 unfolded | mixed, broken as a set | 1-6: folded frames in the house style (match iPhone set). 7-10: raw unfolded captures at 2853x2007 landscape, no headline, no frame, no gradient, a different size from 1-6 and unlike every other shot. 7-10: system sidebar clipped at the bottom ("Account" cut off), floating Home/Training pill sits over the right margin. 10 shots against 6 on iPhone; 1-6 are the iPhone set re-rendered. | reshoot only: keep 7-10 and render them into the same headline and landscape frame as Vitals' set (drop the pill overlap), drop 1-6 except one folded glance frame. Unfolded view exists but is the system's default, see code. |
| Mahj Trainer | 1.4.1, WAITING_FOR_REVIEW | 8 per locale, 4 locales (en-US, vi, es-MX, id) = 32 | folded-only | 32 is 4 x 8, not filler, but all 32 are the iPhone 6.7-inch set re-framed (same 8 screens, same headlines, localized headline over English UI). No unfolded frame. 3 and 4: large empty band above and below the card (Keep or Throw, Play a Hand). 2: top row of tiles clipped. Style matches the live iPhone set. | reshoot only, or needs unfolded layout first for an honest pitch. **In WAITING_FOR_REVIEW: any change means pulling it from review. Not touched.** Recommendation: leave it, ship 1.4.1, fix in the next version. |

## Code check

| App (repo) | Regular-width or unfolded layout | Honest Duo pitch possible today? |
|---|---|---|
| Vitals (`~/vitals`) | Yes, built for Duo: `UnfoldedSplit.swift`, `reservedRegions(.division)` | Yes, already shipped in 1.9.0 |
| Bridge (`~/bridge`) | `HomeView.swift` only: `horizontalSizeClass == .regular` makes Today and Rooms two columns and a tile grid, width capped by `Theme.wideContentWidth`. Drills use `CenteringScrollView` and readable-width caps (iPad rules in `.claude/rules/ipad-layout.md`). No `reservedRegions`, no split view. Branch `shift/shift-duo-bridge-1-1792494475` has no Duo layout code either (grep clean). | Partly. Home is a real wide layout, everything else is a capped single column. A fold-aware Home plus Rooms-beside-drill pane needs app work. |
| Vehicle (`~/keyring`) | None. Only two `ViewThatFits`. | No. Needs app work before any unfolded shot. |
| E3 Fitness (`~/elsa-fitness-website/ios`) | None written. `TabView` of `NavigationStack`s, with a `List` of `NavigationLink`s in `ClientTrainingRootView`. The sidebar plus detail in shots 7-10 is the OS adapting that stack at regular width. | Yes in the narrow sense (the unfolded shots are real), but it is the system default, not a designed layout. |
| Mahj (`~/mahj`) | Same as Bridge: `HomeView.swift` regular-width columns and grid, `ViewThatFits` elsewhere. No fold awareness. | Same as Bridge: partly. |

## Summary of fixes

- keep as is: none strictly, Vitals closest.
- reshoot only: Vitals (optional polish), E3 Fitness, Mahj (blocked by review).
- needs a real unfolded layout first, then reshoot: Bridge, Vehicle.
- pull the Duo set (until the above lands): Bridge, Vehicle. Both are in editable states, so no review cost.

Cross-fleet pattern: the old pipeline outputs the outer display in a portrait frame, which is the layout every compact phone already has, so it adds nothing over the iPhone set. The only genuine unfolded pitches are Vitals 1-4 and E3 7-10. `~/ios/duo/prompt.md` already holds a per-app brief for adding Duo support, with a budget of 6 gh-sim jobs; that is the route for Bridge and Vehicle.
