# Astro ASO setup process (any app)

**Trigger:** In an app repo, point the agent at this doc and say **"go"** (or **"run astro setup"**).

The agent runs a full **App Store Connect metadata pull** and **Astro keyword tracking setup** for the app in the **current working directory**.

Canonical copy: `vitals/docs/astro-setup-process.md` — copy this file + `scripts/astro-*.sh` / `scripts/astro_mcp.py` into other app repos, or reference this path.

---

## Outcomes

When complete, the repo has:

| Artifact | Purpose |
|----------|---------|
| Fresh `fastlane/metadata/**` | Ground truth from ASC |
| `fastlane/metadata.bak.<timestamp>/` | Undo snapshot (from pull script) |
| `scripts/astro-keywords-{store}.json` | Keyword list pushed to Astro |
| `scripts/.astro-app.json` | Astro app ID + last sync time |
| `docs/astro-aso-setup.md` | App-specific ASO reference (agent writes) |

Astro has: app tracked, **50+ keywords** for primary store, tags `asc-field` / `priority` / `phrase`.

---

## Prerequisites (agent verifies first)

- [ ] **Astro** macOS app is **open**
- [ ] Astro → Settings → **MCP Server enabled** (default `http://127.0.0.1:8089/mcp`)
- [ ] App is **already added in Astro** (same name as ASC). MCP cannot create apps without `add_app` + store — if missing, add in Astro UI first.
- [ ] Repo has `fastlane/Appfile` and `scripts/pull-appstore-metadata.sh` (or equivalent deliver setup)
- [ ] ASC API key available: `~/.baseball_credentials` with `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`
- [ ] `fastlane` and `python3` on PATH
- [ ] Optional: Cursor / Claude Code MCP pointed at Astro (for later Q&A)

If scripts are missing in the repo, **copy from vitals**:

```bash
cp /Users/jackwallner/vitals/scripts/astro-setup.sh scripts/
cp /Users/jackwallner/vitals/scripts/astro-build-keywords.py scripts/
cp /Users/jackwallner/vitals/scripts/astro_mcp.py scripts/
cp /Users/jackwallner/vitals/scripts/sync-astro-keywords.sh scripts/  # optional
chmod +x scripts/astro-setup.sh
```

---

## Phase 1 — Discover app identity

From repo root:

```bash
grep app_identifier fastlane/Appfile
cat fastlane/metadata/en-US/name.txt
cat fastlane/metadata/en-US/subtitle.txt
cat fastlane/metadata/en-US/keywords.txt
```

Record:

- **Bundle ID** — e.g. `com.jackwallner.vitals`
- **ASC display name** — e.g. `Total Calories - Daily Tracker`
- **Primary locale** — default `en-US` → Astro store `us`

Confirm the app exists in Astro:

```bash
curl -s -X POST http://127.0.0.1:8089/mcp -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_apps","arguments":{}}}' \
  | python3 -m json.tool
```

Match **ASC name** → **`appId`** (numeric). If no match, stop and ask the user to add the app in Astro.

---

## Phase 2 — Pull fresh ASC metadata

```bash
./scripts/pull-appstore-metadata.sh
```

This overwrites `fastlane/metadata/` and saves `fastlane/metadata.bak.<timestamp>/`.

Re-read after pull:

- `fastlane/metadata/en-US/name.txt`
- `fastlane/metadata/en-US/subtitle.txt`
- `fastlane/metadata/en-US/keywords.txt`
- `fastlane/metadata/en-US/description.txt` (first ~40 lines for positioning)

---

## Phase 3 — Build keyword list

Astro tracks **search queries**, not just the ASC keyword field. Build three buckets:

### A. ASC keyword field (required)

Split `keywords.txt` on commas → lowercase tokens.  
Example: `pedometer,widget,burn` → `pedometer`, `widget`, `burn`.

Tag these **`asc-field`** in Astro.

### B. Phrase-level searches (required — agent judgment)

Read **name**, **subtitle**, and **description**. Add **25–40 multi-word phrases** real users would search.

**How to generate (agent):**

1. Extract 2–3 word phrases from name/subtitle (e.g. "daily tracker", "step count").
2. Read description for features → phrases (widgets, Watch, HealthKit, export, etc.).
3. Add category terms (health/fitness/sports/productivity — whatever fits).
4. **Do not** copy keywords from other apps in Astro.
5. **Do not** add foreign-language terms to US tracking unless that locale is targeted.

**Examples by app type:**

| App type | Example phrases |
|----------|-----------------|
| Calorie / fitness | `calorie tracker`, `apple watch widget`, `step counter`, `daily burn`, `healthkit` |
| Headache / medical log | `headache tracker`, `migraine diary`, `pain log`, `one tap` |
| Sports / stats | `baseball stats`, `savant`, `statcast`, `player stats` |

Pass agent-chosen extras when running setup:

```bash
./scripts/astro-setup.sh --extra "headache diary" "migraine tracker"
```

