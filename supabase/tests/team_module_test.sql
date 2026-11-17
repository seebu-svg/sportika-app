-- Behaviour and row-level security for the team module (migration 0016 RPCs
-- as repaired by 0019).
--
-- Run with `.tmp/local_pg/apply.sh --test supabase/tests/team_module_test.sql`
-- against the scratch stack, or through `supabase test db` where the real
-- pgTAP extension takes over. Everything happens inside one transaction and
-- rolls back: the suite seeds three principals plus forty roster fillers,
-- drives every client-facing team RPC, and reads the notifications each one
-- leaves behind.
--
-- Why this suite exists: the team RPCs had no coverage at all, which is how
-- the consent-chain defect survived — create_team inserted picked players as
-- accepted members while the screen promised invitations, the follow-up
-- invite emitted a notification whose accept path aborted with
-- `no_team_invite`, and no roster event ever notified anyone. The assertions
-- below pin the repaired semantics: the captain is the only accepted member
-- at create, every pick is a real invitation, invite/answer/remove/leave/
-- transfer/delete all notify exactly the people involved, and the roster cap
-- holds. RLS checks close the file.
--
-- Notification assertions switch claims to the RECIPIENT first: the
-- notifications RLS policy shows each member only their own inbox, so a
-- count run under another member's claims reads zero.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(45);

-- ── fixtures ───────────────────────────────────────────────────────────────
-- Principal members: u1 captains, u2 joins and answers, u3 answers and gets
-- uninvited. Fillers exist only to press the roster cap.
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('a5aaaaaa-0000-4000-8000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'team-audit-owner@sportika.test', '$2a$10$notarealhashnotarealhashno',
   now(), now(), now(),
   '{"provider":"email","providers":["email"]}',
   '{"display_name":"Audit Owner"}'),
  ('a5aaaaaa-0000-4000-8000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'team-audit-joiner@sportika.test', '$2a$10$notarealhashnotarealhashno',
   now(), now(), now(),
   '{"provider":"email","providers":["email"]}',
   '{"display_name":"Audit Joiner"}'),
  ('a5aaaaaa-0000-4000-8000-000000000003',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'team-audit-outsider@sportika.test', '$2a$10$notarealhashnotarealhashno',
   now(), now(), now(),
   '{"provider":"email","providers":["email"]}',
   '{"display_name":"Audit Outsider"}');

insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
select
  ('a5bbbbbb-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'team-audit-cap' || g || '@sportika.test',
  '$2a$10$notarealhashnotarealhashno', now(), now(), now(),
  '{"provider":"email","providers":["email"]}',
  jsonb_build_object('display_name', 'Cap Filler ' || g)
  from generate_series(1, 40) g;

select ok((select count(*) >= 43 from public.profiles),
          'fixtures: profiles created for every seeded user');

-- Everything below runs as the signed-in member the claims name.
set local role authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- Team one: the invitation lifecycle
-- ════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);

select public.create_team('Audit XI', 'padel', 'team',
  array['a5aaaaaa-0000-4000-8000-000000000002',
        'a5aaaaaa-0000-4000-8000-000000000003']::uuid[]) as t1 \gset

select is((select status from public.team_members
            where team_id = :'t1'
              and profile_id = 'a5aaaaaa-0000-4000-8000-000000000001'::uuid),
          'accepted',
          'the captain is accepted the moment the team exists');
select is((select status from public.team_members
            where team_id = :'t1'
              and profile_id = 'a5aaaaaa-0000-4000-8000-000000000002'::uuid),
          'invited',
          'a pick is an invitation, not a member');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000002","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_invite'),
          1::bigint,
          'the pick was notified exactly once at create');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000003","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select status from public.team_members
            where team_id = :'t1'
              and profile_id = 'a5aaaaaa-0000-4000-8000-000000000003'::uuid),
          'invited',
          'the second pick is an invitation too');
