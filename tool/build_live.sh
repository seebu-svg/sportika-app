#!/usr/bin/env bash
#
# Builds a Sportika release APK that talks to a real Supabase project.
#
# The two credentials are read from the environment and passed only as
# --dart-define flags, so nothing is ever written into the repo:
#
#   export SUPABASE_URL=https://<ref>.supabase.co
#   export SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
#   tool/build_live.sh                 # pre-flight, then release APK
#   tool/build_live.sh --check         # pre-flight only
#   tool/build_live.sh --split         # one smaller APK per ABI
#   tool/build_live.sh --demo          # device-only demo build, no backend
#
# The pre-flight also reads the project's auth configuration. Some projects only
# expose /auth/v1/settings to the service-role key; exporting it here keeps it in
# the build shell for that one GET and never into the APK:
#
#   export SUPABASE_SERVICE_ROLE_KEY=eyJ...   # optional, pre-flight only
#
# Against a local `supabase start` stack, use the machine's LAN address rather
# than localhost (a phone cannot reach the desktop's loopback); 10.0.2.2 only
# works for an Android emulator.
#
# A release is compiled for exactly one of the two email modes, and the project
# must be set the same way (the pre-flight compares the two):
#
#   export EMAIL_VERIFICATION=true    # default false, matching AppEnv
#
# With it off, signup hands back a session in one call and there is no code
# screen. With it on, the member must type a six-digit code first.
#
# A third credential is optional and never reaches the APK:
#
#   export SUPABASE_ACCESS_TOKEN=sbp_...   # optional, template pre-flight only
#
# With it, the pre-flight also proves the project's email templates carry
# {{ .Token }} and no link, so a build cannot ship against a project that would
# mail a magic link the app cannot use. Without it, that one check is skipped.
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

# Read under `set -u` in both the pre-flight and the dart-define list, so it has
# to have a value even when the caller never mentions it. Defaults to the same
# answer as AppEnv.emailVerificationEnabled.
EMAIL_VERIFICATION="${EMAIL_VERIFICATION:-false}"

case "$EMAIL_VERIFICATION" in
  true | false) ;;
  *) echo "EMAIL_VERIFICATION must be true or false, got: $EMAIL_VERIFICATION" >&2; exit 64 ;;
esac

MODE="release"
CHECK_ONLY=0
SPLIT=()
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --split) SPLIT=(--split-per-abi) ;;
    --demo) MODE="demo" ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

if [[ "$MODE" == "release" ]]; then
  : "${SUPABASE_URL:?set SUPABASE_URL to your project URL, or pass --demo}"
  : "${SUPABASE_PUBLISHABLE_KEY:?set SUPABASE_PUBLISHABLE_KEY to your publishable or anon key, or pass --demo}"
fi

