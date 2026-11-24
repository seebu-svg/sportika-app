#!/usr/bin/env bash
#
# Fast UI iteration for Sportika: one debug `flutter run` session with hot reload.
#
#   tool/live.sh                    # USB device SM (R58M82VX3CL), live backend
#   tool/live.sh --check            # verify prerequisites, print the command, stop
#   tool/live.sh --emulator         # boot the first AVD and run there instead
#   tool/live.sh --emulator=<avd>   # ... a specific AVD
#
# Why not the release APK: `flutter build apk --release` is AOT, so a release
# binary cannot hot reload at all, and every single edit pays the whole Gradle
# pipeline. A debug session installs once and then redraws on a keypress.
#
# Keys inside the session:  r  hot reload (keeps app state)
#                           R  hot restart (reruns main(), resets state)
#                           s  screenshot    q  quit
#
# Hot reload covers Dart edits only. Changing a --dart-define value, adding an
# asset or font to pubspec.yaml, or editing anything under android/ needs a stop
# and a re-run of this script, not a reload.
#
# The two credentials are read from the environment and passed only as
# --dart-define flags, so nothing is ever written into the repo or into a log:
#
#   export SUPABASE_URL=https://<ref>.supabase.co
#   export SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
#
# The email-verification mode matches tool/build_live.sh and defaults to the
# AppEnv value, so a session cannot accidentally bake a stale `true`:
#
#   export EMAIL_VERIFICATION=true    # optional, off by default
#
# NOTE: this debug build shares the applicationId pk.sportika.mobile and the
# debug signing key with the release artifact, so it REPLACES the installed
# release app on the phone. App data survives; to hand the deliverable back
# afterwards run:
#
#   adb install -r -d build/app/outputs/flutter-apk/app-release.apk
#
# The -d is not optional once a split-per-ABI debug build has been installed:
# that artifact carries versionCode 2001 (1 plus 1000 per ABI), so the fat
# release APK at versionCode 1 is refused as a downgrade without it.
#
# There is no backend pre-flight here - the schema/storage checks belong to
# tool/build_live.sh --check, and a UI session should not wait on the network.
#
# Optional environment:
#
#   SPORTIKA_DEVICE_SERIAL / SPORTIKA_DEVICE_MODEL   target another handset
#   EMULATOR_GPU=auto                                hardware-accelerated AVD
#                                (default swiftshader_indirect, the rendering
#                                 mode that boots reliably on this machine)
#
# The reload keys are read from stdin, so run this from an interactive terminal;
# a pipe or a background shell can start the session but never drive it.
#
# Flutter is not on PATH here and /tmp is a small tmpfs, so both are pinned to
# the workspace, matching tool/verify.sh.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export PATH="$HOME/flutter/bin:$PATH"
export TMPDIR="$ROOT/.tmp"
mkdir -p "$TMPDIR"

ADB="$HOME/Android/Sdk/platform-tools/adb"
EMULATOR_BIN="$HOME/Android/Sdk/emulator/emulator"

# The user's physical device ("SM"), overridable for a second handset without
# editing this file.
DEVICE_SERIAL="${SPORTIKA_DEVICE_SERIAL:-R58M82VX3CL}"
DEVICE_MODEL="${SPORTIKA_DEVICE_MODEL:-SM_N970F}"

# Stops before `set -euo pipefail`, so the help text is the header and cannot
# drift out of sync with it.
usage() {
  awk 'NR > 2 && /^set -euo/ {exit} NR > 2 {sub(/^#? ?/, ""); print}' "${BASH_SOURCE[0]}"
}

PROBLEMS=()
NOTES=()
problem() { PROBLEMS+=("$1"); }
note() { NOTES+=("$1"); }
die() { echo "!! $1" >&2; exit 1; }

CHECK_ONLY=0
TARGET_KIND="usb"
TARGET=""
AVD=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --emulator) TARGET_KIND="emulator" ;;
    --emulator=*) TARGET_KIND="emulator" AVD="${arg#--emulator=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) echo "unknown argument: $arg (see tool/live.sh --help)" >&2; exit 64 ;;
  esac
done

EMAIL_VERIFICATION="${EMAIL_VERIFICATION:-false}"
case "$EMAIL_VERIFICATION" in
  true | false) ;;
  *) echo "EMAIL_VERIFICATION must be true or false, got: $EMAIL_VERIFICATION" >&2; exit 64 ;;
esac

# ---------------------------------------------------------------- prerequisites

