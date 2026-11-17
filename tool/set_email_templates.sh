#!/usr/bin/env bash
#
# Applies and proves Sportika's Supabase email templates: six-digit codes, never
# a magic link.
#
# Whether GoTrue sends a code or a link is decided by the template body, not by
# any Dart code — the client already verifies codes on every flow. GoTrue issues
# the code and the link from ONE token, so a template that still renders
# {{ .ConfirmationURL }} lets an inbox prefetcher consume the token and invalidate
# the code the member has not typed yet. Hence: {{ .Token }} in, link markup out.
#
#   export SUPABASE_ACCESS_TOKEN=sbp_...        # account personal access token,
#                                               # from https://supabase.com/dashboard/account/tokens
#   export SUPABASE_PROJECT_REF=uzmgpypqarsvdeewacfz
#   tool/set_email_templates.sh            # show current bodies, PATCH, then prove them
#   tool/set_email_templates.sh --check    # prove them only (used by tool/build_live.sh)
#   tool/set_email_templates.sh --show     # print the four live bodies and change nothing
#
# A personal access token and nothing else: the service-role key is an auth-plane
# credential and api.supabase.com rejects it as an undecodable JWT. Both values
# are read from the environment only, are never written to disk, and are never
# echoed. The HTTP itself runs inside stdlib urllib rather than curl, so neither
# the token nor a response body can be read out of another user's argv or
# /proc cmdline, and /config/auth's SMTP credentials are never printed - only
# the four template subjects and bodies are.
#
# Only the eight mailer template fields are sent. Anything else in the payload
# (OTP expiry, password length, redirect allow-list) is deliberately left out of
# the PATCH: one guessed key must not be able to rewrite unrelated auth settings.
# Set Email OTP expiration (600 s) and OTP length (6) in the dashboard.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="apply"
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --show) MODE="show" ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "!! SUPABASE_ACCESS_TOKEN is unset - export an account personal access token" >&2
  echo "   from https://supabase.com/dashboard/account/tokens (not the service-role key)" >&2
  exit 2
