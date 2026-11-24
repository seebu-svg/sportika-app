#!/usr/bin/env bash
# Padel scoring concurrency smoke.
#
# The pgTAP suites run in one transaction, so they can prove what an RPC does
# but never what two of them do at the same time. This script drives two real
# psql sessions against the same match and checks the four things the design
# promises:
#
#   1. the same client event id sent twice, concurrently, lands exactly once;
#   2. two different event ids both land, with sequential seq values and a
#      monotonically rising revision (the row lock serializes them);
#   3. the projection still agrees with the event log afterwards;
#   4. a point queued against a paused match is refused, and scoring resumes;
#   5. two sessions that complete the same finished match leave exactly one
#      official row, holding the score the fold derived, not any payload.
#
# The sessions authenticate the way the local harness does - `set local role
# authenticated` plus a request.jwt.claims JWT - which needs a connection that
# may assume roles (the scratch postgres superuser, or Supabase's SQL editor /
# service connection). Override with PGHOST / PGPORT / PGUSER / PGPASSWORD /
# PGDATABASE; against the live project use the IPv4 session pooler database.
#
# Everything it creates is a throwaway: a dedicated pair of auth users and one
# match, deleted again at the end whether the run passed or failed.
set -uo pipefail

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-55432}"
export PGUSER="${PGUSER:-postgres}"
export PGDATABASE="${PGDATABASE:-postgres}"
export PGPASSWORD="${PGPASSWORD:-probe}"
export PGSSLMODE="${PGSSLMODE:-disable}"

ORG='a1000000-0000-4000-8000-000000000001'
PLY='a1000000-0000-4000-8000-000000000002'
TITLE='CONCURRENCY SMOKE padel match'

TMP="$(mktemp -d "${TMPDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.tmp}/padel-concurrency-XXXXXX")"
FAILED=0

say() { printf '%s\n' "$*"; }
pass() { printf 'ok   - %s\n' "$*"; }
fail() { printf 'FAIL - %s\n' "$*"; FAILED=$((FAILED + 1)); }

# check <description> <expected> <actual>
check() {
  if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi
}

q() { psql -v ON_ERROR_STOP=1 -q -tA -c "$1" 2>/dev/null | tr -d '\n' | sed -E 's/^[[:space:]]+//'; }
run() { psql -v ON_ERROR_STOP=1 -q -f - >/dev/null; }

# Both racing workers wait for one wall-clock instant, then fire.
barrier() { date -d '+3 seconds' '+%Y-%m-%d %H:%M:%S%z'; }

race_worker() { # <barrier> <claims> <client-id> <out-file>
  psql -v ON_ERROR_STOP=1 -q -tA \
       -v barrier="$1" -v claims="$2" -v client="$3" -v match="$MATCH" \
       -f "$TMP/race.sql" > "$4" 2>&1
}

cleanup() {
  psql -v ON_ERROR_STOP=0 -q -c \
    "delete from public.matches where title = '$TITLE';
     delete from auth.users where id in ('$ORG', '$PLY');" >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

# ── fixture: two throwaway members and one started match ─────────────────────
psql -v ON_ERROR_STOP=1 -q -c \
  "delete from public.matches where title = '$TITLE';
   delete from auth.users where id in ('$ORG', '$PLY');" >/dev/null

psql -v ON_ERROR_STOP=1 -q -f - >/dev/null <<SQL
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('$ORG', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'smoke-organizer@sportika.test', '\$2a\$10\$notarealhashnotarealhashno',
   now(), now(), now(), '{"provider":"email","providers":["email"]}',
   '{"display_name":"Smoke Organizer"}'),
  ('$PLY', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'smoke-player@sportika.test', '\$2a\$10\$notarealhashnotarealhashno',
   now(), now(), now(), '{"provider":"email","providers":["email"]}',
   '{"display_name":"Smoke Player"}')
on conflict (id) do nothing;
SQL

psql -v ON_ERROR_STOP=1 -q -f - >/dev/null <<SQL
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"$ORG","role":"authenticated","aud":"authenticated"}';
select public.create_match(
  'padel', 'One set · first to 4', '{"setsToWin":1,"gamesToWinSet":4}'::jsonb,
  '$TITLE', 'Smoke Court', now() + interval '1 hour', 'invite',
  'Smoke Organizer', 'Smoke Player', 4, 'singles');
select public.invite_match_participant(
  (select id from public.matches where title = '$TITLE'), '$PLY'::uuid, 1);
