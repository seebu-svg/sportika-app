# Sportika

Flutter mobile app for **players and organizers** — discover tournaments, organize
games, and score matches live across cricket, futsal, padel and badminton.

Platform: **Android only** (there is no `ios/`, `web/` or desktop runner in this repo).
Package id: `pk.sportika.mobile`. Backend: Supabase (PostgreSQL + Auth + Realtime + Storage).

---

## 1. Clone

```bash
git clone https://github.com/seebu-svg/sportika-app.git
cd sportika-app
```

The repo is private, so clone over HTTPS needs an authenticated `gh` login or a
personal access token. SSH works too if your key is registered:

```bash
git clone git@github.com:seebu-svg/sportika-app.git
```

`supabase/` (migrations, RLS policies, pgTAP suites, Edge Functions) is tracked in
git on purpose — post-push edits to a migration then show up as a reviewable diff
instead of silently drifting from the live database.

---

## 2. Prerequisites

| Tool | Version / location | Notes |
|---|---|---|
| Flutter | 3.47.x stable (Dart `^3.13.7`) | The helper scripts expect the SDK at `$HOME/flutter`. |
| Android SDK | platform-tools + build-tools, JDK 17 | Scripts expect `$HOME/Android/Sdk`. |
| Supabase CLI | only for backend work | Needed to apply migrations / run a local stack. |
| Python 3 | Pillow | Only for the asset-generation scripts in `tool/`. |

`flutter` is **not** on `PATH` by default on the reference machine, so prefix every
shell with:

```bash
export PATH="$HOME/flutter/bin:$PATH"
```

The `tool/*.sh` scripts do this themselves, and they also pin `TMPDIR` to the
workspace `.tmp` — do the same for any bare `flutter` command:

```bash
mkdir -p .tmp
export TMPDIR="$PWD/.tmp"
```

This is not cosmetic: `/tmp` on the reference machine is a small tmpfs, and Flutter
and Gradle both fail with `No space left on device` (typically at
`CompressAssetsWorkAction`) once it fills.

### One-time fix after cloning

`android/gradle.properties` pins Gradle's temp dir to an **absolute path on the
original machine**:

```
org.gradle.jvmargs=-Xmx3G ... -Djava.io.tmpdir=/home/til3fishnix001/Desktop/sportika_2026@/.tmp
```

Point it at your own clone or Gradle will write to a directory that does not exist:

```bash
sed -i "s|-Djava.io.tmpdir=.*|-Djava.io.tmpdir=$PWD/.tmp|" android/gradle.properties
```

(Do not commit that edit — it is machine-specific. Keep it out of your push.)

### Install dependencies

```bash
flutter pub get
```

`pubspec.lock` is committed, so resolution is pinned and reproducible.

---

## 3. Run it locally

There are two ways to boot the app, and the difference is one compile-time flag.
Configuration is baked in via `--dart-define`; **there is no `.env` file** and
nothing is read from disk at runtime.

### 3a. Demo mode — no backend, no credentials (start here)

```bash
flutter run --dart-define=DEMO_MODE=true
```

This wires `MockAuthenticationService` plus a seeded on-device store, so sign-in
works offline against fake data. Any connected device or emulator is fine:

```bash
flutter devices              # pick an id, then
flutter run -d <device-id> --dart-define=DEMO_MODE=true
```

### 3b. Live mode — against your Supabase project

Credentials are never committed; they come from the environment and are passed only
as `--dart-define` flags:

```bash
export SUPABASE_URL=https://<your-ref>.supabase.co
export SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Then use the iteration wrapper, which checks every prerequisite in one pass and
starts a hot-reload session:

```bash
tool/live.sh --check          # report unmet prereqs + print the command, run nothing
tool/live.sh                  # USB device, debug session with hot reload
tool/live.sh --emulator       # boot an AVD instead (add --emulator=<name> for a specific one)
```

Inside the session: `r` hot reload, `R` hot restart, `s` screenshot, `q` quit.
Hot reload covers Dart edits only — a changed `--dart-define`, a new asset/font in
`pubspec.yaml`, or anything under `android/` needs a re-run, not a reload.

Or drive Flutter directly:

```bash
flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
```

If neither `DEMO_MODE` nor a complete credential pair is supplied, the app does
**not** silently pick a backend: `AppEnv.authBackend` resolves to `unavailable`,
auth fail-closes, and the sign-in screen says the service is not connected.

### Compile-time flags

| Flag | Type | Default | Effect |
|---|---|---|---|
| `DEMO_MODE` | bool | `false` | Device-only seeded demo world; no network calls. |
| `SUPABASE_URL` | string | empty | Project URL. Required for live mode. |
| `SUPABASE_PUBLISHABLE_KEY` | string | empty | Preferred key; falls back to `SUPABASE_ANON_KEY`. |
| `SUPABASE_ANON_KEY` | string | empty | Legacy fallback only. |
| `EMAIL_VERIFICATION` | bool | `false` | When `true`, signup requires a 6-digit email code. Must match the project's *Confirm email* setting. |
| `TERMS_VERSION` | string | built-in | Version string the profile-setup gate accepts. |

---

## 4. Build an APK

```bash
tool/build_live.sh --check     # pre-flight the backend, build nothing
tool/build_live.sh             # release APK (needs SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY)
tool/build_live.sh --split     # per-ABI APKs (arm64 / armeabi-v7a)
tool/build_live.sh --demo      # release APK with DEMO_MODE=true, skips the pre-flight
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

The pre-flight fails the build before Gradle starts unless the live project is
actually ready: REST reachability (`/rest/v1/profiles`), GoTrue health, email
provider enabled, `EMAIL_VERIFICATION` matching the project's confirmation setting,
the `avatars` / `team-media` / `tournament-media` / `match-media` buckets existing
as public-read, and the tables this build writes (`module_media`, `matches`,
`profiles.avatar_path`) existing with the expected columns.

