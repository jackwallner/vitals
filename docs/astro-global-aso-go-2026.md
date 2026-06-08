# Astro global ASO — full “go” playbook (2026)

## Trigger (one command)

In any iOS app repo, say:

> Follow `~/Desktop/astro-global-aso-go-2026.md` and **go**

The agent runs the **entire pipeline below** and **does not stop early**. Finish means:

1. ASC metadata **downloaded** (with backup)  
2. **Every** `fastlane/metadata/<locale>/` folder optimized (`name`, `subtitle`, `keywords`, `description`)  
3. Astro **91 stores** set up with best possible keyword lists (pop/diff + competitors, not “seed only”)  
4. Obvious junk **pruned** in Astro per store  
5. Optimized metadata **uploaded** to an **editable ASC draft version** (API)  
6. **`./scripts/asc-finish-missed.sh`** run (draft version + missing version locales + upload)  
7. App docs written with before/after table  

Optional later: **go refine** (7–14+ days after upload, when rank data exists).

**Canonical paths:** `~/Desktop/astro-global-aso-go-2026.md` · `docs/astro-global-aso-go-2026.md` · scripts: `headaches/scripts/`

---

## Completion criteria (agent must meet all before stopping)

| # | Done when |
|---|-----------|
| 1 | `fastlane/metadata.bak.<timestamp>/` exists from pull |
| 2 | **All** locale dirs under `fastlane/metadata/` (except `review_information`) have optimized `name.txt`, `subtitle.txt`, `keywords.txt`, `description.txt` |
| 3 | Every `keywords.txt` ≤ **100** chars; `name`/`subtitle` ≤ **30** chars (verified) |
| 4 | `./scripts/astro-sync-all-stores.sh` finished for **91** stores (`scripts/astro-keywords-by-store/_summary.json`) |
| 5 | Per-store prune pass (wrong language, junk, cross-app terms) via `remove_keywords` |
| 6 | `fastlane/metadata.bak.pre-upload-*` snapshot exists |
| 7 | `./scripts/asc-finish-missed.sh` **completed** (draft version in `scripts/.asc-state.json`, metadata PATCH ok) |
| 8 | `docs/astro-aso-setup.md` + `docs/astro-phase-b-report.md` with locale table + upload confirmation |

**Do not** stop after pull-only, seed-only, or “ready to upload.” **Upload to a draft ASC version is part of go.**

If deliver fails on live `READY_FOR_SALE`, use **`asc-finish-missed.sh`** (auto draft + API). Report blocker only if unrecoverable.

**Requires fastlane 2.234+** (Homebrew: `/opt/homebrew/bin/fastlane`). Repo uses `scripts/fastlane-bin.sh` — not the old `/usr/local/bin/fastlane` 2.230 gem. `fastlane/Deliverfile` lists all 50 `languages([...])` so deliver enables draft **appInfo** + version localizations on upload.

---

## Languages: what “all possible” means

| Scope | Count | What “go” does |
|-------|-------|----------------|
| **ASC localizations on disk** | All folders from pull (~30–40+ per app) | **Optimize + upload** every one |
| **Astro Search Ads countries** | **91** stores | **Optimize keywords** per store; sync via MCP |
| **Apple Store languages not in ASC** | 50+ possible | **Not in fastlane until you add them in ASC.** Agent lists missing high-value locales in the report; Astro still tracks via fallback locale. |

To add more ASC languages: run Step 2b/9 on a **draft** version (`--draft-only`) — version-level keywords/description upload via API; appInfo may still need ASC UI.

---

## Automatic gap closure (run at end of every **go**)

Closes what a first pass often misses (live version locked, 11 locales, no draft):

```bash
./scripts/asc-finish-missed.sh
```

This script:

1. **`asc-ensure-draft-version`** — finds or creates `PREPARE_FOR_SUBMISSION` (e.g. `1.4.0`); writes `scripts/.asc-state.json`  
2. **`asc-add-missing-localizations.py --draft-only --from-fastlane --all-supported`** — POST **version** localizations for every fastlane folder + supported list (skips locked appInfo with a log line)  
3. **`asc-upload-metadata.sh --create-missing`** — PATCH keywords/description (+ draft appInfo name/subtitle when present)  
4. **`upload-appstore-metadata.sh`** — **fastlane 2.234+ deliver** (`Deliverfile` `languages`) — enables **50 appInfo** + **50 version** locales on draft  