select is((select count(*) from public.notifications
            where type = 'team_invite'),
          1::bigint,
          'the second pick was notified exactly once');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications),
          0::bigint,
          'the captain hears nothing about their own create');

-- The screen's follow-up invite for a pick it already sent at create.
select lives_ok(
  'select public.invite_team_member(' || quote_literal(:'t1')
    || ', ''a5aaaaaa-0000-4000-8000-000000000002''::uuid)',
  're-inviting a pending pick is allowed');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000002","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_invite'),
          1::bigint,
          'the follow-up invite dedupes to the one inbox row');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);
select throws_ok(
  'select public.invite_team_member(' || quote_literal(:'t1')
    || ', ''a5aaaaaa-0000-4000-8000-000000000001''::uuid)',
  '23505', 'already_accepted',
  'inviting an accepted member (the captain included) raises');

-- Joiner answers.
select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000002","role":"authenticated",
    "aud":"authenticated"}', true);

select lives_ok(
  'select public.respond_team_invite(' || quote_literal(:'t1') || ', true)',
  'an invited member can accept');
select is((select status from public.team_members
            where team_id = :'t1'
              and profile_id = 'a5aaaaaa-0000-4000-8000-000000000002'::uuid),
          'accepted',
          'accepting confirms the member row');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_member_joined'),
          1::bigint,
          'the captain hears the join');

-- Outsider declines.
select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000003","role":"authenticated",
    "aud":"authenticated"}', true);

select lives_ok(
  'select public.respond_team_invite(' || quote_literal(:'t1') || ', false)',
  'an invited member can decline');
select is((select count(*) from public.team_members
            where team_id = :'t1'
              and profile_id = 'a5aaaaaa-0000-4000-8000-000000000003'::uuid),
          0::bigint,
          'declining removes the row entirely');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_invite_declined'),
          1::bigint,
          'the captain hears the decline');

-- Re-invite the decliner: the row comes back pending, the inbox stays at the
-- original invitation (stable event key).
select lives_ok(
  'select public.invite_team_member(' || quote_literal(:'t1')
    || ', ''a5aaaaaa-0000-4000-8000-000000000003''::uuid)',
  'a decliner can be invited again');
select is((select status from public.team_members
            where team_id = :'t1'
              and profile_id = 'a5aaaaaa-0000-4000-8000-000000000003'::uuid),
          'invited',
          'the re-invite recreates the pending row');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000003","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_invite'),
          1::bigint,
          'the re-invite dedupes to the original invitation');

-- Removals announce themselves, in both flavours.
select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);

select lives_ok(
  'select public.remove_team_member(' || quote_literal(:'t1')
    || ', ''a5aaaaaa-0000-4000-8000-000000000002''::uuid)',
  'the captain removes an accepted member');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000002","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_member_removed'),
          1::bigint,
          'the removed member hears it');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);

select lives_ok(
  'select public.remove_team_member(' || quote_literal(:'t1')
    || ', ''a5aaaaaa-0000-4000-8000-000000000003''::uuid)',
  'the captain cancels a pending invitation');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000003","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_invite_cancelled'),
          1::bigint,
          'the cancelled invitee hears it');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);
select throws_ok(
  'select public.remove_team_member(' || quote_literal(:'t1')
    || ', ''a5aaaaaa-0000-4000-8000-000000000001''::uuid)',
  '22023', 'captain_cannot_leave',
  'the captain cannot remove themselves');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000002","role":"authenticated",
    "aud":"authenticated"}', true);
select throws_ok(
  'select public.remove_team_member(' || quote_literal(:'t1')
    || ', ''a5aaaaaa-0000-4000-8000-000000000003''::uuid)',
  '42501', 'not_team_captain',
  'a non-owner cannot remove members');

-- ════════════════════════════════════════════════════════════════════════════
-- Team two: captaincy and deletion
-- ════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);

select public.create_team('Audit Two', 'padel', 'team',
  array['a5aaaaaa-0000-4000-8000-000000000002']::uuid[]) as t2 \gset

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000002","role":"authenticated",
    "aud":"authenticated"}', true);