# Every check reports rather than aborts, so `--check` answers the whole question
# in one run instead of forcing a loop of one-problem-at-a-time fixes.
check_toolchain() {
  echo "==> toolchain"
  command -v flutter >/dev/null 2>&1 ||
    problem "flutter not found at \$HOME/flutter/bin - is the SDK still there?"
  [[ -x "$ADB" ]] ||
    problem "adb not found at $ADB - the Android SDK is required to reach the device"

  if [[ "$TARGET_KIND" == "emulator" ]]; then
    [[ -x "$EMULATOR_BIN" ]] ||
      problem "emulator not found at $EMULATOR_BIN - install it with sdkmanager --install emulator"
    if [[ -z "$AVD" ]]; then
      AVD="$("$EMULATOR_BIN" -list-avds 2>/dev/null | head -n1 || true)"
      [[ -n "$AVD" ]] ||
        problem "no AVD is installed - create one in Android Studio or pass --emulator=<name>"
    else
      "$EMULATOR_BIN" -list-avds 2>/dev/null | grep -qx "$AVD" ||
        problem "AVD '$AVD' does not exist (available: $("$EMULATOR_BIN" -list-avds 2>/dev/null | tr '\n' ' '))"
    fi
    echo "    will use AVD ${AVD:-<none>}"
  fi
}

