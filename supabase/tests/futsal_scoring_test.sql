-- The futsal scoring authority, exercised through the same RPCs the app calls.
--
-- Everything runs against the real functions and the real constraints: an entry
-- is written by record_match_event, folded by _futsal_fold_detail, refused by
-- _futsal_event_refusal and paid out by submit_match_result. No assertion below
-- reads a score the test computed on the client's behalf.
--
-- The sequences are the same literals test/futsal_authority_test.dart folds with
-- FutsalEngine, so a drift between the two folds fails in both places rather
-- than silently in one.
--
-- `_tap_user(n)` is one of eleven members: 1 organizes and plays side A, 2-5
-- fill side A, 6-10 fill side B, 11 is a signed-in stranger who may not score.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(86);

-- ── members, logins and small writers ───────────────────────────────────────
create or replace function public._tap_user(p_n int)
returns uuid
language sql
immutable
as $$ select ('a0000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid $$;

-- Switches the request to member p_n for the rest of the transaction.
create or replace function public._tap_login(p_n int)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',  public._tap_user(p_n)::text,
      'role', 'authenticated',
      'aud',  'authenticated')::text,
    true);
end;
$$;

create or replace function public._tap_match(p_title text)
returns uuid
language sql
stable
as $$ select id from public.matches where title = p_title $$;

-- The two fold readers are revoked from every client role, which is the point;
-- these wrappers let the suite read them the way the server does.
create or replace function public._tap_detail(p_title text)
returns jsonb
language sql
security definer
set search_path = public
as $$ select public._futsal_fold_detail(public._tap_match(p_title)) $$;

create or replace function public._tap_fold(p_title text)
returns jsonb
language sql
security definer
set search_path = public
as $$ select public._futsal_fold(public._tap_match(p_title)) $$;

-- Client event ids must be unique per write and stable for a replay test.
create sequence if not exists public._tap_futsal_seq;
grant usage, select on sequence public._tap_futsal_seq to authenticated;

create or replace function public._tap_next_id()
returns text
language sql
as $$ select 'tap-' || nextval('public._tap_futsal_seq')::text $$;

create or replace function public._tap_clock(p_title text, p_action text)
returns void
language sql
as $$
  select public.record_match_event(
    public._tap_match(p_title),
    'tap-' || nextval('public._tap_futsal_seq')::text,
    'clock', null, jsonb_build_object('action', p_action));
$$;

create or replace function public._tap_goal(
  p_title text, p_side int, p_half int default 0
)
returns void
language sql
as $$
  select public.record_match_event(
    public._tap_match(p_title),
    'tap-' || nextval('public._tap_futsal_seq')::text,
    'goal', p_side, jsonb_build_object('half', p_half, 'goalType', 'regular'));
$$;

create or replace function public._tap_kick(
  p_title text, p_side int, p_scored boolean
)
returns void
language sql
as $$
  select public.record_match_event(
    public._tap_match(p_title),
    'tap-' || nextval('public._tap_futsal_seq')::text,
    'penalty', p_side, jsonb_build_object('scored', p_scored));
$$;

-- Kicks must alternate, so this takes one kick per side p_each times.
create or replace function public._tap_kicks(
  p_title text, p_each int, p_scored_a boolean, p_scored_b boolean
)
returns void
language plpgsql
as $$
declare
  i int;
begin
  for i in 1..greatest(coalesce(p_each, 0), 0) loop
    perform public._tap_kick(p_title, 0, p_scored_a);
    perform public._tap_kick(p_title, 1, p_scored_b);
  end loop;
end;
$$;

-- ── fixtures ────────────────────────────────────────────────────────────────
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
select
  public._tap_user(i),
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'futsal' || i || '@sportika.test', '$2a$10$notarealhashnotarealhashno',
  now(), now(), now(), '{"provider":"email","providers":["email"]}',
  jsonb_build_object('display_name', 'Futsal Player ' || i)
from generate_series(1, 11) i;

-- ── schema shape ────────────────────────────────────────────────────────────
select ok(
  (select bool_and(convalidated) from pg_constraint
    where conname in ('matches_futsal_team', 'matches_futsal_capacity',
                      'tournaments_futsal_team')),
  'the three futsal backstops are validated constraints, not future promises');