### C. Optional — Astro intelligence

After base list is synced, if MCP is stable:

- `get_keyword_suggestions` — add high-popularity relevant suggestions only
- `extract_competitors_keywords` — only on a **already-tracked** keyword that ranks; add combos with popularity > 5 that fit the app

Cap total new adds at **~100 per batch** (Astro limit).

---

## Phase 4 — Run automated setup

```bash
./scripts/astro-setup.sh
```

Flags:

| Flag | Effect |
|------|--------|
| `--dry-run` | Build keyword JSON only, no MCP writes |
| `--skip-pull` | Skip ASC pull (metadata already fresh) |
| `--store us` | Astro store code (default `us`) |
| `--extra "phrase"` | Append agent-generated phrases |

Script will:

1. Pull ASC (unless `--skip-pull`)
2. Build `scripts/astro-keywords-us.json`
3. Resolve Astro `appId` by name
4. `add_keywords` (skips duplicates)
5. Create tags: `asc-field`, `priority`, `phrase`
6. Tag ASC tokens + top phrases
7. Write `scripts/.astro-app.json`
8. Print top rankings + ratings

**Re-sync later (no pull):**

```bash
./scripts/sync-astro-keywords.sh
# uses scripts/.astro-app.json + scripts/astro-keywords-us.json
```

---

## Phase 5 — Clean up wrong keywords (manual)

Astro MCP has **no delete keyword** tool. In Astro UI, remove keywords that:

- Belong to a **different app** (cross-contamination)
- Are **wrong language** for the store (e.g. French on US)
- Stuck at rank **1000** for 3+ weeks and irrelevant

Agent: list current keywords via MCP, flag junk, print a bullet list for the user to delete in Astro.

```bash
# Example: list all keywords
curl -s -X POST http://127.0.0.1:8089/mcp -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_app_keywords","arguments":{"appId":"APP_ID","store":"us"}}}'
```

---

## Phase 6 — Write app-specific doc

Create or update **`docs/astro-aso-setup.md`** in the repo with:

- App name, bundle ID, Astro app ID, store
- Live name / subtitle / keywords (from pulled metadata)
- Backup folder name from pull
- Keyword count added
- Tags created
- **Top 10–15 rankings** from setup output
- **Junk keywords to remove** (explicit list)
- Weekly routine (5 bullets)
- Re-sync commands

Use `vitals/docs/astro-aso-setup.md` as the template.

---

## Phase 7 — Report to user

Post a short summary:

1. ASC pull OK + backup path  
2. Astro app ID + keywords added  
3. Best current rankings (celebrate #1–50)  
4. Manual deletions needed  
5. Suggested next ASC experiments (subtitle/keyword field tweaks based on data)

---

## Agent checklist (copy when running "go")

```
[ ] CWD is target app repo root
[ ] Astro MCP ping OK (127.0.0.1:8089)
[ ] App exists in Astro (list_apps)
[ ] Copy astro scripts if missing
[ ] ./scripts/pull-appstore-metadata.sh
[ ] Read name/subtitle/keywords/description
[ ] Decide 25-40 extra phrases for --extra
[ ] ./scripts/astro-setup.sh --extra "..."
[ ] List junk keywords to remove in Astro UI
[ ] Write docs/astro-aso-setup.md
[ ] Summarize rankings + ratings for user
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| MCP connection refused | Open Astro; enable MCP in Settings |
| App not found in Astro | Add app in Astro UI (US store), re-run |
| `pull-appstore-metadata.sh` fails | Check `~/.baseball_credentials`; `brew install fastlane` |
| 429 from MCP | Wait 1 min; Astro limits 60 req/min |
| Keywords added but all rank 1000 | Normal at first; check again in 7–14 days |
| Wrong app matched | Use exact ASC name; set `appId` in `scripts/.astro-app.json` manually |

---

## MCP tools reference

| Tool | Use |
|------|-----|
| `list_apps` | Find app ID |
| `get_app_keywords` | Current rankings |
| `add_keywords` | Bulk add (max 100) |
| `get_keyword_suggestions` | Ideas after base setup |
| `extract_competitors_keywords` | Competitor terms for one tracked keyword |
| `search_app_store` | Live competitor discovery |
| `get_app_ratings` | Ratings by store |
| `manage_tag` / `set_keyword_tag` | Organize keywords |

Docs: https://tryastro.app/docs/mcp/

---

## Per-repo notes (Jack's apps)

| Repo | ASC name | Astro app ID (2026-05-25) |
|------|----------|---------------------------|
| vitals | Total Calories - Daily Tracker | 6761743504 |
| headaches | Headache Tracker - One Tap | 6762074561 |
| baseball | Baseball Savvy StatScout | 6763945657 |
| fitness-streaks | Fitness Habits - Streak Finder | 6762699692 |
| bond | Husband & Wife Reminder - Bond | 101 (temporary; replace at launch) |

Update this table when running setup on each repo.
