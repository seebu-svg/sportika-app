-- Padel official results are written by the server, not by the device.
--
-- The 2026-11 backend audit left one question open: migration 0013 checks a
-- padel result payload against its own fold, but the two `side_scores` strings
-- it stored were still whatever the caller sent, and those strings are what the
-- result card, the scoreboard tile, the vs-card, the history row and the live
-- feed all print. This suite is the proof for migration
-- 0020_padel_result_authority.sql and for the app submitting padel through
-- `complete_padel_match(uuid)`:
--
--  * a completed singles match, decided in a regular tie-break, and a doubles
--    match decided in a super tie-break, both closed out by the RPC alone;
--  * side A and side B carry different, individually correct readings of the
--    same three sets — never one string duplicated;
--  * a manipulated payload cannot become official: invented set lines are
--    replaced by the fold's, invented totals or a wrong winner are refused, and
--    a member who merely plays the match is turned away before the fold is read;
--  * a replayed completion (double tap, dropped answer, retry after publish) is
--    refused by the lifecycle guard and leaves exactly one official row holding
--    the first completion's derived score;
--  * the two doors agree: the same point log submitted through the generic door
--    stores the same two strings as `complete_padel_match`;
--  * the other three sports are untouched — a badminton result is still stored
--    exactly as the app's engine folded it.
--
-- Every score here is asserted from `match_results` after an RPC call. The
-- helpers only ever award points, so no assertion depends on a number this file
-- computed on a caller's behalf.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(35);

-- ── point-sequence helpers (as padel_scoring_test.sql) ──────────────────────
create sequence if not exists public._tap_point_seq;
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

-- One set to each side, in that order: the two reading orders can then be told
-- apart, which a 6-0, 6-0 match could never show.
create or replace function public._tap_one_set_each(p_match uuid)
returns void
language plpgsql
as $$
begin
  perform public._tap_games(p_match, 0, 6);
  perform public._tap_games(p_match, 1, 6);
end;
$$;

-- ── members ─────────────────────────────────────────────────────────────────
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

-- ── fixtures ────────────────────────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

