-- The padel scoring engine, exercised through the same RPCs the app calls.
--
-- Everything here runs against the real functions, the real constraints and the
-- real projection tables; nothing is mocked. The point-sequence helpers below
-- only ever call award_padel_point, so every assertion is about server-derived
-- state, never about a score the test computed on the client's behalf.
--
-- Fixed uuids stand in for four members. Ayesha organizes every match, Sana is
-- the opponent/partner, Bilal and Dania fill the second doubles side.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(84);

-- ── point-sequence helpers ──────────────────────────────────────────────────
create sequence if not exists public._tap_point_seq;
-- The helpers run as the authenticated role, which has no default sequence grant.
grant usage, select on sequence public._tap_point_seq to authenticated;

create or replace function public._tap_id(p_title text)
returns uuid
language sql stable
as $$ select id from public.matches where title = p_title $$;

create or replace function public._tap_award(p_match uuid, p_sides int[])
returns void
language plpgsql
as $$
declare
  i int;
begin
  for i in 1..coalesce(array_length(p_sides, 1), 0) loop
    perform public.award_padel_point(
      p_match, p_sides[i], 'tap-' || nextval('public._tap_point_seq')::text);
  end loop;
end;
$$;

-- Wins p_games games to zero. Only valid while the current game is at 0-0.
create or replace function public._tap_games(p_match uuid, p_side int, p_games int)
returns void
language plpgsql
as $$
declare
  i int;
  j int;
begin
  for i in 1..greatest(coalesce(p_games, 0), 0) loop
    for j in 1..4 loop
      perform public.award_padel_point(
        p_match, p_side, 'tap-' || nextval('public._tap_point_seq')::text);
    end loop;
  end loop;
end;
$$;

-- One game each, p_each times, so a set reaches 6-6 instead of 6-0.
create or replace function public._tap_alternate(p_match uuid, p_each int)
returns void
language plpgsql
as $$
declare
  i int;
begin
  for i in 1..greatest(coalesce(p_each, 0), 0) loop
    perform public._tap_games(p_match, 0, 1);
    perform public._tap_games(p_match, 1, 1);
  end loop;
end;
$$;

-- ── fixtures ────────────────────────────────────────────────────────────────
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('11111111-1111-1111-1111-111111111111',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ayesha@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
   now(), now(), '{"provider":"email","providers":["email"]}',
   '{"display_name":"Ayesha Khan"}'),
  ('22222222-2222-2222-2222-222222222222',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'bilal@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
   now(), now(), '{"provider":"email","providers":["email"]}',
   '{"display_name":"Bilal Ahmed"}'),
  ('33333333-3333-3333-3333-333333333333',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'sana@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
   now(), now(), '{"provider":"email","providers":["email"]}',
   '{"display_name":"Sana Iqbal"}'),
  ('44444444-4444-4444-4444-444444444444',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'dania@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
   now(), now(), '{"provider":"email","providers":["email"]}',
   '{"display_name":"Dania Malik"}');

-- ── schema shape ────────────────────────────────────────────────────────────
select ok(
  (select bool_and(relrowsecurity) from pg_class
    where oid in ('public.padel_match_state'::regclass,
                  'public.padel_match_sets'::regclass,
                  'public.match_disputes'::regclass)),
  'row level security is enabled on the padel projection tables');

select ok(
  (select not bool_or(relforcerowsecurity) from pg_class
    where oid in ('public.padel_match_state'::regclass,
                  'public.padel_match_sets'::regclass,
                  'public.match_disputes'::regclass)),
  'row level security is enabled but not forced, so definer RPCs can write');