Optional before upload: `python3 scripts/aso-apply-locale-optimizations.py` (native keyword pass).

**Install / PATH:** `brew install fastlane` → use `scripts/fastlane-bin.sh` (wraps `/opt/homebrew/bin/fastlane`). Wrong binary = `Unsupported directory name bn-BD`.

---

## Prerequisites

- [ ] **Astro** open · MCP enabled (`http://127.0.0.1:8089/mcp`)
- [ ] App registered in Astro (same name as App Store)
- [ ] `fastlane/Appfile` · `~/.baseball_credentials` (`ASC_*`)
- [ ] `fastlane` + `python3` on PATH
- [ ] Scripts present (copy from `headaches` if missing — see bottom)

---

## Pipeline (run in order — do not skip steps)

### Step 1 — Identity

```bash
grep app_identifier fastlane/Appfile
cat fastlane/metadata/en-US/name.txt
```

MCP `list_apps` → record **appId**. Resolve **live** `ASC_APP_VERSION` (API or last known; Headache example: `1.3.0`).

### Step 2 — Download existing ASC (backup)

```bash
ASC_APP_VERSION=<live> ./scripts/pull-appstore-metadata.sh
```

Ground truth → `fastlane/metadata/**` · backup → `fastlane/metadata.bak.<timestamp>/`

### Step 2b — Add missing ASC localizations (draft version)

**Use a draft version**, not live `READY_FOR_SALE` (appInfo POST is blocked on live apps).

```bash
# Preview on draft
./scripts/asc-add-missing-localizations.sh --dry-run --draft-only --from-fastlane --all-supported

# Create missing version localizations (seeded from fastlane; appInfo may skip — OK)
./scripts/asc-add-missing-localizations.sh --draft-only --from-fastlane --all-supported

# Re-pull draft
eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
./scripts/pull-appstore-metadata.sh
```

Or run the all-in-one closer after the rest of the pipeline: **`./scripts/asc-finish-missed.sh`**

**Note:** ASC locales ≠ Astro’s 91 Search Ads countries. Polish is `pl`; Norwegian is `no`.

### Step 3 — Competitor research (per Astro store / locale)

For **each** of the 91 stores in `scripts/astro-stores-2026.json`, run `search_app_store` with a **native-language** head term (map store → language via fallback locales in that file).

For **each** `fastlane/metadata/<locale>/`:

- Read current `name`, `subtitle`, `keywords`, `description`
- Note top 3–5 competitor names/subtitles from the matching store(s)

Rate limit: ~60 MCP requests/min — batch with sleeps.

### Step 4 — Optimize every ASC locale (fastlane)

For **every** locale directory under `fastlane/metadata/` (skip `review_information` only):

| File | Limit | Rules |
|------|-------|--------|
| `keywords.txt` | 100 | Comma-separated, no spaces after commas, **native language** — **no repeats** of words already in `name` or `subtitle` (Apple indexes all three; duplicates waste space) |
| `subtitle.txt` | 30 | Competitor-aligned, unique per locale |
| `name.txt` | 30 | Keep strong brand string if already winning; else improve |
| `description.txt` | — | Keep structure; weave top keywords naturally (no stuffing) |

**Day-0 keyword strategy (no rank data required):**

- Use competitor SERP + app positioning  
- Prefer terms with good **popularity** and acceptable **difficulty** (from `add_keywords` test batches or suggestions)  
- Fill the 100-char field with high-intent tokens; drop low-value generic filler  

**Verify all locales:**