# A release that cannot reach its schema is worse than no release: the app
# would sign people in and then fail on the first profile read. Checks run
# before Gradle so the answer takes a second instead of six minutes.
preflight() {
  if [[ "$MODE" == "demo" ]]; then
    echo "==> demo build: no backend contact, skips pre-flight"
    return 0
  fi

  echo "==> GET $SUPABASE_URL/rest/v1/profiles?select=id&limit=1"
  local body
  body="$(curl --silent --show-error --location --max-time 20 \
    --get "$SUPABASE_URL/rest/v1/profiles" \
    --data-urlencode "select=id" --data-urlencode "limit=1" \
    --header "apikey: $SUPABASE_PUBLISHABLE_KEY" \
    --header "Authorization: Bearer $SUPABASE_PUBLISHABLE_KEY" || true)"

  if grep -qi 'relation .* does not exist\|Could not find the table' <<<"$body"; then
    echo "!! the profiles table is missing - apply supabase/migrations/0001..0004 first" >&2
    return 1
  fi
  if [[ -z "$body" ]]; then
    echo "!! no response from $SUPABASE_URL - check the URL and your network" >&2
    return 1
  fi
  echo "    schema reachable"

  echo "==> GET $SUPABASE_URL/auth/v1/health"
  local health
  health="$(curl --silent --show-error --location --max-time 20 \
    --header "apikey: $SUPABASE_PUBLISHABLE_KEY" \
    "$SUPABASE_URL/auth/v1/health" || true)"
  grep -q '"name"' <<<"$health" && echo "    gotrue healthy" || echo "    !! unexpected health payload: $health"

  # Two invariants: one that always holds, and one that depends on this build.
  #
  # The Email provider has to be enabled either way. Recovery, change-email and
  # passwordless mail all need it, and with it switched off those mails are
  # composed and delivered nowhere.
  #
  # Whether members confirm their address, though, is a dashboard setting and
  # the app is compiled for exactly one answer. The pair must agree, or signup
  # dead-ends in whichever direction is wrong: with *Confirm email* on and a
  # build that expects no code screen, signUp issues no session and
  # registerWithoutVerification reports EmailVerificationRequired, leaving the
  # member on a form with no next step; with the setting off and a build that
  # expects a code, the app opens the verify screen for a code GoTrue was never
  # asked to send. /auth/v1/settings is the only read that can say which way the
  # project is set, so a build that cannot prove the match does not ship.
  echo "==> GET $SUPABASE_URL/auth/v1/settings"
  local settings_key="${SUPABASE_SERVICE_ROLE_KEY:-$SUPABASE_PUBLISHABLE_KEY}"
  local settings
  settings="$(curl --silent --show-error --location --max-time 20 \
    --header "apikey: $settings_key" \
    --header "Authorization: Bearer $settings_key" \
    "$SUPABASE_URL/auth/v1/settings" || true)"
  local verdict
  if ! verdict="$(python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit("no readable settings payload; export SUPABASE_SERVICE_ROLE_KEY if this project restricts /auth/v1/settings")
expect = sys.argv[2] == "true"
problems = []
if (data.get("external") or {}).get("email") is not True:
    problems.append("the Email provider is switched off, so no code or link can be delivered")
autoconfirm = data.get("mailer_autoconfirm")
if autoconfirm is None:
    problems.append("the settings payload reports no mailer_autoconfirm; export "
                    "SUPABASE_SERVICE_ROLE_KEY if this project restricts /auth/v1/settings")
elif (not autoconfirm) != expect:
    if expect:
        problems.append("the project runs with Confirm email off, so no signup code is "
                        "ever mailed, but this build waits for one - build with "
                        "EMAIL_VERIFICATION=false, or switch Confirm email on")
    else:
        problems.append("the project runs with Confirm email on, so signUp returns no "
                        "session and registration dead-ends, but this build has no code "
                        "screen - build with EMAIL_VERIFICATION=true, or switch Confirm "
                        "email off")
if problems:
    sys.exit("; ".join(problems))
print("    email provider enabled, and project confirmations match this build"
      if not autoconfirm else
      "    email provider enabled, and the project autoconfirms as this build expects")
' "$settings" "$EMAIL_VERIFICATION" 2>&1)"; then
    echo "!! auth settings do not suit this build: $verdict" >&2
    return 1
  fi
  echo "$verdict"

  # Bucket metadata reads are themselves RLS-protected, so GET /bucket/avatars
  # answers "not found" to an anonymous caller even when the bucket exists. The
  # public object path is not gated that way: a missing object proves the bucket
  # is there and public-read, while a missing bucket says so explicitly.
  local name bucket migration
  for pair in avatars:0004_storage.sql team-media:0010_module_media.sql \
    tournament-media:0010_module_media.sql match-media:0010_module_media.sql; do
    name="${pair%%:*}"
    migration="${pair#*:}"
    echo "==> GET $SUPABASE_URL/storage/v1/object/public/$name/.probe"
    bucket="$(curl --silent --show-error --location --max-time 20 \
      --header "apikey: $SUPABASE_PUBLISHABLE_KEY" \
      "$SUPABASE_URL/storage/v1/object/public/$name/.probe" || true)"
    if grep -q 'NoSuchBucket' <<<"$bucket"; then
      echo "!! the $name bucket is missing - every upload to it fails on a device (apply supabase/migrations/$migration)" >&2
      return 1
    fi
    grep -q 'NoSuchKey' <<<"$bucket" || {
      echo "!! unexpected answer for the $name bucket: $bucket" >&2
      return 1
    }
    echo "    $name bucket present and public-read"
  done

  # The media code and the schema ship together. A build that can sign in but
  # cannot read module_media, matches or profiles.avatar_path fails on the first
  # uploaded picture, which is what the gate exists to catch before a phone does.
  # A permission error still proves the table and column exist; only a missing
  # relation (PGRST205) or a missing column (42703) fails the build.
  probe_table() {
    local table="$1" select="$2" migration="$3" answer
    echo "==> GET $SUPABASE_URL/rest/v1/$table?select=$select&limit=1"
    answer="$(curl --silent --show-error --location --max-time 20 \
      --get "$SUPABASE_URL/rest/v1/$table" \
      --data-urlencode "select=$select" --data-urlencode "limit=1" \
      --header "apikey: $SUPABASE_PUBLISHABLE_KEY" \
      --header "Authorization: Bearer $SUPABASE_PUBLISHABLE_KEY" || true)"
    if grep -q 'Could not find the table' <<<"$answer"; then
      echo "!! $table is missing - apply supabase/migrations/$migration" >&2
      return 1
    fi
    if grep -q '42703' <<<"$answer"; then
      echo "!! $table lacks a column this build writes ($select) - apply supabase/migrations/$migration" >&2
      return 1
    fi
    echo "    $table reachable"
  }
  probe_table module_media bucket_id 0010_module_media.sql || return 1
  probe_table matches id 0007_match_module.sql || return 1
  probe_table profiles avatar_path 0010_module_media.sql || return 1

  # Every auth flow in the app verifies a typed six-digit code, but GoTrue
  # decides whether the email carries that code or a link, and it decides by
  # template body. A template that renders the link instead of {{ .Token }}
  # surfaces on a phone as "I never got a code" - indistinguishable from a
  # client bug - and a template that renders both lets an inbox prefetcher
  # consume the shared token before the member types anything. Worth failing a
  # build over, but only when this shell can actually read the project: the
  # check needs an account personal access token, which a plain release build
  # has no reason to carry.
  if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
    # An explicit SUPABASE_PROJECT_REF always wins; otherwise a hosted project's
    # ref is the first host label. A LAN or self-hosted URL has no such label,
    # so say so and fail rather than send a garbage path that would read as a
    # missing project.
    local ref="${SUPABASE_PROJECT_REF:-}"
    if [[ -z "$ref" ]]; then
      local host="${SUPABASE_URL#*://}"
      host="${host%%/*}"; host="${host%%:*}"
      if [[ "$host" == *.supabase.co ]]; then
        ref="${host%%.*}"
      fi
    fi
    if [[ -z "$ref" ]]; then
      echo "!! cannot tell the project ref from $SUPABASE_URL - export SUPABASE_PROJECT_REF" >&2
      return 1
    fi
    echo "==> email templates (api.supabase.com, project $ref)"
    SUPABASE_PROJECT_REF="$ref" tool/set_email_templates.sh --check
  else
    echo "==> email templates: skipped (export SUPABASE_ACCESS_TOKEN to verify them)"
  fi
}

preflight
if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "==> pre-flight only"
  exit 0
fi

# The demo branch must not mention the credential variables at all: they are
# unset for a demo build, and `set -u` turns a mere reference into an abort.
DEFINES=()
if [[ "$MODE" == "demo" ]]; then
  DEFINES=(--dart-define=DEMO_MODE=true)
else
  DEFINES=(--dart-define=SUPABASE_URL="$SUPABASE_URL"
           --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY")
  # Passed only when it differs from the AppEnv default, so no build can bake a
  # stale true into the binary by leaving the variable set in a shell profile.
  if [[ "$EMAIL_VERIFICATION" == "true" ]]; then
    DEFINES+=(--dart-define=EMAIL_VERIFICATION=true)
  fi
fi

echo "==> flutter analyze"
flutter analyze

echo "==> flutter build apk --release"
flutter build apk --release "${SPLIT[@]}" "${DEFINES[@]}"

echo
echo "==> built"
ls -lh build/app/outputs/flutter-apk/*.apk
echo
echo "Install without wiping app data:"
echo "  \$HOME/Android/Sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk"
