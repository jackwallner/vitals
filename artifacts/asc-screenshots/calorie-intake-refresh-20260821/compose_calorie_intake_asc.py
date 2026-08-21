#!/usr/bin/env python3
"""Compose the combined calorie-intake capture with the existing ASC style."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
LEGACY_PATH = ROOT.parent / "total-calories-refresh-20260820" / "compose_total_calories_asc.py"
spec = importlib.util.spec_from_file_location("total_calories_asc_style", LEGACY_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Could not load ASC style compositor: {LEGACY_PATH}")
style = importlib.util.module_from_spec(spec)
spec.loader.exec_module(style)

style.ROOT = ROOT
style.RAW = ROOT / "raw"
style.FINAL = ROOT / "final"
style.QA = ROOT / "qa"

FRAME = {
    "filename": "01-calorie-intake.png",
    "first": "See your",
    "second": "calorie intake",
    "source": "calorie-intake.png",
    "background": "photo",
    "top": 640,
    "width": 885,
    "x": 198,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_contact_sheet(output: Path) -> None:
    with Image.open(output) as source:
        thumbnail = source.convert("RGB").resize((321, 694), Image.Resampling.LANCZOS)
    sheet = Image.new("RGB", (385, 770), (235, 231, 224))
    sheet.paste(thumbnail, (32, 24))
    draw = ImageDraw.Draw(sheet)
    label_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
    draw.text((32, 730), "01  01-calorie-intake", fill=style.INK, font=label_font)
    sheet.save(ROOT / "qa" / "contact-sheet.png", format="PNG")


def main() -> None:
    style.FINAL.mkdir(parents=True, exist_ok=True)
    style.QA.mkdir(parents=True, exist_ok=True)
    output = style.FINAL / FRAME["filename"]
    style.compose_frame(FRAME).save(output, format="PNG", optimize=True)
    write_contact_sheet(output)
    metadata = {
        "canvas": [style.WIDTH, style.HEIGHT],
        "color_mode": "RGB",
        "style_source": str(LEGACY_PATH),
        "headline": "See your calorie intake",
        "literal_source": "raw/calorie-intake.png",
        "raw_sha256": sha256(style.RAW / "calorie-intake.png"),
        "final_sha256": sha256(output),
        "capture_report": "raw/capture-report.json",
        "proof": "One literal app screen shows the +450 net deficit, 2,400 burned minus 1,950 eaten, and the macro card with protein, carbs, fat, and the macro-calorie split.",
    }
    (style.QA / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"final": str(output), "contact_sheet": str(style.QA / "contact-sheet.png")}, indent=2))


if __name__ == "__main__":
    main()
