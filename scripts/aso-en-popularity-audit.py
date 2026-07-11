#!/usr/bin/env python3
"""
Audit which en-US keyword tokens have meaningful search volume in each Astro store.

Run with Astro desktop open (MCP on :8089). Output guides hybrid metadata:
  - pop >= 40: strong EN loanword candidate for that store
  - pop 15-39: include if room after native terms + dedupe
  - pop < 15: skip unless brand term

Usage:
  python3 scripts/aso-en-popularity-audit.py --app bond
  python3 scripts/aso-en-popularity-audit.py --app fitness --app gist
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from astro_mcp import call, ping, DEFAULT_MCP_URL, list_apps, find_app_id  # noqa: E402

APPS: dict[str, dict] = {
    "bond": {
        "id": "6768514177",
        "repo": Path("/Users/jackwallner/bond"),
        "en_seeds": [
            "relationship", "tracker", "countdown", "partner", "marriage", "couple",
            "anniversary", "distance", "messages", "notes", "date", "paired", "love language",
        ],
    },
    "fitness": {
        "id": "6762699692",
        "repo": Path("/Users/jackwallner/fitness-streaks"),
        "en_seeds": [
            "widget", "watch", "streak", "fitness", "workout", "habits", "complication",
            "wellness", "routine", "reminder", "counter", "chain", "steps", "exercise",
        ],
    },
    "gist": {
        "id": "6770138156",
        "repo": Path("/Users/jackwallner/sports"),
        "en_seeds": [
            "conversation", "sports", "small talk", "fan", "football", "scores", "news", "daily",
        ],
    },
    "headache": {
        "id": "6762074561",
        "repo": Path("/Users/jackwallner/headaches"),
        "en_seeds": ["tracker", "widget", "log", "cluster", "migraine", "headache", "pain", "export"],
    },
    "sober": {
        "id": "6768869215",
        "repo": Path("/Users/jackwallner/sober"),
        "en_seeds": ["streak", "app", "sobriety", "recovery", "journal", "calendar"],
    },
    "calories": {
        "id": "6761743504",
        "repo": Path("/Users/jackwallner/vitals"),
        "en_seeds": ["tdee", "bmr", "kcal", "calories", "steps", "widget", "healthkit"],
    },
    "baseball": {
        "id": "6763945657",
        "repo": Path("/Users/jackwallner/baseball"),
        "en_seeds": ["statcast", "savant", "fantasy", "mlb", "baseball", "barrel", "dfs"],
    },
    "glp": {
        "id": "6770137909",
        "repo": Path("/Users/jackwallner/simpleglp"),
        "en_seeds": ["glp-1", "semaglutide", "ozempic", "mounjaro", "tracker", "injection", "dose"],
    },
}

STORES = [
    "us", "mx", "in", "de", "fr", "es", "br", "jp", "kr", "cn", "tw", "it", "nl", "se",
    "au", "ca", "gb", "pl", "tr", "sa", "th", "vn", "id", "my", "ru", "ua", "cz", "dk",
    "fi", "no", "pt", "ro", "hu", "hr", "gr", "sk", "il",
]

THRESHOLD_STRONG = 40
THRESHOLD_WEAK = 15


def popularity(app_id: str, store: str, keyword: str) -> int | None:
    try:
        rows = call(
            DEFAULT_MCP_URL,
            "search_rankings",
            {"appId": app_id, "store": store, "keyword": keyword},
            timeout=30,
        )
        if not rows:
            r = call(
                DEFAULT_MCP_URL,
                "add_keywords",
                {"appId": app_id, "store": store, "keywords": [keyword]},
                timeout=120,
            )
            if isinstance(r, dict) and "results" in r:
                for item in r["results"]:
                    if item.get("keyword", "").lower() == keyword.lower():
                        return item.get("popularity")
            time.sleep(0.3)
            rows = call(
                DEFAULT_MCP_URL,
                "search_rankings",
                {"appId": app_id, "store": store, "keyword": keyword},
                timeout=30,
            )
        if not rows:
            return None
        for item in rows:
            if item.get("keyword", "").lower() == keyword.lower():
                return item.get("popularity")
        return rows[0].get("popularity")
    except Exception:
        return None


def audit_app(cfg: dict) -> dict:
    app_id = cfg["id"]
    out: dict[str, dict[str, int | None]] = {}
    for store in STORES:
        out[store] = {}
        strong, weak = [], []
        for kw in cfg["en_seeds"]:
            pop = popularity(app_id, store, kw)
            out[store][kw] = pop
            if pop is None:
                continue
            if pop >= THRESHOLD_STRONG:
                strong.append(f"{kw}({pop})")
            elif pop >= THRESHOLD_WEAK:
                weak.append(f"{kw}({pop})")
            time.sleep(0.15)
        if strong or weak:
            print(f"  {store}: strong=[{', '.join(strong)}] weak=[{', '.join(weak)}]")
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", action="append", required=True, choices=sorted(APPS))
    parser.add_argument("-o", "--output", type=Path, default=Path("/tmp/astro_en_popularity_audit.json"))
    args = parser.parse_args()

    if not ping():
        raise SystemExit("Astro MCP not reachable — open Astro and enable MCP")

    report = {}
    for key in args.app:
        cfg = APPS[key]
        print(f"\n=== {key} ({cfg['id']}) ===", flush=True)
        report[key] = audit_app(cfg)

    args.output.write_text(json.dumps(report, indent=2))
    print(f"\nWrote {args.output}")


if __name__ == "__main__":
    main()
