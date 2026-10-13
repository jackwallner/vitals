#!/usr/bin/env python3
"""Edit real screen recordings into a captioned iPhone App Preview.

Requires ffmpeg, ffprobe, and Pillow. Shot times refer to the source recording.
Text overlays explain the footage; the app itself is never reconstructed.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH = 886
HEIGHT = 1920
FPS = 30
FONT_DIR = Path("/System/Library/Fonts/Supplemental")


def run(args: list[str]) -> None:
    subprocess.run(args, check=True)


def caption(shot: dict, destination: Path) -> None:
    """Keep captions in the app's title area, above its figures and charts."""
    panel = Image.new("RGBA", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(panel)
    draw.rectangle((0, 0, WIDTH, shot.get("header_height", 280)), fill="white")
    bold = FONT_DIR / "Arial Bold.ttf"
    regular = FONT_DIR / "Arial.ttf"
    draw.text((52, 42), "TOTAL CALORIES", font=ImageFont.truetype(bold, 26), fill="#64646B")
    size = 56
    while draw.textlength(shot["headline"], font=ImageFont.truetype(bold, size)) > WIDTH - 104:
        size -= 1
        if size < 44:
            raise ValueError("Caption is too long to read at App Store size")
    draw.text((48, 101), shot["headline"], font=ImageFont.truetype(bold, size), fill="#15151A")
    font = ImageFont.truetype(regular, 34)
    if draw.textlength(shot["detail"], font=font) > WIDTH - 104:
        raise ValueError("Caption detail is too long")
    draw.text((52, 184), shot["detail"], font=font, fill="#53535B")
    panel.save(destination)


def render_shot(shot: dict, directory: Path, index: int) -> Path:
    source = Path(shot["source"]).expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(source)
    duration = shot["end"] - shot["start"]
    overlay = directory / f"caption-{index}.png"
    output = directory / f"shot-{index}.mp4"
    caption(shot, overlay)
    caption_filter = "[1:v]format=rgba"
    if fade := shot.get("caption_fade_out"):
        caption_filter += f",fade=t=out:st=0:d={fade}:alpha=1"
    caption_filter += "[caption];"
    run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-ss", str(shot["start"]), "-t", str(duration), "-i", str(source),
        "-loop", "1", "-framerate", str(FPS), "-i", str(overlay),
        "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
        "-filter_complex",
        caption_filter + f"[0:v]fps={FPS},scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=decrease:"
        f"force_divisible_by=2,pad={WIDTH}:{HEIGHT}:(ow-iw)/2:(oh-ih)/2:white,"
        "setsar=1,format=yuv420p[screen];"
        "[screen][caption]overlay=0:0:shortest=1,format=yuv420p[video]",
        "-map", "[video]", "-map", "2:a", "-t", str(duration),
        "-c:v", "libx264", "-preset", "slow", "-crf", "18",
        "-profile:v", "high", "-level:v", "4.0",
        "-maxrate", "12M", "-bufsize", "24M",
        "-c:a", "aac", "-profile:a", "aac_low", "-b:a", "256k",
        "-ar", "48000", "-ac", "2", "-movflags", "+faststart", str(output),
    ])
    return output


def verify(output: Path, expected_duration: float) -> dict:
    data = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(output),
    ]))
    video = next(s for s in data["streams"] if s["codec_type"] == "video")
    audio = next(s for s in data["streams"] if s["codec_type"] == "audio")
    duration = float(data["format"]["duration"])
    assert (video["width"], video["height"]) == (WIDTH, HEIGHT)
    assert video["codec_name"] == "h264" and video["pix_fmt"] == "yuv420p"
    assert video["r_frame_rate"] == "30/1"
    assert video["avg_frame_rate"] == "30/1"
    assert int(video["nb_frames"]) == round(expected_duration * FPS)
    assert audio["codec_name"] == "aac" and audio["channels"] == 2
    assert audio["sample_rate"] == "48000"
    assert 15 <= duration <= 30 and abs(duration - expected_duration) < 0.1
    assert int(data["format"]["size"]) <= 500_000_000
    return {
        "duration": duration, "width": WIDTH, "height": HEIGHT, "fps": FPS,
        "video": "H.264 High / yuv420p", "audio": "AAC LC / stereo / 48 kHz / silent",
        "bytes": int(data["format"]["size"]),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    shots = json.loads(args.manifest.read_text())["shots"]
    duration = sum(s["end"] - s["start"] for s in shots)
    if not 15 <= duration <= 30 or any(s["end"] <= s["start"] for s in shots):
        raise ValueError("Use positive shot durations totaling 15 to 30 seconds")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vitals-preview-") as temporary:
        directory = Path(temporary)
        parts = []
        for index, shot in enumerate(shots):
            print(f"Rendering {index + 1}/{len(shots)}: {shot['headline']}", flush=True)
            parts.append(render_shot(shot, directory, index))
        concat = directory / "concat.txt"
        concat.write_text("".join(f"file '{part}'\n" for part in parts))
        run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "concat", "-safe", "0", "-i", str(concat),
            "-vf", "setpts=PTS-STARTPTS,fps=30", "-af", "asetpts=PTS-STARTPTS,apad",
            "-t", str(duration), "-c:v", "libx264", "-preset", "slow", "-crf", "18",
            "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "256k",
            "-movflags", "+faststart", str(args.output),
        ])
    result = verify(args.output, duration)
    print(json.dumps(result, indent=2))
    args.output.with_suffix(".verification.json").write_text(json.dumps(result, indent=2) + "\n")
    run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", "1.5",
        "-i", str(args.output), "-frames:v", "1", "-q:v", "2",
        str(args.output.with_suffix(".poster.jpg")),
    ])


if __name__ == "__main__":
    main()
