# Total Calories App Preview

16.5-second edit of genuine simulator footage, with text overlays explaining the app.
No device frames, marketing screenshot slideshow, loading gaps, or premium catalog screen.

| Time | Footage | Caption |
| --- | --- | --- |
| 0.0 to 3.5s | Daily burn, active/resting breakdown, steps | Your total daily burn |
| 3.5 to 8.2s | 90-day history, scrolling from calories to steps | See your progress over time |
| 8.2 to 14.4s | Generate and preview a populated 90-day PDF | Share your progress |
| 14.4 to 16.5s | Open the native PDF share sheet | Caption fades before the sheet enters |

The report caption says "PDF reports with Vitals+" to identify the paid feature.
The poster frame is the daily totals at 1.5 seconds.

Rebuild on Jack's Mac with ffmpeg, ffprobe, and Pillow installed:

```sh
python3 scripts/compose-app-preview.py \
  artifacts/app-previews/total-calories-20261012/edit.json \
  artifacts/app-previews/total-calories-20261012/total-calories-preview.mp4
```

`edit.json` locates the preserved raw recordings under `~/ios/app-previews/output/total-calories-screen-capture/`.
A reusable copy of the edit is saved there as `total-calories-edited-preview.mp4`.

Validation: full ffmpeg decode, 495 frames at constant 30 fps, 886 by 1920 pixels,
H.264 High, yuv420p, silent stereo AAC LC at 48 kHz, zero-based audio/video timestamps,
and independent visual inspection of captions, transitions, report, and sharing.
`total-calories-preview.verification.json` records the measured export properties.
`asc-upload.json` records the replacement asset in the existing rejected PPO treatment.
