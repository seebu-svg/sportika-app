#!/usr/bin/env bash
#
# Local verification gate for the Sportika frontend.
#
# Flutter is not on PATH in this shell and /tmp is a small tmpfs that Flutter
# and Gradle fill up, so both are pinned to the workspace. Run every phase
# gate through this script:
#
#   tool/verify.sh              format + analyze + test
#   tool/verify.sh --apk        the above, then a debug APK build
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export PATH="$HOME/flutter/bin:$PATH"
export TMPDIR="$ROOT/.tmp"
mkdir -p "$TMPDIR"

echo "==> dart format --set-exit-if-changed lib test tool"
dart format --set-exit-if-changed lib test tool

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test"
flutter test

if [[ "${1:-}" == "--apk" ]]; then
  echo "==> flutter build apk --debug"
  flutter build apk --debug
fi

echo "==> verified"
