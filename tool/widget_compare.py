#!/usr/bin/env python3
"""Pairs each drawing of the home-screen widget with its design render, side by side.

    tool/widget_compare.py

Reads build/widgets/android/<state>-<theme>.png (the widget as Android drew it, 2×; written by
tool/widget_check.sh) and ../design/redesign/widgets/<state>-<theme>.png (the design, 2×, on a
20 dp stage), and writes build/widgets/<state>-<theme>.png: the design on the left, Android on
the right. Needs Pillow.
"""
import sys
from pathlib import Path

from PIL import Image

app = Path(__file__).resolve().parent.parent
ours = app / "build" / "widgets" / "android"
design = next((r / "design" / "redesign" / "widgets" for r in (app.parent, app.parent / "shatibiyyah-data")
               if (r / "design" / "redesign" / "widgets").is_dir()), None)
if design is None:
    sys.exit("the workspace (design/redesign/widgets/) is not around the app")
STAGE = 40  # the design render's margin, in its pixels
GROUND = {"paper": (239, 236, 230, 255), "night": (13, 16, 21, 255)}  # the stage's colour: bg in each theme
done = 0
for path in sorted(ours.glob("*.png")):
    theme = path.stem.rsplit("-", 1)[-1]
    render = design / path.name
    if not render.exists():
        print(f"no design render: {path.stem}")  # a size or a font scale the design does not draw
        continue
    a = Image.open(path).convert("RGBA")
    d = Image.open(render).convert("RGBA")
    d = d.crop((STAGE, STAGE, d.width - STAGE, d.height - STAGE))
    sheet = Image.new("RGBA", (d.width + a.width + 60, max(d.height, a.height) + 40), GROUND[theme])
    sheet.alpha_composite(d, (20, 20))
    sheet.alpha_composite(a, (d.width + 40, 20))
    sheet.convert("RGB").save(app / "build" / "widgets" / path.name)
    done += 1
print(f"{done} pairs in build/widgets/")