check_credentials() {
  echo "==> credentials"
  if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
    problem "export SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY first - without them AppEnv falls back to AuthBackend.unavailable and sign-in fails closed (.tmp/build_now.sh shows how to recover them from the last release APK)"
    return
  fi
  [[ "$SUPABASE_URL" =~ ^https?:// ]] ||
    problem "SUPABASE_URL must start with http:// or https://, got: $SUPABASE_URL"

  # A phone cannot reach the desktop's loopback, and an emulator needs the
  # host alias 10.0.2.2 instead. Both are silent failures: the app starts and
  # every read then errors out.
  local host="${SUPABASE_URL#*://}"
  host="${host%%/*}"
  host="${host%%:*}"
  case "$host" in
    localhost | 127.0.0.1 | ::1)
      if [[ "$TARGET_KIND" == "emulator" ]]; then
        problem "SUPABASE_URL points at $host, which an emulator cannot reach - for a local 'supabase start' stack use http://10.0.2.2:54321"
      else
        problem "SUPABASE_URL points at $host, which the phone cannot reach - use this machine's LAN address (see tool/build_live.sh)"
      fi
      ;;
  esac
  echo "    SUPABASE_URL=$SUPABASE_URL"
  echo "    SUPABASE_PUBLISHABLE_KEY=<set, not printed>"
}

# Returns the serial only while adb considers it ready.
usb_target() {
  "$ADB" devices -l 2>/dev/null |
    awk -v s="$DEVICE_SERIAL" '$1 == s && $2 == "device" {print $1; exit}'
}

# The first emulator adb considers ready. Kept separate because both the check
# and the run path need it.
online_emulator() {
  "$ADB" devices 2>/dev/null |
    awk '/^emulator-[0-9]+[[:space:]]+device/ {print $1; exit}' || true
}

# adb spells the model with an underscore in `devices -l` but the device
# property itself answers SM-N970F, so punctuation is ignored before comparing.
same_model() {
  local a b
  a="$(tr -cd '[:alnum:]' <<<"${1^^}")"
  b="$(tr -cd '[:alnum:]' <<<"${2^^}")"
  [[ "$a" == "$b" ]]
}

check_device() {
  echo "==> ${TARGET_KIND} target"
  if [[ "$TARGET_KIND" == "emulator" ]]; then
    # In --check the AVD is only resolved above; booting it is the run path.
    if [[ "$CHECK_ONLY" == "1" ]]; then
      local running
      running="$(online_emulator)"
      # A placeholder rather than a blank, so the printed command below is never
      # a `-d` with no value that someone could paste and get a device prompt on.
      TARGET="${running:-<emulator booted from '$AVD'>}"
      echo "    $TARGET"
      return
    fi

    # Booting a second AVD while one is online is minutes of wasted work, and
    # the wait loop in boot_emulator returns whichever emulator adb lists first,
    # so the running one is what would have been used anyway.
    local existing
    existing="$(online_emulator)"
    if [[ -n "$existing" ]]; then
      note "reusing the emulator already online ($existing) instead of booting '$AVD'"
      TARGET="$existing"
    else
      TARGET="$(boot_emulator)" || die "emulator '$AVD' did not come online"
    fi
    echo "    $TARGET"
    return
  fi

  if "$ADB" devices 2>/dev/null | awk -v s="$DEVICE_SERIAL" '$1 == s && $2 == "unauthorized" {found=1} END {exit !found}'; then
    problem "device $DEVICE_SERIAL is unauthorized - accept the 'Allow USB debugging' prompt on the phone"
    return
  fi
  if "$ADB" devices 2>/dev/null | awk -v s="$DEVICE_SERIAL" '$1 == s && $2 == "offline" {found=1} END {exit !found}'; then
    problem "device $DEVICE_SERIAL is offline - run '$ADB kill-server && $ADB devices' and re-plug the cable"
    return
  fi

  TARGET="$(usb_target || true)"
  if [[ -z "$TARGET" ]]; then
    problem "device $DEVICE_SERIAL is not attached - check the cable, and 'adb devices -l' for what IS attached"
    return
  fi

  # The model is a note, not a problem: the same handset reports it fine, and a
  # replacement phone would still be the intended target once the serial matches.
  local model
  model="$("$ADB" -s "$TARGET" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "$model" ]] && ! same_model "$model" "$DEVICE_MODEL"; then
    note "device $DEVICE_SERIAL reports model '$model', not the expected '$DEVICE_MODEL'"
  else
    echo "    $TARGET (model ${model:-unknown})"
  fi
}

# Boots the AVD in the background and waits for adb to expose it, then for the
# Android boot to finish. Progress goes to stderr because the caller captures
# stdout as the target id.
boot_emulator() {
  local log="$TMPDIR/live-emulator.log"
  echo "    booting AVD '$AVD' (log: $log)" >&2
  "$EMULATOR_BIN" -avd "$AVD" -gpu "${EMULATOR_GPU:-swiftshader_indirect}" \
    >"$log" 2>&1 &

  local target="" i
  for ((i = 0; i < 120; i++)); do
    target="$(online_emulator)"
    [[ -n "$target" ]] && break
    sleep 1
  done
  if [[ -z "$target" ]]; then
    echo "!! emulator did not appear in 'adb devices' after 120s - see $log" >&2
    return 1
  fi

  # `flutter run` tolerates a booted-but-still-freezing device badly, so wait it
  # out here where the message is legible.
  for ((i = 0; i < 180; i++)); do
    [[ "$("$ADB" -s "$target" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] &&
      { echo "$target"; return 0; }
    sleep 1
  done
  echo "!! $target never reported boot_completed - see $log" >&2
  return 1
}

# ------------------------------------------------------------------- reporting

report() {
  local -a defines=(
    --debug -d "$TARGET"
    --dart-define=SUPABASE_URL="\$SUPABASE_URL"
    --dart-define=SUPABASE_PUBLISHABLE_KEY="<redacted>"
  )
  [[ "$EMAIL_VERIFICATION" == "true" ]] &&
    defines+=(--dart-define=EMAIL_VERIFICATION=true)

  echo "==> would run"
  printf '    flutter run %s\n' "${defines[*]}"
}

check_toolchain
check_credentials
check_device

if [[ "${#NOTES[@]}" -gt 0 ]]; then
  for n in "${NOTES[@]}"; do echo "    note: $n"; done
fi
if [[ "${#PROBLEMS[@]}" -gt 0 ]]; then
  echo "!! prerequisites not met:" >&2
  for p in "${PROBLEMS[@]}"; do echo "   - $p" >&2; done
  exit 1
fi

if [[ "$CHECK_ONLY" == "1" ]]; then
  report
  echo "==> prerequisites ok"
  exit 0
fi

# The reload keys are read from stdin, so a non-interactive shell (an automation,
# a pipe, a background run) can start the session but never drive it.
[[ -t 0 ]] || echo "    note: stdin is not a terminal - 'r'/'R'/'q' will not be read; run this from an interactive shell"

DEFINES=(--dart-define=SUPABASE_URL="$SUPABASE_URL"
         --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY")
if [[ "$EMAIL_VERIFICATION" == "true" ]]; then
  DEFINES+=(--dart-define=EMAIL_VERIFICATION=true)
fi

echo "==> flutter run --debug (first start compiles a debug APK; afterwards press r to hot reload)"
echo "    installing this debug build replaces the release APK on the device; app data is kept"
exec flutter run --debug -d "$TARGET" "${DEFINES[@]}"
