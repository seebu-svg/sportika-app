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
# The exit code alone is not enough: flutter_tools can fail to even load a test
# file (a shutdown race prints "Cannot close sink while adding stream") and still
# leave 0 behind. A gate that answers green on a run that never executed the
# suite is worse than no gate, so the transcript is checked as well.
TEST_LOG="$TMPDIR/verify-flutter-test.log"
flutter test 2>&1 | tee "$TEST_LOG"
TEST_SUMMARY="$(tr '\r' '\n' < "$TEST_LOG")"
if ! grep -q "All tests passed!" <<<"$TEST_SUMMARY"; then
  echo "!! flutter test never reported a clean pass - see $TEST_LOG" >&2
  exit 1
fi
if grep -qE "\[E\]|uncaught errors" <<<"$TEST_SUMMARY"; then
  echo "!! flutter test reported failing or unloadable tests - see $TEST_LOG" >&2
  exit 1
fi

if [[ "${1:-}" == "--apk" ]]; then
  echo "==> flutter build apk --debug"
  flutter build apk --debug
fi

echo "==> verified"
