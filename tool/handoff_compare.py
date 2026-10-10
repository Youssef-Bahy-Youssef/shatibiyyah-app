#!/usr/bin/env python3
"""Pairs each handoff golden with its design render, side by side.

    tool/handoff_compare.py [name ...]      e.g. tool/handoff_compare.py verse-paper

Reads test_goldens/goldens/handoff/<state>-<theme>.png (the app, 2×) and
../design/redesign/handoff/screens/<state>-<theme>.png (the design, 2×), and
writes build/handoff/<state>-<theme>.png: the app on the left, the design on
the right. With no names, every golden. Needs Pillow.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

app = Path(__file__).resolve().parent.parent
goldens = app / "test_goldens" / "goldens" / "handoff"
screens = next((r / "design" / "redesign" / "handoff" / "screens" for r in (app.parent, app.parent / "shatibiyyah-data")
                if (r / "design" / "redesign" / "handoff" / "screens").is_dir()), None)
if screens is None:
    sys.exit("the workspace (design/redesign/handoff/) is not around the app")
out = app / "build" / "handoff"
out.mkdir(parents=True, exist_ok=True)
names = sys.argv[1:] or sorted(p.stem for p in goldens.glob("*.png"))
for name in names:
    ours, design = Image.open(goldens / f"{name}.png").convert("RGB"), Image.open(screens / f"{name}.png").convert("RGB")
    bar = 28
    sheet = Image.new("RGB", (ours.width + design.width + 12, max(ours.height, design.height) + bar), (255, 0, 255))
    draw = ImageDraw.Draw(sheet)
    for x, label, image in ((0, f"app: {name}", ours), (ours.width + 12, f"design: {name}", design)):
        draw.rectangle([x, 0, x + image.width, bar - 1], fill=(0, 0, 0))
        draw.text((x + 8, 8), label, fill=(255, 255, 255))
        sheet.paste(image, (x, bar))
    sheet.save(out / f"{name}.png")
    print(out / f"{name}.png")
