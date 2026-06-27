#!/usr/bin/env python3
"""
Sync live ASC metadata → Astro for all Jack Wallner apps.

Per store (dedicated ASC locale only — no fallback-locale merging):
  1. Pull name, subtitle, keywords from App Store Connect API
  2. Split into individual tokens + related combo phrases
  3. Merge-add keywords to Astro (never remove tracked keywords)
  4. Tag ASC-derived keywords `deployed`; strip `deployed` from everything else

Stores are created in Astro when keywords are added to a new store code.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from astro_mcp import add_keywords, call, list_apps, DEFAULT_MCP_URL, ping  # noqa: E402

# ASC locale → Astro store (direct mapping only; no fallback locales)
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
    {"astroId": "6761743504", "repo": Path("/Users/jackwallner/vitals"), "name": "Total Calories"},
    {"astroId": "6762074561", "repo": Path("/Users/jackwallner/headaches"), "name": "Headache Tracker"},
    {"astroId": "6768514177", "repo": Path("/Users/jackwallner/bond"), "name": "Bond"},
    {"astroId": "6768869215", "repo": Path("/Users/jackwallner/sober"), "name": "Sober Tracker"},
    {"astroId": "6770138156", "repo": Path("/Users/jackwallner/sports"), "name": "Gist"},
    {"astroId": "6763945657", "repo": Path("/Users/jackwallner/baseball"), "name": "Baseball StatScout"},
    {"astroId": "6770137909", "repo": Path("/Users/jackwallner/simpleglp"), "name": "Simple GLP"},
    {"astroId": "6762699692", "repo": Path("/Users/jackwallner/fitness-streaks"), "name": "Fitness Habits"},
]

NAME_SEPARATORS = (" - ", " – ", " — ", ":", "|")
MIN_WORD_LEN = 2
MAX_PHRASE_LEN = 60


def load_asc_lib(repo: Path):
    path = repo / "scripts" / "asc_lib.py"
    if not path.exists():
        raise FileNotFoundError(path)
    spec = importlib.util.spec_from_file_location(f"asc_lib_{repo.name}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def is_cjk(text: str) -> bool:
    return bool(re.search(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]", text))


def norm_key(keyword: str) -> str:
    return keyword if is_cjk(keyword) else keyword.lower()


def tokens_from_keywords_field(raw: str) -> list[str]:
    raw = raw.replace("，", ",").replace("、", ",")
    return [t.strip() for t in raw.split(",") if t.strip()]


def words_from_text(text: str, *, cjk: bool) -> list[str]:
    if not text or cjk:
        return []
    return [w for w in re.findall(r"[\w']+", text.lower()) if len(w) >= MIN_WORD_LEN]


def segments_from_text(text: str, *, cjk: bool) -> list[str]:
    if not text.strip():
        return []
    out: list[str] = []
    if cjk:
        if len(text.strip()) <= MAX_PHRASE_LEN:
            out.append(text.strip())
        return out
    low = text.strip().lower()
    for sep in NAME_SEPARATORS:
        if sep in text:
            out.extend(p.strip().lower() for p in text.split(sep) if p.strip())
    if len(low) <= MAX_PHRASE_LEN:
        out.append(low)
    return out


def adjacent_bigrams(words: list[str]) -> list[str]:
    out: list[str] = []
    for i in range(len(words) - 1):
        a, b = words[i], words[i + 1]
        if len(a) >= MIN_WORD_LEN and len(b) >= MIN_WORD_LEN:
            out.append(f"{a} {b}")
    return out


def extract_deployed_keywords(name: str, subtitle: str, keywords_raw: str) -> list[str]:
    """Individuals from all three ASC fields + related combo phrases."""
    cjk = is_cjk(name + subtitle + keywords_raw)
    items: list[str] = []

    # Keyword field — comma-separated singletons
    for tok in tokens_from_keywords_field(keywords_raw):
        items.append(tok.lower() if not is_cjk(tok) else tok)

    for text in (name, subtitle):
        items.extend(segments_from_text(text, cjk=cjk))
        words = words_from_text(text, cjk=cjk)
        items.extend(words)
        items.extend(adjacent_bigrams(words))

    # Cross-field adjacent bigrams on the combined word stream
    combined_words = words_from_text(f"{name} {subtitle}", cjk=cjk)
    items.extend(adjacent_bigrams(combined_words))

    seen: set[str] = set()
    out: list[str] = []
    for k in items:
        k = k.strip()
        if not k or len(k) > MAX_PHRASE_LEN:
            continue
        key = norm_key(k)
        if key not in seen:
            seen.add(key)
            out.append(k.lower() if not is_cjk(k) else k)
    return out


def pull_live_asc(repo: Path) -> dict[str, dict[str, str]]:
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

    pulled: dict[str, dict[str, str]] = {}
    for locale in sorted(set(info_by_locale) | set(ver_by_locale)):
        info = info_by_locale.get(locale, {})
        ver = ver_by_locale.get(locale, {})
        name = (info.get("name") or "").strip()
        subtitle = (info.get("subtitle") or "").strip()
        keywords = (ver.get("keywords") or "").strip()
        if name or subtitle or keywords:
            pulled[locale] = {"name": name, "subtitle": subtitle, "keywords": keywords}

    print(
        f"  ASC pull {repo.name}: v{live_v['attributes']['versionString']} "
        f"{len(pulled)} locales with metadata"
    )
    return pulled


def build_store_deployed(pulled: dict[str, dict[str, str]]) -> dict[str, set[str]]:
    """Map dedicated ASC locales → Astro stores; union when multiple locales share a store."""
    by_store: dict[str, set[str]] = {}
    for locale, meta in pulled.items():
        store = LOCALE_TO_STORE.get(locale)
        if not store:
            continue
        kws = extract_deployed_keywords(meta["name"], meta["subtitle"], meta["keywords"])
        by_store.setdefault(store, set()).update(norm_key(k) for k in kws)
    return by_store


def set_tag(app_id: str, store: str, keyword: str, tag: str, *, action: str) -> None:
    call(
        DEFAULT_MCP_URL,
        "set_keyword_tag",
        {"appId": app_id, "store": store, "keyword": keyword, "tag": tag, "action": action},
    )
    time.sleep(0.15)


def sync_store(
    app_id: str,
    store: str,
    deployed_norm: set[str],
    deployed_canonical: dict[str, str],
    *,
    dry_run: bool,
) -> dict[str, int]:
    stats = {"added": 0, "tagged": 0, "untagged": 0}
    kws = call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})
    existing_norm = {norm_key(k["keyword"]): k["keyword"] for k in kws}

    to_add = [deployed_canonical[n] for n in deployed_norm if n not in existing_norm]
    if to_add and not dry_run:
        r = add_keywords(DEFAULT_MCP_URL, app_id, store, sorted(to_add))
        stats["added"] = r.get("added", 0)
        time.sleep(0.3)
        kws = call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})
    elif to_add:
        stats["added"] = len(to_add)

    for k in kws:
        kl = norm_key(k["keyword"])
        tags = set(k.get("tags") or [])
        if kl in deployed_norm and "deployed" not in tags:
            if not dry_run:
                set_tag(app_id, store, k["keyword"], "deployed", action="add")
            stats["tagged"] += 1
        elif kl not in deployed_norm and "deployed" in tags:
            if not dry_run:
                set_tag(app_id, store, k["keyword"], "deployed", action="remove")
            stats["untagged"] += 1

    return stats


def sync_app(cfg: dict[str, Any], *, dry_run: bool, skip_pull: bool) -> dict[str, Any]:
    app_id = cfg["astroId"]
    repo: Path = cfg["repo"]
    pulled = pull_live_asc(repo) if not skip_pull else {}
    if skip_pull:
        # Rebuild from fastlane/metadata on disk
        meta_root = repo / "fastlane" / "metadata"
        for locale_dir in sorted(meta_root.iterdir()):
            if not locale_dir.is_dir():
                continue
            locale = locale_dir.name
            name = (locale_dir / "name.txt").read_text(encoding="utf-8").strip() if (locale_dir / "name.txt").exists() else ""
            subtitle = (locale_dir / "subtitle.txt").read_text(encoding="utf-8").strip() if (locale_dir / "subtitle.txt").exists() else ""
            keywords = (locale_dir / "keywords.txt").read_text(encoding="utf-8").strip() if (locale_dir / "keywords.txt").exists() else ""
            if name or subtitle or keywords:
                pulled[locale] = {"name": name, "subtitle": subtitle, "keywords": keywords}

    by_store = build_store_deployed(pulled)
    totals = {"stores": 0, "deployed_keywords": 0, "added": 0, "tagged": 0, "untagged": 0}

    for store, deployed_norm in sorted(by_store.items()):
        # Canonical form for adds (lowercase Latin)
        canonical: dict[str, str] = {}
        for locale, meta in pulled.items():
            if LOCALE_TO_STORE.get(locale) != store:
                continue
            for kw in extract_deployed_keywords(meta["name"], meta["subtitle"], meta["keywords"]):
                canonical.setdefault(norm_key(kw), kw.lower() if not is_cjk(kw) else kw)

        st = sync_store(app_id, store, deployed_norm, canonical, dry_run=dry_run)
        totals["stores"] += 1
        totals["deployed_keywords"] += len(deployed_norm)
        totals["added"] += st["added"]
        totals["tagged"] += st["tagged"]
        totals["untagged"] += st["untagged"]
        print(
            f"  {store}: deployed={len(deployed_norm)} +{st['added']} "
            f"tag={st['tagged']} untag={st['untagged']}",
            flush=True,
        )

    return totals


def main() -> None:
    parser = argparse.ArgumentParser(description="Sync live ASC metadata → Astro deployed tags")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-pull", action="store_true", help="Use fastlane/metadata on disk")
    parser.add_argument("--app", help="Astro app id filter")
    args = parser.parse_args()

    if not ping(DEFAULT_MCP_URL):
        raise SystemExit("Astro MCP not reachable — open Astro and enable MCP")

    astro_apps = {str(a["appId"]): a for a in list_apps(DEFAULT_MCP_URL)}
    grand = {"added": 0, "tagged": 0, "untagged": 0, "stores": 0}

    for cfg in PORTFOLIO:
        app_id = cfg["astroId"]
        if args.app and app_id != args.app:
            continue
        if app_id not in astro_apps:
            print(f"SKIP {cfg['name']}: not in Astro")
            continue

        print(f"\n=== {cfg['name']} ({app_id}) ===", flush=True)
        try:
            totals = sync_app(cfg, dry_run=args.dry_run, skip_pull=args.skip_pull)
        except Exception as e:
            print(f"  ERROR: {e}", flush=True)
            continue
        for k in grand:
            grand[k] += totals.get(k, 0)
        print(
            f"  → stores={totals['stores']} deployed_kw={totals['deployed_keywords']} "
            f"+{totals['added']} tag={totals['tagged']} untag={totals['untagged']}",
            flush=True,
        )

    print(
        f"\n=== DONE stores={grand['stores']} +{grand['added']} "
        f"tag={grand['tagged']} untag={grand['untagged']} ==="
    )


if __name__ == "__main__":
    main()
