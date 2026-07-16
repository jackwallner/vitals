# Astro ASO setup — Total Calories

> **Playbook:** [global ASO rollout archive](~/ios/archive/aso/2026-05/astro-global-aso-go-2026.md)  
> **Keyword strategy:** [`aso-keyword-strategy.md`](aso-keyword-strategy.md)  
> **Phase B report:** [Phase B report](archive/aso/2026-05/astro-phase-b-report.md)

Last updated: **2026-05-25** (local metadata optimize + name/subtitle dedupe; **no ASC upload**)

## App

| Field | Value |
|-------|-------|
| App Store name | Total Calories - Daily Tracker |
| App ID | `6761743504` |
| Bundle ID | `com.jackwallner.vitals` |
| Primary store in Astro | `us` |

## Recommended ASC copy (en-US)

| Field | Value |
|-------|-------|
| **Name** | Total Calories - Daily Tracker |
| **Subtitle** | Daily Burn on Watch & Widget |
| **Keywords** | See `fastlane/metadata/en-US/keywords.txt` (deduped — no repeat of name/subtitle tokens) |

## Dedupe rule (2026 playbook)

Apple indexes **name + subtitle + keywords** together. The keyword field must not repeat words already in name or subtitle (e.g. no `widget`, `watch`, `burn`, `daily`, `tracker`, `calories` in keywords for en-US).

Regenerate all locales:

```bash
python3 scripts/aso-apply-locale-optimizations.py
```

## Astro tags

| Tag | Color | Use for |
|-----|-------|---------|
| `asc-field` | blue | Tokens from the 100-char ASC keyword field |
| `priority` | red | Terms to optimize first (rank + popularity) |
| `phrase` | green | Multi-word search phrases |

## Remove in Astro (wrong app / locale)

- `headache tracker`, `headache migraine diary`, `headache diary`, `headache`, `pain tracker`
- `seguimiento de pasos`, `calculer calories par jour`, `дневник`

## Weekly routine (~10 min)

1. Open Astro → Total Calories → US
2. Sort by **rank change** — note anything that moved up with popularity ≥ 5
3. Anything stuck at **1000** for 2+ weeks → deprioritize or remove
4. After ASC metadata change, wait 7–14 days then re-check

## Re-sync pipeline

```bash
python3 scripts/aso-apply-locale-optimizations.py   # fastlane locales
./scripts/astro-sync-all-stores.sh                 # 91 Astro stores
./scripts/astro-prune-all-stores.sh
python3 scripts/astro-tier1-second-pass.py
```

## Upload to ASC (when ready)

```bash
./scripts/asc-finish-missed.sh
```

Backups: [`localization-aso.md`](localization-aso.md)

## MCP

- Astro: `http://127.0.0.1:8089/mcp`
- Config: `scripts/.astro-app.json`
