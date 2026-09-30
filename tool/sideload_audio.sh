#!/usr/bin/env bash
# tool/sideload_audio.sh — puts the two recordings on a device or emulator for
# testing, where the app looks for them (files/audio/<slug>.mp3), since no audio
# is bundled and the hosting is not up yet. Needs a debug build of the app
# installed (run-as only works for debuggable apps) — run it once from Android
# Studio first.
#
#   tool/sideload_audio.sh            # both recordings
#   tool/sideload_audio.sh atiq       # only Muhammad Atiq (the default reciter)
#   ANDROID_SERIAL=emulator-5554 tool/sideload_audio.sh   # when several devices are attached
set -euo pipefail

cd "$(dirname "$0")/.."
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
APP=com.shatibiyyah.app
SOURCES=../../claude-alignment/recordings

# slug and the size the app expects (recordings.audio_bytes in the snapshot)
declare -a RECORDINGS=("muhammad-atiq-1:144592605" "abdulhamid-alqaryu-1:252351225")
[[ "${1:-}" == "atiq" ]] && RECORDINGS=("muhammad-atiq-1:144592605")

"$ADB" shell run-as "$APP" true 2>/dev/null || {
  echo "The debug app ($APP) is not installed on the device: run it from Android Studio first." >&2
  exit 1
}
"$ADB" shell run-as "$APP" mkdir -p files/audio

for entry in "${RECORDINGS[@]}"; do
  slug=${entry%%:*}
  bytes=${entry##*:}
  src="$SOURCES/$slug/audio/source.mp3"
  [[ -f "$src" ]] || { echo "missing $src" >&2; exit 1; }
  size=$(stat -f %z "$src" 2>/dev/null || stat -c %s "$src")
  [[ "$size" == "$bytes" ]] || { echo "$src is $size bytes, the app expects $bytes" >&2; exit 1; }
  echo "→ $slug ($((bytes / 1000000)) MB)"
  "$ADB" push "$src" "/data/local/tmp/$slug.mp3" >/dev/null
  "$ADB" shell run-as "$APP" cp "/data/local/tmp/$slug.mp3" "files/audio/$slug.mp3"
  "$ADB" shell rm "/data/local/tmp/$slug.mp3"
done
echo "Done. Force-stop and reopen the app (or choose the reciter again) to pick them up."
