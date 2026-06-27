#!/usr/bin/env python3
"""Stage App Store releases: bump version, propagate What's New, ensure ASC draft, upload metadata.

Does NOT submit for review or release. Run testflight.sh separately per app for binaries.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
APPS: dict[str, dict] = {
    "vitals": {
        "bundle": "com.jackwallner.vitals",
        "version": "1.7.2",
        "release_notes": """New in Vitals+

• TDEE & BMR - see your maintenance calories (TDEE) and resting burn (BMR) as a steady 30-day average from Apple Health, right under the ring. The number you'd plan a deficit around, from your own data.

It's an opt-in toggle in Settings, off by default, so the free Today view stays exactly as it was.

Plus the usual under-the-hood fixes to keep your calories and steps accurate across the app, widgets, and Apple Watch.""",
    },
    "posture": {
        "bundle": "com.jackwallner.posture",
        "version": "1.0",
        "release_notes": "Performance improvements and polish across Today, history, and Apple Watch. Thank you for helping us build a calmer posture habit.",
    },
    "bond": {
        "bundle": "com.jackwallner.bond",
        "version": "1.0.1",
        "release_notes": "Stability improvements and polish across reminders, pairing, and settings.",
    },
    "fitness-streaks": {
        "bundle": "com.jackwallner.streaks",
        "version": "1.2.2",
        "release_notes": "Bug fixes and performance improvements across the app, widgets, and Apple Watch.",
    },
    "sober": {
        "bundle": "com.jackwallner.sober",
        "version": "1.1.2",
        "release_notes": "Improvements to your trial and daily check-in experience, plus bug fixes. Thank you for being here.",
    },
    "simpleglp": {
        "bundle": "com.jackwallner.glp",
        "version": "1.0.2",
        "release_notes": "Bug fixes and performance improvements to keep your shot log reliable.",
    },
    "sports": {
        "bundle": "com.jackwallner.sports",
        "version": "1.0.5",
        "release_notes": "Bug fixes and performance improvements to your daily sports briefing.",
    },
    "baseball": {
        "bundle": "com.jackwallner.baseball",
        "version": "1.2.3",
        "release_notes": "Bug fixes and performance improvements across stats, compare, and team views.",
    },
    "headaches": {
        "bundle": "com.jackwallner.headachelogger",
        "version": "1.4.5",
        "release_notes": "Bug fixes and performance improvements for faster, more reliable headache logging.",
    },
    "nicfree": {
        "bundle": "com.jackwallner.quitzyn",
        "version": "1.0",
        "release_notes": "First release. Track your nicotine-free days, grow your garden, and watch your health recover one milestone at a time. Thank you for being here.",
    },
}


def run(cmd: list[str], cwd: Path, env: dict | None = None) -> None:
    print(f"  $ {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def propagate_release_notes(app_dir: Path, text: str) -> int:
    meta = app_dir / "fastlane/metadata"
    if not meta.is_dir():
        print(f"  skip release notes — no fastlane/metadata")
        return 0
    text = text.strip() + "\n"
    count = 0
    skip = {"review_information"}
    for loc_dir in sorted(meta.iterdir()):
        if not loc_dir.is_dir() or loc_dir.name in skip:
            continue
        (loc_dir / "release_notes.txt").write_text(text, encoding="utf-8")
        count += 1
    return count


def bump_project_yml(app_dir: Path, version: str) -> bool:
    yml = app_dir / "project.yml"
    if not yml.exists():
        return False
    content = yml.read_text(encoding="utf-8")
    new_content, n = re.subn(
        r'(MARKETING_VERSION:\s*")[^"]+(")',
        rf'\g<1>{version}\2',
        content,
        count=1,
    )
    if n == 0:
        new_content, n = re.subn(
            r"(MARKETING_VERSION:\s*)[0-9.]+",
            rf"\g<1>{version}",
            content,
            count=1,
        )
    if n == 0:
        print("  warning: could not bump MARKETING_VERSION in project.yml")
        return False
    yml.write_text(new_content, encoding="utf-8")
    print(f"  MARKETING_VERSION -> {version}")
    return True


def ensure_draft(app_dir: Path, version: str, env: dict) -> str:
    state = app_dir / "scripts/.asc-state.json"
    if state.exists():
        state.unlink()
    env = {**env, "ASC_DRAFT_VERSION": version}
    out = subprocess.run(
        [sys.executable, "scripts/asc-ensure-draft-version.py"],
        cwd=app_dir,
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    print(out.stdout.strip())
    for line in out.stdout.splitlines():
        if line.startswith("export ASC_APP_VERSION="):
            return line.split("'", 2)[1]
    m = re.search(r"draftVersion=([0-9.]+)", out.stdout)
    return m.group(1) if m else version


def upload_metadata(app_dir: Path, version: str, env: dict) -> None:
    env = {**env, "ASC_APP_VERSION": version, "SKIP_SCREENSHOTS": "true"}
    run(
        [sys.executable, "scripts/asc-upload-metadata.py", "--create-missing"],
        cwd=app_dir,
        env=env,
    )
    sh = app_dir / "scripts/upload-appstore-metadata.sh"
    if sh.exists():
        run(["bash", str(sh)], cwd=app_dir, env=env)


def load_asc_env() -> dict:
    env = os.environ.copy()
    creds = HOME / ".baseball_credentials"
    if creds.exists():
        for line in creds.read_text().splitlines():
            line = line.strip()
            if line.startswith("export "):
                line = line[len("export ") :]
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    return env


def stage_app(name: str, cfg: dict, env: dict, skip_metadata: bool) -> dict:
    app_dir = HOME / name
    print(f"\n{'='*60}\n{name} ({cfg['bundle']})\n{'='*60}")
    if not app_dir.is_dir():
        print("  missing app dir — skip")
        return {"app": name, "status": "missing"}

    version = cfg["version"]
    bump_project_yml(app_dir, version)
    n = propagate_release_notes(app_dir, cfg["release_notes"])
    print(f"  wrote release_notes to {n} locale(s)")

    if skip_metadata:
        return {"app": name, "version": version, "status": "prepared-local-only"}

    draft = ensure_draft(app_dir, version, env)
    if draft != version:
        print(f"  note: ASC draft is {draft} (requested {version})")
        bump_project_yml(app_dir, draft)
        version = draft

    upload_metadata(app_dir, version, env)
    return {"app": name, "version": version, "status": "metadata-staged"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apps", help="Comma-separated subset (default: all)")
    parser.add_argument("--local-only", action="store_true", help="Only bump version + release notes")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    if args.list:
        for name, cfg in APPS.items():
            print(f"{name}\t{cfg['version']}\t{cfg['bundle']}")
        return

    names = [a.strip() for a in args.apps.split(",")] if args.apps else list(APPS.keys())
    env = load_asc_env()
    results = []
    for name in names:
        if name not in APPS:
            print(f"unknown app: {name}", file=sys.stderr)
            continue
        try:
            results.append(stage_app(name, APPS[name], env, args.local_only))
        except subprocess.CalledProcessError as e:
            print(f"  FAILED: {e}", file=sys.stderr)
            results.append({"app": name, "status": "failed", "error": str(e)})
        time.sleep(1)

    print("\n\n=== Summary ===")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
