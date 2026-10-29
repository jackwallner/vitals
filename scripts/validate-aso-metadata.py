#!/usr/bin/env python3
"""Validate App Store metadata limits and keyword collisions for selected locales."""

from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCALES = [
    "en-US", "en-GB", "en-AU", "en-CA", "de-DE", "fr-FR", "fr-CA",
    "es-ES", "es-MX", "ja", "pl", "it", "nl-NL", "zh-Hans", "pt-BR",
    "sv", "ar-SA", "ru",
]
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "keywords": 100,
    "promotional_text": 170,
    "description": 4000,
}
FIELDS = tuple(LIMITS)
COMPACT_LOCALES = {"ja", "zh-Hans", "zh-Hant"}


def normalize(value: str) -> str:
    return unicodedata.normalize("NFKC", value).casefold()


def app_tokens(name: str, subtitle: str) -> set[str]:
    return {normalize(token) for token in re.findall(r"[\w]+", f"{name} {subtitle}")}


def validate_locale(locale: str) -> list[str]:
    folder = ROOT / "fastlane" / "metadata" / locale
    errors: list[str] = []
    values: dict[str, str] = {}

    for field in FIELDS:
        path = folder / f"{field}.txt"
        if not path.is_file():
            errors.append(f"{field}.txt is missing")
            continue
        raw = path.read_text(encoding="utf-8")
        value = raw.rstrip("\n")
        values[field] = value
        if not value:
            errors.append(f"{field} is empty")
        if value != value.strip():
            errors.append(f"{field} has leading or trailing whitespace")
        if len(value) > LIMITS[field]:
            errors.append(f"{field} is {len(value)} characters, limit is {LIMITS[field]}")
        if "\u2014" in value:
            errors.append(f"{field} contains an em dash")

    if "keywords" in values and "name" in values and "subtitle" in values:
        raw_tokens = values["keywords"].split(",")
        tokens = [token.strip() for token in raw_tokens]
        if any(not token for token in tokens):
            errors.append("keywords contains an empty token")
        if any(any(char.isspace() for char in token) for token in tokens):
            errors.append("keywords contains whitespace inside a token")
        normalized = [normalize(token) for token in tokens if token]
        repeated = sorted({token for token in normalized if normalized.count(token) > 1})
        if repeated:
            errors.append("duplicate keyword tokens: " + ", ".join(repeated))

        title = values["name"]
        subtitle = values["subtitle"]
        title_tokens = app_tokens(title, "")
        subtitle_tokens = app_tokens("", subtitle)
        repeated_from_metadata: set[str] = set()
        for token in normalized:
            if locale in COMPACT_LOCALES:
                compact_title = normalize(re.sub(r"[^\w]", "", title))
                compact_subtitle = normalize(re.sub(r"[^\w]", "", subtitle))
                if token and (token in compact_title or token in compact_subtitle):
                    repeated_from_metadata.add(token)
            elif token in title_tokens or token in subtitle_tokens:
                repeated_from_metadata.add(token)
        if repeated_from_metadata:
            errors.append(
                "keywords repeats name/subtitle tokens: "
                + ", ".join(sorted(repeated_from_metadata))
            )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("locales", nargs="*", help="locale folders to validate")
    args = parser.parse_args()
    locales = args.locales or DEFAULT_LOCALES
    failed = False

    for locale in locales:
        errors = validate_locale(locale)
        if errors:
            failed = True
            for error in errors:
                print(f"FAIL {locale}: {error}")
        else:
            print(f"OK {locale}")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
