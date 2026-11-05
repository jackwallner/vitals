#!/usr/bin/env python3
"""Capture Total Calories frames in each language on the leased simulator pair.

usage: capture.py <iphone-udid> <watch-udid> <out-root> <asc-locale>[,<asc-locale>...] [--scenes a,b]
Raw frames land in <out-root>/<asc-locale>/. A screen counts as ready once two
screenshots in a row match, so chart loading and ring animation have settled.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

# ASC locale -> (language, region locale)
LOCALES = {
    "ar-SA": ("ar", "ar_AE"), "cs": ("cs", "cs_CZ"), "da": ("da", "da_DK"), "de-DE": ("de", "de_DE"),
    "el": ("el", "el_GR"), "es-ES": ("es", "es_ES"), "es-MX": ("es", "es_MX"), "fi": ("fi", "fi_FI"),
    "fr-FR": ("fr", "fr_FR"), "fr-CA": ("fr", "fr_CA"), "he": ("he", "he_IL"), "hi": ("hi", "hi_IN"),
    "hr": ("hr", "hr_HR"), "hu": ("hu", "hu_HU"), "id": ("id", "id_ID"), "it": ("it", "it_IT"),
    "ja": ("ja", "ja_JP"), "ko": ("ko", "ko_KR"), "ms": ("ms", "ms_MY"), "no": ("nb", "nb_NO"),
    "nl-NL": ("nl", "nl_NL"), "pl": ("pl", "pl_PL"), "pt-BR": ("pt-BR", "pt_BR"), "pt-PT": ("pt-PT", "pt_PT"),
    "ro": ("ro", "ro_RO"), "ru": ("ru", "ru_RU"), "sk": ("sk", "sk_SK"), "sv": ("sv", "sv_SE"),
    "th": ("th", "th_TH"), "tr": ("tr", "tr_TR"), "uk": ("uk", "uk_UA"), "vi": ("vi", "vi_VN"),
    "zh-Hans": ("zh-Hans", "zh_CN"), "zh-Hant": ("zh-Hant", "zh_TW"),
}
PHONE_SCENES = {
    "dashboard": "dashboard", "calorie-intake": "calorieIntake", "premium-dashboard": "premiumDashboard",
    "history": "history", "net-deficit": "netDeficit", "macro-goals": "macroGoals",
    "macro-history": "macroHistory", "dark-dashboard": "darkDashboard",
}
WATCH_SCENES = {"watch-today": "watchToday", "watch-breakdown": "watchBreakdown"}
BUNDLE = {"phone": "com.jackwallner.vitals", "watch": "com.jackwallner.vitals.watch"}


def shot(udid: str, path: Path) -> None:
    # Under memory pressure simctl can stall for minutes, so wait and retry.
    for attempt in range(4):
        try:
            subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(path)], check=True, capture_output=True, timeout=120)
            return
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
            if attempt == 3:
                raise
            time.sleep(20)


def settled(udid: str, path: Path, minimum: float, maximum: float) -> None:
    time.sleep(minimum)
    deadline = time.monotonic() + maximum
    with tempfile.TemporaryDirectory() as tmp:
        previous = Path(tmp) / "previous.png"
        shot(udid, previous)
        while time.monotonic() < deadline:
            time.sleep(1.5)
            shot(udid, path)
            with Image.open(previous) as a, Image.open(path) as b:
                same = ImageChops.difference(a.convert("RGB"), b.convert("RGB")).getbbox() is None
                body = b.convert("RGB").crop((0, b.height // 6, b.width, b.height * 5 // 6))
                if same and max(ImageStat.Stat(body).var) >= 8.0:
                    return
            previous.write_bytes(path.read_bytes())
    print(f"  warn: {path.name} never fully settled", flush=True)


def launch(udid: str, bundle: str, scene: str, language: str, region: str) -> None:
    env = os.environ.copy()
    env.update({"SIMCTL_CHILD_VITALS_SCREENSHOT_MODE": "1", "SIMCTL_CHILD_VITALS_SCREENSHOT_SCENE": scene,
                "SIMCTL_CHILD_VITALS_FORCE_INTRO_INELIGIBLE": "1"})
    args = ["-AppleLanguages", f"({language})", "-AppleLocale", region]
    error = ""
    for _ in range(5):
        try:
            result = subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle, *args],
                                    env=env, capture_output=True, text=True, timeout=120)
        except subprocess.TimeoutExpired as timeout:
            error = str(timeout)
        else:
            if result.returncode == 0:
                return
            error = result.stderr
        time.sleep(15)
    raise RuntimeError(error)


def main() -> None:
    iphone, watch, root = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    locales = list(LOCALES) if sys.argv[4] == "all" else sys.argv[4].split(",")
    only = set(sys.argv[6].split(",")) if len(sys.argv) > 6 else None
    # Files newer than this stamp file count as done, so a stalled run can resume.
    stamp = Path(sys.argv[7]).stat().st_mtime if len(sys.argv) > 7 else 0
    for locale in locales:
        language, region = LOCALES[locale]
        out = root / locale
        out.mkdir(parents=True, exist_ok=True)
        expected = len(PHONE_SCENES) + len(WATCH_SCENES)
        if not only and len(list(out.glob("*.png"))) == expected and (out / ".done").exists():
            continue
        started = time.monotonic()
        for name, scene in PHONE_SCENES.items():
            if only and name not in only:
                continue
            if stamp and (out / f"{name}.png").exists() and (out / f"{name}.png").stat().st_mtime > stamp:
                continue
            launch(iphone, BUNDLE["phone"], scene, language, region)
            settled(iphone, out / f"{name}.png", 3.0, 45.0)
        for name, scene in WATCH_SCENES.items():
            if only and name not in only:
                continue
            launch(watch, BUNDLE["watch"], scene, language, region)
            settled(watch, out / f"{name}.png", 3.0, 25.0)
        if not only:
            (out / ".done").touch()
        print(json.dumps({"locale": locale, "seconds": round(time.monotonic() - started)}), flush=True)


if __name__ == "__main__":
    main()