```bash
python3 <<'PY'
from pathlib import Path
for loc in sorted(Path("fastlane/metadata").iterdir()):
    if not loc.is_dir() or loc.name == "review_information":
        continue
    for f, lim in [("name.txt",30),("subtitle.txt",30),("keywords.txt",100)]:
        p = loc / f
        if not p.exists():
            print("MISSING", loc.name, f)
            continue
        s = p.read_text().strip()
        ok = len(s) <= lim
        print(f"{'OK' if ok else 'OVER':4} {len(s):3}/{lim} {loc.name}/{f}")
PY
```

Fix every `OVER` / `MISSING` before upload.

Bulk native keyword pass (after competitor research; **dedupes vs name/subtitle**):

```bash
python3 scripts/aso-apply-locale-optimizations.py
```

Report: `scripts/aso-locale-optimization-report.json`

### Step 5 — Pre-upload backup

```bash
cp -R fastlane/metadata "fastlane/metadata.bak.pre-upload-$(date +%Y%m%d-%H%M%S)"
```

### Step 6 — Astro: all 91 stores

```bash
./scripts/astro-sync-all-stores.sh
```

Uses optimized fastlane text. Re-run after any metadata edit.

Optional US phrase pass:

```bash
./scripts/astro-setup.sh --skip-pull --extra "phrase one" "phrase two"
```

### Step 7 — Astro: prune (all stores)

```bash
./scripts/astro-prune-all-stores.sh
```

Or per store:

```bash
./scripts/astro-optimize.py --store us --prune
./scripts/astro-optimize.py --store de --prune --prune-list "bad term"
```

Rules:

- Wrong script/language for storefront  
- English garbage on non-English stores  
- Test phrases, other-app terms, irrelevant rank-1000 noise  

### Step 8 — Astro: second-pass optimization (best possible)

For Tier-1 stores (`us`, `gb`, `de`, `fr`, `ca`, `au`, `jp`, `br`, `mx`, `es`, `it`, `nl`, `kr`, `cn`, `tw`):

- `get_keyword_suggestions` (with correct `appId` + `store`)  
- `extract_competitors_keywords` on terms you rank ≤100 (if any exist from prior data)  
- Add high pop / reasonable diff winners via `add_keywords` (≤100 per batch)  
- Re-prune duplicates and misfits  

If **no** rank data yet, this step still runs on **market** data (pop/diff on add), not your ranks.

```bash
python3 scripts/astro-tier1-second-pass.py
```

### Step 9 — Upload metadata to ASC (draft)

**Always run the automatic closer** (handles draft version + missing locales + PATCH):

```bash
./scripts/asc-finish-missed.sh
```

Equivalent manual steps:

```bash
eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
./scripts/asc-add-missing-localizations.sh --draft-only --from-fastlane --all-supported
./scripts/asc-upload-metadata.sh   # includes --create-missing
```

**fastlane deliver** (required for appInfo + 11 new locales):

```bash
eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
SKIP_SCREENSHOTS=true ./scripts/upload-appstore-metadata.sh   # metadata only
# SKIP_SCREENSHOTS=false ./scripts/upload-appstore-metadata.sh  # + screenshots
```

Uses `scripts/fastlane-bin.sh` → **fastlane 2.234+** and `fastlane/Deliverfile`.

Success = deliver **finished successfully** + draft has **50** `appInfo` localizations (check `python3 scripts/asc-ensure-draft-version.py`). **Attach a build and submit 1.4.0** to ship.

**Competitor scan (Step 3):** `python3 scripts/astro-competitor-scan.py` → `scripts/astro-competitor-research.json`

### Step 10 — Write docs

- `docs/astro-aso-setup.md` — app id, US highlights, ASC experiments  
- `docs/astro-phase-b-report.md` — every locale: old → new keywords/subtitle/name lengths, Astro store count, upload status  
- `docs/localization-aso.md` — backup paths, restore command  

### Step 11 — Final report to user

1. Pull backup path  
2. Pre-upload backup path  
3. Locales optimized (count + list)  
4. Astro stores synced (91 target)  
5. Upload: **success / failure** + version used  
6. ASC languages **not** on disk but recommended to add  
7. **go refine** — suggest calendar reminder 14 days out  

---

## Agent checklist (copy on “go”)

