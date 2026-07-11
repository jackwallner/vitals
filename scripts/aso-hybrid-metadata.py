#!/usr/bin/env python3
"""
Apply hybrid ASO metadata: native-first keywords + high-pop English loanwords.

English inclusion rule (from Astro popularity research):
  pop >= 40  → include EN term if room (countdown, tracker, widget, fan)
  pop 15-39  → include in Tier-B markets (mx, de, br, in, es) when chars allow
  pop < 15   → native only (unless brand: Bond, GLP-1, statcast, etc.)

Always dedupe keywords against name + subtitle tokens.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Astro store → locales that share search behavior for EN loanword picks
HIGH_EN_BY_STORE: dict[str, list[str]] = {
    # Bond: countdown/tracker search strongly in EN across mx, es, de, br, in
    "bond": {
        "default": [],
        "mx": ["countdown"],
        "es": ["countdown"],
        "de": ["countdown", "tracker"],
        "br": ["countdown"],
        "in": ["countdown", "tracker"],
        "au": ["countdown"],
        "ca": ["countdown"],
        "gb": ["countdown"],
        "us": [],
    },
    "fitness": {
        "default": [],
        "mx": ["widget"],
        "de": ["widget"],
        "es": ["widget"],
        "us": ["widget"],
        "gb": ["widget"],
        "au": ["widget"],
    },
}

LOCALE_TO_STORE = {
    "ar-SA": "sa", "bn-BD": "in", "ca": "es", "cs": "cz", "da": "dk",
    "de-DE": "de", "el": "gr", "en-AU": "au", "en-CA": "ca", "en-GB": "gb",
    "en-US": "us", "es-ES": "es", "es-MX": "mx", "fi": "fi", "fr-CA": "ca",
    "fr-FR": "fr", "gu-IN": "in", "he": "il", "hi": "in", "hr": "hr",
    "hu": "hu", "id": "id", "it": "it", "ja": "jp", "kn-IN": "in", "ko": "kr",
    "ml-IN": "in", "mr-IN": "in", "ms": "my", "nl-NL": "nl", "no": "no",
    "or-IN": "in", "pa-IN": "in", "pl": "pl", "pt-BR": "br", "pt-PT": "pt",
    "ro": "ro", "ru": "ru", "sk": "sk", "sl-SI": "si", "sv": "se",
    "ta-IN": "in", "te-IN": "in", "th": "th", "tr": "tr", "uk": "ua",
    "ur-PK": "sa", "vi": "vn", "zh-Hans": "cn", "zh-Hant": "tw",
}

NAME_SEP = (" - ", " – ", " — ", ":", "|", "：", "·")

# Bond Indian / Pakistan locales — full localization templates
BOND_SOUTH_ASIA: dict[str, dict[str, str]] = {
    "hi": {
        "name": "Bond: प्रेम भाषा याद",
        "subtitle": "जोड़ा · काउंटर · सालगिरह",
        "keywords": "संबंध,ट्रैकर,काउंटडाउन,दूरी,संदेश,नोट,डेट,सवाल,विवाह,युगल,प्रेमी,पति,पत्नी",
    },
    "bn-BD": {
        "name": "Bond: ভালোবাসার ভাষা",
        "subtitle": "দম্পতি · কাউন্টার · বার্ষিকী",
        "keywords": "সম্পর্ক,ট্র্যাকার,কাউন্টডাউন,দূরত্ব,বার্তা,নোট,ডেট,প্রশ্ন,বিবাহ,যুগল,প্রেমিক,স্বামী,স্ত্রী",
    },
    "gu-IN": {
        "name": "Bond: પ્રેમ ભાષા યાદ",
        "subtitle": "જોડી · કાઉન્ટર · વર્ષગાંઠ",
        "keywords": "સંબંધ,ટ્રેકર,કાઉન્ટડાઉન,દૂર,સંદેશ,નોંધ,ડેટ,પ્રશ્ન,લગ્ન,યુગલ,પ્રેમી,પતિ,પત્ની",
    },
    "kn-IN": {
        "name": "Bond: ಪ್ರೀತಿ ಭಾಷೆ ಜ್ಞಾಪ",
        "subtitle": "ಜೋಡಿ · ಕೌಂಟರ್ · ವಾರ್ಷಿಕೋ",
        "keywords": "ಸಂಬಂಧ,ಟ್ರ್ಯಾಕರ್,ಕೌಂಟ್ಡೌನ್,ದೂರ,ಸಂದೇಶ,ನೋಟ್,ಡೇಟ್,ಪ್ರಶ್ನೆ,ಮದುವೆ,ಜೋಡಿ,ಪ್ರೇಮಿ,ಗಂಡ,ಹೆಂಡತಿ",
    },
    "ml-IN": {
        "name": "Bond: സ്നേഹ ഭാഷ ഓർമ്മ",
        "subtitle": "ജോഡി · കൗണ്ടർ · വാർഷികം",
        "keywords": "ബന്ധം,ട്രാക്കർ,കൗണ്ട്ഡൗൺ,ദൂരം,സന്ദേശം,കുറിപ്പ്,ഡേറ്റ്,ചോദ്യം,വിവാഹം,ജോഡി,പ്രേമി,ഭർത്താവ്,ഭാര്യ",
    },
    "mr-IN": {
        "name": "Bond: प्रेम भाषा आठवण",
        "subtitle": "जोडी · काउंटर · वर्धापन",
        "keywords": "नाते,ट्रॅकर,काउंटडाउन,अंतर,संदेश,नोट,डेट,प्रश्न,लग्न,जोडी,प्रिय,नवरा,बायको",
    },
    "or-IN": {
        "name": "Bond: ପ୍ରେମ ଭାଷା ସ୍ମରଣ",
        "subtitle": "ଯୋଡ଼ି · କାଉଣ୍ଟର · ବାର୍ଷିକୀ",
        "keywords": "ସମ୍ପର୍କ,ଟ୍ରାକର,କାଉଣ୍ଟଡାଉନ,ଦୂରତା,ବାର୍ତ୍ତା,ନୋଟ,ଡେଟ,ପ୍ରଶ୍ନ,ବିବାହ,ଯୋଡ଼ି,ପ୍ରେମିକ,ସ୍ଵାମୀ,ସ୍ତ୍ରୀ",
    },
    "pa-IN": {
        "name": "Bond: ਪਿਆਰ ਭਾਸ਼ਾ ਯਾਦ",
        "subtitle": "ਜੋੜਾ · ਕਾਊਂਟਰ · ਸਾਲਗਿਰਹ",
        "keywords": "ਰਿਸ਼ਤਾ,ਟ੍ਰੈਕਰ,ਕਾਊਂਟਡਾਉਨ,ਦੂਰੀ,ਸੁਨੇਹਾ,ਨੋਟ,ਡੇਟ,ਸਵਾਲ,ਵਿਆਹ,ਜੋੜਾ,ਪ੍ਰੇਮੀ,ਪਤੀ,ਪਤਨੀ",
    },
    "ta-IN": {
        "name": "Bond: அன்பு மொழி நினைவூட்ட",
        "subtitle": "ஜோடி · கவுண்டர் · ஆண்டுவிழா",
        "keywords": "உறவு,ட்ராக்கர்,கவுண்டவுன்,தூரம்,செய்தி,குறிப்பு,டேட்,கேள்வி,திருமணம்,ஜோடி,காதலன்,கணவன்,மனைவி",
    },
    "te-IN": {
        "name": "Bond: ప్రేమ భాష జ్ఞాపకం",
        "subtitle": "జంట · కౌంటర్ · వార్షికో",
        "keywords": "సంబంధం,ట్రాకర్,కౌంట్డౌన్,దూరం,సందేశం,నోట్,డేట్,ప్రశ్న,వివాహం,జంట,ప్రేమికుడు,భర్త,భార్య",
    },
    "ur-PK": {
        "name": "Bond: محبت کی زبان",
        "subtitle": "جوڑا · کاؤنٹر · سالگرہ",
        "keywords": "تعلق,ٹریکر,کاؤنٹ ڈاؤن,فاصلہ,پیغام,نوٹ,ڈیٹ,سوال,شادی,جوڑا,محبوب,شوہر,بیوی",
    },
}


def norm(s: str) -> str:
    return s.lower().strip()


def indexed_tokens(name: str, subtitle: str) -> set[str]:
    out: set[str] = set()
    blob = f"{name} {subtitle}"
    for sep in NAME_SEP:
        blob = blob.replace(sep, " ")
    for w in re.findall(r"[\w']+|[\u0600-\u06ff\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\u0900-\u097f]+", blob.lower()):
        if len(w) >= 2:
            out.add(w)
    if re.search(r"[\u3040-\u9fff\u3400-\u9fff]", name + subtitle):
        for chunk in re.findall(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\u0900-\u097f\u0600-\u06ff]+", name + subtitle):
            if len(chunk) >= 2:
                out.add(chunk)
    return out


def parse_kw(raw: str) -> list[str]:
    return [t.strip() for t in raw.replace("，", ",").replace("、", ",").split(",") if t.strip()]


def join_kw(tokens: list[str], limit: int = 100) -> str:
    out: list[str] = []
    length = 0
    for t in tokens:
        add = len(t) + (1 if out else 0)
        if length + add > limit:
            break
        out.append(t)
        length += add
    return ",".join(out)


def dedupe_keywords(name: str, subtitle: str, keywords: list[str]) -> list[str]:
    idx = indexed_tokens(name, subtitle)
    result: list[str] = []
    for t in keywords:
        tl = norm(t)
        if tl in idx:
            continue
        if t in name or t in subtitle:
            continue
        if tl not in {norm(x) for x in result}:
            result.append(t)
    return result


def merge_en_loanwords(
    tokens: list[str], locale: str, app_key: str, extra_en: list[str] | None = None
) -> list[str]:
    store = LOCALE_TO_STORE.get(locale, "us")
    cfg = HIGH_EN_BY_STORE.get(app_key, {})
    en_terms = list(cfg.get(store, cfg.get("default", [])))
    if extra_en:
        en_terms.extend(extra_en)
    existing = {norm(t) for t in tokens}
    for en in en_terms:
        if norm(en) not in existing:
            tokens.append(en)
            existing.add(norm(en))
    return tokens


def write_locale(meta_dir: Path, locale: str, fields: dict[str, str]) -> list[str]:
    issues = []
    d = meta_dir / locale
    d.mkdir(parents=True, exist_ok=True)
    for key, fname in [("name", "name.txt"), ("subtitle", "subtitle.txt"), ("keywords", "keywords.txt")]:
        if key not in fields:
            continue
        val = fields[key].strip()
        lim = 30 if key != "keywords" else 100
        if len(val) > lim:
            issues.append(f"{locale} {key}={len(val)}>{lim}")
        (d / fname).write_text(val + "\n", encoding="utf-8")
    return issues


def fix_bond(repo: Path) -> list[str]:
    issues: list[str] = []
    meta = repo / "fastlane" / "metadata"

    # South Asia full localization
    for loc, fields in BOND_SOUTH_ASIA.items():
        kw = dedupe_keywords(fields["name"], fields["subtitle"], parse_kw(fields["keywords"]))
        issues.extend(write_locale(meta, loc, {**fields, "keywords": join_kw(kw)}))

    # es-MX: Spanish base + high-pop EN countdown (Astro pop 62 mx)
    es_mx = {
        "name": (meta / "es-MX/name.txt").read_text(encoding="utf-8").strip(),
        "subtitle": (meta / "es-MX/subtitle.txt").read_text(encoding="utf-8").strip(),
    }
    base = parse_kw((meta / "es-ES/keywords.txt").read_text(encoding="utf-8"))
    base = [t for t in base if t not in {"larga", "recordatorio"}]  # room for high-pop EN
    kw = merge_en_loanwords(base, "es-MX", "bond")
    kw = dedupe_keywords(es_mx["name"], es_mx["subtitle"], kw)
    issues.extend(write_locale(meta, "es-MX", {**es_mx, "keywords": join_kw(kw)}))

    # Add countdown to es-ES if room (Astro pop 73 es)
    es = {
        "name": (meta / "es-ES/name.txt").read_text(encoding="utf-8").strip(),
        "subtitle": (meta / "es-ES/subtitle.txt").read_text(encoding="utf-8").strip(),
    }
    base = parse_kw((meta / "es-ES/keywords.txt").read_text(encoding="utf-8"))
    if "countdown" not in {norm(t) for t in base}:
        base = [t for t in base if t != "larga"]
        base = merge_en_loanwords(base, "es-ES", "bond")
    kw = dedupe_keywords(es["name"], es["subtitle"], base)
    issues.extend(write_locale(meta, "es-ES", {**es, "keywords": join_kw(kw)}))

    return issues


def fix_fitness_es_mx(repo: Path) -> list[str]:
    meta = repo / "fastlane" / "metadata"
    loc = "es-MX"
    name = (meta / loc / "name.txt").read_text(encoding="utf-8").strip()
    subtitle = (meta / loc / "subtitle.txt").read_text(encoding="utf-8").strip()
    base = parse_kw((meta / "es-ES/keywords.txt").read_text(encoding="utf-8"))
    kw = merge_en_loanwords(base, loc, "fitness")  # widget pop 60 mx
    kw = dedupe_keywords(name, subtitle, kw)
    return write_locale(meta, loc, {"name": name, "subtitle": subtitle, "keywords": join_kw(kw)})


def fix_gist_dupes(repo: Path) -> list[str]:
    issues: list[str] = []
    meta = repo / "fastlane" / "metadata"
    for d in sorted(meta.iterdir()):
        if not d.is_dir():
            continue
        loc = d.name
        kw_path = d / "keywords.txt"
        sub_path = d / "subtitle.txt"
        if not kw_path.exists() or not sub_path.exists():
            continue
        name = (d / "name.txt").read_text(encoding="utf-8").strip() if (d / "name.txt").exists() else ""
        subtitle = sub_path.read_text(encoding="utf-8").strip()
        tokens = parse_kw(kw_path.read_text(encoding="utf-8"))
        deduped = dedupe_keywords(name, subtitle, tokens)
        if deduped != tokens:
            new_kw = join_kw(deduped)
            if len(new_kw) < len(",".join(tokens)) - 5:
                # backfill with sport-specific filler per locale — keep simple: no-op if too much removed
                pass
            kw_path.write_text(new_kw + "\n", encoding="utf-8")
            if len(new_kw) > 100:
                issues.append(f"gist {loc} kw len {len(new_kw)}")
    return issues


def main() -> None:
    repos = {
        "bond": Path("/Users/jackwallner/bond"),
        "fitness": Path("/Users/jackwallner/fitness-streaks"),
        "gist": Path("/Users/jackwallner/sports"),
    }
    all_issues: list[str] = []
    if "bond" in repos:
        all_issues.extend(fix_bond(repos["bond"]))
    if "fitness" in repos:
        all_issues.extend(fix_fitness_es_mx(repos["fitness"]))
    if "gist" in repos:
        all_issues.extend(fix_gist_dupes(repos["gist"]))

    if all_issues:
        print("WARNINGS:")
        for i in all_issues:
            print(f"  {i}")
    else:
        print("Applied hybrid metadata fixes with no limit warnings.")


if __name__ == "__main__":
    main()