select ok(
  (select bool_and(pg_get_constraintdef(oid) like '%futsal%') from pg_constraint
    where conname in ('matches_futsal_team', 'matches_futsal_capacity',
                      'tournaments_futsal_team')),
  'each backstop is scoped to futsal and says nothing about the other sports');

select ok(
  not has_function_privilege(
    'authenticated', 'public._futsal_fold_detail(uuid)', 'EXECUTE')
  and not has_function_privilege(
    'authenticated',
    'public._futsal_event_refusal(jsonb, text, int, jsonb, uuid)', 'EXECUTE'),
  'the fold and the refusal are server internals: members cannot call them');

select ok(
  has_function_privilege(
    'authenticated', 'public.record_match_event(uuid, text, text, int, jsonb)',
    'EXECUTE')
  and has_function_privilege(
    'authenticated',
    'public.submit_match_result(uuid, text, text, jsonb, jsonb, int)',
    'EXECUTE'),
  'the two doors the app calls stay open to signed-in members');

-- ── the organizer builds the fixture set ────────────────────────────────────
set local role authenticated;
select public._tap_login(1);

select public.create_match(
  'futsal', '2 × 20 min',
  '{"halves":2,"halfMinutes":20,"winnerRequired":false,"shootout":false}'::jsonb,
  'F1 regulation', 'Court 1', '2026-04-01 18:00+05', 'public',
  'North Five', 'South Five', 10, 'team', null);
select public.create_match(
  'futsal', '2 × 20 min · knockout',
  '{"halves":2,"halfMinutes":20,"winnerRequired":true,"shootout":true}'::jsonb,
  'F2 knockout', 'Court 2', '2026-04-01 19:00+05', 'public',
  'East Five', 'West Five', 10, 'team', null);
select public.create_match(
  'futsal', '2 × 20 min · extra time & penalties',
  '{"halves":2,"halfMinutes":20,"winnerRequired":true,"shootout":true,
    "extraTime":true,"extraHalfMinutes":5}'::jsonb,
  'F3 extra time', 'Court 3', '2026-04-01 20:00+05', 'public',
  'Harbour Five', 'Valley Five', 10, 'team', null);
select public.create_match(
  'futsal', '2 × 20 min',
  '{"halves":2,"halfMinutes":20}'::jsonb,
  'F4 abandoned', 'Court 4', '2026-04-01 21:00+05', 'public',
  'Ridge Five', 'Meadow Five', 10, 'team', null);
select public.create_match(
  'futsal', '2 × 15 min',
  '{"halves":2,"halfMinutes":15}'::jsonb,
  'F5 paused', 'Court 5', '2026-04-02 18:00+05', 'public',
  'Riverside Five', 'Hilltop Five', 10, 'team', null);
select public.create_match(
  'badminton', 'Best of 3 · 21', '{}'::jsonb, 'B1 not futsal',
  'Hall 1', '2026-04-02 19:00+05', 'public',
  'Futsal Player 1', 'Futsal Player 2', 2, 'singles', null);

select is(
  (select (discipline, capacity)::text from public.matches
    where title = 'F1 regulation'),
  '(team,10)',
  'a futsal match is a team game with room for five a side and a bench');

select throws_ok(
  $$ select public.create_match(
       'futsal', '2 × 20 min', '{}'::jsonb, 'F6 singles futsal', 'Court 6',
       '2026-04-03 18:00+05', 'public', 'A', 'B', 10, 'singles', null) $$,
  '22023', null,
  'create_match refuses a singles futsal match before the constraint has to');

-- four more on side A (the organizer is already accepted there), five on B
select public.invite_match_participant(public._tap_match('F1 regulation'), public._tap_user(2), 0);
select public.invite_match_participant(public._tap_match('F1 regulation'), public._tap_user(3), 0);
select public.invite_match_participant(public._tap_match('F1 regulation'), public._tap_user(4), 0);
select public.invite_match_participant(public._tap_match('F1 regulation'), public._tap_user(5), 0);
select public.invite_match_participant(public._tap_match('F1 regulation'), public._tap_user(6), 1);
select public.invite_match_participant(public._tap_match('F1 regulation'), public._tap_user(7), 1);
select public.invite_match_participant(public._tap_match('F1 regulation'), public._tap_user(8), 1);
select public.invite_match_participant(public._tap_match('F1 regulation'), public._tap_user(9), 1);
select public.invite_match_participant(public._tap_match('F1 regulation'), public._tap_user(10), 1);

