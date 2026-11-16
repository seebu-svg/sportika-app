-- Row level security and RPC behaviour for the match module (migration 0007).
--
-- Run with `supabase test db` against a local stack, or through the session
-- pooler the way `.tmp/run_pgtap.sh` runs the auth suite. The Flutter tests can
-- prove that the device store refuses a non-organizer; only these assertions
-- prove the same claim against the real policies, the real grants and the real
-- security-definer functions.
--
-- Four fixed uuids stand in for four members. Ayesha organizes, Bilal is the
-- assigned official scorer, Sana is invited, Dania is an uninvolved bystander
-- who must never see an invite-only match. Policies are exercised by switching
-- to the `authenticated` role with a `request.jwt.claims` payload, which is what
-- auth.uid() reads inside a real PostgREST request.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(53);

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
select is(
  (select count(*)::int from public.profiles
    where id in ('11111111-1111-1111-1111-111111111111',
                 '22222222-2222-2222-2222-222222222222',
                 '33333333-3333-3333-3333-333333333333',
                 '44444444-4444-4444-4444-444444444444')),
  4, 'the signup trigger still creates a profile per member');

select ok(
  (select bool_and(relrowsecurity) from pg_class
    where oid in (
      'public.matches'::regclass,
      'public.match_participants'::regclass,
      'public.match_events'::regclass,
      'public.match_results'::regclass,
      'public.match_result_corrections'::regclass,
      'public.match_lifecycle_log'::regclass)),
  'row level security is enabled on every match table');

select ok(
  (select not bool_or(relforcerowsecurity) from pg_class
    where oid in (
      'public.matches'::regclass,
      'public.match_events'::regclass)),
  'row level security is enabled but not forced, so the RPCs can still write');

select ok(
  not has_table_privilege('authenticated', 'public.matches', 'INSERT')
  and not has_table_privilege('authenticated', 'public.match_events', 'INSERT')
  and not has_table_privilege('authenticated', 'public.match_events', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.match_results', 'INSERT'),
  'members hold no write grant; every write has to go through an RPC');

select ok(
  not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name in ('matches', 'match_participants')
       and column_name in ('role', 'account_type', 'intent')),
  'the match module adds no role or account-type column');

-- ── organizer Ayesha creates three matches ──────────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.create_match(
  'cricket', 'T20 · 20 overs', '{"overs":20}'::jsonb, 'Friday night derby',
  'Gulberg Arena', '2026-02-14 19:00+05', 'invite',
  'Strikers', 'Challengers', 10, 'team',
  '22222222-2222-2222-2222-222222222222');

select public.create_match(
  'badminton', 'Best of 3 · 21', '{}'::jsonb, 'Sunday smasher',
  'Johar Club', '2026-02-15 10:00+05', 'public',
  'Ayesha K', 'Dania M', 2, 'singles', null);

select public.create_match(
  'cricket', 'Tape ball · 6 overs', '{}'::jsonb, 'Tuesday tape ball',
  'Street 12', '2026-02-17 17:00+05', 'invite',
  'Street Kings', 'Street XI', 2, 'team', null);

select is(
  (select status from public.matches where title = 'Friday night derby'),
  'upcoming', 'a member creates a match in upcoming status');

select is(
  (select rules ->> 'discipline' from public.matches
    where title = 'Friday night derby'),
  'team', 'cricket is forced to the team discipline server-side');

select is(
  (select discipline from public.matches where title = 'Sunday smasher'),
  'singles', 'a racket sport keeps the discipline the organizer chose');

select is(
  (select count(*)::int from public.matches where organizer_id = auth.uid()),
  3, 'the organizer sees the three matches they created');

select is(
  (select status from public.match_participants
    where match_id = (select id from public.matches
                       where title = 'Friday night derby')
      and profile_id = '11111111-1111-1111-1111-111111111111'),
  'accepted', 'the organizer joins their own match as an accepted participant');

select throws_ok(
  $$ select public.create_match(
       'padel', 'Best of 3', '{}'::jsonb, 'No discipline given', 'Court 1',
       '2026-02-18 18:00+05', 'public', 'A', 'B', 4, null, null) $$,
  '22023', null,
  'padel must declare singles or doubles before a match can exist');

select throws_ok(
  $$ select public.create_match(
       'futsal', '2 x 20', '{}'::jsonb, 'A', 'Court 1',
       '2026-02-18 18:00+05', 'public', 'A', 'B', 10, 'team', null) $$,
  '22023', null,
  'a title shorter than the UI allows is refused by the RPC');