select lives_ok(
  'select public.respond_team_invite(' || quote_literal(:'t2') || ', true)',
  'the joiner accepts on team two');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);

select lives_ok(
  'select public.transfer_team_captain(' || quote_literal(:'t2')
    || ', ''a5aaaaaa-0000-4000-8000-000000000002''::uuid)',
  'the captain transfers captaincy');
select is((select owner_id from public.teams where id = :'t2'),
          'a5aaaaaa-0000-4000-8000-000000000002'::uuid,
          'the new captain owns the team');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000002","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_captain_changed'),
          1::bigint,
          'the incoming captain is notified');
select throws_ok(
  'select public.leave_team(' || quote_literal(:'t2') || ')',
  '22023', 'captain_must_transfer',
  'a captain cannot leave without transferring first');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);

select lives_ok(
  'select public.leave_team(' || quote_literal(:'t2') || ')',
  'a plain member can leave');
select is((select count(*) from public.team_members
            where team_id = :'t2'
              and profile_id = 'a5aaaaaa-0000-4000-8000-000000000001'::uuid),
          0::bigint,
          'leaving removes the member row');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000002","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_member_left'),
          1::bigint,
          'the captain hears the leave');

select throws_ok(
  'select public.transfer_team_captain(' || quote_literal(:'t2')
    || ', ''a5aaaaaa-0000-4000-8000-000000000003''::uuid)',
  '22023', 'player_not_in_team',
  'captaincy can only pass to an accepted member');

-- Bring the member back so the deletion has someone to reach.
select lives_ok(
  'select public.invite_team_member(' || quote_literal(:'t2')
    || ', ''a5aaaaaa-0000-4000-8000-000000000001''::uuid)',
  'the captain re-invites the leaver');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);

select lives_ok(
  'select public.respond_team_invite(' || quote_literal(:'t2') || ', true)',
  'the leaver re-accepts');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000002","role":"authenticated",
    "aud":"authenticated"}', true);

select lives_ok(
  'select public.delete_team(' || quote_literal(:'t2') || ')',
  'the captain deletes the team');
select is((select count(*) from public.teams where id = :'t2'),
          0::bigint,
          'the deletion removes the team');

select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.notifications
            where type = 'team_deleted'),
          1::bigint,
          'the accepted member hears the deletion');

-- ════════════════════════════════════════════════════════════════════════════
-- Team three: the roster cap
-- ════════════════════════════════════════════════════════════════════════════

select public.create_team('Audit Full', 'padel', 'team',
  (select array_agg(id order by id) from public.profiles
    where id >= 'a5bbbbbb-0000-4000-8000-000000000001'::uuid
      and id <  'a5bbbbbb-0000-4000-8000-000000000040'::uuid)) as t3 \gset

select is((select count(*) from public.team_members
            where team_id = :'t3'),
          40::bigint,
          'create fills the roster to the cap of forty');
select throws_ok(
  'select public.invite_team_member(' || quote_literal(:'t3')
    || ', ''a5bbbbbb-0000-4000-8000-000000000040''::uuid)',
  '22023', 'team_full',
  'the invite refuses one more than the cap');

-- ════════════════════════════════════════════════════════════════════════════
-- Row-level security
-- ════════════════════════════════════════════════════════════════════════════

set local role anon;
select throws_ok(
  'select count(*) from public.teams',
  '42501', 'permission denied for table teams',
  'anon cannot read teams (no grant, policy is authenticated-only)');
select throws_ok(
  'select count(*) from public.team_members',
  '42501', 'permission denied for table team_members',
  'anon cannot read the roster');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a5aaaaaa-0000-4000-8000-000000000001","role":"authenticated",
    "aud":"authenticated"}', true);
select is((select count(*) from public.teams), 2::bigint,
          'a member reads every team (one remains after the deletion)');
select is((select count(*) from public.team_members), 41::bigint,
          'a member reads the full roster');

select * from finish();
rollback;