select ok(
  not has_table_privilege('authenticated', 'public.padel_match_state', 'INSERT')
  and not has_table_privilege('authenticated', 'public.padel_match_state', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.padel_match_sets', 'INSERT')
  and not has_table_privilege('authenticated', 'public.match_disputes', 'INSERT'),
  'members hold no write grant on any new padel table');

select ok(
  exists (select 1 from pg_trigger
           where tgname = 'match_events_guard'
             and tgrelid = 'public.match_events'::regclass),
  'the event log carries an immutability trigger');

select ok(
  (select count(*)::int from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename in ('padel_match_state', 'padel_match_sets', 'match_disputes')) = 3,
  'the scoreboard, the set records and the disputes are published to Realtime');

-- ── organizer creates the match set ─────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.create_match(
  'padel', 'Best of 3', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'S1 advantage singles', 'Court 1', '2026-03-01 18:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
select public.create_match(
  'padel', 'Best of 3 · golden point', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'S2 golden point', 'Court 2', '2026-03-01 19:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
select public.create_match(
  'padel', 'Best of 3 · tie-break', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'S4 tiebreak', 'Court 3', '2026-03-01 20:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
select public.create_match(
  'padel', 'Best of 3 · super tie-break', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'S5 super tiebreak', 'Court 4', '2026-03-01 21:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
select public.create_match(
  'padel', 'Best of 5 sets', '{"setsToWin":3,"gamesToWinSet":6}'::jsonb,
  'S6 best of five', 'Court 5', '2026-03-02 18:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
select public.create_match(
  'padel', 'Best of 3 · doubles', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'S7 doubles rotation', 'Court 6', '2026-03-02 19:00+05', 'public',
  'Ayesha K & Sana I', 'Bilal A & Dania M', 4, 'doubles', null);
select public.create_match(
  'padel', 'Best of 3 · doubles', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'S8 overflow', 'Court 7', '2026-03-02 20:00+05', 'public',
  'Ayesha K & Sana I', 'Dania M', 4, 'doubles', null);
select public.create_match(
  'padel', 'Best of 3', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'S9 first server', 'Court 8', '2026-03-02 21:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
select public.create_match(
  'padel', 'Best of 3', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'S10 empty roster', 'Court 9', '2026-03-02 22:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
select public.create_match(
  'badminton', 'Best of 3 · 21', '{}'::jsonb, 'B1 not padel',
  'Hall 1', '2026-03-03 10:00+05', 'public',
  'Ayesha K', 'Sana I', 2, 'singles', null);

select public.invite_match_participant(public._tap_id('S1 advantage singles'),  '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('S2 golden point'),      '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('S4 tiebreak'),          '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('S5 super tiebreak'),    '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('S6 best of five'),      '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('S7 doubles rotation'),  '33333333-3333-3333-3333-333333333333', 0);
select public.invite_match_participant(public._tap_id('S7 doubles rotation'),  '22222222-2222-2222-2222-222222222222', 1);
select public.invite_match_participant(public._tap_id('S7 doubles rotation'),  '44444444-4444-4444-4444-444444444444', 1);
select public.invite_match_participant(public._tap_id('S8 overflow'),          '33333333-3333-3333-3333-333333333333', 0);
select public.invite_match_participant(public._tap_id('S8 overflow'),          '44444444-4444-4444-4444-444444444444', 0);
select public.invite_match_participant(public._tap_id('S9 first server'),      '33333333-3333-3333-3333-333333333333', 1);

-- ── invitees accept ─────────────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';
select public.respond_match_invite(public._tap_id('S1 advantage singles'), true);
select public.respond_match_invite(public._tap_id('S2 golden point'), true);
select public.respond_match_invite(public._tap_id('S4 tiebreak'), true);
select public.respond_match_invite(public._tap_id('S5 super tiebreak'), true);
select public.respond_match_invite(public._tap_id('S6 best of five'), true);
select public.respond_match_invite(public._tap_id('S7 doubles rotation'), true);
select public.respond_match_invite(public._tap_id('S8 overflow'), true);
select public.respond_match_invite(public._tap_id('S9 first server'), true);

set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated"}';
select public.respond_match_invite(public._tap_id('S7 doubles rotation'), true);

set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';
select public.respond_match_invite(public._tap_id('S7 doubles rotation'), true);
select public.respond_match_invite(public._tap_id('S8 overflow'), true);

-- ── configuration validation (as organizer) ─────────────────────────────────
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select ok(
  (public.configure_padel_match(
     public._tap_id('S1 advantage singles'),
     '{"setsToWin":2,"gamesToWinSet":6,"tiebreakPoints":7,"noAd":false,
       "matchTiebreak":false,"firstServerSide":0,"firstServerMember":0}'::jsonb)
  ).rules @> '{"setsToWin":2,"gamesToWinSet":6,"tiebreakAt":6,"noAd":false}'::jsonb,
  'configure_padel_match normalises the rule map the fold reads');

select throws_ok(
  $$ select public.configure_padel_match(
       public._tap_id('S9 first server'), '{"setsToWin":5}'::jsonb) $$,
  '22023', null,
  'a best-of-five-sets-to-win value outside 1..3 is refused');

select throws_ok(
  $$ select public.configure_padel_match(
       public._tap_id('S9 first server'),
       '{"setsToWin":1,"matchTiebreak":true}'::jsonb) $$,
  '22023', null,
  'a match tie-break cannot be configured without a deciding set');

select throws_ok(
  $$ select public.configure_padel_match(
       public._tap_id('B1 not padel'), '{"setsToWin":2}'::jsonb) $$,
  '22023', null,
  'the padel configuration RPC refuses another sport');

-- ════════════════════════════════════════════════════════════════════════════
-- S1: advantage singles, standard sets
-- ════════════════════════════════════════════════════════════════════════════
select public.start_padel_match(public._tap_id('S1 advantage singles'), 0, 0);

select is(
  (select (status, revision, points, games, serving_side, point_count)::text
     from public.padel_match_state where match_id = public._tap_id('S1 advantage singles')),
  '(live,1,"[0, 0]","[0, 0]",0,0)',
  'starting a padel match seeds a live scoreboard at revision 1');

select throws_ok(
  $$ select public.start_padel_match(public._tap_id('S1 advantage singles')) $$,
  '22023', null,
  'a match that is already live cannot be started again');

select public._tap_award(public._tap_id('S1 advantage singles'), '{0}');
select is(
  (select points from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  '[1, 0]'::jsonb, 'one point moves the server to 15');

select public._tap_award(public._tap_id('S1 advantage singles'), '{0,0}');
select is(
  (select points from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  '[3, 0]'::jsonb, 'three points without reply is 40-0');

select public._tap_award(public._tap_id('S1 advantage singles'), '{0}');
select is(
  (select (points, games)::text from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  '("[0, 0]","[1, 0]")',
  'the fourth point wins the game and resets the point counters');

select is(
  (select serving_side::int from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  1, 'service passes to the other side after a game');

select ok(
  (select revision from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')) >= 5,
  'every mutation bumps the scoreboard revision');

-- deuce / advantage inside game two
select public._tap_award(public._tap_id('S1 advantage singles'), '{0,0,0,1,1,1}');
select is(
  (select points from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  '[3, 3]'::jsonb, '3-3 is deuce, not a finished game');

select public._tap_award(public._tap_id('S1 advantage singles'), '{1}');
select is(
  (select points from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  '[3, 4]'::jsonb, 'one point past deuce is advantage, still no game');

select public._tap_award(public._tap_id('S1 advantage singles'), '{0}');
select is(
  (select points from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  '[4, 4]'::jsonb, 'winning on advantage returns the game to deuce');

select public._tap_award(public._tap_id('S1 advantage singles'), '{0,0}');
select is(
  (select (points, games)::text from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  '("[0, 0]","[2, 0]")',
  'two points clear from deuce wins the game');

-- set completion 6-0
select public._tap_games(public._tap_id('S1 advantage singles'), 0, 4);
select is(
  (select (games, sets_won)::text from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  '("[0, 0]","[1, 0]")',
  'a sixth game with a two-game margin completes the set and clears the games');

select is(
  (select (side_a_games, side_b_games, winner_side, tiebreak)::text
     from public.padel_match_sets where match_id = public._tap_id('S1 advantage singles')),
  '(6,0,0,f)', 'the completed set is recorded as a 6-0 set for side A');

select ok(
  (select point_seq_start is not null and point_seq_end >= point_seq_start
     from public.padel_match_sets where match_id = public._tap_id('S1 advantage singles')),
  'the set record keeps the event range it was folded from');

-- idempotency
create temp table _tap_probe (k text primary key, v text);
insert into _tap_probe
select 'revision', revision::text from public.padel_match_state
 where match_id = public._tap_id('S1 advantage singles');

select is(
  (public.award_padel_point(
     public._tap_id('S1 advantage singles'), 0, 'dup-1'))->>'deduplicated',
  'false', 'a new client event id is not reported as deduplicated');

insert into _tap_probe
select 'revision-after-dup', revision::text from public.padel_match_state
 where match_id = public._tap_id('S1 advantage singles')
on conflict (k) do update set v = excluded.v;

select is(
  (public.award_padel_point(
     public._tap_id('S1 advantage singles'), 0, 'dup-1'))->>'deduplicated',
  'true', 'replaying the same client event id is reported as deduplicated');

select is(
  (select count(*)::int from public.match_events
    where match_id = public._tap_id('S1 advantage singles')
      and client_event_id = 'dup-1'),
  1, 'the retried client event id exists exactly once');

select is(
  (select revision::text from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  (select v from _tap_probe where k = 'revision-after-dup'),
  'a deduplicated retry does not bump the revision');

-- undo
select is(
  (public.undo_last_padel_point(public._tap_id('S1 advantage singles'), 'wrong side'))->'state'->'points',
  '[0, 0]'::jsonb, 'undo withdraws the newest point and restores the score before it');

select ok(
  (select voided and voided_by = '11111111-1111-1111-1111-111111111111'
          and voided_at is not null and void_reason = 'wrong side'
     from public.match_events
    where match_id = public._tap_id('S1 advantage singles')
      and client_event_id = 'dup-1'),
  'the withdrawn event keeps who, when and why, and is not deleted');

select ok(
  exists (select 1 from public.match_lifecycle_log
           where match_id = public._tap_id('S1 advantage singles')
             and action = 'point_undone'),
  'the undo is written to the lifecycle audit trail');

-- correction of an older event
select public._tap_award(public._tap_id('S1 advantage singles'), '{1,1,1}');
select is(
  (public.correct_padel_event(
     public._tap_id('S1 advantage singles'),
     (select id from public.match_events
       where match_id = public._tap_id('S1 advantage singles')
         and kind = 'point' and side = 1 and not voided
       order by seq desc limit 1),
     'wrong player touched'))->'state'->'points',
  '[0, 2]'::jsonb,
  'correcting an older point recomputes the whole score from the remaining log');

select throws_ok(
  $$ select public.correct_padel_event(
       public._tap_id('S1 advantage singles'),
       (select id from public.match_events
         where match_id = public._tap_id('S1 advantage singles')
           and kind = 'point' and not voided order by seq limit 1),
       'no') $$,
  '22023', null,
  'a correction without a usable reason is refused');

-- pause / resume
select ok(
  (select paused_at is not null and paused_by = '11111111-1111-1111-1111-111111111111'
          and pause_reason = 'court flooded'
     from public.pause_match(public._tap_id('S1 advantage singles'), 'court flooded')),
  'pausing records who paused the match and why');

select is(
  (select status from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  'paused', 'the scoreboard projection mirrors the paused state');

select throws_ok(
  $$ select public.award_padel_point(
       public._tap_id('S1 advantage singles'), 0, 'paused-1') $$,
  '22023', null,
  'no point can be awarded while the match is paused');

select ok(
  (select paused_at is null and pause_reason is null
     from public.resume_match(public._tap_id('S1 advantage singles'))),
  'resuming clears the pause markers');

select is(
  (select status from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  'live', 'the projection returns to live on resume');

-- snapshot contract
select ok(
  (select s ?& array['matchId','revision','state','sets','serving','events',
                      'result','disputes','canScore','isComplete','winnerSide']
     from (select public.get_padel_scoreboard(public._tap_id('S1 advantage singles')) s) q),
  'the reconnect snapshot carries state, sets, events, result and disputes');

select is(
  (public.get_padel_scoreboard(public._tap_id('S1 advantage singles')))->>'canScore',
  'true', 'the organizer is told they may score');

select is(
  (public.get_padel_scoreboard(public._tap_id('S1 advantage singles')))->'state'->'points',
  (select points from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  'the served state and the projection agree on the point counters');

select is(
  (public.get_padel_scoreboard(public._tap_id('S1 advantage singles')))->'state'->'setsWon',
  (select sets_won from public.padel_match_state
    where match_id = public._tap_id('S1 advantage singles')),
  'the served state and the projection agree on the sets won');

-- ════════════════════════════════════════════════════════════════════════════
-- S2: golden point
-- ════════════════════════════════════════════════════════════════════════════
select public.configure_padel_match(
  public._tap_id('S2 golden point'), '{"noAd":true}'::jsonb);

select is(
  (select rules ->> 'noAd' from public.matches
    where id = public._tap_id('S2 golden point')),
  'true', 'golden point is a stored rule, not a client preference');

select public.start_padel_match(public._tap_id('S2 golden point'), 0, 0);
select public._tap_award(public._tap_id('S2 golden point'), '{0,0,0,1,1,1}');

select is(
  (select (points, in_tiebreak)::text from public.padel_match_state
    where match_id = public._tap_id('S2 golden point')),
  '("[3, 3]",f)', 'a golden-point match still sits at deuce before the decider');

select public._tap_award(public._tap_id('S2 golden point'), '{1}');

select is(
  (select (points, games)::text from public.padel_match_state
    where match_id = public._tap_id('S2 golden point')),
  '("[0, 0]","[0, 1]")',
  'the next point after deuce wins the game outright under golden point');

-- ════════════════════════════════════════════════════════════════════════════
-- S4: tie-break at 6-6
-- ════════════════════════════════════════════════════════════════════════════
select public.start_padel_match(public._tap_id('S4 tiebreak'), 0, 0);
select public._tap_alternate(public._tap_id('S4 tiebreak'), 6);

select is(
  (select (games, in_tiebreak)::text from public.padel_match_state
    where match_id = public._tap_id('S4 tiebreak')),
  '("[6, 6]",t)', '6-6 starts a tie-break instead of extending the set');

select is(
  (select serving_side::int from public.padel_match_state
    where match_id = public._tap_id('S4 tiebreak')),
  0, 'the tie-break is served by the side whose turn it is at 6-6');

select public._tap_award(public._tap_id('S4 tiebreak'), '{0}');
select is(
  (select (tiebreak_points, serving_side)::text from public.padel_match_state
    where match_id = public._tap_id('S4 tiebreak')),
  '("[1, 0]",1)',
  'service changes after the first point of a tie-break');

select public._tap_award(public._tap_id('S4 tiebreak'), '{0}');
select is(
  (select serving_side::int from public.padel_match_state
    where match_id = public._tap_id('S4 tiebreak')),
  1, 'service stays put for the second tie-break point');

select public._tap_award(public._tap_id('S4 tiebreak'), '{0}');
select is(
  (select serving_side::int from public.padel_match_state
    where match_id = public._tap_id('S4 tiebreak')),
  0, 'service changes again after every two tie-break points');

select public._tap_award(public._tap_id('S4 tiebreak'), '{0,0,0,0}');

select is(
  (select (games, sets_won, in_tiebreak)::text from public.padel_match_state
    where match_id = public._tap_id('S4 tiebreak')),
  '("[0, 0]","[1, 0]",f)',
  'a 7-0 tie-break wins the set 7-6 and resets the games');

select is(
  (select (side_a_games, side_b_games, tiebreak, tiebreak_points)::text
     from public.padel_match_sets where match_id = public._tap_id('S4 tiebreak')),
  '(7,6,t,"[7, 0]")',
  'the tie-break set keeps its games and its tie-break score');

-- ════════════════════════════════════════════════════════════════════════════
-- S5: super tie-break decider, derived result, publish, reopen
-- ════════════════════════════════════════════════════════════════════════════
select public.configure_padel_match(
  public._tap_id('S5 super tiebreak'), '{"matchTiebreak":true}'::jsonb);
select public.start_padel_match(public._tap_id('S5 super tiebreak'), 0, 0);

select public._tap_games(public._tap_id('S5 super tiebreak'), 0, 6);
select public._tap_games(public._tap_id('S5 super tiebreak'), 1, 6);

select is(
  (select (sets_won, in_tiebreak, decider_tiebreak, games)::text
     from public.padel_match_state
    where match_id = public._tap_id('S5 super tiebreak')),
  '("[1, 1]",t,t,"[0, 0]")',
  'one set each in a match-tie-break format starts the deciding tie-break');

select public._tap_award(public._tap_id('S5 super tiebreak'),
  '{0,0,0,0,0,0,0,0,0,0}');

select is(
  (select (is_complete, winner_side, sets_won)::text
     from public.padel_match_state
    where match_id = public._tap_id('S5 super tiebreak')),
  '(t,0,"[2, 1]")',
  'a 10-0 super tie-break completes the match and names the winner');

select is(
  (select (side_a_games, side_b_games, tiebreak, tiebreak_points)::text
     from public.padel_match_sets
    where match_id = public._tap_id('S5 super tiebreak') and set_index = 2),
  '(1,0,t,"[10, 0]")',
  'the decider is stored as a one-game set with its tie-break score');

select ok(
  (select completed_at is not null and status = 'live'
     from public.matches where id = public._tap_id('S5 super tiebreak')),
  'the match row is stamped complete while the result is still unsubmitted');

select throws_ok(
  $$ select public.award_padel_point(
       public._tap_id('S5 super tiebreak'), 0, 'after-complete') $$,
  '22023', null, 'no point can be awarded once the fold says the match is over');

select throws_ok(
  $$ select public.award_padel_point(
       public._tap_id('S5 super tiebreak'), 2, 'bad-side') $$,
  '22023', null, 'a side outside 0/1 is refused');

select throws_ok(
  $$ select public.award_padel_point(
       public._tap_id('S5 super tiebreak'), null, 'null-side') $$,
  '22023', null, 'a missing side is refused instead of defaulting to side A');

select ok(
  (select side_values = '[2, 1]'::jsonb and winner_index = 0
     from public.complete_padel_match(public._tap_id('S5 super tiebreak'))),
  'complete_padel_match derives sets and winner from the event log');

select is(
  (select side_scores from public.match_results
    where match_id = public._tap_id('S5 super tiebreak')),
  '["6-0, 0-6, 1-0", "0-6, 6-0, 0-1"]'::jsonb,
  'the derived result carries the per-set lines in both orientations');

select is(
  (select headline from public.match_results
    where match_id = public._tap_id('S5 super tiebreak')),
  'Ayesha K won 2-1', 'the derived headline names the winner and the set score');

select is(
  (select status from public.matches where id = public._tap_id('S5 super tiebreak')),
  'submitted', 'a derived result moves the match to submitted, not published');

select is(
  (select status from public.publish_match_result(public._tap_id('S5 super tiebreak'))),
  'published', 'the organizer publishes the derived result');

select ok(
  (select status = 'live' and published_at is null and submitted_at is null
     from public.reopen_padel_match(
       public._tap_id('S5 super tiebreak'), 'wrong winner recorded')),
  'reopening returns the match to live and clears the publication stamps');

select is(
  (select count(*)::int from public.match_result_corrections
    where match_id = public._tap_id('S5 super tiebreak')),
  1, 'reopening preserves the published result in the correction history');

-- ════════════════════════════════════════════════════════════════════════════
-- S6: best of five, client payload checked against the fold
-- ════════════════════════════════════════════════════════════════════════════
select public.start_padel_match(public._tap_id('S6 best of five'), 0, 0);

select public._tap_games(public._tap_id('S6 best of five'), 0, 6);
select public._tap_games(public._tap_id('S6 best of five'), 1, 6);

select is(
  (select is_complete from public.padel_match_state
    where match_id = public._tap_id('S6 best of five')),
  false, 'one set each is not enough in a best-of-five');

select public._tap_games(public._tap_id('S6 best of five'), 0, 6);

select is(
  (select (is_complete, sets_won)::text from public.padel_match_state
    where match_id = public._tap_id('S6 best of five')),
  '(f,"[2, 1]")', 'two sets to one is still short in a best-of-five');

select public._tap_games(public._tap_id('S6 best of five'), 0, 6);

select is(
  (select (is_complete, winner_side, sets_won)::text
     from public.padel_match_state
    where match_id = public._tap_id('S6 best of five')),
  '(t,0,"[3, 1]")', 'winning three sets completes a best-of-five match');

select throws_ok(
  $$ select public.submit_match_result(
       public._tap_id('S6 best of five'), 'Ayesha wins', 'four sets',
       '["6-0","0-6"]'::jsonb, '[2, 1]'::jsonb, 0) $$,
  '22023', null,
  'a client-supplied set total that disagrees with the log is refused');

select throws_ok(
  $$ select public.submit_match_result(
       public._tap_id('S6 best of five'), 'Sana wins', 'four sets',
       '["6-0","0-6"]'::jsonb, '[3, 1]'::jsonb, 1) $$,
  '22023', null,
  'a client-supplied winner that disagrees with the log is refused');

select ok(
  (select winner_index = 0 and side_values = '[3, 1]'::jsonb and walkover = false
     from public.submit_match_result(
       public._tap_id('S6 best of five'), 'Ayesha wins', 'four sets',
       '["6-0, 0-6, 6-0, 6-0", "0-6, 6-0, 0-6, 0-6"]'::jsonb, '[3, 1]'::jsonb, 0)),
  'an agreeing payload is accepted and stored');

select is(
  (select status from public.matches where id = public._tap_id('S6 best of five')),
  'submitted', 'submitting a result closes scoring for the match');

select throws_ok(
  $$ select public.undo_last_padel_point(public._tap_id('S6 best of five'), 'too late') $$,
  '22023', null, 'an undo after submission is refused');

-- ════════════════════════════════════════════════════════════════════════════
-- S7: doubles roster and service order
-- ════════════════════════════════════════════════════════════════════════════
select is(
  (select count(*)::int from public.match_participants
    where match_id = public._tap_id('S7 doubles rotation') and status = 'accepted'),
  4, 'a doubles match accepts two members per side');

select public.start_padel_match(public._tap_id('S7 doubles rotation'), 0, 0);

select is(
  (select (serving_side, serving_member)::text from public.padel_match_state
    where match_id = public._tap_id('S7 doubles rotation')),
  '(0,0)', 'doubles starts with the configured first server');

select public._tap_games(public._tap_id('S7 doubles rotation'), 0, 1);
select is(
  (select (serving_side, serving_member)::text from public.padel_match_state
    where match_id = public._tap_id('S7 doubles rotation')),
  '(1,0)', 'service passes to the other pair after a game');

select public._tap_games(public._tap_id('S7 doubles rotation'), 1, 1);
select is(
  (select (serving_side, serving_member)::text from public.padel_match_state
    where match_id = public._tap_id('S7 doubles rotation')),
  '(0,1)', 'a pair alternates its own two members when it serves again');

-- ════════════════════════════════════════════════════════════════════════════
-- S8 / S9 / S10: roster guards and the configured first server
-- ════════════════════════════════════════════════════════════════════════════
select throws_ok(
  $$ select public.start_padel_match(public._tap_id('S8 overflow')) $$,
  '22023', null,
  'three accepted players on one doubles side is refused at start');

select throws_ok(
  $$ select public.start_padel_match(public._tap_id('S10 empty roster')) $$,
  '22023', null,
  'a match with nobody on the opposing side cannot start');

select public.configure_padel_match(
  public._tap_id('S9 first server'), '{"setsToWin":2}'::jsonb);
select public.start_padel_match(public._tap_id('S9 first server'), 1, 0);

select is(
  (select (serving_side, serving_member)::text from public.padel_match_state
    where match_id = public._tap_id('S9 first server')),
  '(1,0)', 'the organizer can choose who serves first, and the fold honours it');

select is(
  (public.get_padel_scoreboard(public._tap_id('S9 first server')))->'state'->>'firstServerSide',
  '1', 'the configured first server is part of the served state contract');

-- ════════════════════════════════════════════════════════════════════════════
-- Result guards
-- ════════════════════════════════════════════════════════════════════════════
select throws_ok(
  $$ select public.submit_match_result(
       public._tap_id('S1 advantage singles'), 'early', 'early',
       '["0-0","0-0"]'::jsonb, '[1, 0]'::jsonb, 0) $$,
  '22023', null,
  'a result cannot be submitted before the fold says the match is complete');

select throws_ok(
  $$ select public.complete_padel_match(public._tap_id('S1 advantage singles')) $$,
  '22023', null,
  'complete_padel_match refuses a match the log has not finished');

select is(
  (select count(*)::int from public.padel_match_state
    where match_id in (public._tap_id('S1 advantage singles'),
                       public._tap_id('S2 golden point'),
                       public._tap_id('S4 tiebreak'),
                       public._tap_id('S5 super tiebreak'),
                       public._tap_id('S6 best of five'),
                       public._tap_id('S7 doubles rotation'),
                       public._tap_id('S9 first server'))),
  7, 'every started padel match has exactly one scoreboard row');

select * from public.finish();
rollback;
