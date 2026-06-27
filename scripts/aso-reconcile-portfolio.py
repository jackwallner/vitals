#!/usr/bin/env python3
"""
Pull LIVE ASC metadata per app, reconcile Astro keywords all stores.

Keep rule (per store) — a keyword is allowed iff:
  - currentRanking < 1000  (active combo / position), OR
  - exact match in live field singletons for that store's locale(s), OR
  - exact match in app target list, OR
  - exact match in app wall list
  - (US only, when usTracking enabled) exact match in scripts/astro-keywords-us.json
    keywords + curated combo phrases

Everything else is removed. Missing field/target/wall/us-tracking seeds are added.
Verification fails the run if any store violates the rule.
"""
from __future__ import annotations

import importlib.util
import json
import re
import sys
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from astro_mcp import add_keywords, call, list_apps, remove_keywords, DEFAULT_MCP_URL  # noqa: E402

STORES_JSON = SCRIPT_DIR / "astro-stores-2026.json"

LOCALE_TO_STORE: dict[str, str] = {
    "ar-SA": "sa",
    "ca": "es",
    "cs": "cz",
    "da": "dk",
    "de-DE": "de",
    "el": "gr",
    "en-AU": "au",
    "en-CA": "ca",
    "en-GB": "gb",
    "en-US": "us",
    "es-ES": "es",
    "es-MX": "mx",
    "fi": "fi",
    "fr-CA": "ca",
    "fr-FR": "fr",
    "he": "il",
    "hi": "in",
    "hr": "hr",
    "hu": "hu",
    "id": "id",
    "it": "it",
    "ja": "jp",
    "ko": "kr",
    "ms": "my",
    "nl-NL": "nl",
    "no": "no",
    "pl": "pl",
    "pt-BR": "br",
    "pt-PT": "pt",
    "ro": "ro",
    "ru": "ru",
    "sk": "sk",
    "sv": "se",
    "th": "th",
    "tr": "tr",
    "uk": "ua",
    "vi": "vn",
    "zh-Hans": "cn",
    "zh-Hant": "tw",
}

