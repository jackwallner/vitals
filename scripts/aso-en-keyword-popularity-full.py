#!/usr/bin/env python3
"""
Full Astro popularity pull: en-US keyword seeds × all stores for an app.
Batches up to 100 keywords per store via add_keywords (returns popularity).
Checkpoints to JSON so runs can resume.

Usage:
  python3 scripts/aso-en-keyword-popularity-full.py --app bond
  python3 scripts/aso-en-keyword-popularity-full.py --app bond --min-pop 6
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from astro_mcp import call, ping, DEFAULT_MCP_URL  # noqa: E402

APPS: dict[str, dict] = {
    "bond": {
        "id": "6768514177",
        "seeds": [
            "relationship", "tracker", "countdown", "long", "distance", "messages", "notes",
            "date", "partner", "questions", "marriage", "paired", "couple", "anniversary",
            "reminder", "love language", "girlfriend", "boyfriend", "gifts", "gift",
            "widget", "streak", "calendar", "memory", "timer", "app", "log", "watch",
            "spouse", "husband", "wife", "together", "moments", "paired",
        ],
    },
    "fitness": {
        "id": "6762699692",
        "seeds": [
            "widget", "watch", "streak", "fitness", "workout", "habits", "complication",
            "wellness", "routine", "reminder", "counter", "chain", "steps", "exercise",
            "distance", "flights", "daily", "progress", "healthkit", "move", "stand",
        ],
    },
    "headache": {
        "id": "6762074561",
        "seeds": [
            "tracker", "widget", "log", "cluster", "migraine", "headache", "pain",
            "export", "forecast", "trigger", "symptom", "diary", "journal",
        ],
    },
    "sober": {
        "id": "6768869215",
        "seeds": [
            "streak", "app", "sobriety", "recovery", "journal", "calendar", "sober",
            "alcohol", "addiction", "abstinence", "relapse", "dry", "counter",
        ],
    },
    "gist": {
        "id": "6770138156",
        "seeds": [
            "conversation", "sports", "small talk", "fan", "fans", "football", "scores",
            "news", "daily", "icebreaker", "starter", "banter", "recap",
        ],
    },
    "calories": {
        "id": "6761743504",
        "seeds": [
            "tdee", "bmr", "kcal", "calories", "steps", "widget", "healthkit",
            "complication", "deficit", "metabolic", "pacing", "counter",
        ],
    },
    "baseball": {
        "id": "6763945657",
        "seeds": [
            "statcast", "savant", "fantasy", "mlb", "baseball", "barrel", "dfs",
            "wrc", "xwoba", "sprint", "strike", "ranking",
        ],
    },
    "glp": {
        "id": "6770137909",
        "seeds": [
            "glp-1", "glp1", "semaglutide", "ozempic", "mounjaro", "wegovy",
            "tracker", "injection", "dose", "shot", "shots", "peptide", "private",
        ],
    },
}

ALL_STORES = [
    "us", "mx", "es", "de", "fr", "it", "nl", "br", "pt", "in", "jp", "kr", "cn", "tw",
    "au", "ca", "gb", "pl", "se", "no", "dk", "fi", "tr", "sa", "th", "vn", "id", "my",
    "ru", "ua", "cz", "ro", "hu", "hr", "gr", "sk", "il",
]

CHECKPOINT = Path("/tmp/aso_en_keyword_pop_checkpoint.json")


def load_checkpoint() -> dict:
    if CHECKPOINT.exists():
        return json.loads(CHECKPOINT.read_text())
    return {}


def save_checkpoint(data: dict) -> None:
    CHECKPOINT.write_text(json.dumps(data, indent=2))


def fetch_store(app_id: str, store: str, seeds: list[str]) -> dict[str, dict]:
    """Batch-fetch popularity for all seeds in one store."""
    out: dict[str, dict] = {}
    # add_keywords returns popularity per keyword (skips existing)
    try:
        r = call(
            DEFAULT_MCP_URL,
            "add_keywords",
            {"appId": app_id, "store": store, "keywords": seeds},
            timeout=300,
        )
        if isinstance(r, dict) and "results" in r:
            for item in r["results"]:
                kw = item.get("keyword", "")
                out[kw.lower()] = {
                    "pop": item.get("popularity"),
                    "diff": item.get("difficulty"),
                    "skipped": item.get("skipped", False),
                }
    except Exception as e:
        out["__error__"] = {"pop": None, "diff": str(e)}
    # fill gaps via search_rankings
    for kw in seeds:
        kl = kw.lower()
        if kl in out and out[kl].get("pop") is not None:
            continue
        try:
            rows = call(
                DEFAULT_MCP_URL,
                "search_rankings",
                {"appId": app_id, "store": store, "keyword": kw},
                timeout=30,
            )
            if rows:
                for row in rows:
                    if row.get("keyword", "").lower() == kl:
                        out[kl] = {"pop": row.get("popularity"), "diff": row.get("difficulty")}
                        break
                if kl not in out:
                    out[kl] = {"pop": rows[0].get("popularity"), "diff": rows[0].get("difficulty")}
        except Exception:
            out.setdefault(kl, {"pop": None, "diff": None})
        time.sleep(0.1)
    return out


def print_summary(data: dict, seeds: list[str], min_pop: int) -> None:
    print(f"\n{'='*70}")
    print(f"EN keywords with pop >= {min_pop} (excluding us/gb/au/ca)")
    print(f"{'='*70}")
    en_stores = {"us", "gb", "au", "ca"}
    by_term: dict[str, list[tuple[str, int]]] = {}
    by_store: dict[str, list[tuple[str, int]]] = {}
    for store, kws in sorted(data.items()):
        if store.startswith("__"):
            continue
        for kw, meta in kws.items():
            if kw.startswith("__"):
                continue
            p = meta.get("pop")
            if not isinstance(p, (int, float)) or p < min_pop:
                continue
            by_term.setdefault(kw, []).append((store, int(p)))
            if store not in en_stores:
                by_store.setdefault(store, []).append((kw, int(p)))

    for store, hits in sorted(by_store.items()):
        hits.sort(key=lambda x: -x[1])
        print(f"\n{store}: " + ", ".join(f"{k}({p})" for k, p in hits))

    print(f"\n--- Cross-store (non-EN stores, pop>={min_pop}) ---")
    for kw, hits in sorted(by_term.items(), key=lambda x: (-len([h for h in x[1] if h[0] not in en_stores]), -max((h[1] for h in x[1]), default=0))):
        non_en = [(s, p) for s, p in hits if s not in en_stores]
        if len(non_en) >= 1:
            print(f"  {kw}: " + ", ".join(f"{s}:{p}" for s, p in sorted(non_en, key=lambda x: -x[1])))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, choices=sorted(APPS))
    parser.add_argument("--min-pop", type=int, default=6)
    parser.add_argument("--reset", action="store_true")
    args = parser.parse_args()

    if not ping():
        raise SystemExit("Astro MCP not reachable — open Astro and enable MCP")

    cfg = APPS[args.app]
    app_id = cfg["id"]
    seeds = list(dict.fromkeys(cfg["seeds"]))  # dedupe preserve order

    ck = {} if args.reset else load_checkpoint()
    ck.setdefault(args.app, {})

    for i, store in enumerate(ALL_STORES):
        if store in ck[args.app] and "__error__" not in ck[args.app][store]:
            print(f"[{i+1}/{len(ALL_STORES)}] {store} cached", flush=True)
            continue
        print(f"[{i+1}/{len(ALL_STORES)}] {store} fetching {len(seeds)} terms...", flush=True)
        ck[args.app][store] = fetch_store(app_id, store, seeds)
        save_checkpoint(ck)
        time.sleep(0.5)

    out_path = Path(f"/tmp/aso_en_pop_{args.app}_full.json")
    out_path.write_text(json.dumps(ck[args.app], indent=2))
    print(f"\nWrote {out_path}")
    print_summary(ck[args.app], seeds, args.min_pop)


if __name__ == "__main__":
    main()
