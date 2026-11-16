-- Row level security and behaviour for the in-app notification module
-- (migration 0015).
--
-- Run with `supabase test db` against a local stack, or through the session
-- pooler the way `.tmp/run_pgtap.sh` runs the other suites. The Flutter tests
-- can prove that the device store refuses a non-organizer; only these
-- assertions prove the same claim against the real policies, the real grants
-- and the real security-definer functions.
--
-- Five fixed uuids stand in for five members. Ayesha organizes, Bilal is the
-- assigned official scorer, Sana is invited and later disputes a result, Dania
-- is an uninvolved bystander who must never see anybody's inbox, and Ece is a
-- spare profile used to prove deduplication in isolation. Policies are
-- exercised by switching to the `authenticated` role with a
-- `request.jwt.claims` payload, which is what auth.uid() reads inside a real
-- PostgREST request.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(44);

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
   'ece@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
   now(), now(), '{"provider":"email","providers":["email"]}',
   '{"display_name":"Ece Demir"}');

-- ── schema shape ────────────────────────────────────────────────────────────
select ok(
  (select to_regclass('public.notifications') is not null),
  'the notifications table exists');

select ok(
  (select to_regclass('public.notification_preferences') is not null),
  'the notification preferences table exists');

select ok(
  (select bool_and(relrowsecurity) from pg_class
    where oid in ('public.notifications'::regclass,
                  'public.notification_preferences'::regclass)),
  'row level security is enabled on both notification tables');

select ok(
  (select not bool_or(relforcerowsecurity) from pg_class
    where oid in ('public.notifications'::regclass,
                  'public.notification_preferences'::regclass)),
  'row level security is enabled but not forced, so triggers can still write');

select ok(
  has_table_privilege('authenticated', 'public.notifications', 'SELECT')
  and not has_table_privilege('authenticated', 'public.notifications', 'INSERT')
  and not has_table_privilege('authenticated', 'public.notifications', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.notifications', 'DELETE'),
  'members may read notifications but hold no write grant');

select ok(
  not has_table_privilege('authenticated', 'public.notification_preferences', 'INSERT')
  and not has_table_privilege('authenticated', 'public.notification_preferences', 'UPDATE'),
  'notification preferences are written through an RPC only');

select ok(
  (select count(*) = 1 from pg_policies
    where tablename = 'notifications'
      and policyname = 'notifications_select_own'
      and cmd = 'SELECT'),
  'a recipient-only select policy exists on notifications');

select ok(
  (select count(*) = 0 from pg_policies
    where tablename = 'notifications' and cmd <> 'SELECT'),
  'no policy lets a member write a notification');

select ok(
  (select count(*) = 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'),
  'notifications is published for realtime');

select ok(
  not has_function_privilege('authenticated', 'public._notify(
    uuid, text, text, text, text, text, text, jsonb, uuid, text, timestamptz)',
    'EXECUTE'),
  'the internal notify helper is not callable by a member');

-- ── deduplication, proved on its own profile ────────────────────────────────
select ok(
  (select public._notify(
     '55555555-5555-5555-5555-555555555555', 'match', 'match_invite',
     'Match invitation', 'Dedupe probe', 'match', 'probe',
     '{}'::jsonb, null, 'probe:event:1') is not null),
  'the notify helper writes a notification for a real member');

select ok(
  (select public._notify(
     '55555555-5555-5555-5555-555555555555', 'match', 'match_invite',
     'Match invitation', 'Dedupe probe', 'match', 'probe',
     '{}'::jsonb, null, 'probe:event:1') is null),
  'the same event key never lands twice');

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '55555555-5555-5555-5555-555555555555'),
  1, 'the repeated event left exactly one row behind');

-- ── a member cannot forge or rewrite a notification ─────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated"}';

select throws_ok(
  $$insert into public.notifications (recipient_id, category, type, title)
    values ('44444444-4444-4444-4444-444444444444', 'platform', 'platform_test',
            'Forged')$$,
  '42501', null,
  'a member cannot create a system notification');

select throws_ok(
  $$update public.notifications set title = 'rewritten'
    where recipient_id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null,
  'a member cannot rewrite somebody else''s notification');

select is(
  (select public.my_unread_notification_count()),
  0, 'an uninvolved bystander has an empty inbox');

-- ── organizer creates a match and invites Sana ──────────────────────────────
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.create_match(
  'cricket', 'T20 · 20 overs', '{"overs":20}'::jsonb, 'Notification derby',
  'Gulberg Arena', '2026-03-01 19:00+05', 'invite',
  'Strikers', 'Challengers', 10, 'team', null);

select public.invite_match_participant(
  (select id from public.matches where title = 'Notification derby'),
  '33333333-3333-3333-3333-333333333333', 1);

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '33333333-3333-3333-3333-333333333333'
      and type = 'match_invite'),
  1, 'the invitation lands in the invitee inbox');

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '33333333-3333-3333-3333-333333333333'
      and entity_type = 'match'
      and payload ->> 'matchId' is not null),
  1, 'the invitation carries a structured navigation payload');

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '11111111-1111-1111-1111-111111111111'),
  0, 'the organizer is not notified about their own invitation');

-- ── the invitee reads their own inbox ──────────────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';

select is(
  (select public.my_unread_notification_count()),
  1, 'the invitee has one unread notification');

select is(
  (select count(*)::int from public.list_my_notifications(30)),
  1, 'the feed returns the invitee one notification');

select is(
  (select count(*)::int from public.list_my_notifications(30, null, null, true)),
  1, 'the unread filter returns the invitee one notification');

select is(
  (select count(*)::int from public.notifications),
  1, 'row level security hides every other member''s rows');