commit;
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"$PLY","role":"authenticated","aud":"authenticated"}';
select public.respond_match_invite(
  (select id from public.matches where title = '$TITLE'), true);
commit;
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"$ORG","role":"authenticated","aud":"authenticated"}';
select public.start_padel_match(
  (select id from public.matches where title = '$TITLE'), 0, 0);
commit;
SQL

MATCH="$(q "select id from public.matches where title = '$TITLE'")"

if [[ ! $MATCH =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  say "could not create the smoke match (got [$MATCH]); is the harness migrated?"
  exit 1
fi
say "match $MATCH"

cat > "$TMP/race.sql" <<'SQL'
begin;
set local role authenticated;
set local request.jwt.claims = :'claims';
select pg_sleep_until(:'barrier'::timestamptz);
select (public.award_padel_point(:'match'::uuid, 0, :'client'))::text;
commit;
SQL

# ── 1. the same client event id, twice, at the same time ────────────────────
say ''
say 'race 1: one client event id from two sessions'
B="$(barrier)"
race_worker "$B" "{\"sub\":\"$ORG\",\"role\":\"authenticated\",\"aud\":\"authenticated\"}" \
            'smoke-duplicate' "$TMP/r1a.log" &
A1=$!
race_worker "$B" "{\"sub\":\"$ORG\",\"role\":\"authenticated\",\"aud\":\"authenticated\"}" \
            'smoke-duplicate' "$TMP/r1b.log" &
A2=$!
wait "$A1" "$A2"

check 'the duplicate id produced one event' 1 \
  "$(q "select count(*) from public.match_events
         where match_id = '$MATCH' and client_event_id = 'smoke-duplicate'")"
check 'one session was told it was a replay' 1 \
  "$(grep -l '"deduplicated": true' "$TMP"/r1*.log | wc -l | tr -d ' ')"
check 'the other session recorded the point' 1 \
  "$(grep -l '"deduplicated": false' "$TMP"/r1*.log | wc -l | tr -d ' ')"
check 'the projection counted one point' 1 \
  "$(q "select point_count from public.padel_match_state where match_id = '$MATCH'")"

# ── 2. two different client event ids at the same time ──────────────────────
say ''
say 'race 2: two different client event ids'
B="$(barrier)"
race_worker "$B" "{\"sub\":\"$ORG\",\"role\":\"authenticated\",\"aud\":\"authenticated\"}" \
            'smoke-left' "$TMP/r2a.log" &
A1=$!
race_worker "$B" "{\"sub\":\"$ORG\",\"role\":\"authenticated\",\"aud\":\"authenticated\"}" \
            'smoke-right' "$TMP/r2b.log" &
A2=$!
wait "$A1" "$A2"

check 'both points were kept' 2 \
  "$(q "select count(*) from public.match_events
         where match_id = '$MATCH' and client_event_id in ('smoke-left', 'smoke-right')")"
check 'the two events got distinct seq values' 2 \
  "$(q "select count(distinct seq) from public.match_events
         where match_id = '$MATCH' and client_event_id in ('smoke-left', 'smoke-right')")"
check 'seq stayed dense with no gap' 3 \
  "$(q "select max(seq) from public.match_events where match_id = '$MATCH'")"
check 'the revision advanced once per state change' 4 \
  "$(q "select revision from public.padel_match_state where match_id = '$MATCH'")"
check 'the projection agrees with the event log' 3 \
  "$(q "select point_count from public.padel_match_state where match_id = '$MATCH'")"
check 'both racing events sit at seq 2 and 3' 2 \
  "$(q "select count(*) from public.match_events
         where match_id = '$MATCH' and seq in (2, 3)")"

# ── 3. a point arriving while the match is paused ───────────────────────────
say ''
say 'race 3: an award queued against a pause'
B3="$(barrier)"
race_worker "$B3" "{\"sub\":\"$ORG\",\"role\":\"authenticated\",\"aud\":\"authenticated\"}" \
            'smoke-while-paused' "$TMP/r3.log" &
A3=$!
# The pause is committed while the worker is still waiting on its barrier, so
# the award is the one that has to notice it.
psql -v ON_ERROR_STOP=1 -q -f - >/dev/null <<SQL
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"$ORG","role":"authenticated","aud":"authenticated"}';
select public.pause_match((select id from public.matches where title = '$TITLE'), 'smoke pause');
commit;
SQL
wait "$A3"
check 'the queued point was refused' 1 "$(grep -c 'match_paused' "$TMP/r3.log")"
check 'it left no event behind' 0 \
  "$(q "select count(*) from public.match_events
         where match_id = '$MATCH' and client_event_id = 'smoke-while-paused'")"
check 'the score did not move while paused' 3 \
  "$(q "select point_count from public.padel_match_state where match_id = '$MATCH'")"

psql -v ON_ERROR_STOP=1 -q -f - >/dev/null <<SQL
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"$ORG","role":"authenticated","aud":"authenticated"}';
select public.resume_match((select id from public.matches where title = '$TITLE'));
select public.award_padel_point((select id from public.matches where title = '$TITLE'), 1, 'smoke-after-resume');
commit;
SQL