select public.invite_match_participant(public._tap_match('F2 knockout'), public._tap_user(2), 0);
select public.invite_match_participant(public._tap_match('F2 knockout'), public._tap_user(3), 0);
select public.invite_match_participant(public._tap_match('F2 knockout'), public._tap_user(4), 0);
select public.invite_match_participant(public._tap_match('F2 knockout'), public._tap_user(5), 0);
select public.invite_match_participant(public._tap_match('F2 knockout'), public._tap_user(6), 1);
select public.invite_match_participant(public._tap_match('F2 knockout'), public._tap_user(7), 1);
select public.invite_match_participant(public._tap_match('F2 knockout'), public._tap_user(8), 1);
select public.invite_match_participant(public._tap_match('F2 knockout'), public._tap_user(9), 1);
select public.invite_match_participant(public._tap_match('F2 knockout'), public._tap_user(10), 1);

select public.invite_match_participant(public._tap_match('F3 extra time'), public._tap_user(2), 0);
select public.invite_match_participant(public._tap_match('F3 extra time'), public._tap_user(3), 0);
select public.invite_match_participant(public._tap_match('F3 extra time'), public._tap_user(4), 0);
select public.invite_match_participant(public._tap_match('F3 extra time'), public._tap_user(5), 0);
select public.invite_match_participant(public._tap_match('F3 extra time'), public._tap_user(6), 1);
select public.invite_match_participant(public._tap_match('F3 extra time'), public._tap_user(7), 1);
select public.invite_match_participant(public._tap_match('F3 extra time'), public._tap_user(8), 1);
select public.invite_match_participant(public._tap_match('F3 extra time'), public._tap_user(9), 1);
select public.invite_match_participant(public._tap_match('F3 extra time'), public._tap_user(10), 1);

select public.invite_match_participant(public._tap_match('F4 abandoned'), public._tap_user(2), 0);
select public.invite_match_participant(public._tap_match('F4 abandoned'), public._tap_user(6), 1);

select public.invite_match_participant(public._tap_match('F5 paused'), public._tap_user(2), 0);
select public.invite_match_participant(public._tap_match('F5 paused'), public._tap_user(6), 1);

select public._tap_login(2);
select public.respond_match_invite(public._tap_match('F1 regulation'), true);
select public.respond_match_invite(public._tap_match('F2 knockout'), true);
select public.respond_match_invite(public._tap_match('F3 extra time'), true);
select public.respond_match_invite(public._tap_match('F4 abandoned'), true);
select public.respond_match_invite(public._tap_match('F5 paused'), true);

select public._tap_login(3);
select public.respond_match_invite(public._tap_match('F1 regulation'), true);
select public.respond_match_invite(public._tap_match('F2 knockout'), true);
select public.respond_match_invite(public._tap_match('F3 extra time'), true);

select public._tap_login(4);
select public.respond_match_invite(public._tap_match('F1 regulation'), true);
select public.respond_match_invite(public._tap_match('F2 knockout'), true);
select public.respond_match_invite(public._tap_match('F3 extra time'), true);

select public._tap_login(5);
select public.respond_match_invite(public._tap_match('F1 regulation'), true);
select public.respond_match_invite(public._tap_match('F2 knockout'), true);
select public.respond_match_invite(public._tap_match('F3 extra time'), true);

select public._tap_login(6);
select public.respond_match_invite(public._tap_match('F1 regulation'), true);
select public.respond_match_invite(public._tap_match('F2 knockout'), true);
select public.respond_match_invite(public._tap_match('F3 extra time'), true);
select public.respond_match_invite(public._tap_match('F4 abandoned'), true);
select public.respond_match_invite(public._tap_match('F5 paused'), true);

select public._tap_login(7);
select public.respond_match_invite(public._tap_match('F1 regulation'), true);
select public.respond_match_invite(public._tap_match('F2 knockout'), true);
select public.respond_match_invite(public._tap_match('F3 extra time'), true);