select is(
  (select public.get_notification(
     (select id from public.notifications
       where recipient_id = '11111111-1111-1111-1111-111111111111'
       limit 1))),
  null::public.notifications,
  'a notification id from another member reads as absent');

-- ── Sana accepts, the organizer is told ────────────────────────────────────
select public.respond_match_invite(
  (select id from public.matches where title = 'Notification derby'), true);

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '11111111-1111-1111-1111-111111111111'
      and type = 'match_invite_accepted'),
  1, 'the organizer is told that the invitation was accepted');

-- ── the organizer appoints an official scorer ──────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.assign_match_scorer(
  (select id from public.matches where title = 'Notification derby'),
  '22222222-2222-2222-2222-222222222222');

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '22222222-2222-2222-2222-222222222222'
      and type = 'scorer_assigned'
      and category = 'scorer'),
  1, 'the new official scorer is told about the assignment');

-- ── the schedule moves ─────────────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.update_match(
  (select id from public.matches where title = 'Notification derby'),
  'Notification derby', 'Gulberg Arena', '2026-03-08 19:00+05',
  'Strikers', 'Challengers', 10);

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '33333333-3333-3333-3333-333333333333'
      and type = 'match_schedule_changed'),
  1, 'the player is told that the schedule moved');

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '22222222-2222-2222-2222-222222222222'
      and type = 'match_schedule_changed'),
  1, 'the official scorer is told that the schedule moved');

-- ── read state is recipient-only ───────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated"}';

select is(
  (select public.mark_notification_read(
     (select id from public.notifications
       where recipient_id = '33333333-3333-3333-3333-333333333333' limit 1))),
  null::public.notifications,
  'a member cannot mark somebody else''s notification as read');

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '33333333-3333-3333-3333-333333333333'
      and read_at is null),
  2, 'the other member''s notification is still unread');

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';

select ok(
  (select to_jsonb(public.mark_notification_read(
     (select id from public.notifications
       where recipient_id = '33333333-3333-3333-3333-333333333333'
       order by created_at limit 1))) ->> 'read_at' is not null),
  'a member can mark their own notification as read');

select is(
  (select public.my_unread_notification_count()),
  1, 'the unread count drops by exactly one');

select ok(
  (select public.mark_all_notifications_read() >= 1),
  'marking everything read reports how many rows it touched');

select is(
  (select public.my_unread_notification_count()),
  0, 'nothing is left unread');

-- ── preferences gate the optional categories ───────────────────────────────
select ok(
  (select (public.update_notification_preferences(
     p_match_activity => false)).match_activity is false),
  'a member can switch match activity off');

set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.update_match(
  (select id from public.matches where title = 'Notification derby'),
  'Notification derby', 'Gulberg Arena', '2026-03-15 19:00+05',
  'Strikers', 'Challengers', 10);

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '33333333-3333-3333-3333-333333333333'
      and type = 'match_schedule_changed'),
  1, 'no new match notification reaches a member who opted out');

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '22222222-2222-2222-2222-222222222222'
      and type = 'match_schedule_changed'),
  2, 'a member who stayed opted in is still told');

-- Match activity back on, so the scenarios further down still reach the
-- member who opted out a moment ago.
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';

select public.update_notification_preferences(p_match_activity => true);

-- ── the match runs, the result is published, a dispute is raised ───────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.start_match(
  (select id from public.matches where title = 'Notification derby'));

-- The official scorer submits the score, so the organizer is the one who has
-- to learn that a result is waiting for review.
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated"}';

select public.submit_match_result(
  (select id from public.matches where title = 'Notification derby'),
  'Strikers won by 6 wickets', 'Chased 161 in 18.4 overs',
  '[161,158]'::jsonb, '["161","158"]'::jsonb, 0);

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '11111111-1111-1111-1111-111111111111'
      and type = 'match_result_submitted'),
  1, 'the organizer is told that a result is waiting for review');

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.publish_match_result(
  (select id from public.matches where title = 'Notification derby'));

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '33333333-3333-3333-3333-333333333333'
      and type = 'result_published'),
  1, 'the player is told that the official result is out');

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';

select public.raise_match_dispute(
  (select id from public.matches where title = 'Notification derby'),
  'The score shown does not match the official scorecard.');

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '11111111-1111-1111-1111-111111111111'
      and type = 'dispute_submitted'),
  1, 'the organizer is told that a dispute was raised');

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.resolve_match_dispute(
  (select id from public.match_disputes
    where match_id = (select id from public.matches
                        where title = 'Notification derby')),
  'The scorecard was correct; the app display was wrong.', 'resolved');

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '33333333-3333-3333-3333-333333333333'
      and type = 'dispute_resolved'),
  1, 'the member who raised the dispute is told how it ended');

-- ── a cancelled match reaches everybody who was in it ──────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.create_match(
  'futsal', '5-a-side', '{}'::jsonb, 'Rainy friendly', 'Street 12',
  '2026-03-22 17:00+05', 'invite', 'Reds', 'Blues', 10, 'team', null);

select public.invite_match_participant(
  (select id from public.matches where title = 'Rainy friendly'),
  '33333333-3333-3333-3333-333333333333', 1);

select public.cancel_match(
  (select id from public.matches where title = 'Rainy friendly'),
  'Heavy rain');

reset role;

select is(
  (select count(*)::int from public.notifications
    where recipient_id = '33333333-3333-3333-3333-333333333333'
      and type = 'match_cancelled'),
  1, 'the player is told that the match was cancelled');

-- ── the scheduled reminder is idempotent ───────────────────────────────────
select is(
  (select public.dispatch_due_notifications()),
  0, 'nothing is due for a match that is not an hour away');

select is(
  (select count(*)::int from public.notifications
    where type = 'match_starting_soon'),
  0, 'no reminder was invented for a distant match');

select * from finish();
rollback;
