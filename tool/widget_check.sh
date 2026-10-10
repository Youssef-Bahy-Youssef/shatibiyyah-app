#!/usr/bin/env bash
# Checks the home-screen widget's drawing on a connected Android (plan 6.1), where its text is
# shaped and measured. Dart tests cannot: the widget is drawn by Android itself.
#
#   tool/widget_check.sh             build the debug app, install it, run the probe, pair the images
#   tool/widget_check.sh --no-build  use the debug app already installed
#
# The probe (android/app/src/debug/…/WidgetProbe.kt) lays out all 1173 verses at five sizes and
# fails this script if one is wider than its line, crosses the hairline or nears the edge. Its
# drawings of the design's states land in build/widgets/android/, and tool/widget_compare.py sets
# each beside its design render in build/widgets/. PACKAGE names another application id.
set -euo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
package="${PACKAGE:-com.shatibiyyah.app}"
cd "$app_dir"

if [[ " $* " != *" --no-build "* ]]; then
  flutter build apk --debug
  adb install -r build/app/outputs/flutter-apk/app-debug.apk
fi

remote="/sdcard/Android/data/$package/files/widget-probe"
adb shell rm -rf "$remote"
adb shell am broadcast -n "$package/com.shatibiyyah.app.widgets.WidgetProbe" >/dev/null
for _ in $(seq 1 60); do
  adb shell "test -f $remote/report.json" && break
  sleep 1
done

rm -rf build/widgets/android
mkdir -p build/widgets
adb pull "$remote" build/widgets/android >/dev/null
python3 - build/widgets/android/report.json <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
if not r.get("ok"):
    sys.exit("the probe failed: " + r.get("error", "no report"))
print(f"widest hemistich: verse {r['widestVerse']}, {r['widestEm']:.3f} em; {r['verses']} verses")
bad = 0
for f in r["forms"]:
    bad += f["bad"]
    print(f"  {f['size']}: verse size {f['verseSizes']}, {f['movedDown']} moved down, {f['bad']} bad {f['firstBad']}")
for w in r["placed"]:
    print(f"  on the home screen: widget {w['id']} at {w['sizesDp']} dp, {w['maskBytes']} of {r['bitmapLimitBytes']} bytes")
if bad:
    sys.exit(f"{bad} layouts do not hold")
PY
python3 tool/widget_compare.py
