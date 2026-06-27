#!/usr/bin/env python3
"""Step 3: search_app_store for each Astro store (native head term)."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from astro_mcp import call, ping

MCP_URL = "http://127.0.0.1:8089/mcp"
STORES_JSON = Path(__file__).parent / "astro-stores-2026.json"
OUT = Path(__file__).parent / "astro-competitor-research.json"

# Native search head terms — Total Calories
HEAD_TERMS: dict[str, str] = {
    "us": "calorie tracker watch",
    "gb": "calorie tracker watch",
    "de": "kalorien tracker uhr",
    "fr": "calories brûlées montre",
    "es": "calorías quemadas reloj",
    "mx": "calorías quemadas reloj",
    "br": "calorias queimadas relógio",
    "jp": "消費カロリー ウォッチ",
    "kr": "칼로리 소모 워치",
    "cn": "消耗热量 手表",
    "tw": "消耗卡路里 手錶",
    "it": "calorie bruciate orologio",
    "nl": "calorieën verbrand horloge",
    "pl": "spalone kalorie zegarek",
    "ru": "калории сожженные часы",
    "tr": "yakılan kalori saat",
    "sa": "سعرات حرارية محروقة",
    "in": "calorie tracker watch",
    "th": "แคลอรี่เผา นาฬิกา",
    "vi": "calo đốt đồng hồ",
    "id": "pelacak kalori jam",
}

DEFAULT_TERM = "calorie tracker watch"


def head_term(store: str) -> str:
    return HEAD_TERMS.get(store, DEFAULT_TERM)


def main() -> None:
    if not ping(MCP_URL):
        raise SystemExit("error: Astro MCP not reachable")
    stores = json.loads(STORES_JSON.read_text())["stores"]
    results: dict = {"scannedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "stores": {}}
    for i, entry in enumerate(stores):
        code = entry["code"]
        term = head_term(code)
        try:
            hits = call(MCP_URL, "search_app_store", {"query": term, "store": code, "limit": 5})
            top = []
            if isinstance(hits, list):
                for h in hits[:5]:
                    if isinstance(h, dict):
                        top.append(
                            {
                                "name": h.get("name") or h.get("trackName"),
                                "subtitle": h.get("subtitle"),
                                "bundleId": h.get("bundleId"),
                            }
                        )
            results["stores"][code] = {"term": term, "competitors": top}
            print(f"{code}: {len(top)} hits for '{term}'")
        except Exception as e:
            results["stores"][code] = {"term": term, "error": str(e)}
            print(f"{code}: ERROR {e}", file=sys.stderr)
        if i < len(stores) - 1:
            time.sleep(1.2)
    OUT.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