select public._tap_login(8);
select public.respond_match_invite(public._tap_match('F1 regulation'), true);
select public.respond_match_invite(public._tap_match('F2 knockout'), true);
select public.respond_match_invite(public._tap_match('F3 extra time'), true);

select public._tap_login(9);
select public.respond_match_invite(public._tap_match('F1 regulation'), true);
select public.respond_match_invite(public._tap_match('F2 knockout'), true);
select public.respond_match_invite(public._tap_match('F3 extra time'), true);

select public._tap_login(10);
select public.respond_match_invite(public._tap_match('F1 regulation'), true);
select public.respond_match_invite(public._tap_match('F2 knockout'), true);
select public.respond_match_invite(public._tap_match('F3 extra time'), true);

select ok(
  (select count(*) from public.match_participants
    where match_id = public._tap_match('F1 regulation')
      and status = 'accepted' and side = 0) = 5
  and (select count(*) from public.match_participants
        where match_id = public._tap_match('F1 regulation')
          and status = 'accepted' and side = 1) = 5,
  'both fives are accepted before a ball is kicked');

-- ── the backstops bite even when a caller writes a table directly ───────────
reset role;

select throws_ok(
  $$ update public.matches set discipline = 'singles'
      where title = 'F4 abandoned' $$,
  '23514', null,
  'a futsal match cannot be switched to singles behind the RPCs back');

select throws_ok(
  $$ update public.matches set capacity = 8 where title = 'F4 abandoned' $$,
  '23514', null,
  'a futsal match cannot shrink below ten participant slots');

select throws_ok(
  $$ insert into public.tournaments
       (id, organizer_id, name, sport_key, format, entry_type, starts_at, ends_at)
     values
       ('tap-futsal-individual', public._tap_user(1), 'Tap futsal individual',
        'futsal', 'knockout', 'individual',
        now() + interval '7 days', now() + interval '8 days') $$,
  '23514', null,
  'a futsal tournament can never be an individual event');

set local role authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- F1: regulation, goals by half, half time, undo, submit
-- ════════════════════════════════════════════════════════════════════════════
select public._tap_login(1);

-- The row has to be live before the log opens; the clock event below is the
-- kick-off itself, which is a separate thing from the lifecycle transition.
select public.start_match(public._tap_match('F1 regulation'));

select is(
  public._tap_fold('F1 regulation')->>'phase',
  'pre',
  'an empty log folds to a match waiting for kick-off');

select is(
  public._tap_detail('F1 regulation')->'goals',
  '[0, 0]'::jsonb,
  'the folded score starts at nothing');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'lineup', 0,
       jsonb_build_object('players', jsonb_build_array(
         public._tap_user(1), public._tap_user(2), public._tap_user(3),
         public._tap_user(4)))) $$,
  '22023', null,
  'a starting four is refused: a futsal lineup is five players');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'lineup', 0,
       jsonb_build_object('players', jsonb_build_array(
         public._tap_user(1), public._tap_user(2), public._tap_user(3),
         public._tap_user(4), public._tap_user(6)))) $$,
  '22023', null,
  'a lineup cannot borrow a player from the other side');

select lives_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'lineup', 0,
       jsonb_build_object('players', jsonb_build_array(
         public._tap_user(1), public._tap_user(2), public._tap_user(3),
         public._tap_user(4), public._tap_user(5)))) $$,
  'the five accepted players of side A form a valid starting five');

select public._tap_clock('F1 regulation', 'start');

select is(
  public._tap_fold('F1 regulation')->>'phase',
  'running',
  'start puts the match on the clock');

select is(
  (select (status, started_at is not null)::text from public.matches
    where title = 'F1 regulation'),
  '(live,t)',
  'the row itself moves to live, so the workspace can be opened');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'clock', null,
       '{"action":"start"}'::jsonb) $$,
  '22023', null,
  'a running clock cannot be started a second time');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'lineup', 0,
       jsonb_build_object('players', jsonb_build_array(
         public._tap_user(1), public._tap_user(2), public._tap_user(3),
         public._tap_user(4), public._tap_user(5)))) $$,
  '22023', null,
  'the lineup locks the moment the clock starts');

