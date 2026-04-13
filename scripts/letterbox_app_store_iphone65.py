#!/usr/bin/env python3
"""
Scale and letterbox PNGs to App Store Connect "iPhone 6.5\" Display" sizes.

Accepted dimensions (portrait or landscape):
  1242×2688, 2688×1242, 1284×2778, 2778×1284

Default output: 1284×2778 (portrait), white letterboxing, centered.

Requires: pip3 install Pillow

Usage:
  python3 scripts/letterbox_app_store_iphone65.py ~/Desktop/my-screenshots/*.png
  python3 scripts/letterbox_app_store_iphone65.py --out ./asc-65 ./raw/*.png

Re-capture from Xcode Simulator (e.g. iPhone 16 Pro Max) at 100% scale for best quality;
this script fixes aspect/size only — upscaling tiny thumbnails will look soft.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError as e:
    print("Install Pillow: pip3 install Pillow", file=sys.stderr)
    raise SystemExit(1) from e

# App Store Connect — iPhone 6.5" (see Media Manager error text)
PORTRAIT = (1284, 2778)
LANDSCAPE = (2778, 1284)


def letterbox(im: Image.Image, target_w: int, target_h: int, fill: tuple[int, int, int]) -> Image.Image:
    """Scale uniformly to fit inside target; center on canvas."""
    tw, th = target_w, target_h
    w, h = im.size
    scale = min(tw / w, th / h)
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    resized = im.resize((nw, nh), Image.Resampling.LANCZOS)
    if resized.mode not in ("RGB", "RGBA"):
        resized = resized.convert("RGBA")
    canvas = Image.new("RGB", (tw, th), fill)
    x = (tw - nw) // 2
    y = (th - nh) // 2
    if resized.mode == "RGBA":
        canvas.paste(resized, (x, y), resized)
    else:
        canvas.paste(resized, (x, y))
    return canvas


def main() -> None:
    p = argparse.ArgumentParser(description="Letterbox PNGs to iPhone 6.5\" App Store size")
    p.add_argument("images", nargs="+", help="Input PNG files")
    p.add_argument(
        "--out",
        type=Path,
        default=Path("app_store_iphone65_out"),
        help="Output directory (created if needed)",
    )
    p.add_argument(
        "--landscape",
        action="store_true",
        help=f"Use {LANDSCAPE[0]}×{LANDSCAPE[1]} instead of portrait",
    )
    p.add_argument("--fill", default="ffffff", help="Hex background without #, default ffffff")
    args = p.parse_args()

    tw, th = LANDSCAPE if args.landscape else PORTRAIT
    fr = int(args.fill[0:2], 16)
    fg = int(args.fill[2:4], 16)
    fb = int(args.fill[4:6], 16)
    fill = (fr, fg, fb)

    args.out.mkdir(parents=True, exist_ok=True)
    for i, path in enumerate(sorted(Path(x) for x in args.images)):
        path = path.expanduser()
        if not path.is_file():
            print(f"Skip (not a file): {path}", file=sys.stderr)
            continue
        im = Image.open(path).convert("RGBA")
        out = letterbox(im, tw, th, fill)
        stem = path.stem[:80]
        dest = args.out / f"{i+1:02d}_{stem}_{tw}x{th}.png"
        out.save(dest, "PNG", optimize=True)
        print(dest, "←", path, f"({im.size[0]}×{im.size[1]})")


if __name__ == "__main__":
    main()
