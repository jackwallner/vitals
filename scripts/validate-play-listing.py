#!/usr/bin/env python3
"""Validate Total Calories' (Vitals) Google Play listing copy under android/play-assets/metadata/android.

Checks every locale folder for Play's limits (title 30, short 80, full 4000),
the house rules (no em dashes, no prices, no Apple wording, no promo words in
the title, no medical claims outside the not-a-medical-device disclaimer),
the Total Calories brand in the title, the Health Connect and Google Play
mentions in the full description and, outside English, the line saying the
app itself is in English. If
.play-live-listing.json exists at the repo root, en-US must match it exactly.
Exit 1 on any failure.

Usage: scripts/validate-play-listing.py [--root DIR]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / "android/play-assets/metadata/android"
LIVE = REPO / ".play-live-listing.json"
LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
# Play language codes accepted by the Publishing API (fastlane supply list).
PLAY_LANGS = set(
    "af am ar az-AZ be bg bn-BD ca cs-CZ da-DK de-DE el-GR en-AU en-CA en-GB en-IN "
    "en-SG en-US en-ZA es-419 es-ES es-US et eu-ES fa fi-FI fil fr-CA fr-FR gl-ES "
    "hi-IN hr hu-HU hy-AM id is-IS it-IT iw-IL ja-JP ka-GE km-KH kn-IN ko-KR ky-KG "
    "lo-LA lt lv mk-MK ml-IN mn-MN mr-IN ms ms-MY my-MM ne-NP nl-NL no-NO pl-PL "
    "pt-BR pt-PT rm ro ru-RU si-LK sk sl sr sv-SE sw ta-IN te-IN th tr-TR uk vi "
    "zh-CN zh-HK zh-TW zu".split()
)
# The 50 locales this listing ships in (same set as Sober).
EXPECTED = set(
    "en-US en-GB en-AU en-CA en-IN de-DE fr-FR fr-CA es-ES es-419 es-US pt-BR pt-PT "
    "it-IT nl-NL sv-SE no-NO da-DK fi-FI pl-PL cs-CZ sk sl hr hu-HU ro el-GR tr-TR "
    "ru-RU uk ar iw-IL hi-IN bn-BD mr-IN ta-IN te-IN kn-IN ml-IN id ms ms-MY th vi "
    "ja-JP ko-KR zh-CN zh-TW zh-HK ca".split()
)
TITLE_BANNED = re.compile(
    r"\b(free|best|top|#1|new|sale|gratis|gratuit|gratuito|kostenlos|neu|nuevo|nouveau|novo)\b"
    r"|免费|免費|無料|무료|最佳|最好",
    re.I,
)
PRICE = re.compile(r"[$€£¥₹]\s?\d|\d[.,]\d\d\s?(?:€|zł|kr|lei|Kč|₺|₽|₴)")
APPLE = re.compile(r"\b(?:Apple|App Store|iPhone|iPad|iCloud|Apple Watch|HealthKit|watchOS)\b", re.I)
MEDICAL = re.compile(r"\b(treat|treats|cure|cures|diagnose|diagnoses)\b", re.I)
# The en-US disclaimer sentence names the words it disclaims; skip it.
DISCLAIMER = re.compile(r"[^.\n]*not a medical device[^.\n]*\.", re.I)
BRAND = "Total Calories"
URL_OK = re.compile(r"https://jackwallner\.github\.io/\S+")
# A word for "English" in each listing language, used to find the
# "the app itself is in English" line.
ENGLISH = {
    "ar": "الإنجليزية", "bn": "ইংরেজি", "ca": "anglès", "cs": "angličtině",
    "da": "engelsk", "de": "Englisch", "el": "αγγλικά", "es": "inglés",
    "fi": "englanninkielinen", "fr": "anglais", "hi": "अंग्रेज़ी", "hr": "engleskom",
    "hu": "angol", "id": "Inggris", "it": "inglese", "iw": "באנגלית",
    "ja": "英語", "kn": "ಇಂಗ್ಲಿಷ್", "ko": "영어", "ml": "ഇംഗ്ലീഷ", "mr": "इंग्रजी",
    "ms": "Inggeris", "nl": "Engels", "no": "engelsk", "pl": "angielskim",
    "pt": "inglês", "ro": "engleză", "ru": "английском", "sk": "angličtine",
    "sl": "angleščini", "sv": "engelska", "ta": "ஆங்கில", "te": "ఇంగ్లీష్",
    "th": "ภาษาอังกฤษ", "tr": "İngilizce", "uk": "англійською", "vi": "tiếng Anh",
    "zh-CN": "英文", "zh-TW": "英文", "zh-HK": "英文",
}


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip() if path.exists() else ""


def live_en_us() -> dict[str, str] | None:
    if not LIVE.exists():
        return None
    for x in json.loads(LIVE.read_text(encoding="utf-8")).get("listings", []):
        if x.get("language") == "en-US":
            return {
                "title.txt": x.get("title", ""),
                "short_description.txt": x.get("shortDescription", ""),
                "full_description.txt": x.get("fullDescription", ""),
            }
    return None


def check_text(name: str, text: str, limit: int) -> list[str]:
    errs: list[str] = []
    n = len(text)
    if n == 0 or n > limit:
        errs.append(f"{name} {n}/{limit}")
    if "—" in text:
        errs.append(f"{name} has an em dash")
    if re.search("[­​﻿]", text):
        errs.append(f"{name} has an invisible character")
    if m := PRICE.search(text):
        errs.append(f"{name} looks like it has a price: {m.group(0)!r}")
    if m := APPLE.search(URL_OK.sub("", text)):
        errs.append(f"{name} mentions Apple wording: {m.group(0)!r}")
    if m := MEDICAL.search(DISCLAIMER.sub("", text)):
        errs.append(f"{name} has a medical claim word: {m.group(0)!r}")
    if name != "full_description.txt" and "\n" in text:
        errs.append(f"{name} spans lines")
    return errs


def check(locale_dir: Path, live: dict[str, str] | None) -> list[str]:
    errs: list[str] = []
    loc = locale_dir.name
    if loc not in PLAY_LANGS:
        errs.append(f"unknown Play language code {loc}")
    for name, limit in LIMITS.items():
        p = locale_dir / name
        if not p.exists():
            errs.append(f"missing {name}")
            continue
        errs += check_text(name, read(p), limit)
        if loc == "en-US" and live and read(p) != live[name].strip():
            errs.append(f"{name} differs from the live listing in .play-live-listing.json")
    title = read(locale_dir / "title.txt")
    full = read(locale_dir / "full_description.txt")
    if BRAND not in title:
        errs.append(f"title lacks the {BRAND} brand")
    if m := TITLE_BANNED.search(title):
        errs.append(f"title has a promo word {m.group(0)!r}: {title!r}")
    if "Google Play" not in full:
        errs.append("full description does not mention Google Play purchases")
    if "Health Connect" not in full:
        errs.append("full description does not name Health Connect")
    if not loc.startswith("en"):
        word = ENGLISH.get(loc) or ENGLISH.get(loc.split("-")[0])
        if not word:
            errs.append("no English-note marker defined for this language")
        elif word not in full:
            errs.append(f"full description does not say the app is in English ({word!r})")
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT)
    args = ap.parse_args()
    live = live_en_us()
    bad = 0
    dirs = sorted(d for d in args.root.iterdir() if d.is_dir())
    for d in dirs:
        errs = check(d, live)
        t = read(d / "title.txt")
        s = read(d / "short_description.txt")
        f = read(d / "full_description.txt")
        status = "OK " if not errs else "BAD"
        print(f"{status} {d.name:7} t{len(t):>3} s{len(s):>3} f{len(f):>5}  {t}")
        for e in errs:
            print(f"      - {e}")
        bad += bool(errs)
    names = {d.name for d in dirs}
    missing, extra = sorted(EXPECTED - names), sorted(names - EXPECTED)
    if missing:
        print(f"\nmissing locales: {' '.join(missing)}")
    if extra:
        print(f"\nunexpected locales: {' '.join(extra)}")
    print(f"\n{len(dirs)} locales, {bad} with problems")
    return 1 if bad or missing or extra else 0


if __name__ == "__main__":
    sys.exit(main())