select public._tap_goal('F1 regulation', 0, 0);
select public._tap_goal('F1 regulation', 1, 0);
select public._tap_goal('F1 regulation', 0, 0);

select is(
  public._tap_detail('F1 regulation')->'goals',
  '[2, 1]'::jsonb,
  'three goals in the first half fold to 2-1');

select is(
  public._tap_detail('F1 regulation')->'byHalf',
  '[[2, 1], [0, 0]]'::jsonb,
  'the fold keeps the goals by half, which is what the report prints');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'goal', 0,
       jsonb_build_object('half', 0, 'goalType', 'regular',
                          'playerId', public._tap_user(6))) $$,
  '22023', null,
  'a goal cannot be credited to a player on the other side');

select lives_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'goal', 0,
       jsonb_build_object('half', 0, 'goalType', 'regular',
                          'playerId', public._tap_user(2))) $$,
  'a goal credited to a player of that side is accepted');

select lives_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'goal', 0,
       jsonb_build_object('half', 0, 'goalType', 'ownGoal',
                          'playerId', public._tap_user(6))) $$,
  'an own goal is credited against the player of the side it came from');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'goal', 0,
       jsonb_build_object('half', 0, 'goalType', 'bicycle')) $$,
  '22023', null,
  'an invented goal type is refused instead of stored');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'penalty', 0,
       '{"scored":true}'::jsonb) $$,
  '22023', null,
  'a shootout kick during play is refused');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'card', 1,
       jsonb_build_object('colour', 'blue', 'half', 0)) $$,
  '22023', null,
  'a card has to be yellow or red');

select lives_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'card', 1,
       jsonb_build_object('colour', 'yellow', 'half', 0)) $$,
  'a yellow card is recorded as an audit entry');

select lives_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'foul', 1,
       jsonb_build_object('half', 0)) $$,
  'a foul is recorded against the half it happened in');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'substitution', 1,
       jsonb_build_object('inId', public._tap_user(6),
                          'outId', public._tap_user(2), 'half', 0)) $$,
  '22023', null,
  'a substitution must move two players of the same side');

select lives_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'substitution', 1,
       jsonb_build_object('inId', public._tap_user(7),
                          'outId', public._tap_user(6), 'half', 0)) $$,
  'a substitution between two accepted players of one side is accepted');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F1 regulation'), public._tap_next_id(), 'timeout', 0,
       '{}'::jsonb) $$,
  '22023', null,
  'an unknown futsal kind is refused: the contract is closed');

-- the same client event id twice is one write, not two
select public.record_match_event(
  public._tap_match('F1 regulation'), 'tap-replay-card', 'card', 1,
  '{"colour":"red","half":0}'::jsonb);

select is(
  (select (id, seq)::text from public.record_match_event(
     public._tap_match('F1 regulation'), 'tap-replay-card', 'card', 1,
     '{"colour":"red","half":0}'::jsonb)),
  (select (id, seq)::text from public.match_events
    where match_id = public._tap_match('F1 regulation')
      and client_event_id = 'tap-replay-card'),
  'a repeated client event id returns the stored row');

select is(
  (select count(*)::int from public.match_events
    where match_id = public._tap_match('F1 regulation')
      and client_event_id = 'tap-replay-card'),
  1,
  'the replay did not write a second row');

select is(
  (select count(*)::int from public.match_events
    where match_id = public._tap_match('F1 regulation') and not voided),
  11,
  'every accepted entry above is in the log, and none of the refusals are');

select public._tap_clock('F1 regulation', 'end_half');

select is(
  public._tap_fold('F1 regulation')->>'phase',
  'halfTime',
  'ending the first half leaves the match at half time, not at full time');

select public._tap_clock('F1 regulation', 'resume');

select is(
  public._tap_fold('F1 regulation')->>'half',
  '2',
  'resuming moves the fold into the second half');

select public._tap_goal('F1 regulation', 0, 1);

select is(
  public._tap_detail('F1 regulation')->'byHalf',
  '[[4, 1], [1, 0]]'::jsonb,
  'a second-half goal lands in its own half bucket');

select public._tap_clock('F1 regulation', 'end_half');

select is(
  public._tap_fold('F1 regulation')->>'phase',
  'complete',
  'ending the second half completes a match that is not level');

