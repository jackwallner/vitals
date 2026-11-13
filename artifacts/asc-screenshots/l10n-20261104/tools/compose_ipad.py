#!/usr/bin/env python3
"""Compose the Total Calories 13-inch iPad set (2064x2752) for ASC locales.

Same headers (copy/headers.json frames 02, 04, 06, 07, 08), colours and backgrounds as the
iPhone set; the capture sits in an iPad outline under the header.

usage: compose_ipad.py <raw-root> <headline-binary> <out-root> <locale|all>
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
spec = importlib.util.spec_from_file_location("style", BASE.parent / "total-calories-refresh-20260820" / "compose_total_calories_asc.py")
style = importlib.util.module_from_spec(spec)
spec.loader.exec_module(style)

W, H = 2064, 2752
SCALE = 1.25  # the header tool draws on a 1284 px canvas
# (header key, output file, raw capture, background)
FRAMES = [
    ("02", "01_know-your-total-burn.png", "dashboard", "cream"),
    ("04", "02_see-what-makes-your-burn.png", "premium-dashboard", "white"),
    ("06", "03_burned-minus-eaten.png", "net-deficit", "teal"),
    ("07", "04_set-your-macro-goals.png", "macro-goals", "cream"),
    ("08", "05_spot-your-macro-patterns.png", "macro-history", "white"),
]
SCREEN_TOP, BOTTOM_MARGIN, BEZEL = 760, 70, 26
# The live English set's headers (the iPhone set's headers.json starts at the translations).
EN_US = {
    "02": {"first": "Know your", "second": "total burn"},
    "04": {"first": "See what makes", "second": "your burn"},
    "06": {"first": "Burned minus", "second": "eaten"},
    "07": {"first": "Set your", "second": "macro goals"},
    "08": {"first": "Spot your", "second": "macro patterns"},
}


def canvas(kind: str) -> Image.Image:
    img = Image.new("RGBA", (W, H), (*{"teal": style.TEAL_DARK, "white": style.WHITE}.get(kind, style.CREAM), 255))
    if kind == "teal":
        style.draw_glow(img, (-700, 1500, 1500, 3400), style.MINT, 60)
    elif kind == "white":
        style.draw_glow(img, (1200, -400, 2500, 900), style.CORAL, 70)
        style.draw_glow(img, (-500, 2000, 900, 3300), style.TEAL, 45)
    return img


def header_colors(kind: str):
    return (style.WHITE, style.MINT) if kind == "teal" else (style.INK, style.CORAL)


def ipad_layer(source: Path) -> tuple[Image.Image, tuple[int, int]]:
    shot = style.load_rgb(source)
    height = H - SCREEN_TOP - BOTTOM_MARGIN - 2 * BEZEL
    width = round(height * shot.width / shot.height)
    outer = (width + 2 * BEZEL, height + 2 * BEZEL)
    pad = 90  # room for the blurred shadow, so it is never cut at the layer edge
    layer = Image.new("RGBA", (outer[0] + 2 * pad, outer[1] + 2 * pad), (0, 0, 0, 0))
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((pad, pad, pad + outer[0], pad + outer[1]),
                                             radius=round(width * 0.05), fill=(0, 0, 0, 200))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)), dest=(0, 24))
    ImageDraw.Draw(layer).rounded_rectangle((pad, pad, pad + outer[0] - 1, pad + outer[1] - 1), radius=round(width * 0.055),
                                            fill=(8, 8, 8, 255), outline=(52, 52, 52, 255), width=3)
    screen = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    screen.paste(shot.resize((width, height), Image.Resampling.LANCZOS), (0, 0), style.rounded_mask((width, height), round(width * 0.04)))
    layer.alpha_composite(screen, dest=(pad + BEZEL, pad + BEZEL))
    return layer, ((W - layer.width) // 2, SCREEN_TOP - BEZEL - pad)


def compose(locale: str, raw_root: Path, headline: Path, out_root: Path, copy: dict) -> list[dict]:
    out = out_root / locale
    out.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory() as tmp:
        jobs = []
        for key, _, _, kind in FRAMES:
            color, accent = header_colors(kind)
            jobs.append({"first": copy[key]["first"], "second": copy[key]["second"], "locale": locale,
                         "color": list(color), "accent": list(accent), "out": f"{tmp}/{key}.png"})
        result = json.loads(subprocess.run([str(headline)], input=json.dumps(jobs), text=True,
                                           capture_output=True, check=True).stdout)
        for (key, filename, source, kind), measured in zip(FRAMES, result):
            if not measured["fits"]:
                raise RuntimeError(f"{locale} {key}: header {measured['width']} px wide at {measured['size']}")
            with Image.open(measured["out"]) as drawn:
                header = drawn.convert("RGBA")
            header = header.resize((round(header.width * SCALE), round(header.height * SCALE)), Image.Resampling.LANCZOS)
            img = canvas(kind)
            img.alpha_composite(header, dest=((W - header.width) // 2, 0))
            layer, pos = ipad_layer(raw_root / locale / f"{source}.png")
            style.alpha_paste(img, layer, pos)
            path = out / filename
            img.convert("RGB").save(path, format="PNG", optimize=True)
            records.append({"file": filename, "first": copy[key]["first"], "second": copy[key]["second"],
                            "size": round(measured["size"] * SCALE), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    return records


def main() -> None:
    raw_root, headline, out_root = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    copy = json.loads((BASE / "copy/headers.json").read_text())
    copy["en-US"] = EN_US
    locales = [l for l in copy if not l.startswith("_")] if sys.argv[4] == "all" else sys.argv[4].split(",")
    provenance = {}
    for locale in locales:
        provenance[locale] = compose(locale, raw_root, headline, out_root, copy[locale])
        print(locale, [r["size"] for r in provenance[locale]], flush=True)
    (out_root / "provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
