#!/usr/bin/env python3
"""Compose the Total Calories App Store review set from literal app captures."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


WIDTH = 1284
HEIGHT = 2778
ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
FINAL = ROOT / "final"
QA = ROOT / "qa"

CREAM = (251, 247, 241)
WHITE = (255, 255, 255)
INK = (24, 20, 16)
CORAL = (202, 75, 55)
CORAL_LIGHT = (255, 138, 101)
TEAL = (25, 132, 101)
TEAL_DARK = (20, 76, 61)
MINT = (124, 217, 181)
BROWN = (26, 20, 16)


def font_path(italic: bool) -> str:
    return "/System/Library/Fonts/SFNSItalic.ttf" if italic else "/System/Library/Fonts/SFNSRounded.ttf"


def load_font(size: int, italic: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(font_path(italic), size)


def load_rgb(path: Path) -> Image.Image:
    with Image.open(path) as source:
        return source.convert("RGB")


def fit_image(path: Path, size: tuple[int, int], centering: tuple[float, float] = (0.5, 0.5)) -> Image.Image:
    return ImageOps.fit(load_rgb(path), size, method=Image.Resampling.LANCZOS, centering=centering)


def alpha_paste(canvas: Image.Image, layer: Image.Image, xy: tuple[int, int]) -> None:
    canvas.alpha_composite(layer, dest=xy)


def draw_glow(canvas: Image.Image, box: tuple[int, int, int, int], color: tuple[int, int, int], alpha: int) -> None:
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse(box, fill=(*color, alpha))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(100)))


def headline_font_size(first: str, second: str) -> int:
    for size in range(202, 135, -2):
        first_box = load_font(size).getbbox(first)
        second_box = load_font(size, italic=True).getbbox(second)
        if max(first_box[2] - first_box[0], second_box[2] - second_box[0]) <= 1110:
            return size
    return 136


def draw_headline(
    canvas: Image.Image,
    first: str,
    second: str,
    top: int = 145,
    color: tuple[int, int, int] = INK,
    accent: tuple[int, int, int] = CORAL,
) -> None:
    size = headline_font_size(first, second)
    first_font = load_font(size)
    second_font = load_font(size, italic=True)
    draw = ImageDraw.Draw(canvas)

    first_box = draw.textbbox((0, 0), first, font=first_font, stroke_width=2)
    second_box = draw.textbbox((0, 0), second, font=second_font, stroke_width=2)
    first_x = (WIDTH - (first_box[2] - first_box[0])) // 2 - first_box[0]
    second_x = (WIDTH - (second_box[2] - second_box[0])) // 2 - second_box[0]
    draw.text((first_x, top), first, font=first_font, fill=color, stroke_width=2, stroke_fill=color)
    draw.text(
        (second_x, top + size - 8),
        second,
        font=second_font,
        fill=accent,
        stroke_width=2,
        stroke_fill=accent,
    )


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def phone_layer(source_path: Path, width: int, top: int, x: int | None = None) -> tuple[Image.Image, tuple[int, int]]:
    source = load_rgb(source_path)
    screen_height = round(width * source.height / source.width)
    bezel = 22
    outer_size = (width + bezel * 2, screen_height + bezel * 2)
    screen = source.resize((width, screen_height), Image.Resampling.LANCZOS)

    layer = Image.new("RGBA", outer_size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", outer_size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (bezel, bezel, outer_size[0] - bezel, outer_size[1] - bezel),
        radius=round(width * 0.12),
        fill=(0, 0, 0, 205),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    layer.alpha_composite(shadow, dest=(0, 32))
    ImageDraw.Draw(layer).rounded_rectangle(
        (0, 0, outer_size[0] - 1, outer_size[1] - 1),
        radius=round(width * 0.13),
        fill=(8, 8, 8, 255),
        outline=(52, 52, 52, 255),
        width=3,
    )
    screen_layer = Image.new("RGBA", (width, screen_height), (0, 0, 0, 0))
    screen_layer.paste(screen, (0, 0), rounded_mask((width, screen_height), round(width * 0.105)))
    layer.alpha_composite(screen_layer, dest=(bezel, bezel))
    return layer, (x if x is not None else (WIDTH - outer_size[0]) // 2, top)


def crop_photo(path: Path, size: tuple[int, int], centering: tuple[float, float] = (0.5, 0.5)) -> Image.Image:
    image = fit_image(path, size, centering)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(image, (0, 0), rounded_mask(size, min(size) // 12))
    return layer


def watch_layer(source_path: Path, width: int, band_color: tuple[int, int, int]) -> Image.Image:
    body_height = round(width * 1.17)
    band_width = round(width * 0.72)
    band_height = round(body_height * 0.72)
    body_top = round(band_height * 0.58)
    total_height = body_top + body_height + round(band_height * 0.58)
    layer = Image.new("RGBA", (width, total_height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    draw.rounded_rectangle(
        (
            (width - band_width) // 2,
            0,
            (width + band_width) // 2,
            body_top + round(band_height * 0.24),
        ),
        radius=round(width * 0.09),
        fill=(*band_color, 255),
    )
    draw.rounded_rectangle(
        (
            (width - band_width) // 2,
            body_top + body_height - round(band_height * 0.24),
            (width + band_width) // 2,
            total_height,
        ),
        radius=round(width * 0.09),
        fill=(*band_color, 255),
    )
    for index in range(5):
        hole_y = 22 + index * 34
        draw.ellipse(
            (
                width // 2 - 6,
                hole_y,
                width // 2 + 6,
                hole_y + 12,
            ),
            fill=(30, 30, 30, 120),
        )

    draw.rounded_rectangle(
        (0, body_top, width - 1, body_top + body_height - 1),
        radius=round(width * 0.25),
        fill=(8, 8, 8, 255),
        outline=(53, 53, 53, 255),
        width=4,
    )
    source = fit_image(source_path, (width - 34, body_height - 34))
    screen = Image.new("RGBA", source.size, (0, 0, 0, 0))
    screen.paste(source, (0, 0), rounded_mask(source.size, round(width * 0.19)))
    layer.alpha_composite(screen, dest=(17, body_top + 17))
    return layer


def base_canvas(kind: str) -> Image.Image:
    if kind == "dark":
        canvas = Image.new("RGBA", (WIDTH, HEIGHT), (*BROWN, 255))
        draw_glow(canvas, (-360, -260, 1480, 850), CORAL, 105)
        draw_glow(canvas, (760, 1840, 1640, 2980), TEAL, 60)
        return canvas
    if kind == "teal":
        canvas = Image.new("RGBA", (WIDTH, HEIGHT), (*TEAL_DARK, 255))
        draw_glow(canvas, (-500, 1250, 1100, 3250), MINT, 60)
        return canvas
    if kind == "white":
        canvas = Image.new("RGBA", (WIDTH, HEIGHT), (*WHITE, 255))
        draw_glow(canvas, (680, -300, 1680, 800), CORAL, 70)
        draw_glow(canvas, (-300, 1900, 720, 3100), TEAL, 45)
        return canvas
    return Image.new("RGBA", (WIDTH, HEIGHT), (*CREAM, 255))


def photo_canvas(path: Path) -> Image.Image:
    image = fit_image(path, (WIDTH, HEIGHT), centering=(0.5, 0.72)).convert("RGBA")
    image.putalpha(215)
    canvas = Image.new("RGBA", (WIDTH, HEIGHT), (*CREAM, 255))
    canvas.alpha_composite(image)
    veil = Image.new("RGBA", (WIDTH, HEIGHT), (251, 247, 241, 95))
    canvas.alpha_composite(veil)
    return canvas


def source_path(name: str) -> Path:
    candidate = RAW / name
    if candidate.exists() and candidate.stat().st_size > 20_000:
        return candidate
    if name == "premium.png":
        return ROOT.parents[2] / "fastlane/screenshots/en-US/1_iphone_07.png"
    raise FileNotFoundError(candidate)


FRAMES = [
    {"filename": "01-total-burn.png", "first": "Know your", "second": "total burn", "source": "dashboard.png", "background": "cream", "top": 690, "width": 1010},
    {"filename": "02-active-resting.png", "first": "See what makes", "second": "your burn", "source": "premium-dashboard.png", "background": "white", "top": 690, "width": 1010},
    {"filename": "03-daily-patterns.png", "first": "Find your", "second": "daily patterns", "source": "history.png", "background": "white", "top": 690, "width": 1010},
    {"filename": "04-net-deficit.png", "first": "Burned minus", "second": "eaten", "source": "net-deficit.png", "background": "teal", "top": 920, "width": 1010},
    {"filename": "05-macros.png", "first": "See your", "second": "macros", "source": "macro-dashboard.png", "background": "photo", "top": 700, "width": 885, "x": 198},
    {"filename": "06-macro-goals.png", "first": "Set your", "second": "macro goals", "source": "macro-goals.png", "background": "cream", "top": 700, "width": 1010},
    {"filename": "07-macro-patterns.png", "first": "Spot your", "second": "macro patterns", "source": "macro-history.png", "background": "white", "top": 690, "width": 1010},
    {"filename": "08-on-your-wrist.png", "first": "Keep it on", "second": "your wrist", "source": "watch", "background": "cream", "top": 0, "width": 0},
    {"filename": "09-dark-mode.png", "first": "Read it in", "second": "dark mode", "source": "dark-dashboard.png", "background": "dark", "top": 690, "width": 1010},
    {"filename": "10-go-further.png", "first": "Go", "second": "further", "source": "premium.png", "background": "dark", "top": 720, "width": 1010},
]


def compose_frame(frame: dict[str, object]) -> Image.Image:
    background = str(frame["background"])
    if background == "photo":
        canvas = photo_canvas(ROOT / "macro-still-life.png")
    else:
        canvas = base_canvas(background)

    if background == "teal":
        headline_color, accent = WHITE, MINT
    elif background == "dark":
        headline_color, accent = WHITE, CORAL_LIGHT
    else:
        headline_color, accent = INK, CORAL
    draw_headline(canvas, str(frame["first"]), str(frame["second"]), color=headline_color, accent=accent)

    if frame["source"] == "watch":
        photo = crop_photo(ROOT / "watch-context.jpg", (700, 1500), centering=(0.46, 0.48))
        alpha_paste(canvas, photo, (-100, 920))
        watch = watch_layer(ROOT / "watch-capture.png", 500, CORAL_LIGHT)
        alpha_paste(canvas, watch, (625, 805))
        small_watch = watch_layer(ROOT / "watch-capture.png", 310, TEAL)
        alpha_paste(canvas, small_watch, (910, 1830))
        return canvas.convert("RGB")

    phone, position = phone_layer(
        source_path(str(frame["source"])),
        int(frame["width"]),
        int(frame["top"]),
        int(frame["x"]) if "x" in frame else None,
    )
    alpha_paste(canvas, phone, position)
    return canvas.convert("RGB")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_contact_sheet(paths: Iterable[Path]) -> None:
    paths = list(paths)
    thumb_width = 245
    thumb_height = round(thumb_width * HEIGHT / WIDTH)
    gap = 34
    label_height = 54
    sheet = Image.new("RGB", (thumb_width * 2 + gap * 3, (thumb_height + label_height) * 5 + gap * 6), (235, 231, 224))
    draw = ImageDraw.Draw(sheet)
    label_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 24)
    for index, path in enumerate(paths):
        row, column = divmod(index, 2)
        x = gap + column * (thumb_width + gap)
        y = gap + row * (thumb_height + label_height + gap)
        with Image.open(path) as image:
            thumbnail = image.convert("RGB").resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        sheet.paste(thumbnail, (x, y))
        draw.text((x, y + thumb_height + 12), f"{index + 1:02d}  {path.stem}", fill=INK, font=label_font)
    sheet.save(QA / "contact-sheet.png", format="PNG")


def write_metadata(paths: list[Path]) -> None:
    raw_records = {}
    for path in sorted(RAW.glob("*.png")):
        raw_records[path.name] = {"size_bytes": path.stat().st_size, "sha256": sha256(path)}
    metadata = {
        "canvas": [WIDTH, HEIGHT],
        "color_mode": "RGB",
        "reference_zip": "/Users/jackwallner/Downloads/Total Calories.zip",
        "style_source": "screenshots-app/panels.jsx",
        "phone_source": "screenshots-app/phone-screens.jsx",
        "generated_asset": "macro-still-life.png",
        "watch_source": {
            "filename": "watch-capture.png",
            "sha256": sha256(ROOT / "watch-capture.png"),
        },
        "frames": [
            {
                "filename": frame["filename"],
                "headline": f"{frame['first']} {frame['second']}",
                "literal_source": frame["source"],
                "sha256": sha256(FINAL / str(frame["filename"])),
            }
            for frame in FRAMES
        ],
        "raw_sources": raw_records,
    }
    (QA / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")


def main() -> None:
    FINAL.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    paths = []
    for frame in FRAMES:
        output = FINAL / str(frame["filename"])
        compose_frame(frame).save(output, format="PNG", optimize=True)
        paths.append(output)
    write_contact_sheet(paths)
    write_metadata(paths)
    print(json.dumps({"frames": [str(path) for path in paths], "contact_sheet": str(QA / "contact-sheet.png")}, indent=2))


if __name__ == "__main__":
    main()
