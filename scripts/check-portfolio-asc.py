#!/usr/bin/env python3
"""Print ASC draft version state for all portfolio apps."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_lib import ASCClient, bearer_token, find_app, find_editable_version, find_live_version, load_credentials

APPS = {
    "vitals": "com.jackwallner.vitals",
    "posture": "com.jackwallner.posture",
    "bond": "com.jackwallner.bond",
    "fitness-streaks": "com.jackwallner.streaks",
    "sober": "com.jackwallner.sober",
    "simpleglp": "com.jackwallner.glp",
    "sports": "com.jackwallner.sports",
    "baseball": "com.jackwallner.baseball",
    "headaches": "com.jackwallner.headachelogger",
    "nicfree": "com.jackwallner.quitzyn",
}


def latest_build(client: ASCClient, app_id: str) -> dict | None:
    data = client.get(
        f"/builds?filter[app]={app_id}&limit=1&sort=-uploadedDate"
        "&fields[builds]=version,processingState"
    )
    items = data.get("data", [])
    return items[0] if items else None


def version_build(client: ASCClient, version_id: str) -> str | None:
    data = client.get(f"/appStoreVersions/{version_id}?include=build")
    included = data.get("included", [])
    for item in included:
        if item.get("type") == "builds":
            return item.get("attributes", {}).get("version")
    return None


def main() -> None:
    key_id, issuer_id, key_path = load_credentials()
    client = ASCClient(bearer_token(key_id, issuer_id, key_path))
    rows = []
    for name, bundle in APPS.items():
        app = find_app(client, bundle)
        aid = app["id"]
        live = find_live_version(client, aid)
        draft = find_editable_version(client, aid)
        build = latest_build(client, aid)
        attached = version_build(client, draft["id"]) if draft else None
        rows.append(
            {
                "app": name,
                "live": live["attributes"]["versionString"] if live else None,
                "draft": draft["attributes"]["versionString"] if draft else None,
                "draftState": draft["attributes"]["appStoreState"] if draft else None,
                "attachedBuild": attached,
                "latestBuild": build["attributes"]["version"] if build else None,
                "buildState": build["attributes"]["processingState"] if build else None,
            }
        )
    print(json.dumps(rows, indent=2))


if __name__ == "__main__":
    main()
