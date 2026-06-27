#!/usr/bin/env python3
"""Verify every tracked Astro keyword has a useful role per ~/Desktop/aso.md."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from astro_mcp import call, list_apps, DEFAULT_MCP_URL  # noqa: E402

REPOS = {
    "6761743504": Path("/Users/jackwallner/vitals"),
    "6762074561": Path("/Users/jackwallner/headaches"),
    "6768514177": Path("/Users/jackwallner/bond"),
    "6768869215": Path("/Users/jackwallner/sober"),
    "6770138156": Path("/Users/jackwallner/sports"),
    "6763945657": Path("/Users/jackwallner/baseball"),
    "6770137909": Path("/Users/jackwallner/simpleglp"),
    "6762699692": Path("/Users/jackwallner/fitness-streaks"),
    "104": Path("/Users/jackwallner/posture"),
}

# Known false-friends / moderation junk from aso-plans
BLOCKLIST = {
    "6768869215": {
        "alcohol diary",  # moderation SERP
        "sober streak",   # collapsed post-refresh, not in field
    },
    "6762074561": set(),  # already cleaned
}

# Phrases that are brand/ranking anchors worth keeping even untagged if rank <= 250
def load_field_pool(repo: Path) -> set[str]:
    pool: set[str] = set()
    meta = repo / "fastlane/metadata/en-US"
    for fname in ("keywords.txt", "subtitle.txt", "name.txt"):
        p = meta / fname
        if p.exists():
            text = p.read_text().strip().lower()
            for part in re.split(r"[,/&\-\s]+", text):
                part = part.strip()
                if part and part not in ("the", "a", "an", "for", "and", "on", "from", "with"):
                    pool.add(part)
    return pool


def classify(kw: dict, field_pool: set[str], blocklist: set[str]) -> tuple[str, str]:
    keyword = kw["keyword"]
    tags = set(kw.get("tags") or [])
    rank = kw.get("currentRanking") or 1000
    pop = kw.get("popularity") or 0
    diff = kw.get("difficulty") or 0

    if keyword.lower() in blocklist:
        return "REMOVE", "blocklist (aso-plan false-friend)"

    if "deployed" in tags:
        if rank == 1000 and pop > 5:
            return "OK", "deployed field word (watch indexing)"
        return "OK", "deployed field word"

    if "target" in tags:
        if pop <= 5 and rank >= 250:
            return "OK", "target cluster (ownable-floor niche)"
        if diff > 65 and pop > 5 and rank >= 100:
            return "WATCH", "target but diff>65 — aspirational"
        return "OK", "target gap"

    if "wall" in tags:
        return "OK", "wall ceiling watch"

    # Has a real position
    if rank <= 250:
        return "OK", f"ranking position #{rank}"

    if rank < 1000:
        return "OK", f"climbing #{rank} — monitor"

    # Untagged @ 1000
    words = set(keyword.lower().split())
    if words & field_pool:
        return "OK", "field-pool combo (unlocks coverage)"

    if pop <= 5:
        return "REMOVE", "pop≤5 @ 1000, no tag, no position — aso.md §4 noise"

    if diff > 65:
        return "REMOVE", f"pop>{pop} diff>{diff} @ 1000 — unwinnable untagged"

    # pop>5 @ 1000 but plausible combo — needs human/tag
    return "REVIEW", f"pop={pop} diff={diff} @ 1000 untagged — needs target tag or removal"


def audit_app(app_id: str) -> dict:
    repo = REPOS.get(app_id)
    field_pool = load_field_pool(repo) if repo else set()
    blocklist = BLOCKLIST.get(app_id, set())

    kws = call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": "us"})
    buckets: dict[str, list] = {"OK": [], "WATCH": [], "REVIEW": [], "REMOVE": []}

    for kw in sorted(kws, key=lambda x: x["keyword"]):
        verdict, reason = classify(kw, field_pool, blocklist)
        buckets[verdict].append({
            "keyword": kw["keyword"],
            "rank": kw.get("currentRanking"),
            "pop": kw.get("popularity"),
            "diff": kw.get("difficulty"),
            "tags": kw.get("tags") or [],
            "reason": reason,
        })

    return {
        "total": len(kws),
        "ok": len(buckets["OK"]),
        "watch": len(buckets["WATCH"]),
        "review": len(buckets["REVIEW"]),
        "remove": len(buckets["REMOVE"]),
        "buckets": buckets,
    }


def main() -> None:
    apps = list_apps(DEFAULT_MCP_URL)
    jack_apps = [a for a in apps if str(a["appId"]) in REPOS]

    summary = []
    all_remove = []
    all_review = []

    for app in jack_apps:
        app_id = str(app["appId"])
        r = audit_app(app_id)
        summary.append({
            "app": app["name"],
            "appId": app_id,
            "total": r["total"],
            "ok": r["ok"],
            "watch": r["watch"],
            "review": r["review"],
            "remove": r["remove"],
        })
        for item in r["buckets"]["REMOVE"]:
            all_remove.append({**item, "app": app["name"], "appId": app_id})
        for item in r["buckets"]["REVIEW"]:
            all_review.append({**item, "app": app["name"], "appId": app_id})

    print("=== US KEYWORD USEFULNESS AUDIT ===\n")
    for s in summary:
        pct = 100 * s["ok"] / s["total"] if s["total"] else 0
        flag = "✓" if s["remove"] == 0 and s["review"] <= 3 else "⚠"
        print(
            f"{flag} {s['app']}: {s['total']} tracked | "
            f"{s['ok']} useful | {s['watch']} watch | {s['review']} review | {s['remove']} remove"
        )

    print(f"\n=== REMOVE candidates ({len(all_remove)}) ===")
    for item in all_remove[:40]:
        print(f"  [{item['app']}] {item['keyword']} — {item['reason']}")
    if len(all_remove) > 40:
        print(f"  ... +{len(all_remove)-40} more")

    print(f"\n=== REVIEW (untagged plausible, {len(all_review)}) ===")
    for item in all_review[:30]:
        print(f"  [{item['app']}] {item['keyword']} (pop={item['pop']} diff={item['diff']}) — {item['reason']}")
    if len(all_review) > 30:
        print(f"  ... +{len(all_review)-30} more")

    # Non-US spot check: count pop5@1000 not in US set per app
    print("\n=== NON-US residual junk (pop≤5 @ 1000, not in US keep-set) ===")
    for app in jack_apps:
        app_id = str(app["appId"])
        us_set = {
            k["keyword"].lower()
            for k in call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": "us"})
        }
        junk = 0
        for store in app.get("stores") or []:
            if store == "us":
                continue
            kws = call(DEFAULT_MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})
            junk += sum(
                1
                for k in kws
                if k.get("currentRanking") == 1000
                and (k.get("popularity") or 0) <= 5
                and k["keyword"].lower() not in us_set
            )
        if junk:
            print(f"  {app['name']}: {junk} non-US junk keywords remain")

    out = Path("/tmp/aso-audit.json")
    out.write_text(json.dumps({"summary": summary, "remove": all_remove, "review": all_review}, indent=2))
    print(f"\nFull report: {out}")


if __name__ == "__main__":
    main()
