# ASO keyword strategy — Total Calories (US)

**Data snapshot:** 2026-05-25 · Astro MCP · 55 keywords tracked

## The mix (popularity vs difficulty vs your rank)

Apple search is not one game. Use three buckets:

| Bucket | Meaning | Your action |
|--------|---------|-------------|
| **Attack** | You rank **&lt;100** OR climbing fast · relevance high | Subtitle, screenshot #1–3, description opener |
| **Siege** | Stuck **1000** but **popularity ≥50** · hard but huge (`widget`, `ring`, `watch`) | Keyword field + visuals; expect months |
| **Ignore** | 1000 + low pop OR wrong topic | Remove from Astro |

### Attack (optimize now)

| Keyword | Rank | Pop | Diff | Notes |
|---------|------|-----|------|-------|
| total calories | 1 | 5 | 69 | Defend via **app name** — do not rename |
| daily burn | 57 | 21 | 64 | **Best growth** (+19) — lead marketing here |
| daily calorie burn | 3 | 5 | 51 | **Immediate win** — use in description (added 2026-05-25) |
| watch face calories | 141 | 5 | 68 | Climbing target — Watch screenshot #1 |
| burned calories | 22 | 5 | 44 | Strong; align copy |
| watch calories | 20 | 5 | 73 | Watch-first story |
| widget calories | 42 | 5 | 60 | Widget + calories combo |
| apple watch calories | 42 | 5 | 72 | Same cluster |
| tdee | 86 | 13 | 46 | Niche; keep TDEE/BMR in keyword field |
| kcal | 95 | 15 | 70 | Subtitle already has Kcal |
| active calories | 72 | 5 | 56 | Vitals+ angle |
| calories burned | 62 | 5 | 57 | Phrase in description |

### Siege (keyword field + screenshots; patience)

| Keyword | Rank | Pop | Diff | Notes |
|---------|------|-----|------|-------|
| widget | 1000 | 70 | 83 | #1 volume opportunity · not in subtitle → **must stay in keyword field** |
| ring | 1000 | 77 | 79 | Move/activity ring searches |
| watch | 1000 | 66 | 64 | In subtitle already — don’t duplicate in field |
| calorie tracker | 1000 | 74 | 80 | Very competitive · siege only |
| health | 1000 | 68 | 79 | Too generic |
| pedometer | 1000 | 55 | 78 | Fits steps · keep in field |
| fasting | 1000 | 58 | 70 | Adjacent (you have fasting in field) |

### Ignore / remove from Astro

`headache tracker`, `headache migraine diary`, `headache diary`, `headache`, `pain tracker`, `seguimiento de pasos`, `calculer calories par jour`, `дневник`

---

## Recommended App Store Connect copy

### Name (30 chars) — no change

`Total Calories - Daily Tracker`

### Subtitle (30 chars) — **recommended change**

**Current:** `Watch Step Count & Burned Kcal`  
**Proposed:** `Daily Burn on Watch & Widget`

Why: Surfaces your fastest-climbing term (**daily burn**) plus two siege terms (**watch**, **widget**) without repeating the app name. Steps/kcal still covered in description + keywords.

Alternate if you prefer steps emphasis: `Calories Burned · Watch Widget` (30 chars)

### Keyword field (100 chars) — **recommended change**

**Current (wastes space on subtitle duplicates `watch`, `kcal`):**

`pedometer,activity,widget,watch,ring,TDEE,BMR,walking,burn,complication,kcal,fast,fasting,health,all`

**Proposed (97 chars):**

```
pedometer,widget,ring,TDEE,BMR,burn,complication,deficit,resting,active,pace,fasting,walking,move
```

| Token | Role |
|-------|------|
| widget, ring, pedometer, move | Siege high-volume searches |
| TDEE, BMR, burn, fasting | Attack + niche metabolism |
| complication | Watch face niche |
| deficit, resting, active | Vitals+ / ranking cluster |
| pace | Unique feature (pacing) |
| walking, activity | Light activity adjacency |

**Removed:** `watch`, `kcal` (subtitle), `fast`, `all`, `health` (low ROI)

---

## Astro: what to track (52 → curated)

**Priority tag (check weekly):**  
`total calories`, `daily burn`, `burned calories`, `watch calories`, `widget calories`, `apple watch calories`, `tdee`, `kcal`, `widget`, `ring`, `calorie widget`, `lock screen widget`

**Add when syncing:**  
`calorie widget`, `lock screen widget`, `move ring`, `daily calorie burn`, `calories burned tracker`, `watch face calories`

**Delete:** all headache / wrong-locale terms (see Ignore above)

---

## Screenshots ↔ keywords

Searchers need to see what they typed.

| Order | Target keyword cluster | Headline direction |
|-------|------------------------|-------------------|
| 1 | watch calories · total calories | “Total calories on your Watch face” |
| 2 | widget · widget calories | “Home Screen widgets — calories & steps” |
| 3 | daily burn · burned calories | “Your daily burn at a glance” |
| 4 | History / trends | “30-day trends from Apple Health” |
| 5 | deficit · Vitals+ | “Net deficit & PDF reports (Vitals+)” |

Do **not** lead with Net Deficit if ASO goal is discovery for Watch/widget/burn terms.

---

## Description (minimal edits)

First 2 sentences should include: **daily burn**, **Apple Watch complication**, **Home Screen widget**, **calories burned**, **step count**.

Example opener tweak:

> Total Calories shows your **daily burn** and total calories burned (active + resting) plus step count on your **Apple Watch** face, **Home Screen**, and **Lock Screen** — free.

Keep Vitals+ / net deficit mid-page.

---

## Promotional text (170 chars)

```
See your daily burn and total calories on your Apple Watch face and Home Screen widgets — free. Private, on-device, from Apple Health.
```

---

## What not to chase

| Term | Why skip |
|------|----------|
| calorie tracker (alone) | pop 74, diff 80, rank 1000 — dominated by MFP, Lose It, etc. |
| workout planner, gym | Competitor noise from `daily burn` extraction |
| widgetsmith, wallpapers | Competitor noise from `widget` extraction |
| AI calorie | Trendy but not your positioning |

---

## Measurement plan

After you ship subtitle + keyword field + screenshot order:

| When | Check |
|------|-------|
| Day 0 | Note change date in Astro keyword notes |
| Day 7 | `daily burn`, `widget`, `watch calories` ranks |
| Day 14 | Decide keep or revert subtitle |
| Day 30 | Promote any term that broke into top 100 |

**Win condition:** `daily burn` → top 40; `widget` or `ring` → top 200 (from 1000).

---

## Files to apply

- `fastlane/metadata/en-US/keywords.txt` — updated to proposed field
- `fastlane/metadata/en-US/subtitle.txt` — proposed (confirm before upload)
- Upload via `./scripts/upload-appstore-metadata.sh` when ready (not automatic)