select throws_ok(
  $$ select public.create_match(
       'futsal', '2 x 20', '{}'::jsonb, 'Ghost scorer', 'Court 1',
       '2026-02-18 18:00+05', 'public', 'A', 'B', 10, 'team',
       '99999999-9999-9999-9999-999999999999') $$,
  '22023', null,
  'a scorer id that is not a registered member is refused');

-- ── invitations ─────────────────────────────────────────────────────────────
select is(
  (select status from public.invite_match_participant(
     (select id from public.matches where title = 'Friday night derby'),
     '33333333-3333-3333-3333-333333333333', 1)),
  'invited', 'inviting a member creates a pending participant row');

select throws_ok(
  $$ select public.invite_match_participant(
       (select id from public.matches where title = 'Friday night derby'),
       '11111111-1111-1111-1111-111111111111', 0) $$,
  '22023', null,
  'the organizer is already on their own match and cannot be invited again');

select throws_ok(
  $$ select public.invite_match_participant(
       (select id from public.matches where title = 'Friday night derby'),
       '99999999-9999-9999-9999-999999999999', 1) $$,
  '22023', null,
  'a profile id that does not exist is refused');

-- ── invited member Sana ─────────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';

select is(
  (select count(*)::int from public.matches),
  2, 'an invited member sees the invite-only match and the public one only');

select is(
  (select status from public.respond_match_invite(
     (select id from public.matches where title = 'Friday night derby'), true)),
  'accepted', 'an invited member accepts their own invite');

select throws_ok(
  $$ select public.assign_match_scorer(
       (select id from public.matches where title = 'Friday night derby'),
       '33333333-3333-3333-3333-333333333333') $$,
  '42501', null,
  'an accepted participant cannot assign the official scorer');

select throws_ok(
  $$ select public.start_match(
       (select id from public.matches where title = 'Friday night derby')) $$,
  '42501', null,
  'an accepted participant cannot start the match');

select throws_ok(
  $$ select public.record_match_event(
       (select id from public.matches where title = 'Friday night derby'),
       'sana-tap-1', 'ball', 0, '{"runs":4}'::jsonb) $$,
  '42501', null,
  'an accepted participant cannot record a scoring event');

-- ── uninvolved member Dania ─────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';

select is(
  (select count(*)::int from public.matches),
  1, 'a member outside an invite-only match never sees it');

select is(
  (select count(*)::int from public.match_events),
  0, 'events of a match a member cannot see are invisible too');

-- ── assigned scorer Bilal ───────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated"}';

select is(
  (select count(*)::int from public.matches),
  2, 'the assigned scorer sees the match they score and the public one');

select throws_ok(
  $$ select public.assign_match_scorer(
       (select id from public.matches where title = 'Friday night derby'),
       '33333333-3333-3333-3333-333333333333') $$,
  '42501', null,
  'a scorer cannot hand the whistle to another member');

select is(
  (select status from public.start_match(
     (select id from public.matches where title = 'Friday night derby'))),
  'live', 'the assigned scorer starts the match');

select is(
  (select seq from public.record_match_event(
     (select id from public.matches where title = 'Friday night derby'),
     'bilal-tap-1', 'ball', 0,
     '{"runs":4,"batter":"Bilal","bowler":"Sana"}'::jsonb)),
  1::bigint, 'the first recorded event takes sequence 1');

select is(
  (select seq from public.record_match_event(
     (select id from public.matches where title = 'Friday night derby'),
     'bilal-tap-1', 'ball', 0,
     '{"runs":4,"batter":"Bilal","bowler":"Sana"}'::jsonb)),
  1::bigint, 'a retried client event id returns the original row, never a copy');

select is(
  (select count(*)::int from public.match_events),
  1, 'the retry did not insert a second event');

select is(
  (select seq from public.record_match_event(
     (select id from public.matches where title = 'Friday night derby'),
     'bilal-tap-2', 'ball', 0, '{"runs":1}'::jsonb)),
  2::bigint, 'the next event takes the next sequence number');

select throws_ok(
  $$ select public.void_match_event(
       (select id from public.matches where title = 'Friday night derby'),
       (select id from public.match_events
         where client_event_id = 'bilal-tap-1')) $$,
  '22023', null,
  'undo only reaches the newest active event');

select is(
  (select voided from public.void_match_event(
     (select id from public.matches where title = 'Friday night derby'),
     (select id from public.match_events where client_event_id = 'bilal-tap-2'))),
  true, 'the newest event can be withdrawn');

select is(
  (select event_count from public.matches where title = 'Friday night derby'),
  2::bigint, 'undo never rewinds the monotonic sequence pointer');

select public.submit_match_result(
  (select id from public.matches where title = 'Friday night derby'),
  'Strikers won by 5 wickets', 'Chased 98 in 18.2 overs',
  '["98/5","97/9"]'::jsonb, '[98,97]'::jsonb, 0);

