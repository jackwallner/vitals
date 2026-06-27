#!/usr/bin/env python3
"""Write true native name/subtitle/keywords/description for locales still in English."""
from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
SCRIPT_DIR = Path(__file__).resolve().parent


def _load_aso_helpers():
    path = SCRIPT_DIR / "aso-apply-locale-optimizations.py"
    spec = importlib.util.spec_from_file_location("aso_apply", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.dedupe_keywords, mod.pack_keywords, mod.trim_subtitle


dedupe_keywords, pack_keywords, trim_subtitle = _load_aso_helpers()


def apply_one(loc: str, data: dict[str, str]) -> None:
    d = META / loc
    d.mkdir(parents=True, exist_ok=True)
    name = data["name"].strip()
    sub = trim_subtitle(data["subtitle"].strip())
    kw = pack_keywords(
        [p for p in dedupe_keywords(name, sub, data["keywords"]).split(",") if p]
    )
    (d / "name.txt").write_text(name + "\n", encoding="utf-8")
    (d / "subtitle.txt").write_text(sub + "\n", encoding="utf-8")
    (d / "keywords.txt").write_text(kw + "\n", encoding="utf-8")
    (d / "description.txt").write_text(data["description"].strip() + "\n", encoding="utf-8")
    us = META / "en-US"
    for f in (
        "support_url.txt",
        "marketing_url.txt",
        "privacy_url.txt",
        "release_notes.txt",
        "promotional_text.txt",
        "apple_tv_privacy_policy.txt",
    ):
        if not (d / f).exists() and (us / f).exists():
            (d / f).write_text((us / f).read_text(encoding="utf-8"), encoding="utf-8")


def main() -> None:
    content: dict[str, dict[str, str]] = {}
    bundle = SCRIPT_DIR / "native-locale-content.json"
    per_locale = SCRIPT_DIR / "native_locale_content"
    if bundle.exists():
        content.update(json.loads(bundle.read_text(encoding="utf-8")))
    if per_locale.is_dir():
        for path in sorted(per_locale.glob("*.json")):
            content[path.stem] = json.loads(path.read_text(encoding="utf-8"))
    if not content:
        raise SystemExit(f"Missing {bundle} or {per_locale}/*.json")
    for loc, data in sorted(content.items()):
        apply_one(loc, data)
        kw_len = len((META / loc / "keywords.txt").read_text(encoding="utf-8").strip())
        print(f"applied {loc} (keywords {kw_len}/100)")
    print(f"Done — {len(content)} locales")


if __name__ == "__main__":
    main()