PORTFOLIO: list[dict[str, Any]] = [
    {
        "astroId": "6761743504",
        "repo": Path("/Users/jackwallner/vitals"),
        "name": "Total Calories",
        "pullAsc": True,
        "targets": [
            "tdee tracker", "tdee bmr", "tdee calculator", "bmr calculator",
            "total energy", "total daily energy expenditure", "bmi", "bmi calculator",
            "tdee", "metabolic", "complication",
        ],
        "walls": [
            "calorie tracker", "calorie counter", "calorie deficit tracker",
            "calorie calculator", "apple fitness",
        ],
        "usTracking": True,
    },
    {
        "astroId": "6762074561",
        "repo": Path("/Users/jackwallner/headaches"),
        "name": "Headache Tracker",
        "pullAsc": True,
        "targets": [
            "one tap headache", "headache forecast", "barometric headache",
            "headache tracker", "pressure headache", "track migraine",
            "migraine forecast", "cluster headache tracker", "one tap migraine",
        ],
        "walls": [
            "migraine buddy", "migraine tracker", "weather migraine",
            "headache diary", "pressure pal", "symptom diary",
        ],
    },
    {
        "astroId": "6768514177",
        "repo": Path("/Users/jackwallner/bond"),
        "name": "Bond",
        "pullAsc": True,
        "targets": [
            "love language", "love language app", "love language reminder",
            "love language reminders", "love languages", "love reminder",
            "marriage reminder", "partner reminder", "relationship reminders", "bond love",
        ],
        "walls": [
            "love nudge", "couples app", "paired", "relationship tracker",
            "anniversary countdown", "love counter", "cozy couples",
        ],
    },
    {
        "astroId": "6768869215",
        "repo": Path("/Users/jackwallner/sober"),
        "name": "Sober Tracker",
        "pullAsc": True,
        "targets": [
            "dry days", "dry january", "alcohol countdown", "sober countdown",
            "sober app", "quit drinking", "abstinence tracker", "apple watch sober",
        ],
        "walls": [
            "sober tracker", "i am sober", "alcohol free", "habit tracker",
            "drink less", "alcohol tracker",
        ],
    },
    {
        "astroId": "6770138156",
        "repo": Path("/Users/jackwallner/sports"),
        "name": "Gist",
        "pullAsc": True,
        "targets": [
            "talking points", "small talk", "things to talk about", "non sports fan",
            "sports brief", "sports recap", "sports small talk",
            "sports for beginners", "understand sports", "sports explained",
        ],
        "walls": [
            "sports news", "sports scores", "conversation starters", "icebreaker",
            "party games", "college football",
        ],
    },
    {
        "astroId": "6763945657",
        "repo": Path("/Users/jackwallner/baseball"),
        "name": "Baseball StatScout",
        "pullAsc": True,
        "targets": [
            "baseball savant", "mlb savant", "statcast", "statcast percentiles",
            "baseball percentiles", "savant stats", "baseball analytics",
            "statcast leaderboard", "mlb statcast",
        ],
        "walls": ["mlb", "scout", "velo", "sports", "war", "sports analytics", "baseball app"],
    },
    {
        "astroId": "6770137909",
        "repo": Path("/Users/jackwallner/simpleglp"),
        "name": "Simple GLP",
        "pullAsc": True,
        "targets": [
            "simple glp", "simple shot tracker", "simple glp1", "shot reminder",
            "weekly shot", "glp-1 shot", "ozempic shot", "weekly shot tracker",
            "glp-1 diary", "zepbound shot", "glp-1 shot tracker", "ozempic shot tracker",
        ],
        "walls": [
            "glp1 tracker", "glp-1 tracker", "weight loss tracker",
            "apple watch", "health app", "peptide tracker",
        ],
    },
    {
        "astroId": "6762699692",
        "repo": Path("/Users/jackwallner/fitness-streaks"),
        "name": "Fitness Habits",
        "pullAsc": True,
        "targets": [
            "stand streak", "move streak", "ring streak", "step streak",
            "healthkit streak", "fitness habits", "health streaks",
            "exercise streak", "apple health streak", "streak finder",
        ],
        "walls": [
            "habit tracker", "steps", "workout", "widget", "health",
            "apple watch", "fitness app", "fitness tracker", "workout tracker",
            "habit", "apple health", "step counter", "exercise tracker",
        ],
    },
    {
        "astroId": "104",
        "repo": Path("/Users/jackwallner/posture"),
        "name": "Posture",
        "pullAsc": False,
        "targets": [
            "posture reminder", "posture check", "posture tracker", "airpods posture",
            "desk posture", "slouch", "neck posture", "text neck", "improve posture",
        ],
        "walls": ["habit tracker", "fitness", "upright", "apple health"],
    },
]


