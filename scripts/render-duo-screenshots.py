#!/usr/bin/env python3
"""Render the iPhone Duo App Store set (1398x2034) from raw Duo captures.

Unfolded frames show the real inner-display capture (2853x2007) in a landscape
device outline; the folded frame shows the outer capture (1398x2034) in a
portrait one. Colors and type match the live iPhone set.

    scripts/render-duo-screenshots.py <capture-dir> <out-dir>
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1398, 2034
TOP, BOTTOM = (0xF5, 0xF6, 0xEE), (0xD8, 0xE3, 0xCB)
INK = (0x20, 0x2B, 0x24)
FONT = "/System/Library/Fonts/SFNSRounded.ttf"

# (output name, source capture, header, folded)
FRAMES = [
    ("01-burn-and-trend.png", "launch-inner.png", "Today's burn beside your 30-day trend", False),
    ("02-deficit-all-month.png", "calorieIntake-inner.png", "Burned, eaten and your deficit all month", False),
    ("03-vitals-plus-tools.png", "premiumActive-inner.png", "Every Vitals+ tool beside your history", False),
    ("04-body-profile.png", "bodyProfile-inner.png", "Your BMI beside your trends", False),
    ("05-folded-glance.png", "launch-outer.png", "Fold it shut for a quick glance", True),
]


def background() -> Image.Image:
    img = Image.new("RGB", (W, H))
    px = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        px.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img


def header_font(size: int) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(FONT, size)
    font.set_variation_by_name("Medium")
    return font


def wrap(text: str, font: ImageFont.FreeTypeFont, width: int) -> list[str] | None:
    """One line if it fits, else the two-line break with the most even lengths;
    None when no two-line break fits at this size."""
    if font.getlength(text) <= width:
        return [text]
    words = text.split()
    splits = [(" ".join(words[:i]), " ".join(words[i:])) for i in range(1, len(words))]
    fitting = [pair for pair in splits if max(map(font.getlength, pair)) <= width]
    if not fitting:
        return None
    return list(min(fitting, key=lambda pair: max(map(font.getlength, pair))))


def draw_header(img: Image.Image, text: str) -> int:
    """Draws a centred header of at most two lines; returns its bottom edge."""
    draw = ImageDraw.Draw(img)
    size = 112
    while True:
        font = header_font(size)
        lines = wrap(text, font, W - 2 * 90)
        if lines or size <= 80:
            break
        size -= 4
    assert lines, f"header does not fit in two lines: {text}"
    line_h = round(size * 1.12)
    y = 150
    for line in lines:
        draw.text(((W - font.getlength(line)) / 2, y), line, font=font, fill=INK)
        y += line_h
    return y


def device(screen: Image.Image, width: int, radius: int, bezel: int) -> Image.Image:
    """Screen inside a black rounded outline, with a soft drop shadow."""
    scale = (width - 2 * bezel) / screen.width
    shot = screen.resize((width - 2 * bezel, round(screen.height * scale)), Image.LANCZOS)
    w, h = width, shot.height + 2 * bezel
    pad = 80
    out = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    shadow = Image.new("L", out.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle([pad, pad + 24, pad + w, pad + h + 24], radius, fill=90)
    out.putalpha(shadow.filter(ImageFilter.GaussianBlur(36)))
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([0, 0, w - 1, h - 1], radius, fill=(18, 18, 20, 255))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius - bezel, fill=255)
    body.paste(shot, (bezel, bezel), mask)
    out.alpha_composite(body, (pad, pad))
    return out


def render(src: Path, header: str, folded: bool) -> Image.Image:
    img = background()
    top = draw_header(img, header) + 70
    screen = Image.open(src).convert("RGB")
    if folded:
        avail_h = H - top - 110
        width = round(avail_h * screen.width / screen.height)
        art = device(screen, width, radius=96, bezel=22)
    else:
        art = device(screen, W - 2 * 22, radius=64, bezel=18)
    pad = 80
    x = (W - art.width) // 2
    y = top - pad if folded else top + (H - top - (art.height - 2 * pad)) // 2 - pad - 60
    canvas = img.convert("RGBA")
    canvas.alpha_composite(art, (x, y))
    return canvas.convert("RGB")


def main() -> None:
    src_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, src, header, folded in FRAMES:
        frame = render(src_dir / src, header, folded)
        assert frame.size == (W, H)
        frame.save(out_dir / name)
        print(out_dir / name)


if __name__ == "__main__":
    main()
