# Astro ASO Phase B — Total Calories (local prep)

**Date:** 2026-05-25  
**App ID:** `6761743504`  
**ASC upload:** **Skipped** (local files only — existing ASC unchanged)

## Summary

| Item | Status |
|------|--------|
| Locales on disk | **38** (`fastlane/metadata/*`) |
| Char limits (name/subtitle/keywords) | **Pass** (all ≤30/30/100) |
| Name/subtitle keyword dedupe | **Applied** (`aso-apply-locale-optimizations.py`) |
| Pull backup | `fastlane/metadata.bak.20260525-081116/` |
| Pre-upload backup | `fastlane/metadata.bak.pre-upload-20260525-190321/` |
| Astro 91-store sync | **In progress** — `./scripts/astro-sync-all-stores.sh` (fixed MCP client; ~1 store/min) |
| Gap retry | `./scripts/astro-sync-retry-gaps.sh` after main sync |
| Astro prune + tier-1 pass | **Pending** after sync |
| ASC draft upload | **Done** — version **1.5.3** (`PREPARE_FOR_SUBMISSION`), 49 locales API + deliver |

## en-US (primary)

| Field | Before | After | Len |
|-------|--------|-------|-----|
| **Subtitle** | Watch Step Count & Burned Kcal | Daily Burn on Watch & Widget | 28 |
| **Keywords** | pedometer,activity,widget,watch,ring,… | Deduped vs name/subtitle (no widget/burn/watch/daily/tracker/calories) | ~95–100 |

**Indexed in name/subtitle (excluded from keywords):** total, calories, daily, tracker, burn, watch, widget

**Keyword field (after dedupe):** high-intent only — pedometer, ring, TDEE, BMR, complication, deficit, resting, active, pace, fasting, walking, healthkit, activity, steps, …

Full per-locale diff: `scripts/aso-locale-optimization-report.json`

## Subtitle theme (all optimized locales)

Native variants of **“daily burn on watch & widget”** — surfaces attack term *daily burn* without duplicating it in the keyword field where subtitle already indexes it.

## Why Astro was empty (most countries)

1. **ASC/fastlane ≠ Astro** — metadata upload does not add Astro keywords.
2. **Full sync never completed** — earlier runs were interrupted; only US had manual setup.
3. **MCP overload** — batches of 8 + 120s timeout → HTTP 500 / timeouts. Fixed in `scripts/astro_mcp.py` (batches of 3, 300s timeout, retry + single-keyword fallback).

## Astro cleanup (manual + scripts)

Remove in Astro UI if still present:

- `headache tracker`, `headache migraine diary`, `headache diary`, `headache`, `pain tracker`
- Wrong-locale phrases: `seguimiento de pasos`, `calculer calories par jour`, `дневник`

Then run:

```bash
./scripts/astro-sync-all-stores.sh
./scripts/astro-prune-all-stores.sh
python3 scripts/astro-tier1-second-pass.py
```

## Upload when ready

```bash
./scripts/asc-finish-missed.sh
```

See [`localization-aso.md`](localization-aso.md) for restore paths.

## go refine

Calendar reminder **~2026-06-08** (14 days after ASC upload) — re-pull, tune from ranks, prune, upload again.