def load_asc_lib(repo: Path):
    path = repo / "scripts" / "asc_lib.py"
    if not path.exists():
        raise FileNotFoundError(path)
    spec = importlib.util.spec_from_file_location(f"asc_lib_{repo.name}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def tokens_from_keywords(raw: str) -> list[str]:
    raw = raw.replace("，", ",").replace("、", ",")
    return [t.strip().lower() for t in raw.split(",") if t.strip()]


def pull_live_asc(repo: Path) -> dict[str, dict[str, str]]:
    """Pull READY_FOR_SALE metadata from ASC API into fastlane/metadata/."""
    asc = load_asc_lib(repo)
    key_id, issuer_id, key_path = asc.load_credentials()
    client = asc.ASCClient(asc.bearer_token(key_id, issuer_id, key_path))
    app = asc.find_app(client, asc.bundle_id_from_appfile())
    live_v = asc.find_live_version(client, app["id"])
    if not live_v:
        raise RuntimeError(f"{repo.name}: no READY_FOR_SALE version")
    live_infos = [
        i
        for i in asc.list_all(client, f"/apps/{app['id']}/appInfos")
        if i.get("attributes", {}).get("appStoreState") == "READY_FOR_SALE"
    ]
    if not live_infos:
        raise RuntimeError(f"{repo.name}: no live appInfo")
    live_info = live_infos[0]

    info_by_locale = {
        loc["attributes"]["locale"]: loc["attributes"]
        for loc in asc.list_all(client, f"/appInfos/{live_info['id']}/appInfoLocalizations")
    }
    ver_by_locale = {
        loc["attributes"]["locale"]: loc["attributes"]
        for loc in asc.list_all(
            client, f"/appStoreVersions/{live_v['id']}/appStoreVersionLocalizations"
        )
    }

    meta_dir = repo / "fastlane" / "metadata"
    meta_dir.mkdir(parents=True, exist_ok=True)
    locales = sorted(set(info_by_locale) | set(ver_by_locale))
    pulled: dict[str, dict[str, str]] = {}

    for locale in locales:
        info = info_by_locale.get(locale, {})
        ver = ver_by_locale.get(locale, {})
        name = (info.get("name") or "").strip()
        subtitle = (info.get("subtitle") or "").strip()
        keywords = (ver.get("keywords") or "").strip()
        loc_dir = meta_dir / locale
        loc_dir.mkdir(parents=True, exist_ok=True)
        if name:
            (loc_dir / "name.txt").write_text(name + "\n", encoding="utf-8")
        if subtitle:
            (loc_dir / "subtitle.txt").write_text(subtitle + "\n", encoding="utf-8")
        if keywords:
            (loc_dir / "keywords.txt").write_text(keywords + "\n", encoding="utf-8")
        pulled[locale] = {"name": name, "subtitle": subtitle, "keywords": keywords}

    print(
        f"  ASC pull {repo.name}: live v{live_v['attributes']['versionString']} "
        f"{len(locales)} locales"
    )
    return pulled


def load_stores_plan() -> dict[str, dict]:
    return {e["code"]: e for e in json.loads(STORES_JSON.read_text())["stores"]}


def locale_dirs_for_store(store_code: str, store_entry: dict, meta_root: Path) -> list[Path]:
    dirs: list[Path] = []
    seen: set[str] = set()
    for locale in list(store_entry.get("fallbackLocales", [])) + ["en-US"]:
        d = meta_root / locale
        if d.is_dir() and locale not in seen:
            seen.add(locale)
            dirs.append(d)
    for locale, mapped in LOCALE_TO_STORE.items():
        if mapped == store_code:
            d = meta_root / locale
            if d.is_dir() and locale not in seen:
                seen.add(locale)
                dirs.append(d)
    return dirs


def field_singletons_for_store(repo: Path, store_code: str, plan: dict[str, dict]) -> set[str]:
    entry = plan.get(store_code)
    if not entry:
        return set()
    meta_root = repo / "fastlane" / "metadata"
    words: set[str] = set()
    for d in locale_dirs_for_store(store_code, entry, meta_root):
        kw_file = d / "keywords.txt"
        if kw_file.exists():
            words.update(tokens_from_keywords(kw_file.read_text(encoding="utf-8")))
    return words


def keep_set_for_store(
    repo: Path,
    store: str,
    plan: dict[str, dict],
    targets: set[str],
    walls: set[str],
    ranking_keywords: set[str],
) -> set[str]:
    return field_singletons_for_store(repo, store, plan) | targets | walls | ranking_keywords


def should_keep(kw: dict, allowed: set[str]) -> bool:
    rank = kw.get("currentRanking") or 1000
    if rank < 1000:
        return True
    return kw["keyword"].lower() in allowed


def set_tag(app_id: str, store: str, keyword: str, tag: str) -> None:
    try:
        call(
            DEFAULT_MCP_URL,
            "set_keyword_tag",
            {"appId": app_id, "store": store, "keyword": keyword, "tag": tag, "action": "add"},
        )
    except RuntimeError as e:
        if "already assigned" not in str(e).lower():
            raise
    time.sleep(0.2)


def reconcile_app(cfg: dict, astro_stores: list[str], plan: dict[str, dict], *, dry_run: bool) -> dict:
    app_id = cfg["astroId"]
    repo: Path = cfg["repo"]
    targets = {t.lower() for t in cfg["targets"]}
    walls = {w.lower() for w in cfg["walls"]}
    stats = {"removed": 0, "added": 0, "tagged": 0, "violations": []}

    for store in astro_stores:
        kws = call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})
        ranking = {k["keyword"].lower() for k in kws if (k.get("currentRanking") or 1000) < 1000}
        field = field_singletons_for_store(repo, store, plan)
        # US: field + English target/wall phrases + rankings.
        # Non-US: only that locale's live field words + rankings (no English phrase bloat).
        if store == "us":
            allowed = field | targets | walls | ranking
        else:
            allowed = field | ranking

        to_remove = [k["keyword"] for k in kws if not should_keep(k, allowed)]
        if to_remove and not dry_run:
            remove_keywords(DEFAULT_MCP_URL, app_id, store, to_remove)
            time.sleep(0.4)
            stats["removed"] += len(to_remove)
        elif to_remove:
            stats["removed"] += len(to_remove)

        # Re-fetch after removal
        kws = call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})
        existing = {k["keyword"].lower() for k in kws}

        # Seed field words per store; target/wall phrases only on US (English strategy).
        seed_targets = targets if store == "us" else set()
        seed_walls = walls if store == "us" else set()
        seeds: list[str] = []
        for w in field | seed_targets | seed_walls:
            if w not in existing:
                seeds.append(w)
        print(f"  store {store}: -{len(to_remove)} +{len(seeds)}", flush=True)
        if seeds and not dry_run:
            r = add_keywords(DEFAULT_MCP_URL, app_id, store, sorted(seeds))
            stats["added"] += r.get("added", 0)
            time.sleep(0.4)
            kws = call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})

        if store == "us" and not dry_run:
            for k in kws:
                kl = k["keyword"].lower()
                tags = set(k.get("tags") or [])
                if kl in field and "deployed" not in tags:
                    set_tag(app_id, store, k["keyword"], "deployed")
                    stats["tagged"] += 1
                elif kl in targets and "target" not in tags:
                    set_tag(app_id, store, k["keyword"], "target")
                    stats["tagged"] += 1
                elif kl in walls and "wall" not in tags:
                    set_tag(app_id, store, k["keyword"], "wall")
                    stats["tagged"] += 1

        # Verify
        kws = call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})
        ranking = {k["keyword"].lower() for k in kws if (k.get("currentRanking") or 1000) < 1000}
        field = field_singletons_for_store(repo, store, plan)
        if store == "us":
            allowed = field | targets | walls | ranking
        else:
            allowed = field | ranking
        for k in kws:
            if not should_keep(k, allowed):
                stats["violations"].append(f"{store}:{k['keyword']}")

    return stats


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-pull", action="store_true")
    parser.add_argument("--app", help="astro app id filter")
    args = parser.parse_args()

    plan = load_stores_plan()
    astro_apps = {str(a["appId"]): a for a in list_apps(DEFAULT_MCP_URL)}

    total_removed = 0
    all_violations: list[str] = []

    for cfg in PORTFOLIO:
        app_id = cfg["astroId"]
        if args.app and app_id != args.app:
            continue
        if app_id not in astro_apps:
            print(f"SKIP {cfg['name']}: not in Astro")
            continue

        print(f"\n=== {cfg['name']} ({app_id}) ===")
        if cfg["pullAsc"] and not args.skip_pull:
            try:
                pull_live_asc(cfg["repo"])
            except Exception as e:
                print(f"  WARN ASC pull failed: {e}")

        stores = astro_apps[app_id].get("stores") or ["us"]
        stats = reconcile_app(cfg, stores, plan, dry_run=args.dry_run)
        total_removed += stats["removed"]
        all_violations.extend(stats["violations"])
        print(
            f"  removed={stats['removed']} added={stats['added']} "
            f"tagged={stats['tagged']} violations={len(stats['violations'])}"
        )

    print(f"\n=== TOTAL removed={total_removed} violations={len(all_violations)} ===")
    if all_violations:
        for v in all_violations[:20]:
            print(f"  ! {v}")
        if not args.dry_run:
            sys.exit(1)
    elif not args.dry_run:
        print("VERIFY OK — every keyword in every store has a role.")


if __name__ == "__main__":
    main()
