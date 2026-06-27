#!/usr/bin/env python3
"""Apply optimized native keywords/subtitles for Total Calories (all fastlane locales).

Dedupes keywords against each locale's name + subtitle (Apple indexes all three;
repeats waste the 100-char keyword field — see astro-global-aso-go-2026.md).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"

# Candidate pools (≤100 after dedupe vs name/subtitle). Omit watch/widget/burn/daily/tracker/calories where indexed.
KEYWORDS: dict[str, str] = {
    # Priority order: pack to 100 chars after dedupe (high-intent first, not FIFO-trim from end)
    "en-US": "pedometer,ring,TDEE,BMR,steps,kcal,complication,deficit,resting,fasting,lockscreen,move,health,metabolism,counter,active,pace,walking,healthkit,activity",
    "en-GB": "pedometer,ring,TDEE,BMR,steps,kcal,complication,deficit,resting,fasting,lockscreen,move,health,metabolism,counter,active,pace,walking,healthkit,activity",
    "en-AU": "pedometer,ring,TDEE,BMR,steps,kcal,complication,deficit,resting,fasting,lockscreen,move,health,metabolism,counter,active,pace,walking,healthkit,activity",
    "en-CA": "pedometer,ring,TDEE,BMR,steps,kcal,complication,deficit,resting,fasting,lockscreen,move,health,metabolism,counter,active,pace,walking,healthkit,activity",
    "de-DE": "Schrittzähler,Ring,TDEE,BMR,Komplikation,Defizit,Ruhe,aktiv,Fasten,Gehen,Bewegung,HealthKit,Aktivität,Schritte,kcal,Sperrbildschirm,Stoffwechsel,Zähler,Gesundheit,Pace",
    "fr-FR": "podomètre,anneau,TDEE,BMR,complication,déficit,repos,actif,jeûne,marche,mouvement,healthkit,activité,pas,kcal,écranverrouillé,métabolisme,compteur,santé,rythme",
    "fr-CA": "podomètre,anneau,TDEE,BMR,complication,déficit,repos,actif,jeûne,marche,mouvement,healthkit,activité,pas,kcal,écranverrouillé,métabolisme,compteur,santé,rythme",
    "es-ES": "podómetro,anillo,TDEE,BMR,complicación,déficit,reposo,activo,ritmo,ayuno,caminar,mover,healthkit,actividad,pasos,kcal,pantallabloqueo,metabolismo,contador,salud",
    "es-MX": "podómetro,anillo,TDEE,BMR,complicación,déficit,reposo,activo,ritmo,ayuno,caminar,mover,healthkit,actividad,pasos,kcal,pantallabloqueo,metabolismo,contador,salud",
    "ca": "podòmetre,anell,TDEE,BMR,complicació,dèficit,repòs,actiu,ritme,dejuni,caminar,moure,healthkit,activitat,passos,kcal,pantallabloqueig,metabolisme,comptador,salut",
    "it": "pedometro,anello,TDEE,BMR,complicazione,deficit,riposo,attivo,ritmo,digiuno,camminare,mossa,healthkit,attività,passi,kcal,schermoblocco,metabolismo,contatore,salute",
    "pt-BR": "pedômetro,anel,TDEE,BMR,complicação,déficit,repouso,ativo,ritmo,jejum,caminhar,mover,healthkit,atividade,passos,kcal,telabloqueio,metabolismo,contador,saúde",
    "pt-PT": "pedómetro,anel,TDEE,BMR,complicação,déficit,repouso,ativo,ritmo,jejum,caminhar,mover,healthkit,atividade,passos,kcal,telabloqueio,metabolismo,contador,saúde",
    "nl-NL": "stappenteller,ring,TDEE,BMR,complicatie,tekort,rust,actief,tempo,vasten,lopen,bewegen,healthkit,activiteit,stappen,kcal,vergrendelscherm,metabolisme,teller,gezondheid",
    "pl": "krokomierz,pierścień,TDEE,BMR,komplikacja,deficyt,spoczynek,aktywny,rytm,post,chodzenie,ruch,healthkit,aktywność,kroki,kcal,ekranblokady,metabolizm,licznik,zdrowie",
    "sv": "stegräknare,ring,TDEE,BMR,komplikation,underskott,vila,aktiv,takt,fasta,gång,rörelse,healthkit,aktivitet,steg,kcal,låsskärm,metabolism,räknare,hälsa",
    "da": "skridttæller,ring,TDEE,BMR,komplikation,underskud,hvile,aktiv,takt,faste,gang,bevægelse,healthkit,aktivitet,skridt,kcal,låseskærm,stofskifte,tæller,sundhed",
    "no": "skritteller,ring,TDEE,BMR,komplikasjon,underskudd,hvile,aktiv,takt,faste,gang,bevegelse,healthkit,aktivitet,skritt,kcal,låseskjerm,stoffskifte,teller,helse",
    "fi": "askelmittari,rengas,TDEE,BMR,komplikaatio,alijäämä,lepo,aktiivinen,tahti,paasto,kävely,liike,healthkit,toiminta,askeleet,kcal,lukitusnäyttö,aineenvaihdunta,laskuri,terveys",
    "cs": "krokoměr,kroužek,TDEE,BMR,komplikace,deficit,klid,aktivní,tempo,půst,chůze,pohyb,healthkit,aktivita,kroky,kcal,zamčenáobrazovka,metabolismus,počítadlo,zdraví",
    "sk": "krokoměr,krúžok,TDEE,BMR,komplikácia,deficit,pokoj,aktívny,tempo,pôst,chôdza,pohyb,healthkit,aktivita,kroky,kcal,zamknutáobrazovka,metabolizmus,počítadlo,zdravie",
    "hu": "lépésszámláló,gyűrű,TDEE,BMR,komplikáció,hiány,pihenő,aktív,tempó,böjt,séta,mozgás,healthkit,aktivitás,lépések,kcal,zároltképernyő,anyagcsere,számláló,egészség",
    "ro": "pedometru,inel,TDEE,BMR,complicație,deficit,odihnă,activ,ritm,post,mers,mișcare,healthkit,activitate,pași,kcal,ecranblocat,metabolism,contor,sănătate",
    "hr": "pedometar,prsten,TDEE,BMR,komplikacija,deficit,odmor,aktivan,ritam,post,hodanje,pokret,healthkit,aktivnost,koraci,kcal,zaključanekran,metabolizam,brojač,zdravlje",
    "el": "βηματόμετρο,δακτύλιος,TDEE,BMR,επιπλοκή,έλλειμμα,ανάπαυση,ενεργό,ρυθμός,νηστεία,περπάτημα,κίνηση,healthkit,δραστηριότητα,βήματα,kcal,κλειδωμένηοθόνη,μεταβολισμός,μετρητής,υγεία",
    "tr": "adımsayar,halka,TDEE,BMR,komplikasyon,açık,dinlenme,aktif,tempo,oruç,yürüyüş,hareket,healthkit,aktivite,adımlar,kcal,kilitliekran,metabolizma,sayaç,sağlık",
    "ru": "шагомер,кольцо,TDEE,BMR,осложнение,дефицит,отдых,активный,темп,пост,ходьба,движение,healthkit,активность,шаги,kcal,экранблокировки,метаболизм,счётчик,здоровье",
    "uk": "крокомір,кільце,TDEE,BMR,ускладнення,дефіцит,відпочинок,активний,темп,піст,ходьба,рух,healthkit,активність,кроки,kcal,екранблокування,метаболізм,лічильник,здоров'я",
    "ja": "歩数計,リング,TDEE,BMR,コンプリケーション,不足,安静,アクティブ,ペース,断食,ウォーキング,ムーブ,healthkit,活動,歩数,kcal,ロック画面,代謝,カウンター,健康",
    "ko": "만보기,링,TDEE,BMR,컴플리케이션,부족,휴식,활동,페이스,단식,걷기,이동,healthkit,활동량,걸음,kcal,잠금화면,대사,카운터,건강",
    "zh-Hans": "计步器,圆环,TDEE,BMR,表盘,缺口,静息,活动,节奏,断食,步行,移动,healthkit,活动量,步数,kcal,锁屏,代谢,计数器,健康",
    "zh-Hant": "計步器,圓環,TDEE,BMR,錶盤,缺口,靜息,活動,節奏,斷食,步行,移動,healthkit,活動量,步數,kcal,鎖屏,代謝,計數器,健康",
    "ar-SA": "عدادخطوات,حلقة,TDEE,BMR,مضاعفة,عجز,راحة,نشط,إيقاع,صيام,مشي,حركة,healthkit,نشاط,خطوات,kcal,شاشةالقفل,أيض,عداد,صحة",
    "he": "מדצעדים,טבעת,TDEE,BMR,סיבוך,גירעון,מנוחה,פעיל,קצב,צום,הליכה,תנועה,healthkit,פעילות,צעדים,kcal,מסךנעילה,חילוףחומרים,מונה,בריאות",
    "hi": "पेडोमीटर,रिंग,TDEE,BMR,जटिलता,घाटा,विश्राम,सक्रिय,गति,उपवास,चलना,गति,healthkit,गतिविधि,कदम,kcal,लॉकस्क्रीन,चयापचय,काउंटर,स्वास्थ्य",
    "th": "นับก้าว,แหวน,TDEE,BMR,ภาพปะ,ขาด,พัก,กระตือ,จังหวะ,อด,เดิน,เคลื่อน,healthkit,กิจกรรม,ก้าว,kcal,หน้าจอล็อก,เมตาบอลิซึม,ตัวนับ,สุขภาพ",
    "vi": "đếmbước,vòng,TDEE,BMR,phứctạp,thiếu,nghỉ,hoạt,nhịp,nhịn,đibộ,dichuyen,healthkit,hoạtđộng,bước,kcal,mànhìnhkhóa,traođổichất,đếm,sứckhỏe",
    "id": "pedometer,cincin,TDEE,BMR,komplikasi,defisit,istirahat,aktif,ritme,puasa,jalan,gerak,healthkit,aktivitas,langkah,kcal,layarkunci,metabolisme,pencacah,kesehatan",
    "ms": "pedometer,cincin,TDEE,BMR,komplikasi,defisit,rehat,aktif,ritma,puasa,jalan,gerak,healthkit,aktiviti,langkah,kcal,skrinkunci,metabolisme,pembilang,kesihatan",
}

SUBTITLES: dict[str, str] = {
    "en-US": "Daily Burn on Watch & Widget",
    "en-GB": "Daily Burn on Watch & Widget",
    "en-AU": "Daily Burn on Watch & Widget",
    "en-CA": "Daily Burn on Watch & Widget",
    "de-DE": "Tagesverbrennung Uhr & Widget",
    "fr-FR": "Brûlure du jour Montre Widget",
    "fr-CA": "Brûlure du jour Montre Widget",
    "es-ES": "Quema diaria reloj y widget",
    "es-MX": "Quema diaria reloj y widget",
    "ca": "Cal cremat diari rellotge",
    "it": "Bruciatura giornaliera orologio",
    "pt-BR": "Queima diária relógio widget",
    "pt-PT": "Queima diária relógio widget",
    "nl-NL": "Dagelijkse verbranding horloge",
    "pl": "Dzienna spalanka zegarek widget",
    "sv": "Daglig förbränning klocka",
    "da": "Dagligt forbrænd ur widget",
    "no": "Daglig forbrenning klokke",
    "fi": "Päivittäinen kulutus kello",
    "cs": "Denní spálení hodinky widget",
    "sk": "Denné spaľovanie hodinky",
    "hu": "Napi elégés óra widget",
    "ro": "Ardere zilnică ceas widget",
    "hr": "Dnevno sagorijevanje sat",
    "el": "Ημερήσια καύση ρολόι widget",
    "tr": "Günlük yakım saat widget",
    "ru": "Сжигание в день часы виджет",
    "uk": "Щоденне спалення годинник",
    "ja": "今日の消費 腕時計＆ウィジェット",
    "ko": "일일 소모 워치·위젯",
    "zh-Hans": "每日消耗 手表与小组件",
    "zh-Hant": "每日消耗 手錶與小工具",
    "ar-SA": "حرق يومي ساعة وودجت",
    "he": "שריפה יומית שעון ווידג'ט",
    "hi": "दैनिक बर्न घड़ी विजेट",
    "th": "เผาผลาญรายวัน นาฬิกา วิดเจ็ต",
    "vi": "Đốt cháy hàng ngày đồng hồ",
    "id": "Pembakaran harian jam widget",
    "ms": "Pembakaran harian jam widget",
    "bn-BD": "পদক্ষেপমাপক,রিং,tdee,bmr,জটিলতা,ঘাটতি,বিশ্রাম,সক্রিয়,গতি,উপবাস,হাঁটা,healthkit,কার্যকলাপ",
    "gu-IN": "પગલાકાર,રિંગ,tdee,bmr,જટિલતા,ઘાટો,વિશ્રામ,સક્રિય,ગતિ,ઉપવાસ,ચાલ,vitality,healthkit",
    "kn-IN": "ಪೆಡೋಮೀಟರ್,ರಿಂಗ್,tdee,bmr,ಸಂಕೀರ್ಣತೆ,ಕೊರತೆ,ವಿಶ್ರಾಂತಿ,ಸಕ್ರಿಯ,ವೇಗ,ಉಪವಾಸ,ನಡೆ,healthkit,ಚಟುವಟಿಕೆ",
    "ml-IN": "നടക്കൽമാപകൻ,റിംഗ്,tdee,bmr,സങ്കീർണത,കുറവ്,വിശ്രാമം,സജീവം,വേഗം,ഉപവാസം,നടപ്പ്,healthkit",
    "mr-IN": "पाऊलमोजक,रिंग,tdee,bmr,गुंतागुंत,तूट,विश्रांती,सक्रिय,गती,उपवास,चाल,healthkit",
    "or-IN": "ପଦଚାଳନାମାପକ,ରିଂ,tdee,bmr,ଜଟିଳତା,ଘାଟ,ବିଶ୍ରାମ,ସକ୍ରିୟ,ଗତି,ଉପବାସ,ଚାଲ,healthkit",
    "pa-IN": "ਕਦਮਮਾਪ,tdee,bmr,ਰਿੰਗ,ਜਟਿਲਤਾ,ਘਾਟਾ,ਆਰਾਮ,ਸਰਗਰਮ,ਰਫ਼ਤਾਰ,ਉਪਵਾਸ,ਟੁਰਨਾ,healthkit",
    "ta-IN": "படியெண்ணி,மோதிரம்,tdee,bmr,சிக்கல்,பற்றாக்குறை,ஓய்வு,செயல்,வேகம்,உபவாசம்,நடை,healthkit",
    "te-IN": "అడుగులమాపకం,రింగ్,tdee,bmr,సంక్లిష్టత,లోపం,విశ్రాంతి,చురుకు,వేగం,ఉపవాసం,నడక,healthkit",
    "ur-PK": "قدمشمار,انگ,ring,tdee,bmr,پیچیدگی,کمی,آرام,فعال,رفتار,روزہ,چلنا,healthkit",
    "sl-SI": "merilnikkorakov,obroč,tdee,bmr,komplikacija,primanjkljaj,pocitek,aktiven,tempo,post,hoja,healthkit",
}


def indexed_terms(name: str, subtitle: str) -> set[str]:
    """Tokens already credited via App Store name + subtitle."""
    text = f"{name} {subtitle}".lower()
    terms: set[str] = set()
    for w in re.findall(r"[\w']+", text, flags=re.UNICODE):
        w = w.strip("'")
        if len(w) >= 2:
            terms.add(w)
    return terms


def dedupe_keywords(name: str, subtitle: str, keywords_csv: str) -> str:
    """Drop keywords already present in name/subtitle (ASC ASO Assist rule)."""
    indexed = indexed_terms(name, subtitle)
    kept: list[str] = []
    for raw in keywords_csv.replace(" ", "").split(","):
        kw = raw.strip().lower()
        if not kw:
            continue
        if kw in indexed:
            continue
        if any(kw == t or (len(kw) >= 4 and kw in t) or (len(t) >= 4 and t in kw) for t in indexed):
            continue
        kept.append(kw)
    return ",".join(kept)


def pack_keywords(parts: list[str], limit: int = 100) -> str:
    """Keep highest-priority terms first until the 100-char limit (fill, don't waste space)."""
    kept: list[str] = []
    for kw in parts:
        kw = kw.strip()
        if not kw:
            continue
        trial = ",".join(kept + [kw]) if kept else kw
        if len(trial) <= limit:
            kept.append(kw)
    return ",".join(kept)


def trim_subtitle(s: str, limit: int = 30) -> str:
    return s[:limit] if len(s) > limit else s


def main() -> None:
    report: dict[str, dict] = {}
    for loc_dir in sorted(META.iterdir()):
        if not loc_dir.is_dir() or loc_dir.name == "review_information":
            continue
        loc = loc_dir.name
        if loc not in KEYWORDS:
            continue
        kw_path = loc_dir / "keywords.txt"
        sub_path = loc_dir / "subtitle.txt"
        old_kw = kw_path.read_text(encoding="utf-8").strip() if kw_path.exists() else ""
        old_sub = sub_path.read_text(encoding="utf-8").strip() if sub_path.exists() else ""
        name = (loc_dir / "name.txt").read_text(encoding="utf-8").strip() if (loc_dir / "name.txt").exists() else ""
        sub_for_dedupe = SUBTITLES.get(loc, old_sub)
        raw_kw = KEYWORDS[loc]
        deduped = [p for p in dedupe_keywords(name, sub_for_dedupe, raw_kw).split(",") if p]
        new_kw = pack_keywords(deduped)
        kw_path.write_text(new_kw + "\n", encoding="utf-8")
        new_sub = old_sub
        if loc in SUBTITLES:
            new_sub = trim_subtitle(SUBTITLES[loc])
            sub_path.write_text(new_sub + "\n", encoding="utf-8")
        report[loc] = {
            "keywords": {"old": old_kw, "new": new_kw, "len": len(new_kw)},
            "subtitle": {"old": old_sub, "new": new_sub, "len": len(new_sub)} if loc in SUBTITLES else {},
        }
    out = ROOT / "scripts" / "aso-locale-optimization-report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"Updated {len(report)} locales → {out}")


if __name__ == "__main__":
    main()
