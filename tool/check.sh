#!/usr/bin/env bash
# Local stand-in for CI: static analysis and tests for the app, the data
# platform's tests, and an Android App Bundle build when an SDK is present.
#
#   tool/check.sh          analyze + test (app) + pytest (data)
#   tool/check.sh --aab    also build a release AAB (needs the Android SDK and
#                          android/keystore.properties pointing at the upload key)
set -euo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
data_dir="$app_dir/../../shatibiyyah-data"

cd "$app_dir"
echo "== flutter analyze"
flutter analyze --no-pub
echo "== flutter test"
flutter test --no-pub

if [[ -x "$data_dir/.venv/bin/pytest" ]]; then
  echo "== pytest (shatibiyyah-data)"
  (cd "$data_dir" && .venv/bin/pytest -q)
else
  echo "== pytest skipped: $data_dir/.venv not found"
fi

if [[ "${1:-}" == "--aab" ]]; then
  echo "== flutter build appbundle"
  flutter build appbundle --release
fi
