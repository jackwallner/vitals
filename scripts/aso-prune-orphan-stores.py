#!/usr/bin/env python3
"""Remove all keywords from Astro stores with no dedicated ASC locale."""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from astro_mcp import call, list_apps, remove_keywords, DEFAULT_MCP_URL, ping  # noqa: E402

LOCALE_TO_STORE: dict[str, str] = {
    "ar-SA": "sa", "ca": "es", "cs": "cz", "da": "dk", "de-DE": "de", "el": "gr",
    "en-AU": "au", "en-CA": "ca", "en-GB": "gb", "en-US": "us", "es-ES": "es", "es-MX": "mx",
    "fi": "fi", "fr-CA": "ca", "fr-FR": "fr", "he": "il", "hi": "in", "hr": "hr", "hu": "hu",
    "id": "id", "it": "it", "ja": "jp", "ko": "kr", "ms": "my", "nl-NL": "nl", "no": "no",
    "pl": "pl", "pt-BR": "br", "pt-PT": "pt", "ro": "ro", "ru": "ru", "sk": "sk", "sv": "se",
    "th": "th", "tr": "tr", "uk": "ua", "vi": "vn", "zh-Hans": "cn", "zh-Hant": "tw",
}

APPS: list[dict[str, str]] = [
    {"astroId": "6762699692", "repo": "/Users/jackwallner/fitness-streaks", "name": "Fitness Habits"},
]


def dedicated_stores(repo: Path) -> set[str]:
    stores: set[str] = set()
    meta = repo / "fastlane" / "metadata"
    if not meta.is_dir():
        return stores
    for loc in meta.iterdir():
        if loc.is_dir() and LOCALE_TO_STORE.get(loc.name):
            stores.add(LOCALE_TO_STORE[loc.name])
    return stores


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--app", help="Astro app id filter")
    args = parser.parse_args()

    if not ping(DEFAULT_MCP_URL):
        raise SystemExit("Astro MCP not reachable")

    astro = {str(a["appId"]): a for a in list_apps(DEFAULT_MCP_URL)}
    total_removed = 0

    for cfg in APPS:
        app_id = cfg["astroId"]
        if args.app and app_id != args.app:
            continue
        if app_id not in astro:
            print(f"SKIP {cfg['name']}: not in Astro")
            continue

        keep = dedicated_stores(Path(cfg["repo"]))
        astro_stores = set(astro[app_id].get("stores") or [])
        orphans = sorted(astro_stores - keep)
        print(f"\n=== {cfg['name']} ({app_id}) ===")
        print(f"  keep={len(keep)} astro={len(astro_stores)} orphan={len(orphans)}")

        for store in orphans:
            kws = call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})
            keywords = [k["keyword"] for k in kws]
            if not keywords:
                print(f"  {store}: empty")
                continue
            print(f"  {store}: removing {len(keywords)} keywords", flush=True)
            if not args.dry_run:
                remove_keywords(DEFAULT_MCP_URL, app_id, store, keywords)
                time.sleep(0.3)
            total_removed += len(keywords)

    print(f"\n=== DONE removed={total_removed} ===")


if __name__ == "__main__":
    main()