```
[ ] Scripts + astro-stores-2026.json copied if missing
[ ] Astro MCP ping OK · appId known · ASC_APP_VERSION known
[ ] pull-appstore-metadata.sh (backup created)
[ ] asc-add-missing-localizations --draft-only (or defer to finish-missed)
[ ] astro-competitor-scan.py (91 stores)
[ ] aso-apply-locale-optimizations.py + char verify ALL locales
[ ] pre-upload backup
[ ] astro-sync-all-stores.sh (91)
[ ] astro-prune-all-stores.sh
[ ] astro-tier1-second-pass.py
[ ] asc-finish-missed.sh SUCCESS (draft upload)
[ ] docs written + user report
[ ] DO NOT STOP until upload succeeds or hard blocker documented
```

---

## Optional: “go refine” (later)

Only after **7–14 days** on live metadata. Re-pull → `astro-optimize --all-stores` → tune fastlane from **your** ranks → prune → upload again.

---

## Scripts to copy

```bash
REPO=/Users/jackwallner/headaches
for f in astro_mcp.py astro-setup.sh astro-build-keywords.py \
  astro-sync-all-stores.py astro-sync-all-stores.sh astro-stores-2026.json \
  astro-optimize.py pull-appstore-metadata.sh restore-appstore-metadata.sh \
  asc-add-missing-localizations.py asc-add-missing-localizations.sh asc-supported-locales.json \
  asc_lib.py asc-upload-metadata.py asc-upload-metadata.sh asc-ensure-draft-version.py \
  asc-ensure-draft-version.sh asc-finish-missed.sh fastlane-bin.sh \
  aso-apply-locale-optimizations.py \
  astro-competitor-scan.py astro-prune-all-stores.sh astro-tier1-second-pass.py \
  upload-appstore-metadata.sh; do
  cp "$REPO/scripts/$f" scripts/ 2>/dev/null || cp "$REPO/scripts/${f%.sh}.py" scripts/ 2>/dev/null
done
chmod +x scripts/*.sh
cp "$REPO/docs/astro-global-aso-go-2026.md" docs/ 2>/dev/null || true
cp "$REPO/fastlane/Deliverfile" fastlane/ 2>/dev/null || true
```

---

## MCP tools

| Tool | Use in “go” |
|------|-------------|
| `list_apps` | appId |
| `search_app_store` | Competitors per store |
| `add_keywords` | All 91 stores |
| `remove_keywords` | Prune |
| `get_keyword_suggestions` | Second pass |
| `get_app_keywords` | If prior data exists |

https://tryastro.app/docs/mcp/

---

## Jack’s Astro app IDs

| App | appId |
|-----|-------|
| Total Calories | 6761743504 |
| Headache Tracker - One Tap | 6762074561 |
| Baseball Savvy StatScout | 6763945657 |
| Fitness Habits | 6762699692 |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Pull version error | Set `ASC_APP_VERSION` to live ASC version |
| keywords OVER 100 | Shorten field; drop weakest tokens |
| MCP 429 | Sleep 60s; one store at a time |
| Upload rejected on live | Run `./scripts/asc-finish-missed.sh` (draft API) |
| deliver “no editable version” | `asc-ensure-draft-version` then `asc-upload-metadata.sh` |
| appInfo 409 on new locale | Expected on live app — version locs still created on draft |
| Unsupported metadata folder (bn-BD, …) | Use `scripts/fastlane-bin.sh` (2.234+), not `/usr/local/bin/fastlane` |
| Wrong fastlane version | `brew install fastlane` · `scripts/fastlane-bin.sh --version` → 2.234+ |
| keywords OVER 100 | Shorten field; drop weakest tokens |
| Missing locale folder | `asc-add-missing-localizations --draft-only --from-fastlane` |

---

## One-liner (orchestration — agent does steps 4–7 in between)

```bash
ASC_APP_VERSION=1.3.0 ./scripts/pull-appstore-metadata.sh
python3 scripts/aso-apply-locale-optimizations.py
./scripts/astro-sync-all-stores.sh
./scripts/astro-prune-all-stores.sh
./scripts/asc-finish-missed.sh
```