fi
if (( ${#SUPABASE_ACCESS_TOKEN} < 20 )); then
  # A real personal access token is far longer than this. Short values are always
  # a leftover from testing or a half-pasted string, and PATCHing with one reads
  # as an authentication failure rather than as "you are holding the wrong env".
  echo "!! SUPABASE_ACCESS_TOKEN looks like a placeholder, not a real token" >&2
  echo "   (len ${#SUPABASE_ACCESS_TOKEN}); unset it and export the token from" >&2
  echo "   https://supabase.com/dashboard/account/tokens" >&2
  exit 2
fi
if [[ -z "${SUPABASE_PROJECT_REF:-}" ]]; then
  echo "!! SUPABASE_PROJECT_REF is unset - export your project ref, e.g." >&2
  echo "   export SUPABASE_PROJECT_REF=uzmgpypqarsvdeewacfz" >&2
  exit 2
fi
if [[ -n "${SUPABASE_MANAGEMENT_API:-}" && "${SUPABASE_MANAGEMENT_API}" != "https://api.supabase.com" ]]; then
  # Overriding the host is for a local stack or a test double. Say which host a
  # write would land on, because "it worked" against the wrong target is the
  # most expensive way to learn that a variable was still exported.
  echo "!! SUPABASE_MANAGEMENT_API points at ${SUPABASE_MANAGEMENT_API} - not api.supabase.com" >&2
fi

exec python3 - "$MODE" <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

MODE = sys.argv[1] if len(sys.argv) > 1 else "apply"
API = os.environ.get("SUPABASE_MANAGEMENT_API", "https://api.supabase.com").rstrip("/")
TOKEN = os.environ["SUPABASE_ACCESS_TOKEN"]
REF = os.environ["SUPABASE_PROJECT_REF"]
CONFIG_PATH = f"/v1/projects/{REF}/config/auth"
# Every printed line names the absolute target, so an operator can see which
# project a write went to instead of inferring it from a bare path.
TARGET = f"{API}{CONFIG_PATH}"

CODE = '<p style="font-size:32px;letter-spacing:8px;font-weight:700">{{ .Token }}</p>'

# label, subject key, content key, subject, body. Bodies match
# AUTH_IMPLEMENTATION_PLAN.md Appendix B, which docs/AUTHENTICATION.md points at;
# edit one, edit the other.
TEMPLATES = [
    (
        "Confirm signup",
        "mailer_subjects_confirmation",
        "mailer_templates_confirmation_content",
        "Your Sportika code",
        "<h2>Confirm your Sportika account</h2>"
        "<p>Enter this code in the app to finish creating your account:</p>"
        f"{CODE}"
        "<p>The code expires in 10 minutes. If you did not sign up, ignore this email.</p>",
    ),
    (
        "Magic link or OTP",
        "mailer_subjects_magic_link",
        "mailer_templates_magic_link_content",
        "Your Sportika sign-in code",
        "<h2>Sign in to Sportika</h2>"
        "<p>Enter this code in the app to sign in:</p>"
        f"{CODE}"
        "<p>The code expires in 10 minutes. If you did not ask to sign in, your password"
        " has not changed and you can ignore this email.</p>",
    ),
    (
        "Reset password",
        "mailer_subjects_recovery",
        "mailer_templates_recovery_content",
        "Reset your Sportika password",
        "<h2>Reset your Sportika password</h2>"
        "<p>Enter this code in the app, then choose a new password:</p>"
        f"{CODE}"
        "<p>The code expires in 10 minutes. If you did not ask for this, your password"
        " has not changed.</p>",
    ),
    (
        "Change email address",
        "mailer_subjects_email_change",
        "mailer_templates_email_change_content",
        "Confirm your new Sportika email",
        "<h2>Confirm your new email address</h2>"
        "<p>Enter this code in the app to confirm {{ .NewEmail }} as your Sportika address:</p>"
        f"{CODE}"
        "<p>The code expires in 10 minutes. If you did not ask for this change, your"
        " current address stays as it is.</p>",
    ),
]


def call(method, payload=None):
    """One Management API request. Returns the parsed body, or None on 204."""
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        API + CONFIG_PATH,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        # The status is the useful part; error bodies from this endpoint echo
        # request context and could carry payload material.
        hint = ""
        if error.code in (401, 403):
            hint = (
                " - SUPABASE_ACCESS_TOKEN must be an account personal access token"
                " from https://supabase.com/dashboard/account/tokens,"
                " not a service-role or publishable key"
            )
        elif error.code == 404:
            hint = " - check SUPABASE_PROJECT_REF"
        raise SystemExit(f"!! {method} {TARGET} failed with HTTP {error.code}{hint}")
    except urllib.error.URLError as error:
        raise SystemExit(f"!! cannot reach {TARGET}: {error.reason}")
    if not raw:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        raise SystemExit(f"!! {method} {TARGET} returned a non-JSON body")


def prove(config):
    """Asserts every template carries the code and carries no link. Never prints
    the payload: /config/auth contains SMTP credentials."""
    failures = 0
    for label, _subject_key, content_key, _subject, _body in TEMPLATES:
        content = config.get(content_key)
        if not isinstance(content, str) or not content:
            print(f"FAIL  {label}: {content_key} is absent from the API response")
            failures += 1
            continue
        problems = []
        if "{{ .Token }}" not in content:
            problems.append("no {{ .Token }}, so no six-digit code is ever sent")
        if "{{ .ConfirmationURL }}" in content:
            problems.append("still renders {{ .ConfirmationURL }}, so a prefetching"
                            " inbox can consume the token and invalidate the code")
        if problems:
            print(f"FAIL  {label}: {'; '.join(problems)}")
            failures += 1
        else:
            print(f"PASS  {label}: code only, no link")
    return failures


def render(config):
    """Prints the four live template bodies and nothing else from the payload.

    Template HTML is not a secret; the rest of /config/auth is. Applying this
    script overwrites the project's existing bodies, and docs/AUTHENTICATION.md
    promises rollback is "a template edit, not a deploy" - that promise only
    holds if the previous bodies are on screen to be pasted back.
    """
    for label, subject_key, content_key, _subject, _body in TEMPLATES:
        subject = config.get(subject_key)
        content = config.get(content_key)
        print(f"--- {label}")
        print(f"subject: {subject if isinstance(subject, str) else '(absent)'}")
        print(f"body   : {content if isinstance(content, str) else '(absent)'}")
    print()


if MODE == "show":
    print(f"==> GET {TARGET}")
    shown = call("GET")
    if not isinstance(shown, dict):
        raise SystemExit("!! the project returned no auth configuration object")
    render(shown)
    # Still a verdict, not just a printout: `--show` is what an operator runs
    # before applying, and a project that already delivers codes should say so.
    failures = prove(shown)
    if failures:
        print(f"!! {failures} of {len(TEMPLATES)} templates still cannot deliver a code")
        raise SystemExit(1)
    print(f"==> all {len(TEMPLATES)} templates send a six-digit code")
    raise SystemExit(0)

if MODE == "apply":
    print(f"==> GET {TARGET}")
    before = call("GET")
    if not isinstance(before, dict):
        raise SystemExit("!! the project returned no auth configuration object")
    print("    current templates - save these to roll back:\n")
    render(before)
    fields = {}
    for _label, subject_key, content_key, subject, body in TEMPLATES:
        fields[subject_key] = subject
        fields[content_key] = body
    print(f"==> PATCH {TARGET} (8 mailer template fields, nothing else)")
    call("PATCH", fields)
    print("    accepted")

print(f"==> GET {TARGET}")
current = call("GET")
if not isinstance(current, dict):
    raise SystemExit("!! the project returned no auth configuration object")

failures = prove(current)
if failures:
    print(f"!! {failures} of {len(TEMPLATES)} templates still cannot deliver a code")
    raise SystemExit(1)
print(f"==> all {len(TEMPLATES)} templates send a six-digit code")
PY
