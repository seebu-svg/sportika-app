-- Who may score, who may only watch, and what the database refuses outright.
--
-- The scoring suite proves the rules; this one proves the boundary. Every
-- assertion either switches to a role with a forged real-looking request
-- (exactly what a modified client sends) or inspects the grants and policies
-- that make the boundary real.
--
-- Members: Ayesha organizes, Bilal is the match scorer, Sana is a participant,
-- Dania is an uninvolved bystander, Omar organizes a different tournament.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(56);

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
   '{"display_name":"Dania Malik"}'),
  ('55555555-5555-5555-5555-555555555555',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'omar@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
   now(), now(), '{"provider":"email","providers":["email"]}',
   '{"display_name":"Omar Raza"}');

create or replace function public._tap_id(p_title text)
returns uuid
language sql stable
security definer
set search_path = public
as $$ select id from public.matches where title = p_title $$;

create sequence if not exists public._tap_point_seq;
grant usage, select on sequence public._tap_point_seq to authenticated;

-- Wins p_games games to zero; only valid while the current game is at 0-0.
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

-- ── grants and function hygiene ─────────────────────────────────────────────
select ok(
  not has_table_privilege('authenticated', 'public.matches', 'INSERT')
  and not has_table_privilege('authenticated', 'public.matches', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.match_events', 'INSERT')
  and not has_table_privilege('authenticated', 'public.match_events', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.match_events', 'DELETE')
  and not has_table_privilege('authenticated', 'public.padel_match_state', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.match_disputes', 'UPDATE'),
  'members hold no write grant on matches, events, scoreboard or disputes');

select ok(
  not has_function_privilege('anon', 'public.award_padel_point(uuid,int,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.pause_match(uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_padel_scoreboard(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.raise_match_dispute(uuid,text)', 'EXECUTE'),
  'no scoring RPC is callable without a session');

select ok(
  not has_function_privilege('authenticated', 'public._padel_fold(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public._padel_fold_detail(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public._padel_rebuild_state(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public._padel_snapshot(uuid,uuid)', 'EXECUTE'),
  'the internal fold and projection helpers are not callable from the API');

select ok(
  (select bool_and(proconfig::text like '%search_path=public%')
     from pg_proc
    where oid in ('public.award_padel_point(uuid,int,text)'::regprocedure,
                  'public.pause_match(uuid,text)'::regprocedure,
                  'public.resume_match(uuid)'::regprocedure,
                  'public.undo_last_padel_point(uuid,text)'::regprocedure,
                  'public.correct_padel_event(uuid,uuid,text)'::regprocedure,
                  'public.reopen_padel_match(uuid,text)'::regprocedure,
                  'public.complete_padel_match(uuid)'::regprocedure,
                  'public.submit_match_result(uuid,text,text,jsonb,jsonb,int)'::regprocedure,
                  'public.configure_padel_match(uuid,jsonb,text)'::regprocedure,
                  'public.start_padel_match(uuid,int,int)'::regprocedure,
                  'public.create_match(text,text,jsonb,text,text,timestamptz,text,text,text,int,text,uuid,text,text)'::regprocedure,
                  'public.raise_match_dispute(uuid,text)'::regprocedure,
                  'public.resolve_match_dispute(uuid,text,text)'::regprocedure)),
  'every security-definer entry point pins search_path to public');

-- ── the organizer sets the stage ─────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.create_match(
  'padel', 'Best of 3', '{"setsToWin":2,"gamesToWinSet":6}'::jsonb,
  'SEC1 guarded match', 'Court 1', '2026-04-01 18:00+05', 'invite',
  'Ayesha K', 'Sana I', 4, 'singles', null);

select public.create_match(
  'padel', 'One set · first to 4', '{"setsToWin":1,"gamesToWinSet":4}'::jsonb,
  'SEC2 fixture match', 'Court 2', '2026-04-01 19:00+05', 'invite',
  'Ayesha K', 'Sana I', 4, 'singles', null);

select public.invite_match_participant(public._tap_id('SEC1 guarded match'),
  '33333333-3333-3333-3333-333333333333', 1);
select public.invite_match_participant(public._tap_id('SEC2 fixture match'),
  '33333333-3333-3333-3333-333333333333', 1);

-- Sana accepts both.
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';
select public.respond_match_invite(public._tap_id('SEC1 guarded match'), true);
select public.respond_match_invite(public._tap_id('SEC2 fixture match'), true);

-- Bilal becomes the official scorer of SEC1.
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';
select public.assign_match_scorer(public._tap_id('SEC1 guarded match'),
  '22222222-2222-2222-2222-222222222222');
select public.configure_padel_match(public._tap_id('SEC2 fixture match'),
  '{"setsToWin":1,"gamesToWinSet":4}'::jsonb);
select public.start_padel_match(public._tap_id('SEC1 guarded match'), 0, 0);

select is(
  (select scorer_id from public.matches where id = public._tap_id('SEC1 guarded match')),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'the organizer assigned an official scorer');

-- ── spectator Dania ─────────────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';

select is(
  (select count(*)::int from public.matches where id = public._tap_id('SEC1 guarded match')),
  0, 'a bystander cannot read an invite-only match row');

select is(
  (select count(*)::int from public.match_events
    where match_id = public._tap_id('SEC1 guarded match')),
  0, 'a bystander cannot read the event log of that match');

select is(
  (select count(*)::int from public.padel_match_state
    where match_id = public._tap_id('SEC1 guarded match')),
  0, 'a bystander cannot read the scoreboard projection');

select is(
  (select count(*)::int from public.match_participants
    where match_id = public._tap_id('SEC1 guarded match')),
  0, 'a bystander cannot read the participant list');

select throws_ok(
  $$ select public.award_padel_point(public._tap_id('SEC1 guarded match'), 0, 'spectator-1') $$,
  '42501', null, 'a spectator cannot award a point');

select throws_ok(
  $$ select public.pause_match(public._tap_id('SEC1 guarded match'), 'let me in') $$,
  '42501', null, 'a spectator cannot pause the match');

select throws_ok(
  $$ select public.undo_last_padel_point(public._tap_id('SEC1 guarded match'), 'nope') $$,
  '42501', null, 'a spectator cannot withdraw a point');

select throws_ok(
  $$ select public.start_padel_match(public._tap_id('SEC1 guarded match')) $$,
  '42501', null, 'a spectator cannot (re)start the match');

select throws_ok(
  $$ select public.get_padel_scoreboard(public._tap_id('SEC1 guarded match')) $$,
  '42501', null, 'the snapshot RPC refuses a caller who may not view the match');

select is(
  public.can_view_match(public._tap_id('SEC1 guarded match')),
  false, 'the visibility predicate itself returns false for a bystander');

-- ── participant Sana: may watch, may not score ───────────────────────────────
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';

select is(
  (select count(*)::int from public.padel_match_state
    where match_id = public._tap_id('SEC1 guarded match')),
  1, 'an accepted participant can read the scoreboard');

select throws_ok(
  $$ select public.award_padel_point(public._tap_id('SEC1 guarded match'), 0, 'participant-1') $$,
  '42501', null, 'being a participant does not grant scoring authority');

select throws_ok(
  $$ select public.assign_match_scorer(public._tap_id('SEC1 guarded match'),
       '33333333-3333-3333-3333-333333333333') $$,
  '42501', null, 'a participant cannot make themselves the official scorer');

select throws_ok(
  $$ select public.submit_match_result(
       public._tap_id('SEC1 guarded match'), 'Sana wins', '',
       '["6-0","0-6"]'::jsonb, '[2, 0]'::jsonb, 1) $$,
  '42501', null, 'a participant cannot submit an official result');

-- ── assigned scorer Bilal: may score, may not adjudicate ─────────────────────
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated"}';

select ok(
  (public.award_padel_point(public._tap_id('SEC1 guarded match'), 0, 'scorer-1'))->'state'->'points'
    = '[1, 0]'::jsonb,
  'the assigned official scorer can award a point');

select ok(
  (select paused_at is not null
     from public.pause_match(public._tap_id('SEC1 guarded match'), 'injury')),
  'the assigned official scorer can pause the match');

select ok(
  (select paused_at is null
     from public.resume_match(public._tap_id('SEC1 guarded match'))),
  'the assigned official scorer can resume the match');

select public.undo_last_padel_point(public._tap_id('SEC1 guarded match'), 'wrong side');
select ok(
  (select voided from public.match_events
    where match_id = public._tap_id('SEC1 guarded match')
      and client_event_id = 'scorer-1'),
  'the assigned official scorer can withdraw the newest point');

select throws_ok(
  $$ select public.correct_padel_event(
       public._tap_id('SEC1 guarded match'),
       (select id from public.match_events
         where match_id = public._tap_id('SEC1 guarded match') order by seq desc limit 1),
       'let me fix an old point') $$,
  '42501', null, 'a scorer cannot reach back into older events; correction is the organizer''s');

select throws_ok(
  $$ select public.reopen_padel_match(public._tap_id('SEC1 guarded match'), 'I disagree') $$,
  '42501', null, 'a scorer cannot reopen a submitted result');

select throws_ok(
  $$ select public.publish_match_result(public._tap_id('SEC1 guarded match')) $$,
  '42501', null, 'a scorer cannot publish a result');

-- ── match_of_fixture is now visibility-aware ─────────────────────────────────
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.claim_tournament_organizer('T-SEC');

select public.create_match(
  'padel', 'One set · first to 4', '{"setsToWin":1,"gamesToWinSet":4}'::jsonb,
  'SEC3 linked fixture', 'Court 3', '2026-04-02 18:00+05', 'invite',
  'Ayesha K', 'Sana I', 4, 'singles', null, 'T-SEC', 'F1');

select public.invite_match_participant(public._tap_id('SEC3 linked fixture'),
  '33333333-3333-3333-3333-333333333333', 1);
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';
select public.respond_match_invite(public._tap_id('SEC3 linked fixture'), true);
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select is(
  (select id from public.match_of_fixture('T-SEC', 'F1')),
  public._tap_id('SEC3 linked fixture'),
  'the fixture lookup returns the match to its organizer');

set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';
select is(
  (select id from public.match_of_fixture('T-SEC', 'F1')),
  null::uuid, 'the same fixture lookup yields no match id for a bystander');

-- ── the tournament claim boundary ───────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","aud":"authenticated"}';

select throws_ok(
  $$ select public.create_match(
       'padel', 'One set · first to 4', '{"setsToWin":1,"gamesToWinSet":4}'::jsonb,
       'Omar takeover', 'Court 9', '2026-04-03 18:00+05', 'public',
       'Omar R', 'Ayesha K', 4, 'singles', null, 'T-SEC', 'F9') $$,
  '42501', null, 'a member cannot generate a fixture inside another organizer''s tournament');

set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select throws_ok(
  $$ select public.create_match(
       'padel', 'One set · first to 4', '{"setsToWin":1,"gamesToWinSet":4}'::jsonb,
       'Duplicate fixture', 'Court 3', '2026-04-02 18:00+05', 'public',
       'Ayesha K', 'Sana I', 4, 'singles', null, 'T-SEC', 'F1') $$,
  '23505', null, 'a fixture can only ever be linked to one match');

-- ── the tournament scorer bridge ────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select ok(
  (public.assign_fixture_scorer('T-SEC', 'F1', '44444444-4444-4444-4444-444444444444'))->>'matchId'
    = public._tap_id('SEC3 linked fixture')::text,
  'assigning a fixture scorer reports the match it was mirrored onto');

select is(
  (select scorer_id from public.matches where id = public._tap_id('SEC3 linked fixture')),
  '44444444-4444-4444-4444-444444444444'::uuid,
  'the fixture assignment is mirrored onto matches.scorer_id');

set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';

select public.start_padel_match(public._tap_id('SEC3 linked fixture'), 0, 0);
select ok(
  (public.award_padel_point(public._tap_id('SEC3 linked fixture'), 1, 'bridge-1'))->'state'->'points'
    = '[0, 1]'::jsonb,
  'a tournament-bridge scorer can score the linked fixture through the RPCs');

set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';
select public.revoke_fixture_scorer('T-SEC', 'F1', '44444444-4444-4444-4444-444444444444');

select is(
  (select scorer_id from public.matches where id = public._tap_id('SEC3 linked fixture')),
  null, 'revoking the fixture assignment clears the mirrored scorer');

-- Close the fixture out so there is a published result to scope-test.
select public._tap_games(public._tap_id('SEC3 linked fixture'), 0, 4);
select public.complete_padel_match(public._tap_id('SEC3 linked fixture'));
select public.publish_match_result(public._tap_id('SEC3 linked fixture'));

set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';
select throws_ok(
  $$ select public.award_padel_point(public._tap_id('SEC3 linked fixture'), 1, 'bridge-2') $$,
  '42501', null, 'a revoked fixture scorer can no longer score');

set local request.jwt.claims =
  '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","aud":"authenticated"}';
select throws_ok(
  $$ select public.assign_fixture_scorer('T-SEC', 'F1',
       '55555555-5555-5555-5555-555555555555') $$,
  '42501', null, 'only the tournament claim owner may assign a fixture scorer');

-- ── disputes ────────────────────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select throws_ok(
  $$ select public.raise_match_dispute(public._tap_id('SEC1 guarded match'),
       'there is no result yet') $$,
  '22023', null, 'a dispute cannot be raised before a result exists');

-- Finish and publish SEC1 so a dispute has something to contest.
select public._tap_games(public._tap_id('SEC1 guarded match'), 0, 6);
select public._tap_games(public._tap_id('SEC1 guarded match'), 1, 6);
select public._tap_games(public._tap_id('SEC1 guarded match'), 0, 6);
select public.complete_padel_match(public._tap_id('SEC1 guarded match'));
select public.publish_match_result(public._tap_id('SEC1 guarded match'));

select is(
  (select status from public.matches where id = public._tap_id('SEC1 guarded match')),
  'published', 'the organizer publishes the official result');

set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';

select is(
  (select status from public.raise_match_dispute(
     public._tap_id('SEC1 guarded match'), 'second set was scored wrong')),
  'open', 'a participant can dispute a published result');

select throws_ok(
  $$ select public.raise_match_dispute(
       public._tap_id('SEC1 guarded match'), 'and again') $$,
  '23505', null, 'a member cannot stack two open disputes on one match');

select throws_ok(
  $$ select public.resolve_match_dispute(
       (select id from public.match_disputes
         where match_id = public._tap_id('SEC1 guarded match')
           and status = 'open' limit 1),
       'resolved by the player', 'resolved') $$,
  '42501', null, 'a participant cannot resolve their own dispute');

set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select ok(
  (select status = 'resolved'
          and resolution = 'recounted from the log'
          and resolved_by = '11111111-1111-1111-1111-111111111111'
          and resolved_at is not null
     from public.resolve_match_dispute(
       (select id from public.match_disputes
         where match_id = public._tap_id('SEC1 guarded match')
           and status = 'open' limit 1),
       'recounted from the log', 'resolved')),
  'the organizer resolves a dispute and the resolution is stamped');

select throws_ok(
  $$ select public.resolve_match_dispute(
       (select id from public.match_disputes
         where match_id = public._tap_id('SEC1 guarded match')
           and status = 'resolved' limit 1),
       'closed twice', 'resolved') $$,
  '22023', null, 'a closed dispute cannot be closed again');

select ok(
  exists (select 1 from public.match_lifecycle_log
           where match_id = public._tap_id('SEC1 guarded match')
             and action in ('dispute_raised', 'dispute_resolved')),
  'both dispute steps are in the audit trail');

-- ── published results stay scoped ───────────────────────────────────────────
select is(
  (select count(*)::int from public.published_fixture_results('T-SEC')),
  1, 'the claim owner sees one published fixture result in their tournament');

set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';
select is(
  (select count(*)::int from public.published_fixture_results('T-SEC')),
  0, 'a bystander sees no published fixture result they may not read');

-- ── no billing module: scoring, results and disputes stay free ────────────
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.start_padel_match(public._tap_id('SEC2 fixture match'), 0, 0);

select ok(
  (public.award_padel_point(public._tap_id('SEC2 fixture match'), 0, 'free-1'))->'state'->'points'
    = '[1, 0]'::jsonb,
  'scoring a match needs no billing module');

-- ── direct writes are refused by the database itself ────────────────────────
select throws_ok(
  $$ insert into public.padel_match_state (match_id)
     values (public._tap_id('SEC1 guarded match')) $$,
  '42501', null, 'a client cannot insert a scoreboard row');

select throws_ok(
  $$ update public.padel_match_state set points = '[4, 0]'::jsonb
      where match_id = public._tap_id('SEC1 guarded match') $$,
  '42501', null, 'a client cannot overwrite the official score state');

select throws_ok(
  $$ update public.match_events set side = 1
      where match_id = public._tap_id('SEC1 guarded match') $$,
  '42501', null, 'a client cannot rewrite an event');

select throws_ok(
  $$ insert into public.match_disputes (match_id, raised_by, reason)
     values (public._tap_id('SEC1 guarded match'),
             '44444444-4444-4444-4444-444444444444', 'forged dispute') $$,
  '42501', null, 'a client cannot forge a dispute row');

select throws_ok(
  $$ insert into public.official_scorer_assignments
       (tournament_id, fixture_id, scorer_profile_id, authorized_by)
     values ('T-SEC', 'F1', '55555555-5555-5555-5555-555555555555',
             '55555555-5555-5555-5555-555555555555') $$,
  '42501', null, 'a client cannot forge a scorer assignment');

-- Rewriting history is refused for every role, including the database owner:
-- the trigger, not a grant, is what protects the log from a future RPC mistake.
reset role;
select throws_ok(
  $$ update public.match_events set side = 1
      where client_event_id = 'scorer-1' $$,
  '42501', 'match_events_are_immutable',
  'the event log refuses any rewrite of the scoring payload');

select throws_ok(
  $$ update public.match_events set voided = false
      where client_event_id = 'scorer-1' and voided $$,
  '42501', 'match_event_cannot_be_restored',
  'a withdrawn event cannot be restored by flipping the flag back');

-- Deleting is the other half of the promise. A client may never do it, while
-- the backend must be able to: without that, a match could never be removed or
-- cascaded away, and the guard would block its own retention path.
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';
select throws_ok(
  $$ delete from public.match_events where client_event_id = 'scorer-1' $$,
  '42501', null, 'a client cannot delete a scoring event');

reset role;
select lives_ok(
  $$ delete from public.match_events where client_event_id = 'scorer-1' $$,
  'the backend can purge events when a match is removed');

select * from public.finish();
rollback;
