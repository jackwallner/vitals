#!/usr/bin/env python3
"""Rebuild ASC frames 2 and 3 for Total Calories.

Frame 2 ("Keep it on your wrist") now carries two pieces of Watch evidence: the
Watch app itself and the real watch face with the calorie and step
complications, because "it lives on your wrist" is a bigger promise than "there
is a Watch app".

Frame 3 ("See your calorie intake") keeps the same literal capture but lifts the
Net Deficit and Macros cards out of the screen with a tinted glow and stroke, so
the two things the frame is actually selling are the two things the eye lands
on at search-grid size.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent
LEGACY = ROOT.parent / "total-calories-refresh-20260820" / "compose_total_calories_asc.py"
spec = importlib.util.spec_from_file_location("total_calories_asc_style", LEGACY)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Could not load ASC style compositor: {LEGACY}")
style = importlib.util.module_from_spec(spec)
spec.loader.exec_module(style)

style.ROOT = ROOT.parent / "total-calories-refresh-20260820"
style.RAW = ROOT / "raw"
style.FINAL = ROOT / "final"
style.QA = ROOT / "qa"

WIDTH, HEIGHT = style.WIDTH, style.HEIGHT

# Frame 3 geometry. The literal capture is 1206 x 2622 and is pasted by
# style.phone_layer at `width` with a 22 px bezel, so screen-space coordinates
# convert to canvas coordinates with one scale and one offset.
INTAKE = {"width": 885, "top": 640, "x": 198}
RAW_SIZE = (1206, 2622)
# Card bounds measured off the raw capture (white background, cardSurface fill).
CARDS = {
    "deficit": {"box": (72, 1390, 1134, 1750), "color": style.TEAL},
    "macros": {"box": (72, 1806, 1134, 2194), "color": style.CORAL},
}


def to_canvas(box: tuple[int, int, int, int]) -> tuple[float, float, float, float]:
    scale = INTAKE["width"] / RAW_SIZE[0]
    off_x = INTAKE["x"] + 22
    off_y = INTAKE["top"] + 22
    x0, y0, x1, y1 = box
    return (x0 * scale + off_x, y0 * scale + off_y, x1 * scale + off_x, y1 * scale + off_y)


def highlight_glow(canvas: Image.Image) -> None:
    """Tinted halo behind the phone, so the two cards radiate past the bezel.

    Drawn before the device is pasted: nothing may tint the literal capture, or
    the frame stops being evidence of what the app looks like.
    """
    boxes = {name: to_canvas(card["box"]) for name, card in CARDS.items()}
    radius = round(INTAKE["width"] * 0.045)
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    for name, card in CARDS.items():
        x0, y0, x1, y1 = boxes[name]
        # Wide enough to clear the device on both sides, so the halo is visible
        # beside the phone instead of hiding under it.
        gdraw.rounded_rectangle(
            (x0 - 150, y0 - 60, x1 + 150, y1 + 60),
            radius=radius + 60,
            fill=(*card["color"], 205),
        )
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(70)))


def highlight_overlay(canvas: Image.Image, scrim: int) -> None:
    """Optional scrim over the rest of the screen, then the stroke on each card."""
    boxes = {name: to_canvas(card["box"]) for name, card in CARDS.items()}
    radius = round(INTAKE["width"] * 0.045)

    if scrim:
        # Darken the rest of the screen so the two cards read as the lit part of
        # it. The cards themselves are cut out of the veil and stay untouched.
        screen = to_canvas((0, 0, RAW_SIZE[0], RAW_SIZE[1]))
        veil = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        vdraw = ImageDraw.Draw(veil)
        vdraw.rounded_rectangle(screen, radius=round(INTAKE["width"] * 0.105), fill=(18, 15, 12, scrim))
        for name in CARDS:
            x0, y0, x1, y1 = boxes[name]
            vdraw.rounded_rectangle((x0 - 10, y0 - 10, x1 + 10, y1 + 10), radius=radius + 10, fill=(0, 0, 0, 0))
        canvas.alpha_composite(veil)

    stroke = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(stroke)
    for name, card in CARDS.items():
        x0, y0, x1, y1 = boxes[name]
        sdraw.rounded_rectangle(
            (x0 - 8, y0 - 8, x1 + 8, y1 + 8),
            radius=radius + 8,
            outline=(*card["color"], 245),
            width=8,
        )
    canvas.alpha_composite(stroke)


def compose_intake(scrim: int) -> Image.Image:
    canvas = style.photo_canvas(style.ROOT / "macro-still-life.png")
    style.draw_headline(canvas, "See your", "calorie intake")
    highlight_glow(canvas)
    phone, position = style.phone_layer(
        style.RAW / "calorie-intake.png", INTAKE["width"], INTAKE["top"], INTAKE["x"]
    )
    style.alpha_paste(canvas, phone, position)
    highlight_overlay(canvas, scrim)
    return canvas.convert("RGB")


def compose_wrist() -> Image.Image:
    """Watch app above, real watch face with complications below."""
    canvas = style.base_canvas("cream")
    style.draw_headline(canvas, "Keep it on", "your wrist")

    photo = style.crop_photo(style.ROOT / "watch-context.jpg", (640, 1420), centering=(0.46, 0.48))
    style.alpha_paste(canvas, photo, (-110, 1030))

    # Both watches at the same size: the app screen and the face carrying its
    # complications are two halves of one claim, not a hero and a footnote.
    app_watch = style.watch_layer(style.RAW / "watch-app.png", 455, style.CORAL_LIGHT)
    style.alpha_paste(canvas, app_watch, (606, 700))

    face_watch = style.watch_layer(style.RAW / "watch-face-complications.png", 455, style.TEAL)
    style.alpha_paste(canvas, face_watch, (700, 1690))
    return canvas.convert("RGB")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    style.FINAL.mkdir(parents=True, exist_ok=True)
    style.QA.mkdir(parents=True, exist_ok=True)
    outputs = {}

    wrist = style.FINAL / "02-on-your-wrist.png"
    compose_wrist().save(wrist, format="PNG", optimize=True)
    outputs["02-on-your-wrist.png"] = sha256(wrist)

    for label, scrim in (("halo", 0), ("halo-scrim", 30)):
        path = style.FINAL / f"03-calorie-intake-{label}.png"
        compose_intake(scrim).save(path, format="PNG", optimize=True)
        outputs[path.name] = sha256(path)

    (style.QA / "provenance.json").write_text(
        json.dumps(
            {
                "canvas": [WIDTH, HEIGHT],
                "color_mode": "RGB",
                "style_source": str(LEGACY),
                "frames": {
                    "02-on-your-wrist.png": {
                        "headline": "Keep it on your wrist",
                        "literal_sources": ["raw/watch-app.png", "raw/watch-face-complications.png"],
                        "proof": "Watch app screen plus the real watch face carrying the calorie and step complications.",
                    },
                    "03-calorie-intake": {
                        "headline": "See your calorie intake",
                        "literal_sources": ["raw/calorie-intake.png"],
                        "treatment": "Net Deficit and Macros cards lifted with a tinted glow and stroke; no pixels of the capture altered inside the cards.",
                    },
                },
                "raw_sha256": {p.name: sha256(p) for p in sorted(style.RAW.glob("*.png"))},
                "final_sha256": outputs,
            },
            indent=2,
        )
        + "\n"
    )
    print(json.dumps(outputs, indent=2))


if __name__ == "__main__":
    main()