select is(
  (select status from public.matches where title = 'Friday night derby'),
  'submitted', 'the scorer submits the result for review');

select throws_ok(
  $$ select public.record_match_event(
       (select id from public.matches where title = 'Friday night derby'),
       'bilal-tap-3', 'ball', 0, '{"runs":6}'::jsonb) $$,
  '22023', null,
  'no event can be recorded once the result is submitted');

select throws_ok(
  $$ select public.publish_match_result(
       (select id from public.matches where title = 'Friday night derby')) $$,
  '42501', null,
  'the scorer cannot publish their own submission; publication stays with the organizer');

-- ── organizer publishes, corrects, and is then blocked ──────────────────────
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select is(
  (select status from public.publish_match_result(
     (select id from public.matches where title = 'Friday night derby'))),
  'published', 'the organizer publishes the submitted result');

select public.correct_match_result(
  (select id from public.matches where title = 'Friday night derby'),
  'Strikers won by 4 wickets', 'Chased 98 in 18.2 overs; one run ruled a bye',
  '["98/4","97/9"]'::jsonb, '[98,97]'::jsonb, 0,
  'Scoring error on the final over');

select is(
  (select count(*)::int from public.match_result_corrections),
  1, 'a correction keeps one previous-result row');

select is(
  (select headline from public.match_results
    where match_id = (select id from public.matches
                       where title = 'Friday night derby')),
  'Strikers won by 4 wickets', 'the correction becomes the published result');

select throws_ok(
  $$ select public.record_match_walkover(
       (select id from public.matches where title = 'Friday night derby'),
       1, 'Challengers did not turn up') $$,
  '22023', null,
  'a published match cannot be turned into a walkover');

select throws_ok(
  $$ select public.cancel_match(
       (select id from public.matches where title = 'Friday night derby'),
       'Called off') $$,
  '22023', null,
  'a published match cannot be cancelled');

-- ── walkover ────────────────────────────────────────────────────────────────
select is(
  (select status from public.record_match_walkover(
     (select id from public.matches where title = 'Sunday smasher'),
     0, 'Opponent withdrew')),
  'walkover', 'the organizer records a walkover on an upcoming match');

select is(
  (select winner_index from public.match_results
    where match_id = (select id from public.matches
                       where title = 'Sunday smasher')),
  0, 'the walkover publishes a winner without any scoring log');

select throws_ok(
  $$ select public.record_match_walkover(
       (select id from public.matches where title = 'Sunday smasher'),
       1, 'Again') $$,
  '22023', null,
  'a walkover match cannot be awarded twice');

-- ── capacity and cancellation ───────────────────────────────────────────────
select is(
  (select status from public.invite_match_participant(
     (select id from public.matches where title = 'Tuesday tape ball'),
     '44444444-4444-4444-4444-444444444444', 1)),
  'invited', 'the organizer invites a second player to a two-a-side match');

set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';

select is(
  (select status from public.respond_match_invite(
     (select id from public.matches where title = 'Tuesday tape ball'), true)),
  'accepted', 'the invitee accepts, filling the match');

select is(
  (select count(*)::int from public.matches),
  2, 'accepting an invite reveals the match to the participant');

set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select throws_ok(
  $$ select public.invite_match_participant(
       (select id from public.matches where title = 'Tuesday tape ball'),
       '33333333-3333-3333-3333-333333333333', 1) $$,
  '22023', null,
  'the RPC refuses an invite once the capacity is reached');

select is(
  (select status from public.cancel_match(
     (select id from public.matches where title = 'Tuesday tape ball'),
     'Rain')),
  'cancelled', 'the organizer cancels an upcoming match');

select throws_ok(
  $$ select public.cancel_match(
       (select id from public.matches where title = 'Tuesday tape ball'),
       'Rain again') $$,
  '22023', null,
  'a cancelled match cannot be cancelled twice');

-- ── realtime ────────────────────────────────────────────────────────────────
select ok(
  (select count(*) = 3 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename in ('matches', 'match_events', 'match_results')),
  'the match tables are published to realtime so subscribers get Postgres Changes');

-- ── anonymous ───────────────────────────────────────────────────────────────
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok(
  'select * from public.matches', '42501', null,
  'an anonymous visitor cannot read matches');

select throws_ok(
  $$ select public.create_match(
       'cricket', 'T20', '{}'::jsonb, 'Anonymous match', 'Nowhere',
       '2026-02-20 18:00+05', 'public', 'A', 'B', 10, 'team', null) $$,
  '42501', null,
  'an anonymous visitor cannot create a match');

select * from finish();
rollback;