check 'scoring works again after the resume' 4 \
  "$(q "select point_count from public.padel_match_state where match_id = '$MATCH'")"

# ── 4. two sessions complete the same match at the same time ────────────────
say ''
say 'race 4: two completions of one finished match'

# Finish the set first, through the RPC the app uses: the fixture plays to four
# games, side A has three points of the current game on the board and the
# player has one, so thirteen awards to side A closes the match at 4-0.
CLOSE=""
for i in $(seq 1 13); do
  CLOSE+="select public.award_padel_point('$MATCH'::uuid, 0, 'smoke-close-$i');"
  CLOSE+=$'\n'
done
psql -v ON_ERROR_STOP=1 -q -f - >/dev/null <<SQL
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"$ORG","role":"authenticated","aud":"authenticated"}';
$CLOSE
commit;
SQL

cat > "$TMP/complete.sql" <<'SQL'
begin;
set local role authenticated;
set local request.jwt.claims = :'claims';
select pg_sleep_until(:'barrier'::timestamptz);
select (public.complete_padel_match(:'match'::uuid)).*;
commit;
SQL

complete_worker() { # <barrier> <out-file>
  psql -v ON_ERROR_STOP=0 -q -tA \
       -v barrier="$1" \
       -v claims='{"sub":"'"$ORG"'","role":"authenticated","aud":"authenticated"}' \
       -v match="$MATCH" -f "$TMP/complete.sql" > "$2" 2>&1
}

B4="$(barrier)"
complete_worker "$B4" "$TMP/r4a.log" &
C1=$!
complete_worker "$B4" "$TMP/r4b.log" &
C2=$!
wait "$C1" "$C2"

# One row, the first completion's, holding both reading orders the fold says -
# which is what the row lock plus the lifecycle guard must guarantee however
# many devices tap Submit.
check 'exactly one official row' 1 \
  "$(q "select count(*) from public.match_results where match_id = '$MATCH'")"
check 'the winner was refused the second completion' 1 \
  "$(grep -l 'invalid_match_transition' "$TMP"/r4*.log | wc -l | tr -d ' ')"
check 'the other completed it' 1 \
  "$(grep -l '4-0' "$TMP"/r4*.log | wc -l | tr -d ' ')"
check 'the row carries the derived strings, both orders' t \
  "$(q "select side_scores = jsonb_build_array('4-0', '0-4')
         from public.match_results where match_id = '$MATCH'")"
check 'the match is in review, not live' submitted \
  "$(q "select status from public.matches where id = '$MATCH'")"

# ── 5. teardown really cleans up ────────────────────────────────────────────
say ''
say 'teardown'
psql -v ON_ERROR_STOP=1 -q -c \
  "delete from public.matches where title = '$TITLE';
   delete from auth.users where id in ('$ORG', '$PLY');" >/dev/null

check 'the throwaway match is gone' 0 \
  "$(q "select count(*) from public.matches where title = '$TITLE'")"
check 'its events went with it' 0 \
  "$(q "select count(*) from public.match_events where match_id = '$MATCH'")"
check 'its official row went with it' 0 \
  "$(q "select count(*) from public.match_results where match_id = '$MATCH'")"
check 'the throwaway state row is gone' 0 \
  "$(q "select count(*) from public.padel_match_state where match_id = '$MATCH'")"
check 'the throwaway users are gone' 0 \
  "$(q "select count(*) from auth.users where id in ('$ORG', '$PLY')")"

say ''
if [[ "$FAILED" -gt 0 ]]; then
  say "concurrency smoke: $FAILED check(s) failed"
  exit 1
fi
say 'concurrency smoke: all checks passed'
