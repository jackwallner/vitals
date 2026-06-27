#!/usr/bin/env python3
"""Migrate all Jack iOS apps to deployed/target/wall tag taxonomy (aso.md §5)."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from astro_mcp import call, DEFAULT_MCP_URL, add_keywords  # noqa: E402

LEGACY_TAGS = (
    "priority",
    "push",
    "defend",
    "phrase",
    "benchmark",
    "sideline-live",
    "kw-refresh-jun26",
    "v1.0.1",
    "aspirational",
    "drop-candidate",
    "tier1-hero",
)

APPS: dict[str, dict[str, Any]] = {
    "6761743504": {
        "name": "Total Calories",
        "deployed": [
            "tdee",
            "bmr",
            "complication",
            "resting",
            "active",
            "ring",
            "calculator",
            "deficit",
            "net",
            "kcal",
            "energy",
            "steps",
            "metabolic",
            "pacing",
        ],
        "target": [
            "tdee tracker",
            "tdee bmr",
            "tdee calculator",
            "bmr calculator",
            "total energy",
            "total daily energy expenditure",
            "bmi",
            "bmi calculator",
            "metabolic",
            "complication",
        ],
        "wall": [
            "calorie tracker",
            "calorie counter",
            "calorie deficit tracker",
            "calorie calculator",
            "apple fitness",
        ],
        "add_keywords": [],
    },
    "6762074561": {
        "name": "Headache Tracker",
        "deployed": [
            "simple",
            "track",
            "barometric",
            "pressure",
            "cluster",
            "tension",
            "trigger",
            "pain",
            "relief",
            "forecast",
            "chronic",
            "aura",
            "export",
            "seconds",
        ],
        "target": [
            "one tap headache",
            "headache forecast",
            "barometric headache",
            "headache tracker",
            "pressure headache",
            "track migraine",
            "migraine forecast",
            "cluster headache tracker",
            "one tap migraine",
        ],
        "wall": [
            "migraine buddy",
            "migraine tracker",
            "weather migraine",
            "headache diary",
            "pressure pal",
            "symptom diary",
        ],
        "add_keywords": ["symptom diary", "relief"],
    },
    "6768514177": {
        "name": "Bond",
        "deployed": [
            "countdown",
            "long",
            "distance",
            "messages",
            "notes",
            "date",
            "partner",
            "questions",
            "marriage",
            "nudge",
            "spouse",
            "milestone",
        ],
        "target": [
            "love language",
            "love language app",
            "love language reminder",
            "love language reminders",
            "love languages",
            "love reminder",
            "marriage reminder",
            "partner reminder",
            "relationship reminders",
            "bond love",
        ],
        "wall": [
            "love nudge",
            "couples app",
            "paired",
            "relationship tracker",
            "anniversary countdown",
            "love counter",
            "cozy couples",
        ],
        "add_keywords": [
            "countdown",
            "long",
            "distance",
            "messages",
            "notes",
            "date",
            "partner",
            "questions",
            "marriage",
            "nudge",
            "spouse",
            "milestone",
            "anniversary countdown",
        ],
    },
    "6768869215": {
        "name": "Sober Tracker",
        "deployed": [
            "countdown",
            "quit",
            "drinking",
            "cut",
            "time",
            "streak",
            "recovery",
            "daily",
            "abstinence",
            "since",
            "clean",
            "january",
            "widget",
        ],
        "target": [
            "dry days",
            "dry january",
            "alcohol countdown",
            "sober countdown",
            "sober app",
            "quit drinking",
            "abstinence tracker",
            "apple watch sober",
        ],
        "wall": [
            "sober tracker",
            "i am sober",
            "alcohol free",
            "habit tracker",
            "drink less",
            "alcohol tracker",
        ],
        "add_keywords": [
            "sober tracker",
            "i am sober",
            "alcohol free",
            "habit tracker",
            "drink less",
            "alcohol tracker",
            "countdown",
            "quit",
            "drinking",
            "cut",
            "time",
            "recovery",
            "daily",
            "since",
            "clean",
            "widget",
        ],
    },
    "6770138156": {
        "name": "Gist",
        "deployed": [
            "beginners",
            "explained",
            "understand",
            "questions",
            "coworker",
            "watercooler",
            "office",
            "party",
            "fan",
            "non",
            "brief",
            "casual",
            "clueless",
        ],
        "target": [
            "talking points",
            "small talk",
            "things to talk about",
            "non sports fan",
            "sports brief",
            "sports recap",
            "sports small talk",
        ],
        "wall": [
            "sports news",
            "sports scores",
            "conversation starters",
            "icebreaker",
            "party games",
            "college football",
        ],
        "add_keywords": [
            "beginners",
            "explained",
            "understand",
            "questions",
            "coworker",
            "watercooler",
            "office",
            "party",
            "fan",
            "non",
            "brief",
            "casual",
            "clueless",
            "sports small talk",
            "sports news",
            "sports scores",
            "conversation starters",
            "icebreaker",
            "party games",
            "college football",
        ],
    },
    "6763945657": {
        "name": "Baseball StatScout",
        "deployed": [
            "savant",
            "xwoba",
            "oaa",
            "wrc",
            "wrcplus",
            "barrel",
            "exit",
            "velocity",
            "hitting",
            "pitching",
            "fielding",
            "metrics",
            "percentile",
            "analytics",
        ],
        "target": [
            "baseball savant",
            "mlb savant",
            "statcast",
            "statcast percentiles",
            "baseball percentiles",
            "savant stats",
            "baseball analytics",
            "statcast leaderboard",
            "mlb statcast",
        ],
        "wall": [
            "mlb",
            "scout",
            "velo",
            "sports",
            "war",
            "sports analytics",
            "baseball app",
        ],
        "add_keywords": ["scout", "velo", "sports", "war", "exit", "velocity", "hitting", "pitching", "fielding", "metrics", "analytics", "percentile"],
    },
    "6770137909": {
        "name": "Simple GLP",
        "deployed": [
            "mounjaro",
            "semaglutide",
            "tirzepatide",
            "weekly",
            "reminder",
            "private",
            "log",
            "injection",
            "dose",
            "schedule",
            "shotsy",
            "journey",
        ],
        "target": [
            "simple glp",
            "simple shot tracker",
            "simple glp1",
            "shot reminder",
            "weekly shot",
            "glp-1 shot",
            "ozempic shot",
            "weekly shot tracker",
            "glp-1 diary",
            "zepbound shot",
        ],
        "wall": [
            "glp1 tracker",
            "glp-1 tracker",
            "weight loss tracker",
            "apple watch",
            "health app",
        ],
        "add_keywords": [
            "glp1 tracker",
            "glp-1 tracker",
            "weight loss tracker",
            "dose",
            "schedule",
            "journey",
            "reminder",
            "private",
        ],
    },
    "6762699692": {
        "name": "Fitness Habits",
        "deployed": [
            "stand",
            "ring",
            "step",
            "sleep",
            "exercise",
            "watch",
            "move",
            "apple",
            "healthkit",
            "activity",
            "goal",
            "day",
            "progress",
            "close",
            "train",
            "habits",
            "fitness",
            "streak",
            "tracker",
        ],
        "target": [
            "stand streak",
            "move streak",
            "ring streak",
            "step streak",
            "healthkit streak",
            "fitness habits",
            "health streaks",
            "exercise streak",
            "apple health streak",
            "streak finder",
        ],
        "wall": [
            "habit tracker",
            "steps",
            "workout",
            "widget",
            "health",
            "apple watch",
            "fitness app",
        ],
        "add_keywords": ["close", "train", "apple", "goal", "activity"],
    },
    "104": {
        "name": "Posture (placeholder)",
        "deployed": [
            "reminder",
            "habit",
            "health",
            "body",
            "back",
            "care",
            "spine",
            "align",
            "tracker",
            "streak",
            "airpods",
            "watch",
            "widget",
            "slouch",
            "hunch",
            "posture",
        ],
        "target": [
            "posture reminder",
            "posture check",
            "posture tracker",
            "airpods posture",
            "desk posture",
            "slouch",
            "neck posture",
            "text neck",
            "improve posture",
        ],
        "wall": [
            "habit tracker",
            "fitness",
            "upright",
            "apple health",
        ],
        "add_keywords": [
            "habit tracker",
            "fitness",
            "upright",
            "body",
            "care",
            "hunch",
            "reminder",
            "habit",
            "health",
            "align",
        ],
    },
}


def get_keywords(mcp_url: str, app_id: str, store: str) -> list[dict[str, Any]]:
    return call(mcp_url, "get_app_keywords", {"appId": app_id, "store": store})


def set_tag(
    mcp_url: str,
    app_id: str,
    store: str,
    keyword: str,
    tag: str,
    action: str,
    *,
    sleep: float = 0.35,
) -> dict[str, Any]:
    try:
        result = call(
            mcp_url,
            "set_keyword_tag",
            {
                "appId": app_id,
                "store": store,
                "keyword": keyword,
                "tag": tag,
                "action": action,
            },
        )
        time.sleep(sleep)
        return {"ok": True, "result": result}
    except RuntimeError as e:
        msg = str(e)
        if "already assigned" in msg.lower() or "not assigned" in msg.lower():
            return {"ok": True, "skipped": msg}
        return {"ok": False, "error": msg}


def migrate_app(mcp_url: str, app_id: str, store: str = "us") -> dict[str, Any]:
    cfg = APPS[app_id]
    name = cfg["name"]
    print(f"\n=== {name} ({app_id}) store={store} ===")

    existing = {k["keyword"].lower(): k for k in get_keywords(mcp_url, app_id, store)}
    print(f"  tracked: {len(existing)}")

    to_add = [kw for kw in cfg.get("add_keywords", []) if kw.lower() not in existing]
    if to_add:
        print(f"  adding {len(to_add)} keywords...")
        add_result = add_keywords(mcp_url, app_id, store, to_add)
        print(f"  added ~{add_result.get('added', 0)}")
        time.sleep(2)
        existing = {k["keyword"].lower(): k for k in get_keywords(mcp_url, app_id, store)}

    stats = {"deployed": 0, "target": 0, "wall": 0, "legacy_removed": 0, "errors": []}

    for tag_name in ("deployed", "target", "wall"):
        for kw in cfg.get(tag_name, []):
            if kw.lower() not in existing:
                stats["errors"].append(f"missing {tag_name}: {kw}")
                continue
            r = set_tag(mcp_url, app_id, store, kw, tag_name, "add")
            if r.get("ok"):
                stats[tag_name] += 1
            else:
                stats["errors"].append(f"add {tag_name} {kw}: {r.get('error')}")

    for kw_lower, meta in existing.items():
        tags = meta.get("tags") or []
        for legacy in LEGACY_TAGS:
            if legacy in tags:
                r = set_tag(mcp_url, app_id, store, meta["keyword"], legacy, "remove")
                if r.get("ok"):
                    stats["legacy_removed"] += 1
                else:
                    stats["errors"].append(
                        f"remove {legacy} from {meta['keyword']}: {r.get('error')}"
                    )

    print(
        f"  deployed={stats['deployed']} target={stats['target']} wall={stats['wall']} "
        f"legacy_removed={stats['legacy_removed']} errors={len(stats['errors'])}"
    )
    if stats["errors"][:5]:
        for e in stats["errors"][:5]:
            print(f"    ! {e}")
    return stats


def main() -> None:
    mcp_url = DEFAULT_MCP_URL
    store = "us"
    if len(sys.argv) > 1:
        app_filter = sys.argv[1:]
    else:
        app_filter = list(APPS.keys())

    all_stats: dict[str, Any] = {}
    for app_id in app_filter:
        if app_id not in APPS:
            print(f"Unknown app id: {app_id}")
            continue
        all_stats[app_id] = migrate_app(mcp_url, app_id, store)

    tags = call(mcp_url, "manage_tag", {"action": "list"})
    print("\n=== Account tag counts ===")
    for t in sorted(tags, key=lambda x: x["name"]):
        print(f"  {t['name']}: {t['keywordsCount']}")

    print("\n=== Summary ===")
    print(json.dumps(all_stats, indent=2))


if __name__ == "__main__":
    main()