select is(
  public._tap_fold('F1 regulation')->>'winnerSide',
  '0',
  'the fold names the winner rather than leaving it to the caller');

select ok(
  (select completed_at is not null from public.matches
    where title = 'F1 regulation'),
  'the match is marked complete the moment the log says so');

select ok(
  exists (select 1 from public.match_lifecycle_log
           where match_id = public._tap_match('F1 regulation')
             and action = 'futsal_auto_complete'),
  'the auto-completion is logged, with the fold it was derived from');

select throws_ok(
  $$ select public._tap_goal('F1 regulation', 1, 1) $$,
  '22023', null,
  'a completed match refuses further entries');

-- undo reopens: without this an undone whistle left the match unscorable
select lives_ok(
  format(
    'select public.void_match_event(%L, %L)',
    public._tap_match('F1 regulation'),
    (select id from public.match_events
      where match_id = public._tap_match('F1 regulation')
        and kind = 'clock' and (data->>'action') = 'end_half' and not voided
      order by seq desc limit 1)),
  'the scorer can undo the wrong full-time whistle');

select ok(
  (select completed_at is null from public.matches
    where title = 'F1 regulation'),
  'undoing the last entry reopens the match instead of freezing it');

select is(
  public._tap_fold('F1 regulation')->>'phase',
  'running',
  'the reopened match folds back to a running clock');

select ok(
  exists (select 1 from public.match_lifecycle_log
           where match_id = public._tap_match('F1 regulation')
             and action = 'match_reopened'),
  'the reopening is logged, which is what the audit trail reads');

-- Named notation keeps the two score arguments apart: p_side_scores is the text
-- pair, p_side_values the numbers the fold is compared against.
select throws_ok(
  format(
    'select public.submit_match_result(
       p_match_id => %L, p_headline => %L, p_detail => %L,
       p_side_scores => %L::jsonb, p_side_values => %L::jsonb,
       p_winner_index => %s)',
    public._tap_match('F1 regulation'), 'North Five win', 'Derived',
    '["5","1"]', '[5,1]', 0),
  '22023', null,
  'an unfinished futsal match cannot be submitted');

select public._tap_clock('F1 regulation', 'end_half');

select throws_ok(
  format(
    'select public.submit_match_result(
       p_match_id => %L, p_headline => %L, p_detail => %L,
       p_side_scores => %L::jsonb, p_side_values => %L::jsonb,
       p_winner_index => %s)',
    public._tap_match('F1 regulation'), 'North Five win', 'Derived',
    '["0","0"]', '[9,9]', 0),
  '22023', null,
  'a payload the fold disagrees with is refused, not stored');

select throws_ok(
  format(
    'select public.submit_match_result(
       p_match_id => %L, p_headline => %L, p_detail => %L,
       p_side_scores => %L::jsonb, p_side_values => %L::jsonb,
       p_winner_index => %s)',
    public._tap_match('F1 regulation'), 'North Five win', 'Derived',
    '["5","1"]', '[5,1]', 1),
  '22023', null,
  'the winner has to agree with the fold as well as the score');

select lives_ok(
  format(
    'select public.submit_match_result(
       p_match_id => %L, p_headline => %L, p_detail => %L,
       p_side_scores => %L::jsonb, p_side_values => %L::jsonb,
       p_winner_index => %s)',
    public._tap_match('F1 regulation'), 'North Five win', 'Derived from the log',
    '["9","9"]', '[5,1]', 0),
  'a submission that matches the fold is accepted');

select is(
  (select side_scores from public.match_results
    where match_id = public._tap_match('F1 regulation')),
  '["5", "1"]'::jsonb,
  'the stored score strings are the fold''s, never the ones the caller sent');

select is(
  (select side_values from public.match_results
    where match_id = public._tap_match('F1 regulation')),
  '[5, 1]'::jsonb,
  'the numeric values are stored beside the strings every surface prints');

select is(
  (select (status, submitted_at is not null, completed_at is not null)::text
     from public.matches where title = 'F1 regulation'),
  '(submitted,t,t)',
  'submitting stamps the match and keeps it complete');

