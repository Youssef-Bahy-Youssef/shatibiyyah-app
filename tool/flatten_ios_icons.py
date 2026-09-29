"""Drop the alpha channel from the iOS app icons (App Store icons may not carry one).

Run after `flutter test tool/render_brand_assets.dart`:

    python3 tool/flatten_ios_icons.py

The icons are full-bleed and opaque already; this only rewrites them as RGB.
"""
from pathlib import Path

from PIL import Image

ICONS = Path(__file__).resolve().parent.parent / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

for png in sorted(ICONS.glob("*.png")):
    image = Image.open(png)
    if image.mode != "RGB":
        image.convert("RGB").save(png, optimize=True)
        print(f"flattened {png.name}")
