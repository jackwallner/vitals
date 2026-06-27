#!/usr/bin/env python3
"""Prune non-US Astro keywords: pop<=5 @ rank 1000 not in US keep-set."""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from astro_mcp import call, list_apps, remove_keywords, DEFAULT_MCP_URL  # noqa: E402

APPS = [
    "6768514177",  # Bond
    "6762074561",  # Headaches
    "6762699692",  # Fitness
    "6770137909",  # Simple GLP
    "6761743504",  # Total Calories
    "6770138156",  # Gist
    "6768869215",  # Sober
    "6763945657",  # Baseball
    "104",         # Posture placeholder
]


def prune_app(mcp_url: str, app_id: str, *, dry_run: bool = False) -> dict:
    apps = list_apps(mcp_url)
    app = next((a for a in apps if str(a["appId"]) == app_id), None)
    if not app:
        raise SystemExit(f"App {app_id} not found")
    stores = app.get("stores") or []
    us_kws = {
        k["keyword"].lower()
        for k in call(mcp_url, "get_app_keywords", {"appId": app_id, "store": "us"})
    }
    removed_total = 0
    per_store: dict[str, int] = {}

    for store in stores:
        if store == "us":
            continue
        kws = call(mcp_url, "get_app_keywords", {"appId": app_id, "store": store})
        to_remove = [
            k["keyword"]
            for k in kws
            if k.get("currentRanking") == 1000
            and (k.get("popularity") or 0) <= 5
            and k["keyword"].lower() not in us_kws
        ]
        if to_remove:
            per_store[store] = len(to_remove)
            if not dry_run:
                remove_keywords(mcp_url, app_id, store, to_remove)
                time.sleep(1.5)
            removed_total += len(to_remove)

    return {"app": app.get("name"), "us_keep": len(us_kws), "removed": removed_total, "stores": per_store}


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("app_ids", nargs="*", default=APPS)
    args = p.parse_args()

    for app_id in args.app_ids:
        r = prune_app(DEFAULT_MCP_URL, app_id, dry_run=args.dry_run)
        print(f"{r['app']}: US keep={r['us_keep']} removed={r['removed']} ({len(r['stores'])} stores)")
        if r["stores"]:
            top = sorted(r["stores"].items(), key=lambda x: -x[1])[:5]
            print(f"  top stores: {top}")


if __name__ == "__main__":
    main()