select throws_ok(
  format(
    'select public.submit_match_result(
       p_match_id => %L, p_headline => %L, p_detail => %L,
       p_side_scores => %L::jsonb, p_side_values => %L::jsonb,
       p_winner_index => %s)',
    public._tap_match('F1 regulation'), 'Again', 'Again',
    '["5","1"]', '[5,1]', 0),
  '22023', null,
  'a second submission is refused by the status, not silently overwritten');

-- ════════════════════════════════════════════════════════════════════════════
-- F2: knockout decided early in the shootout
-- ════════════════════════════════════════════════════════════════════════════
select public.start_match(public._tap_match('F2 knockout'));
select public._tap_clock('F2 knockout', 'start');
select public._tap_clock('F2 knockout', 'end_half');
select public._tap_clock('F2 knockout', 'resume');
select public._tap_clock('F2 knockout', 'end_half');

select is(
  public._tap_fold('F2 knockout')->>'phase',
  'shootout',
  'level after two halves, a knockout match goes to penalties');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F2 knockout'), public._tap_next_id(), 'goal', 0,
       '{"half":1,"goalType":"regular"}'::jsonb) $$,
  '22023', null,
  'a goal during the shootout is refused');

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F2 knockout'), public._tap_next_id(), 'clock', null,
       '{"action":"end_half"}'::jsonb) $$,
  '22023', null,
  'the clock cannot be ended by half once the shootout has begun');

select throws_ok(
  $$ select public._tap_kick('F2 knockout', 1, true) $$,
  '22023', null,
  'the second side cannot kick first: kicks alternate');

select public._tap_kick('F2 knockout', 0, true);
select is(
  public._tap_fold('F2 knockout')->'shootoutScores',
  '[1, 0]'::jsonb,
  'the first kick is scored to side A');

select throws_ok(
  $$ select public._tap_kick('F2 knockout', 0, true) $$,
  '22023', null,
  'side A cannot kick twice in a row');

select public._tap_kick('F2 knockout', 1, true);
select public._tap_kick('F2 knockout', 0, true);
select public._tap_kick('F2 knockout', 1, false);
select public._tap_kick('F2 knockout', 0, true);
select public._tap_kick('F2 knockout', 1, false);

select is(
  public._tap_fold('F2 knockout')->'shootoutTaken',
  '[3, 3]'::jsonb,
  'both sides have taken three kicks');

select public._tap_kick('F2 knockout', 0, true);

select is(
  public._tap_fold('F2 knockout')->'shootoutScores',
  '[4, 1]'::jsonb,
  'the shootout stands at 4-1 with side B unable to catch up');

select is(
  public._tap_fold('F2 knockout')->>'phase',
  'complete',
  'the shootout is decided early, before the fifth kick of side B');

select is(
  public._tap_fold('F2 knockout')->>'winnerSide',
  '0',
  'the early decision names side A as the winner');

select is(
  public._tap_fold('F2 knockout')->>'completionReason',
  'Won on penalties',
  'the completion reason says how the match was won');

select throws_ok(
  $$ select public._tap_kick('F2 knockout', 1, true) $$,
  '22023', null,
  'a decided shootout takes no further kicks');

-- ════════════════════════════════════════════════════════════════════════════
-- F3: extra time, then sudden death
-- ════════════════════════════════════════════════════════════════════════════
select public.start_match(public._tap_match('F3 extra time'));
select public._tap_clock('F3 extra time', 'start');
select public._tap_clock('F3 extra time', 'end_half');
select public._tap_clock('F3 extra time', 'resume');
select public._tap_clock('F3 extra time', 'end_half');

select is(
  public._tap_fold('F3 extra time')->>'phase',
  'halfTime',
  'level after regulation, a match with extra time plays on instead of shooting out');

select public._tap_clock('F3 extra time', 'resume');

select is(
  public._tap_fold('F3 extra time')->>'extraTime',
  'true',
  'the third period is flagged as extra time');

select public._tap_clock('F3 extra time', 'end_half');
select public._tap_clock('F3 extra time', 'resume');
select public._tap_clock('F3 extra time', 'end_half');

select is(
  public._tap_fold('F3 extra time')->>'phase',
  'shootout',
  'still level after both extra halves, the shootout decides it');

select public._tap_kicks('F3 extra time', 5, true, true);

