#!/usr/bin/env python3
"""Apply 625plan.md §3 (en-US) + §4 structural rule-set to fastlane/metadata.

Does NOT upload — run asc-ensure-draft-version.py then asc-upload-metadata.py after.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"

# §3 exact US target (100 chars keywords)
EN_US_SUBTITLE = "TDEE Burn on Watch & Widget"
EN_US_KEYWORDS = "bmr,complication,resting,active,ring,calculator,deficit,net,energy,steps,metabolic,pacing,bmi,burned"

ENGLISH_LOCALES = {"en-US", "en-GB", "en-AU", "en-CA"}

# §4.4 burned-word gaps (best-effort; SERP-validated per plan §8.4 in a later pass)
BURNED_BY_LOCALE: dict[str, str] = {
    "de-DE": "verbrannt",
    "fr-FR": "brûlées",
    "fr-CA": "brûlées",
    "es-ES": "quemadas",
    "es-MX": "quemadas",
    "ca": "cremades",
    "it": "bruciate",
    "pt-BR": "queimadas",
    "pt-PT": "queimadas",
    "nl-NL": "verbrand",
    "pl": "spalone",
    "tr": "yakılan",
    "sv": "förbrända",
    "da": "forbrændt",
    "no": "forbrent",
    "fi": "poltettu",
    "cs": "spálené",
    "sk": "spálené",
    "hu": "elégett",
    "ro": "arse",
    "hr": "sagorjeno",
    "el": "καμένες",
    "ru": "сожжённые",
    "uk": "спалені",
    "ja": "消費",
    "ko": "소모",
    "zh-Hans": "消耗",
    "zh-Hant": "消耗",
    "ar-SA": "محروق",
    "he": "נשרף",
    "hi": "जली",
    "th": "เผาไหม้",
    "vi": "đốt",
    "id": "terbakar",
    "ms": "terbakar",
}

# §4.7 TDEE-leading subtitles (≤30 chars), conversion-friendly
SUBTITLE_BY_LOCALE: dict[str, str] = {
    "en-US": EN_US_SUBTITLE,
    "en-GB": EN_US_SUBTITLE,
    "en-AU": EN_US_SUBTITLE,
    "en-CA": EN_US_SUBTITLE,
    "de-DE": "TDEE Verbrennung Uhr Widget",
    "fr-FR": "TDEE Brûlure Montre Widget",
    "fr-CA": "TDEE Brûlure Montre Widget",
    "es-ES": "TDEE Quema Reloj y Widget",
    "es-MX": "TDEE Quema Reloj y Widget",
    "ca": "TDEE Cremat Rellotge Widget",
    "it": "TDEE Bruciatura Orologio",
    "pt-BR": "TDEE Queima Relógio Widget",
    "pt-PT": "TDEE Queima Relógio Widget",
    "nl-NL": "TDEE Verbranding Horloge",
    "pl": "TDEE Spalanie Zegarek",
    "sv": "TDEE Förbränning Klocka",
    "da": "TDEE Forbrænding Ur Widget",
    "no": "TDEE Forbrenning Klokke",
    "fi": "TDEE Kulutus Kello Widget",
    "cs": "TDEE Spálení Hodinky",
    "sk": "TDEE Spaľovanie Hodinky",
    "hu": "TDEE Elégés Óra Widget",
    "ro": "TDEE Ardere Ceas Widget",
    "hr": "TDEE Sagorijevanje Sat",
    "el": "TDEE Καύση Ρολόι Widget",
    "tr": "TDEE Yakım Saat Widget",
    "ru": "TDEE Сжигание Часы Виджет",
    "uk": "TDEE Спалення Годинник",
    "ja": "TDEE消費 腕時計＆ウィジェット",
    "ko": "TDEE 소모 워치·위젯",
    "zh-Hans": "TDEE消耗 手表与小组件",
    "zh-Hant": "TDEE消耗 手錶與小工具",
    "ar-SA": "TDEE حرق ساعة وودجت",
    "he": "TDEE שריפה שעון ווידג'ט",
    "hi": "TDEE बर्न घड़ी विजेट",
    "th": "TDEE เผาผลาญ นาฬิกา วิดเจ็ต",
    "vi": "TDEE Đốt cháy Đồng hồ",
    "id": "TDEE Bakar Jam Widget",
    "ms": "TDEE Bakar Jam Widget",
    "bn-BD": "TDEE বার্ন ঘড়ি ওয়িজেট",
    "gu-IN": "TDEE બર્ન વોચ વિજેટ",
    "kn-IN": "TDEE ಬರ್ನ್ ವಾಚ್ ವಿಜೆಟ್",
    "ml-IN": "TDEE ബേൺ വാച്ച് വിജറ്റ്",
    "mr-IN": "TDEE बर्न वॉच विजेट",
    "or-IN": "TDEE ବର୍ନ ୱାଚ ଉଇଜେଟ",
    "pa-IN": "TDEE ਬਰਨ ਵਾਚ ਵਿਜਟ",
    "ta-IN": "TDEE எரிப்பு வாட்ச் விஜெட்",
    "te-IN": "TDEE బర్న్ వాచ్ విడ్జెట్",
    "ur-PK": "TDEE برن واچ ویجٹ",
    "sl-SI": "TDEE Zgorevanje Ura Widget",
}

# §4.6 drop ring-equivalents in non-English (lowercase match)
RING_EQUIVALENTS = {
    "ring", "anel", "anillo", "anell", "pierścień", "pierścien", "rengas", "kroužek",
    "krúžok", "gyűrű", "inel", "prsten", "δακτύλιος", "halka", "кольцо", "кільце",
    "リング", "링", "圆环", "圓環", "حلقة", "טבעת", "रिंग", "แหวน", "vòng", "cincin",
    "obroč", "rīng", "রিং", "રિંગ", "ರಿಂಗ್", "റിംഗ്", "ରିଂ", "ਰਿੰਗ", "மோதிரம்",
    "రింగ్", "انگ",
}


def pack_keywords(parts: list[str], limit: int = 100) -> str:
    kept: list[str] = []
    for kw in parts:
        kw = kw.strip()
        if not kw:
            continue
        trial = ",".join(kept + [kw]) if kept else kw
        if len(trial) <= limit:
            kept.append(kw)
    return ",".join(kept)


def transform_keywords(locale: str, current: str) -> str:
    if locale in ENGLISH_LOCALES:
        return EN_US_KEYWORDS

    parts = [p.strip() for p in current.replace(" ", "").split(",") if p.strip()]
    filtered: list[str] = []
    seen: set[str] = set()
    for p in parts:
        low = p.lower()
        if low == "tdee":
            continue
        if low in RING_EQUIVALENTS:
            continue
        if low in seen:
            continue
        seen.add(low)
        filtered.append(p)

    if "bmi" not in seen:
        filtered.append("bmi")
        seen.add("bmi")

    burned = BURNED_BY_LOCALE.get(locale)
    if burned and burned.lower() not in seen:
        filtered.append(burned)
        seen.add(burned.lower())

    if locale != "en-US" and "kcal" not in seen:
        filtered.append("kcal")
        seen.add("kcal")

    return pack_keywords(filtered)


def trim_subtitle(s: str, limit: int = 30) -> str:
    return s[:limit] if len(s) > limit else s


def main() -> None:
    report: dict[str, dict] = {}
    for loc_dir in sorted(META.iterdir()):
        if not loc_dir.is_dir() or loc_dir.name == "review_information":
            continue
        loc = loc_dir.name
        kw_path = loc_dir / "keywords.txt"
        sub_path = loc_dir / "subtitle.txt"
        if not kw_path.exists() or not sub_path.exists():
            continue

        old_kw = kw_path.read_text(encoding="utf-8").strip()
        old_sub = sub_path.read_text(encoding="utf-8").strip()

        new_sub = trim_subtitle(SUBTITLE_BY_LOCALE.get(loc, f"TDEE {old_sub}"[:24]))
        new_kw = transform_keywords(loc, old_kw)

        sub_path.write_text(new_sub + "\n", encoding="utf-8")
        kw_path.write_text(new_kw + "\n", encoding="utf-8")

        if old_kw != new_kw or old_sub != new_sub:
            report[loc] = {
                "subtitle": {"old": old_sub, "new": new_sub},
                "keywords": {"old": old_kw, "new": new_kw, "len": len(new_kw)},
            }

    out = ROOT / "scripts" / "625-metadata-report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Updated {len(report)} locales → {out}")
    for loc in ("en-US", "de-DE", "fr-FR", "ja"):
        if loc in report:
            print(f"  {loc} subtitle: {report[loc]['subtitle']['new']!r}")


if __name__ == "__main__":
    main()
