#!/usr/bin/env python3
"""Stage per-locale 13-inch iPad screenshot sets (2064x2752) on the editable App Store version.

    scripts/stage-ipad-screenshots.py --root <dir of <locale>/*.png> [--create-version] [--apply]

Only the APP_IPAD_PRO_3GEN_129 set of each locale folder is replaced (files in name
order); iPhone, Duo and Watch sets are never touched. A locale folder with no matching
localization on the version is reported and skipped. Never submits anything.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

BIN = Path.home() / "ios/appstore-screenshots/bin"
sys.path.insert(0, str(BIN))
from _asc import ASC  # noqa: E402

sync = SourceFileLoader("sync", str(BIN / "asc-sync-screenshots")).load_module()
duo = SourceFileLoader("duo", str(BIN / "asc-stage-duo")).load_module()

BUNDLE = "com.jackwallner.vitals"
DISPLAY = "APP_IPAD_PRO_3GEN_129"
SIZE = (2064, 2752)


def stage(c: ASC, loc: dict, pngs: list[Path]) -> list[str]:
    sets = {s["attributes"]["screenshotDisplayType"]: s for s in
            c.all(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")}
    s = sets.get(DISPLAY) or c.post("/v1/appScreenshotSets", {"data": {
        "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": DISPLAY},
        "relationships": {"appStoreVersionLocalization": {
            "data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
    for old in c.all(f"/v1/appScreenshotSets/{s['id']}/appScreenshots?limit=50"):
        c.delete(f"/v1/appScreenshots/{old['id']}")
    ids = [sync.upload_one(c, s["id"], p) for p in pngs]
    c.patch(f"/v1/appScreenshotSets/{s['id']}/relationships/appScreenshots",
            {"data": [{"type": "appScreenshots", "id": i} for i in ids]})
    for _ in range(60):
        now = c.all(f"/v1/appScreenshotSets/{s['id']}/appScreenshots?limit=50")
        states = [(x["attributes"].get("assetDeliveryState") or {}).get("state") for x in now]
        if all(st == "COMPLETE" for st in states):
            break
        time.sleep(5)
    if [x["id"] for x in now] != ids or set(states) != {"COMPLETE"}:
        raise RuntimeError(f"{loc['attributes']['locale']}: readback mismatch {states}")
    return ids


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", required=True, type=Path)
    ap.add_argument("--create-version", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--only", help="comma list of locales")
    a = ap.parse_args()

    folders = {d.name: sorted(d.glob("*.png")) for d in sorted(a.root.expanduser().iterdir()) if d.is_dir()}
    only = set(a.only.split(",")) if a.only else None
    for loc, pngs in list(folders.items()):
        if only and loc not in only:
            del folders[loc]
            continue
        if not 1 <= len(pngs) <= 10:
            sys.exit(f"{loc}: need 1-10 PNGs, found {len(pngs)}")
        for p in pngs:
            if sync.png_size(p) != SIZE:
                sys.exit(f"{p} is {sync.png_size(p)}, not {SIZE}")

    c = ASC()
    app = sync.find_app(c, BUNDLE)
    ver = duo.editable_version(c, app["id"], a.create_version, a.apply)
    version = ver["attributes"]["versionString"]
    print(f"{app['attributes']['name']} {version} ({ver['attributes']['appStoreState']}): "
          f"{len(folders)} locales", file=sys.stderr)
    if not a.apply:
        return
    locs = {x["attributes"]["locale"]: x for x in
            c.all(f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=200")}
    done, skipped = [], []
    for locale, pngs in folders.items():
        if locale not in locs:
            skipped.append(locale)
            continue
        stage(c, locs[locale], pngs)
        done.append(locale)
        print(f"  {locale}: {len(pngs)} frames", file=sys.stderr, flush=True)
    print(json.dumps({"version": version, "version_id": ver["id"], "done": done, "skipped": skipped,
                      "version_locales_without_set": sorted(set(locs) - set(done))}))


if __name__ == "__main__":
    main()