Install on a device:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Debug builds share the `pk.sportika.mobile` applicationId and the debug signing key,
so installing one **replaces** the release app (app data survives). To put the
release artifact back afterwards you need `-d`: a split-per-ABI debug build carries
versionCode `2001` versus the fat release at `1`, so Android refuses the restore as
a downgrade without it.

```bash
adb install -r -d build/app/outputs/flutter-apk/app-release.apk
```

Release signing currently falls back to the debug keystore
(`android/app/build.gradle.kts`), so these APKs are for local testing, not Play.

---

## 5. Test and verify

```bash
tool/verify.sh              # dart format check + flutter analyze + flutter test
tool/verify.sh --apk        # the above, then a debug APK build
```

`tool/verify.sh` is the canonical gate. It treats a green exit code as insufficient,
because `flutter_tools` can fail to load a test file and still exit 0 — the run
transcript must contain `All tests passed!` and no `[E]` lines.

Individual suites (63 files under `test/`, all against in-memory fixtures — no live
backend needed):

```bash
flutter test test/<name>_test.dart
```

For a scoped Dart change, the accepted gate is targeted rather than the full APK
build:

```bash
dart format --set-exit-if-changed --output=none lib test tool
flutter analyze
flutter test test/<affected>_test.dart
```

Integration journeys need a real device or emulator and will refuse to run headless:

```bash
flutter test integration_test/journeys_test.dart -d <device-id>
```

---

## 6. Backend (optional — only to run your own Supabase)

The frontend talks to whatever `SUPABASE_URL` you pass, so skip this section entirely
if you are just running the app in demo mode.

Schema is versioned as ordered SQL in `supabase/migrations/` (`0001`–`0026`).
`supabase/config.toml` configures the local stack; it is not read by the Flutter app.

Apply to a linked project:

```bash
supabase link --project-ref <ref>
supabase db push
```

Prove a migration is safe over an existing schema by running the pending files a
**second** time against a freshly populated local database — first pass to build the
schema, second pass to catch non-idempotent statements. Read-only introspection of
the linked project works without any DB password:

```bash
supabase db query --linked "select count(*) from storage.buckets"
```

Note the SQL is a positional argument (there is no `-c` flag), `--linked` must be
explicit, and `supabase migration list --linked` shows only *recorded* versions — it
will not reveal changes applied by hand on the dashboard.

pgTAP suites for the backend live in `supabase/tests/` (15 files).

Regenerate bundled assets if you change branding or sport photography:

```bash
python3 tool/generate_branding.py     # icons, launchers, splash, tokens.json
python3 tool/process_medal_assets.py  # achievement medal graphics
python3 tool/fetch_sport_photos.py    # assets/images/sports/*.jpg
```

Fonts (Inter, Barlow Condensed — SIL OFL) and all images are bundled locally via the
`flutter.assets` / `flutter.fonts` sections of `pubspec.yaml`, never fetched at runtime.

---

## 7. Layout

```
lib/
  main.dart            composition root: picks demo / live / unavailable backend
  app/                 env.dart (all config), providers, routes, error handling
  core/                domain models, controllers, repository interfaces +
                       local and Supabase implementations (core/data/)
  features/            one folder per feature: discover, matches, personal games,
                       profile, teams, live scoring, monetization, onboarding
  shared/              reusable widgets, layout scaffolds, local JSON store
assets/                branding, fonts, medals, sport photos
supabase/              migrations, RLS, pgTAP tests, Edge Functions
test/                  unit + widget tests against in-memory fixtures
tool/                  live.sh, build_live.sh, verify.sh, asset generators
```

Navigation is five tabs — Home / Tournament / Match / Team / Me. Roles are player and
organizer only; there is no admin function in this app.

---

## 8. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `flutter: command not found` | `export PATH="$HOME/flutter/bin:$PATH"` |
| Build dies with `No space left on device` | `/tmp` is a small tmpfs — `export TMPDIR="$PWD/.tmp"` and fix `android/gradle.properties` (see §2) |
| `engine.stamp.tmp.NNNN: Read-only file system` during an analyze/build | Your shell has mounted the SDK read-only; re-run the same command with write access to `$HOME/flutter` |
| App launches, sign-in says the service is not connected | No `SUPABASE_URL`/key and no `DEMO_MODE` → backend resolved to `unavailable` by design |
| Everything errors after launch on an emulator | `SUPABASE_URL` points at `localhost`/`127.0.0.1`, which a device cannot reach; for a local `supabase start` stack use `http://10.0.2.2:54321` |
| Signup ends in a dead-end or `EmailVerificationRequired` | `EMAIL_VERIFICATION` disagrees with the project's *Confirm email* setting; pass the matching value |
| Release APK won't install after a debug session | Use `adb install -r -d` (versionCode `2001` vs `1` downgrade refusal) |
| First screen is black for ~15-20s | Normal JIT cold start for a debug build, not a crash |
| Gradle fails on a fresh clone | `java.io.tmpdir` still points at the original machine's path (see §2) |

---

## 9. Quickstart recap

```bash
git clone https://github.com/seebu-svg/sportika-app.git
cd sportika-app
export PATH="$HOME/flutter/bin:$PATH"
mkdir -p .tmp && export TMPDIR="$PWD/.tmp"
sed -i "s|-Djava.io.tmpdir=.*|-Djava.io.tmpdir=$PWD/.tmp|" android/gradle.properties
flutter pub get
flutter run --dart-define=DEMO_MODE=true      # no backend needed
```
