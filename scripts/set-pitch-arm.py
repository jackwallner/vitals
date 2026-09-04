#!/usr/bin/env python3
"""Edit the onboarding pitch routing table on every RevenueCat offering.

The table is carried on offering metadata under `onboarding_pitch` and is read
by 1.8.4+. Older builds never look at the key, so every edit here is inert for
anyone on the App Store build until 1.8.4 is live.

Usage:
  set-pitch-arm.py show                  print the table on every offering
  set-pitch-arm.py ramp <0-100>          set enroll_pct (0 = everyone gets fallback)
  set-pitch-arm.py test <arm> <arm>...   run these arms, split evenly, food-safe
  set-pitch-arm.py force <arm>           pin everyone to one arm (ship the winner)
  set-pitch-arm.py unforce               drop the pin, go back to the weights
  set-pitch-arm.py salt <string>         reshuffle every assignment

Arms: a current (control), b macro/food, c locked numbers, d two weeks,
      e two weeks + net deficit. b and e need food data, so they are only ever
      written into the logs_food segment; d is written into no_food_log only.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from typing import Dict, List, Optional

PROJECT = "projd0d314f5"
BASE = f"https://api.revenuecat.com/v2/projects/{PROJECT}"
KEY_NAME = "onboarding_pitch"

LOGGER_ONLY = {"b", "e"}
NON_LOGGER_ONLY = {"d"}
ALL_ARMS = ["a", "b", "c", "d", "e"]


def secret_key() -> str:
    path = os.path.expanduser("~/.vitals_credentials")
    with open(path) as handle:
        for line in handle:
            if line.startswith("RC_SECRET_KEY"):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit(f"RC_SECRET_KEY not found in {path}")


def request(method: str, path: str, body: Optional[dict] = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{BASE}{path}", data=data, method=method)
    req.add_header("Authorization", f"Bearer {secret_key()}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        sys.exit(f"{method} {path} -> {error.code}\n{error.read().decode()}")


def offerings() -> List[dict]:
    return request("GET", "/offerings?limit=50")["items"]


def segments_for(arms: List[str]) -> Dict[str, Dict[str, int]]:
    """Split `arms` evenly, keeping food-dependent arms in the right segment.

    `canDraw` in the app refuses b and e without food data whatever this says,
    so a table that put them in no_food_log would silently degrade to the
    fallback and quietly shrink the test. Filter here instead, so the weights
    describe what actually runs.
    """
    table = {}
    for segment, banned in (("logs_food", NON_LOGGER_ONLY), ("no_food_log", LOGGER_ONLY)):
        live = [arm for arm in arms if arm not in banned]
        if not live:
            sys.exit(f"no arm left for segment {segment} out of {arms}")
        share = 100 // len(live)
        weights = {arm: share for arm in live}
        weights[live[0]] += 100 - share * len(live)
        table[segment] = weights
    return table


def apply(mutate) -> None:
    for offering in offerings():
        metadata = dict(offering.get("metadata") or {})
        table = dict(metadata.get(KEY_NAME) or {})
        mutate(table)
        metadata[KEY_NAME] = table
        request("POST", f"/offerings/{offering['id']}", {"metadata": metadata})
        print(f"  {offering['lookup_key']:<18} {json.dumps(table, sort_keys=True)}")


def main() -> None:
    argv = sys.argv[1:]
    if not argv:
        sys.exit(__doc__)
    command, args = argv[0], argv[1:]

    if command == "show":
        for offering in offerings():
            table = (offering.get("metadata") or {}).get(KEY_NAME)
            current = " (current)" if offering.get("is_current") else ""
            print(f"{offering['lookup_key']}{current}: {json.dumps(table, sort_keys=True)}")
        return

    if command == "ramp":
        percent = int(args[0])
        if not 0 <= percent <= 100:
            sys.exit("ramp takes 0-100")
        print(f"enroll_pct -> {percent}")
        apply(lambda table: table.__setitem__("enroll_pct", percent))
        return

    if command == "test":
        arms = args or sys.exit("test needs at least one arm")
        for arm in arms:
            if arm not in ALL_ARMS:
                sys.exit(f"unknown arm {arm!r}, expected one of {ALL_ARMS}")
        table = segments_for(arms)
        print(f"arms {' '.join(arms)} -> {json.dumps(table, sort_keys=True)}")
        apply(lambda current: current.__setitem__("segments", table))
        return

    if command == "force":
        arm = args[0]
        if arm not in ALL_ARMS:
            sys.exit(f"unknown arm {arm!r}")
        print(f"force -> {arm} (everyone, next fetch)")
        apply(lambda table: table.__setitem__("force", arm))
        return

    if command == "unforce":
        print("force -> null")
        apply(lambda table: table.__setitem__("force", None))
        return

    if command == "salt":
        value = args[0]
        print(f"salt -> {value} (reshuffles every assignment)")
        apply(lambda table: table.__setitem__("salt", value))
        return

    sys.exit(__doc__)


if __name__ == "__main__":
    main()
