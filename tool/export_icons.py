"""Export the prototype's icon sprite to assets/icons/*.svg (item 3.2, ADR 0019).

Reads every <symbol id="i-NAME"> of the sprite in design/redesign/v2.js (the workspace around the
app) and writes assets/icons/NAME.svg: the symbol's own markup inside a root that carries the sprite's
stroked style (24 grid, 1.6 stroke, round caps and joins, currentColor). TzIcon swaps the root's
fill/stroke for the filled glyphs. The output depends only on v2.js.

    python3 tool/export_icons.py            # write assets/icons/
    python3 tool/export_icons.py --check    # exit 1 if assets/icons/ is out of date
"""
import pathlib
import re
import sys

APP = pathlib.Path(__file__).resolve().parents[1]
OUT = APP / "assets" / "icons"
ROOT = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
        'stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">')


def sprite():
    """v2.js where the workspace keeps it: the app inside it (app/), or the repositories side by side."""
    for root in (APP.parent, APP.parent / "shatibiyyah-data"):
        f = root / "design" / "redesign" / "v2.js"
        if f.exists():
            return f
    raise SystemExit("design/redesign/v2.js not found: check out the workspace around the app")


def symbols():
    text = sprite().read_text()
    out = {}
    for name, view_box, body in re.findall(r'<symbol id="i-([\w-]+)" viewBox="([^"]+)">(.*?)</symbol>', text, re.S):
        if view_box != "0 0 24 24":
            raise SystemExit(f"i-{name}: viewBox {view_box}, not the 24 grid")
        out[name] = f"{ROOT}{body}</svg>\n"
    return out


def main(argv):
    icons = symbols()
    if "--check" in argv:
        on_disk = {p.stem: p.read_text() for p in OUT.glob("*.svg")}
        if on_disk != icons:
            print("assets/icons/ is out of date: run tool/export_icons.py", file=sys.stderr)
            return 1
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    for stale in OUT.glob("*.svg"):
        if stale.stem not in icons:
            stale.unlink()
    for name, svg in icons.items():
        (OUT / f"{name}.svg").write_text(svg)
    print(f"wrote {len(icons)} icons to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
