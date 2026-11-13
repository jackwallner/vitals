#!/usr/bin/env python3
"""Capture Total Calories on a 13-inch iPad simulator in each language (portrait, 2064x2752).

usage: capture_ipad.py <ipad-udid> <out-root> <asc-locale>[,...]|all
Raw frames land in <out-root>/<asc-locale>/. Reuses capture.py's launch and settle logic.
The iPad shows Today and History side by side, so the frames are the scenes whose
History pane differs: free, Vitals+, net deficit, macro goals, macro history.
"""
from __future__ import annotations

import json
import sys
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

cap = SourceFileLoader("capture", str(Path(__file__).resolve().parent / "capture.py")).load_module()

cap.LOCALES = {"en-US": ("en", "en_US"), **cap.LOCALES}
IPAD_SCENES = {
    "dashboard": "dashboard", "premium-dashboard": "premiumDashboard", "net-deficit": "netDeficit",
    "macro-goals": "macroGoals", "macro-history": "macroHistory",
}


def main() -> None:
    udid, root = sys.argv[1], Path(sys.argv[2])
    locales = list(cap.LOCALES) if sys.argv[3] == "all" else sys.argv[3].split(",")
    for locale in locales:
        language, region = cap.LOCALES[locale]
        out = root / locale
        out.mkdir(parents=True, exist_ok=True)
        if (out / ".done").exists():
            continue
        started = time.monotonic()
        for name, scene in IPAD_SCENES.items():
            cap.launch(udid, cap.BUNDLE["phone"], scene, language, region)
            cap.settled(udid, out / f"{name}.png", 3.0, 45.0)
        (out / ".done").touch()
        print(json.dumps({"locale": locale, "seconds": round(time.monotonic() - started)}), flush=True)


if __name__ == "__main__":
    main()