-- A1 singles, decider won in a regular tie-break; closed by the padel RPC.
select public.create_match(
  'padel', 'Best of 3 · tie-break', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'A1 singles tiebreak', 'Court 1', '2026-03-01 18:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
-- A2 doubles, decider won in a super tie-break; closed by the padel RPC.
select public.create_match(
  'padel', 'Best of 3 · super tie-break',
  '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'A2 doubles super tiebreak', 'Court 2', '2026-03-01 19:00+05', 'public',
  'Ayesha K & Sana I', 'Bilal A & Dania M', 4, 'doubles', null);
-- A3 forged score text, honest totals, through the generic door.
select public.create_match(
  'padel', 'Best of 3 · tie-break', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'A3 forged text', 'Court 3', '2026-03-01 20:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
-- A4 forged totals and a forged winner, through the generic door.
select public.create_match(
  'padel', 'Best of 3 · tie-break', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'A4 forged totals', 'Court 4', '2026-03-01 21:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
-- A5 barely started: the fold has not finished it.
select public.create_match(
  'padel', 'Best of 3 · tie-break', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'A5 unfinished', 'Court 5', '2026-03-01 22:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
-- A6 completed once, then asked again three different ways.
select public.create_match(
  'padel', 'Best of 3 · super tie-break',
  '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'A6 duplicate', 'Court 6', '2026-03-02 18:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
-- A7 the same point log as A1, submitted through the generic door.
select public.create_match(
  'padel', 'Best of 3 · tie-break', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'A7 parity', 'Court 7', '2026-03-02 19:00+05', 'public',
  'Ayesha K', 'Sana I', 4, 'singles', null);
-- A8 badminton, which the app still folds for itself.
select public.create_match(
  'badminton', 'Best of 3 · 21', '{}'::jsonb, 'A8 not padel',
  'Hall 1', '2026-03-02 20:00+05', 'public',
  'Ayesha K', 'Sana I', 2, 'singles', null);

select public.invite_match_participant(public._tap_id('A1 singles tiebreak'),       '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('A2 doubles super tiebreak'), '33333333-3333-3333-3333-333333333333', 0);
select public.invite_match_participant(public._tap_id('A2 doubles super tiebreak'), '22222222-2222-2222-2222-222222222222', 1);
select public.invite_match_participant(public._tap_id('A2 doubles super tiebreak'), '44444444-4444-4444-4444-444444444444', 1);
select public.invite_match_participant(public._tap_id('A3 forged text'),            '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('A4 forged totals'),          '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('A5 unfinished'),             '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('A6 duplicate'),              '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('A7 parity'),                 '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('A8 not padel'),              '33333333-3333-3333-3333-333333333333', 1);

set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';
select public.respond_match_invite(public._tap_id('A1 singles tiebreak'),       true);
select public.respond_match_invite(public._tap_id('A2 doubles super tiebreak'), true);
select public.respond_match_invite(public._tap_id('A3 forged text'),            true);
select public.respond_match_invite(public._tap_id('A4 forged totals'),          true);
select public.respond_match_invite(public._tap_id('A5 unfinished'),             true);
select public.respond_match_invite(public._tap_id('A6 duplicate'),              true);
select public.respond_match_invite(public._tap_id('A7 parity'),                 true);
select public.respond_match_invite(public._tap_id('A8 not padel'),              true);

set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated"}';
select public.respond_match_invite(public._tap_id('A2 doubles super tiebreak'), true);

set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';
select public.respond_match_invite(public._tap_id('A2 doubles super tiebreak'), true);

-- ── the point logs ──────────────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

-- A1 / A3 / A7: A 6-0, B 6-0, then 6-6 and the decider tie-break to A, so the
-- completed sets read 6-0, 0-6, 7-6 from side A and 0-6, 6-0, 6-7 from side B.
select public.start_padel_match(public._tap_id('A1 singles tiebreak'), 0, 0);
select public._tap_one_set_each(public._tap_id('A1 singles tiebreak'));
select public._tap_alternate(public._tap_id('A1 singles tiebreak'), 6);
-- One set each, so the decider tie-break is played to ten, not to seven.
select public._tap_award(public._tap_id('A1 singles tiebreak'),
  '{0,0,0,0,0,0,0,0,0,0}');

select public.start_padel_match(public._tap_id('A3 forged text'), 0, 0);
select public._tap_one_set_each(public._tap_id('A3 forged text'));
select public._tap_alternate(public._tap_id('A3 forged text'), 6);
select public._tap_award(public._tap_id('A3 forged text'),
  '{0,0,0,0,0,0,0,0,0,0}');

select public.start_padel_match(public._tap_id('A7 parity'), 0, 0);
select public._tap_one_set_each(public._tap_id('A7 parity'));
select public._tap_alternate(public._tap_id('A7 parity'), 6);
select public._tap_award(public._tap_id('A7 parity'),
  '{0,0,0,0,0,0,0,0,0,0}');

-- A4 / A6: a super tie-break decider, so the last line is one game, not seven.
-- The rule has to be configured, exactly as the app's setup screen does it:
-- `matchTiebreak` is what makes one set each start a ten-point decider.
select public.configure_padel_match(
  public._tap_id('A4 forged totals'), '{"matchTiebreak":true}'::jsonb);
select public.start_padel_match(public._tap_id('A4 forged totals'), 0, 0);
select public._tap_one_set_each(public._tap_id('A4 forged totals'));
select public._tap_award(public._tap_id('A4 forged totals'),
  '{1,1,1,1,1,1,1,1,1,1}');

select public.configure_padel_match(
  public._tap_id('A6 duplicate'), '{"matchTiebreak":true}'::jsonb);
select public.start_padel_match(public._tap_id('A6 duplicate'), 0, 0);
select public._tap_one_set_each(public._tap_id('A6 duplicate'));
select public._tap_award(public._tap_id('A6 duplicate'),
  '{0,0,0,0,0,0,0,0,0,0}');

-- A2: doubles, the same super tie-break shape.
select public.configure_padel_match(
  public._tap_id('A2 doubles super tiebreak'), '{"matchTiebreak":true}'::jsonb);
select public.start_padel_match(public._tap_id('A2 doubles super tiebreak'), 0, 0);
select public._tap_one_set_each(public._tap_id('A2 doubles super tiebreak'));
select public._tap_award(public._tap_id('A2 doubles super tiebreak'),
  '{0,0,0,0,0,0,0,0,0,0}');

-- A5: one point of one game.
select public.start_padel_match(public._tap_id('A5 unfinished'), 0, 0);
select public._tap_award(public._tap_id('A5 unfinished'), '{0}');

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  A singles match, decided in a tie-break, completed by the RPC alone
-- ════════════════════════════════════════════════════════════════════════════
select is(
  (select (is_complete, winner_side, sets_won)::text
     from public.padel_match_state
    where match_id = public._tap_id('A1 singles tiebreak')),
  '(t,0,"[2, 1]")',
  'A1: the log says side A took the decider, two sets to one');

select ok(
  (select side_values = '[2, 1]'::jsonb and winner_index = 0
          and walkover = false and published_by is not null
     from public.complete_padel_match(public._tap_id('A1 singles tiebreak'))),
  'A1: complete_padel_match takes no score argument and still writes totals, winner and actor');

select is(
  (select side_scores from public.match_results
    where match_id = public._tap_id('A1 singles tiebreak')),
  '["6-0, 0-6, 7-6", "0-6, 6-0, 6-7"]'::jsonb,
  'A1: each side is given its own reading of the same three sets');

select isnt(
  (select side_scores->>0 from public.match_results
    where match_id = public._tap_id('A1 singles tiebreak')),
  (select side_scores->>1 from public.match_results
    where match_id = public._tap_id('A1 singles tiebreak')),
  'A1: the two sides never share one duplicated score string');

select is(
  (select detail from public.match_results
    where match_id = public._tap_id('A1 singles tiebreak')),
  'Set 1: 6-0 · Set 2: 0-6 · Set 3: 7-6',
  'A1: the set lines are spelled out of the fold in match order');

select is(
  (select headline from public.match_results
    where match_id = public._tap_id('A1 singles tiebreak')),
  'Ayesha K won 2-1',
  'A1: the headline names the winner the fold chose');

select is(
  (select status from public.matches
    where id = public._tap_id('A1 singles tiebreak')),
  'submitted',
  'A1: the completion moves the match to awaiting review');

select ok(
  (select submitted_at is not null and completed_at is not null
          and published_at is null
     from public.matches where id = public._tap_id('A1 singles tiebreak')),
  'A1: submitted and completed are stamped, publication is still the organizer''s');

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  A doubles match, decided in a super tie-break
-- ════════════════════════════════════════════════════════════════════════════
select ok(
  (select winner_index = 0 and side_values = '[2, 1]'::jsonb
     from public.complete_padel_match(public._tap_id('A2 doubles super tiebreak'))),
  'A2: a doubles match completes through the same door with no score supplied');

select is(
  (select side_scores from public.match_results
    where match_id = public._tap_id('A2 doubles super tiebreak')),
  '["6-0, 0-6, 1-0", "0-6, 6-0, 0-1"]'::jsonb,
  'A2: the super tie-break decider is one game read from each end');

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  The generic door no longer stores the caller's score strings
-- ════════════════════════════════════════════════════════════════════════════
select lives_ok(
  $$ select public.submit_match_result(
       public._tap_id('A3 forged text'), 'Ayesha K wins 2-1',
       'as the device chose to say it',
       '["6-0, 6-0, 6-0", "6-0, 6-0, 6-0"]'::jsonb, '[2, 1]'::jsonb, 0) $$,
  'A3: an agreeing payload still submits, so no honest client is broken');

select is(
  (select side_scores from public.match_results
    where match_id = public._tap_id('A3 forged text')),
  '["6-0, 0-6, 7-6", "0-6, 6-0, 6-7"]'::jsonb,
  'A3: the stored lines are the fold''s, not the three sixes that arrived');

select is(
  (select headline from public.match_results
    where match_id = public._tap_id('A3 forged text')),
  'Ayesha K wins 2-1',
  'A3: the wording stays the caller''s; only the score is taken over');

-- The same log, submitted by a client that did the arithmetic correctly.
select ok(
  (select winner_index = 0
     from public.submit_match_result(
       public._tap_id('A7 parity'), 'Ayesha K won 2-1',
       'Set 1: 6-0 · Set 2: 0-6 · Set 3: 7-6',
       '["6-0, 0-6, 7-6", "0-6, 6-0, 6-7"]'::jsonb, '[2, 1]'::jsonb, 0)),
  'A7: an honest padel payload is accepted through the generic door');

select is(
  (select side_scores from public.match_results
    where match_id = public._tap_id('A7 parity')),
  (select side_scores from public.match_results
    where match_id = public._tap_id('A1 singles tiebreak')),
  'A7: the same point log stores the same two strings through either door');

select throws_ok(
  $$ select public.submit_match_result(
       public._tap_id('A4 forged totals'), 'x', 'y',
       '["6-0, 0-6, 1-0", "0-6, 6-0, 0-1"]'::jsonb, '[3, 0]'::jsonb, 0) $$,
  '22023', 'score_payload_mismatch',
  'A4: set totals the recorded points do not support are refused');

select throws_ok(
  $$ select public.submit_match_result(
       public._tap_id('A4 forged totals'), 'x', 'y',
       '["6-0, 0-6, 1-0", "0-6, 6-0, 0-1"]'::jsonb, '[2, 1]'::jsonb, 1) $$,
  '22023', 'score_payload_mismatch',
  'A4: a winner the recorded points do not name is refused');

select ok(
  (select not exists (select 1 from public.match_results
                       where match_id = public._tap_id('A4 forged totals'))),
  'A4: a refused submission leaves no official row behind');

select throws_ok(
  $$ select public.submit_match_result(
       public._tap_id('A5 unfinished'), 'x', 'y',
       '["1-0","0-1"]'::jsonb, '[1, 0]'::jsonb, 0) $$,
  '22023', 'match_not_complete',
  'A5: the generic door also refuses a match the log has not finished');

select throws_ok(
  $$ select public.complete_padel_match(public._tap_id('A5 unfinished')) $$,
  '22023', 'match_not_complete',
  'A5: the padel door refuses to close out a match the log has not finished');

select is(
  (select status from public.matches
    where id = public._tap_id('A5 unfinished')),
  'live',
  'A5: a refusal leaves the match live, so scoring simply continues');

-- ════════════════════════════════════════════════════════════════════════════
-- 4.  A member who only plays the match cannot complete it
-- ════════════════════════════════════════════════════════════════════════════
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated"}';

select throws_ok(
  $$ select public.complete_padel_match(
       public._tap_id('A2 doubles super tiebreak')) $$,
  '42501', 'not_match_scorer',
  'a player on the winning side cannot submit the result he did not score');

select ok(
  (select status = 'submitted' from public.matches
    where id = public._tap_id('A2 doubles super tiebreak')),
  'the refusal from a player does not touch the row the organizer''s scorer wrote');

set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  Duplicate and interrupted completion requests
-- ════════════════════════════════════════════════════════════════════════════
select ok(
  (select match_id is not null
     from public.complete_padel_match(public._tap_id('A6 duplicate'))),
  'A6: the first completion is written');

-- The double tap, and the retry after an answer lost in transit: the work is
-- already done, so the RPC says so instead of writing a second time.
select throws_ok(
  $$ select public.complete_padel_match(public._tap_id('A6 duplicate')) $$,
  '22023', 'invalid_match_transition',
  'A6: a replayed completion is refused because the match is no longer live');

select is(
  (select count(*)::int from public.match_results
    where match_id = public._tap_id('A6 duplicate')),
  1, 'A6: exactly one official row survives the replay');

select is(
  (select count(*)::int from public.match_lifecycle_log
    where match_id = public._tap_id('A6 duplicate')
      and action = 'result_submitted'),
  1, 'A6: the refused replay records no second submission');

select is(
  (select side_scores from public.match_results
    where match_id = public._tap_id('A6 duplicate')),
  '["6-0, 0-6, 1-0", "0-6, 6-0, 0-1"]'::jsonb,
  'A6: the replay cannot rewrite the score of the row already published to review');

select public.publish_match_result(public._tap_id('A6 duplicate'));

select throws_ok(
  $$ select public.complete_padel_match(public._tap_id('A6 duplicate')) $$,
  '22023', 'invalid_match_transition',
  'A6: completion after publication is refused as well');

select is(
  (select status from public.matches
    where id = public._tap_id('A6 duplicate')),
  'published',
  'A6: the refused completion leaves the published match published');

-- Reopening for a correction, then completing again, is the 0013 path and must
-- still derive from the log rather than from anything the caller remembers.
select public.reopen_padel_match(public._tap_id('A6 duplicate'), 're-scored');

select is(
  (select status from public.matches
    where id = public._tap_id('A6 duplicate')),
  'live',
  'A6: reopening puts the match back live so the result can be derived again');

select ok(
  (select side_scores = '["6-0, 0-6, 1-0", "0-6, 6-0, 0-1"]'::jsonb
          and winner_index = 0
     from public.complete_padel_match(public._tap_id('A6 duplicate'))),
  'A6: re-completion re-derives the same score from the unchanged log');

-- ════════════════════════════════════════════════════════════════════════════
-- 6.  The surface: one builder, still callable, other sports untouched
-- ════════════════════════════════════════════════════════════════════════════
select ok(
  not has_function_privilege('authenticated',
    'public._padel_derived_scores(uuid)', 'EXECUTE'),
  'the score builder itself is not a door members can call');

select ok(
  has_function_privilege('authenticated',
    'public.complete_padel_match(uuid)', 'EXECUTE'),
  'complete_padel_match stays executable by authenticated members');

select public.start_match(public._tap_id('A8 not padel'));

select is(
  (select side_scores
     from public.submit_match_result(
       public._tap_id('A8 not padel'), 'Sana I wins', 'three games',
       '["18-21, 21-15, 19-21", "21-18, 15-21, 21-19"]'::jsonb,
       '[1, 2]'::jsonb, 1)),
  '["18-21, 21-15, 19-21", "21-18, 15-21, 21-19"]'::jsonb,
  'badminton: a sport the app folds for itself keeps the strings it sent');

select * from public.finish();
rollback;
