#!/usr/bin/env python3
"""Check App Store field lengths and keyword collisions for chosen locales.

Usage: scripts/check-locale-fields.py [locale ...]  (default: the 2026-11-20 l10n set)
Prints per-locale character counts against limits and flags keyword problems.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "fastlane" / "metadata"
DEFAULT = ["en-GB", "de-DE", "fr-FR", "es-ES", "uk", "zh-Hant", "ja", "zh-Hans", "pl", "it"]
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170, "description": 4000}
CJK = re.compile(r"[぀-ヿ㐀-鿿]")


def words(text: str) -> set[str]:
    return {w.lower() for w in re.findall(r"[\w']+", text) if len(w) > 1}


def check(loc: str) -> int:
    d = ROOT / loc
    f = {k: (d / f"{k}.txt").read_text().rstrip("\n") for k in LIMITS}
    problems = 0
    print(f"== {loc}")
    for k, lim in LIMITS.items():
        n = len(f[k])
        flag = "" if n <= lim else "  OVER"
        problems += n > lim
        print(f"  {k:17} {n:5}/{lim}{flag}")
    for k, v in f.items():
        if "—" in v or re.search(r"\bnot\b[^.]{0,40}\bbut\b", v, re.I):
            print(f"  FLAG {k}: em dash or not-but construction")
            problems += 1
    toks = f["keywords"].split(",")
    seen: set[str] = set()
    ns = f["name"] + " " + f["subtitle"]
    nsw = words(ns)
    for t in toks:
        tl = t.lower()
        if t != t.strip() or not t:
            print(f"  FLAG whitespace/empty token {t!r}"); problems += 1
        if tl in seen:
            print(f"  FLAG duplicate {t}"); problems += 1
        seen.add(tl)
        if tl == "app":
            print("  FLAG 'app'"); problems += 1
        if tl in nsw or (CJK.search(t) and t in ns):
            print(f"  FLAG in name/subtitle: {t}"); problems += 1
        if tl.endswith("s") and tl[:-1] in {x.lower() for x in toks}:
            print(f"  FLAG plural pair: {t}"); problems += 1
    return problems


if __name__ == "__main__":
    locs = sys.argv[1:] or DEFAULT
    total = sum(check(loc) for loc in locs)
    print("PROBLEMS:", total)
    sys.exit(1 if total else 0)
