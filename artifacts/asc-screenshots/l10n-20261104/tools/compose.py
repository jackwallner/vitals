#!/usr/bin/env python3
"""Compose the nine-frame Total Calories iPhone set for one or more ASC locales.

Same layout, backgrounds and photo as the live en-US set, from per-language
captures. Headers come from copy/headers.json and are drawn by the headline tool
(CoreText) so every script shapes correctly.

usage: compose.py <raw-root> <headline-binary> <out-root> <locale|all>
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
BASE = HERE.parent
STYLE_ROOT = BASE.parent / "total-calories-refresh-20260820"
spec = importlib.util.spec_from_file_location("style", STYLE_ROOT / "compose_total_calories_asc.py")
style = importlib.util.module_from_spec(spec)
spec.loader.exec_module(style)

FRAMES = [
    ("01", "01_keep-it-on-your-wrist.png", "wrist", "cream", 0, 0, None),
    ("02", "02_know-your-total-burn.png", "dashboard", "cream", 690, 1010, None),
    ("03", "03_see-your-calorie-intake.png", "calorie-intake", "photo", 640, 885, 198),
    ("04", "04_see-what-makes-your-burn.png", "premium-dashboard", "white", 690, 1010, None),
    ("05", "05_find-your-daily-patterns.png", "history", "white", 690, 1010, None),
    ("06", "06_burned-minus-eaten.png", "net-deficit", "teal", 920, 1010, None),
    ("07", "07_set-your-macro-goals.png", "macro-goals", "cream", 700, 1010, None),
    ("08", "08_spot-your-macro-patterns.png", "macro-history", "white", 690, 1010, None),
    ("09", "09_read-it-in-dark-mode.png", "dark-dashboard", "dark", 690, 1010, None),
]
RAW_SIZE = (1206, 2622)


def header_colors(background: str) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    if background == "teal":
        return style.WHITE, style.MINT
    if background == "dark":
        return style.WHITE, style.CORAL_LIGHT
    return style.INK, style.CORAL


def card_boxes(source: Path) -> list[tuple[int, int, int, int]]:
    """Find the deficit and macro cards from the capture: they differ per language."""
    with Image.open(source) as image:
        rgb = image.convert("RGB")
    runs, start = [], None
    for y in range(1100, rgb.height):
        inside = rgb.getpixel((100, y)) != (255, 255, 255)
        if inside and start is None:
            start = y
        if not inside and start is not None:
            if y - start > 150:
                runs.append((72, start, 1134, y))
            start = None
    if len(runs) < 2:
        raise RuntimeError(f"{source}: expected two cards, found {runs}")
    return runs[:2]


def to_canvas(box: tuple[int, int, int, int], width: int, x: int, top: int) -> tuple[float, float, float, float]:
    scale = width / RAW_SIZE[0]
    return (box[0] * scale + x + 22, box[1] * scale + top + 22, box[2] * scale + x + 22, box[3] * scale + top + 22)


def intake_canvas(raw: Path, header: Image.Image) -> Image.Image:
    width, top, x = 885, 640, 198
    source = raw / "calorie-intake.png"
    boxes = [to_canvas(b, width, x, top) for b in card_boxes(source)]
    colors = [style.TEAL, style.CORAL]
    radius = round(width * 0.045)
    canvas = style.photo_canvas(STYLE_ROOT / "macro-still-life.png")
    canvas.alpha_composite(header)
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    for (x0, y0, x1, y1), color in zip(boxes, colors):
        draw.rounded_rectangle((x0 - 150, y0 - 60, x1 + 150, y1 + 60), radius=radius + 60, fill=(*color, 205))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(70)))
    phone, position = style.phone_layer(source, width, top, x)
    style.alpha_paste(canvas, phone, position)
    stroke = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(stroke)
    for (x0, y0, x1, y1), color in zip(boxes, colors):
        draw.rounded_rectangle((x0 - 8, y0 - 8, x1 + 8, y1 + 8), radius=radius + 8, outline=(*color, 245), width=8)
    canvas.alpha_composite(stroke)
    return canvas


def wrist_canvas(raw: Path, header: Image.Image) -> Image.Image:
    """Watch app above and its calorie breakdown below, both captured in the language."""
    canvas = style.base_canvas("cream")
    canvas.alpha_composite(header)
    photo = style.crop_photo(STYLE_ROOT / "watch-context.jpg", (640, 1420), centering=(0.46, 0.48))
    style.alpha_paste(canvas, photo, (-110, 1030))
    style.alpha_paste(canvas, style.watch_layer(raw / "watch-today.png", 455, style.CORAL_LIGHT), (606, 700))
    style.alpha_paste(canvas, style.watch_layer(raw / "watch-breakdown.png", 455, style.TEAL), (700, 1690))
    return canvas


def compose(locale: str, raw_root: Path, headline: Path, out_root: Path, copy: dict) -> list[dict]:
    raw = raw_root / locale
    out = out_root / locale
    out.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory() as tmp:
        jobs = []
        for key, _, _, background, *_ in FRAMES:
            color, accent = header_colors(background)
            jobs.append({"first": copy[key]["first"], "second": copy[key]["second"], "locale": locale,
                         "color": list(color), "accent": list(accent), "out": f"{tmp}/{key}.png"})
        result = json.loads(subprocess.run([str(headline)], input=json.dumps(jobs), text=True,
                                           capture_output=True, check=True).stdout)
        for (key, filename, source, background, top, width, x), measured in zip(FRAMES, result):
            if not measured["fits"]:
                raise RuntimeError(f"{locale} {key}: header {measured['width']} px wide at {measured['size']}")
            header = Image.new("RGBA", (style.WIDTH, style.HEIGHT), (0, 0, 0, 0))
            with Image.open(measured["out"]) as drawn:
                header.alpha_composite(drawn.convert("RGBA"))
            if source == "wrist":
                canvas = wrist_canvas(raw, header)
            elif source == "calorie-intake":
                canvas = intake_canvas(raw, header)
            else:
                canvas = style.photo_canvas(STYLE_ROOT / "macro-still-life.png") if background == "photo" else style.base_canvas(background)
                canvas.alpha_composite(header)
                phone, position = style.phone_layer(raw / f"{source}.png", width, top, x)
                style.alpha_paste(canvas, phone, position)
            path = out / filename
            canvas.convert("RGB").save(path, format="PNG", optimize=True)
            records.append({"file": filename, "first": copy[key]["first"], "second": copy[key]["second"],
                            "size": measured["size"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    return records


def main() -> None:
    raw_root, headline, out_root = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    copy = json.loads((BASE / "copy/headers.json").read_text())
    locales = [l for l in copy if not l.startswith("_")] if sys.argv[4] == "all" else sys.argv[4].split(",")
    provenance = {}
    for locale in locales:
        provenance[locale] = compose(locale, raw_root, headline, out_root, copy[locale])
        print(locale, "sizes", [r["size"] for r in provenance[locale]], flush=True)
    if sys.argv[4] == "all":
        (BASE / "provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
