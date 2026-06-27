#!/usr/bin/env python3
"""Attach the latest VALID TestFlight build to each app's editable ASC version.

Does NOT submit for review. Run after testflight.sh uploads finish processing.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_lib import (
    ASCClient,
    EDITABLE_STATES,
    bearer_token,
    find_app,
    find_editable_version,
    load_credentials,
)

APPS: dict[str, str] = {
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


def list_builds(client: ASCClient, app_id: str, limit: int = 15) -> list[dict]:
    data = client.get(
        f"/builds?filter[app]={app_id}&limit={limit}&sort=-uploadedDate"
        "&fields[builds]=version,processingState,uploadedDate,expired"
    )
    return data.get("data", [])


def latest_valid_build(client: ASCClient, app_id: str) -> dict | None:
    for b in list_builds(client, app_id):
        attrs = b.get("attributes", {})
        if attrs.get("expired"):
            continue
        if attrs.get("processingState") == "VALID":
            return b
    return None


def attach_build(client: ASCClient, version_id: str, build_id: str) -> None:
    client.patch(
        f"/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build_id}},
    )


def stage_app(client: ASCClient, name: str, bundle: str, wait: bool) -> dict:
    app = find_app(client, bundle)
    app_id = app["id"]
    draft = find_editable_version(client, app_id)
    if not draft:
        return {"app": name, "status": "no-editable-version"}

    vid = draft["id"]
    vstr = draft["attributes"]["versionString"]
    vst = draft["attributes"]["appStoreState"]
    if vst not in EDITABLE_STATES:
        return {"app": name, "status": "not-editable", "version": vstr, "state": vst}

    build = None
    for attempt in range(wait and 40 or 1):
        build = latest_valid_build(client, app_id)
        if build:
            break
        if not wait:
            break
        print(f"  {name}: waiting for VALID build (attempt {attempt + 1}/40)...", flush=True)
        time.sleep(30)

    if not build:
        return {"app": name, "status": "no-valid-build", "version": vstr}

    bid = build["id"]
    bnum = build["attributes"]["version"]
    bstate = build["attributes"]["processingState"]
    if bstate != "VALID":
        return {
            "app": name,
            "status": "build-not-valid",
            "version": vstr,
            "build": bnum,
            "processingState": bstate,
        }

    attach_build(client, vid, bid)
    return {
        "app": name,
        "status": "attached",
        "version": vstr,
        "build": bnum,
        "buildId": bid,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apps", help="Comma-separated subset")
    parser.add_argument("--wait", action="store_true", help="Poll until VALID build exists")
    args = parser.parse_args()

    key_id, issuer_id, key_path = load_credentials()
    client = ASCClient(bearer_token(key_id, issuer_id, key_path))

    names = [a.strip() for a in args.apps.split(",")] if args.apps else list(APPS.keys())
    results = []
    for name in names:
        if name not in APPS:
            print(f"unknown app: {name}", file=sys.stderr)
            continue
        print(f"\n=== {name} ===", flush=True)
        try:
            results.append(stage_app(client, name, APPS[name], args.wait))
        except Exception as e:
            print(f"  FAILED: {e}", file=sys.stderr)
            results.append({"app": name, "status": "failed", "error": str(e)})

    print("\n=== Summary ===")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