select is(
  public._tap_fold('F3 extra time')->>'phase',
  'shootout',
  '5-5 after five kicks each is sudden death, not a draw');

select public._tap_kick('F3 extra time', 0, true);
select is(
  public._tap_fold('F3 extra time')->>'phase',
  'shootout',
  'a single scored kick in sudden death decides nothing yet');

select public._tap_kick('F3 extra time', 1, false);

select is(
  public._tap_fold('F3 extra time')->'shootoutTaken',
  '[6, 6]'::jsonb,
  'both sides have taken six kicks in sudden death');

select is(
  public._tap_fold('F3 extra time')->'shootoutScores',
  '[6, 5]'::jsonb,
  'the sudden-death tally reads 6-5');

select is(
  public._tap_fold('F3 extra time')->>'phase',
  'complete',
  'the tie is broken the moment one side misses in sudden death');

select is(
  public._tap_fold('F3 extra time')->>'winnerSide',
  '0',
  'side A wins the sudden death');

-- ════════════════════════════════════════════════════════════════════════════
-- F4: abandonment
-- ════════════════════════════════════════════════════════════════════════════
select public.start_match(public._tap_match('F4 abandoned'));
select public._tap_clock('F4 abandoned', 'start');
select public._tap_goal('F4 abandoned', 1, 0);
select public._tap_clock('F4 abandoned', 'end_match');

select is(
  public._tap_fold('F4 abandoned')->>'phase',
  'complete',
  'end_match stops a match that never reached full time');

select is(
  public._tap_fold('F4 abandoned')->>'completionReason',
  'Match ended by scorer/organizer',
  'the fold records that the scorer ended it rather than the clock');

select is(
  public._tap_fold('F4 abandoned')->>'winnerSide',
  '1',
  'the side that was ahead when it was ended wins');

-- ════════════════════════════════════════════════════════════════════════════
-- F5: a lifecycle pause freezes writes but still lets the match be ended
-- ════════════════════════════════════════════════════════════════════════════
select public.start_match(public._tap_match('F5 paused'));
select public._tap_clock('F5 paused', 'start');
select public.pause_match(public._tap_match('F5 paused'), 'Floodlight failure');

select throws_ok(
  $$ select public._tap_goal('F5 paused', 0, 0) $$,
  '22023', null,
  'a paused match takes no new goals');

select lives_ok(
  $$ select public.record_match_event(
       public._tap_match('F5 paused'), public._tap_next_id(), 'clock', null,
       '{"action":"end_match"}'::jsonb) $$,
  'a paused match can still be ended, which is the whole point of the exception');

select is(
  public._tap_fold('F5 paused')->>'phase',
  'complete',
  'ending a paused match completes it');

-- ════════════════════════════════════════════════════════════════════════════
-- authorization and sport scoping
-- ════════════════════════════════════════════════════════════════════════════
select public._tap_login(11);

select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('F5 paused'), public._tap_next_id(), 'goal', 0,
       '{"half":0}'::jsonb) $$,
  '42501', null,
  'a member who does not score the match cannot write to its log');

select throws_ok(
  format(
    'select public.void_match_event(%L, %L)',
    public._tap_match('F4 abandoned'),
    (select id from public.match_events
      where match_id = public._tap_match('F4 abandoned') limit 1)),
  '42501', null,
  'and cannot undo an entry either');

select public._tap_login(1);
select public.start_match(public._tap_match('B1 not futsal'));

-- Badminton grew its own door in 0024 (and cricket in 0026), so no seeded sport
-- still falls through to the generic path. The isolation the fixture proves is
-- now that a futsal-only kind is refused by BADMINTON's own contract rather than
-- silently accepted: the futsal goal vocabulary does not leak across sports.
select throws_ok(
  $$ select public.record_match_event(
       public._tap_match('B1 not futsal'), public._tap_next_id(), 'goal', 0,
       '{}'::jsonb) $$,
  '22023', 'invalid_event_kind',
  'a futsal goal kind is refused by the badminton door, not stored');

select is(
  (select count(*)::int from public.match_events
    where match_id = public._tap_match('B1 not futsal')),
  0,
  'the refused badminton entry left no row behind');

select finish();
rollback;
