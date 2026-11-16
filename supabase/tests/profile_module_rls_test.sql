-- Row level security and RPC behaviour for the profile module (migration 0006).
--
-- Run with `supabase test db` against a local stack. The Flutter tests cannot
-- prove that member B is unable to assign a scorer to member A's tournament;
-- these assertions are the only place the claim and grant rules are exercised.
--
-- Three fixed uuids stand in for three members. Policies are checked by switching
-- to the `authenticated` role with a `request.jwt.claims` payload, which is what
-- auth.uid() reads inside a real PostgREST request.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(27);

-- ── fixtures ────────────────────────────────────────────────────────────────
-- Ayesha organizes tournament t-1. Bilal is a scorer. Sana is a bystander.
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
   '{"display_name":"Sana Iqbal"}');

select is(
  (select count(*)::int from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  1, 'the signup trigger still creates a profile row');

-- ── schema shape ────────────────────────────────────────────────────────────
select ok(
  (select bool_and(relrowsecurity) from pg_class
    where oid in (
      'public.match_organizer_claims'::regclass,
      'public.official_scorer_assignments'::regclass)),
  'row level security is enabled on the profile module tables');

select ok(
  not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and column_name in ('role', 'account_type', 'intent')),
  'the profile module adds no role or account-type column');

-- ── organizer A ─────────────────────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.claim_tournament_organizer('t-1');

select is(
  (select organizer_id from public.match_organizer_claims
    where tournament_id = 't-1'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'an organizer claims a tournament id as their own');

select throws_ok(
  $$ insert into public.official_scorer_assignments
       (tournament_id, fixture_id, scorer_profile_id, authorized_by)
     values ('t-1', 'f-direct',
             '22222222-2222-2222-2222-222222222222',
             '11111111-1111-1111-1111-111111111111') $$,
  '42501', null,
  'assignments cannot be inserted directly; only the RPC can write');

select is(
  (select status from public.assign_official_scorer(
     't-1', 'f-1', '22222222-2222-2222-2222-222222222222')),
  'assigned',
  'the organizer can assign a scorer to a match in their tournament');

select is(
  (select count(*)::int from public.official_scorer_assignments),
  1, 'the organizer sees the assignment they made');

-- ── scorer B ────────────────────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated"}';

select is(
  (select count(*)::int from public.official_scorer_assignments),
  1, 'the assigned scorer sees their own assignment');

select throws_ok(
  $$ select public.assign_official_scorer(
       't-1', 'f-2', '33333333-3333-3333-3333-333333333333') $$,
  '42501', null,
  'a scorer cannot assign another scorer to someone else''s tournament');

select throws_ok(
  $$ select public.revoke_official_scorer(
       'f-1', '22222222-2222-2222-2222-222222222222') $$,
  '42501', null,
  'a scorer cannot revoke their own assignment; the organizer owns it');

select public.respond_to_scorer_assignment(
  (select id from public.official_scorer_assignments where fixture_id = 'f-1'),
  true
);

select is(
  (select status from public.official_scorer_assignments where fixture_id = 'f-1'),
  'accepted', 'the scorer can accept their own assignment');

select public.claim_tournament_organizer('t-2');

select is(
  (select organizer_id from public.match_organizer_claims
    where tournament_id = 't-2'),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'a second member can claim a different tournament');

select throws_ok(
  $$ select public.claim_tournament_organizer('t-1') $$,
  '42501', null,
  'a tournament id already claimed by another member cannot be taken over');

-- ── bystander C ─────────────────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated"}';

select is(
  (select count(*)::int from public.official_scorer_assignments),
  0, 'an uninvolved member sees no assignments');

select throws_ok(
  $$ select public.respond_to_scorer_assignment(
       (select id from public.official_scorer_assignments where fixture_id = 'f-1'),
       true) $$,
  '42501', null,
  'a bystander cannot answer an assignment that is not theirs');

-- ── organizer A revokes ─────────────────────────────────────────────────────
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select public.revoke_official_scorer(
  'f-1', '22222222-2222-2222-2222-222222222222');

select is(
  (select status from public.official_scorer_assignments where fixture_id = 'f-1'),
  'revoked', 'the organizer can revoke an assignment');

select is(
  (select status from public.assign_official_scorer(
     't-1', 'f-1', '22222222-2222-2222-2222-222222222222')),
  'assigned',
  're-assigning the same pair restores the assignment instead of duplicating');

-- ── personal information ────────────────────────────────────────────────────
select public.update_profile_details(
  'Ayesha Khan', 'Karachi', 'Weekend cricketer',
  date '1996-04-12', 'woman', 'weekly'
);

select is(
  (select date_of_birth::text from public.profiles_private
    where profile_id = '11111111-1111-1111-1111-111111111111'),
  '1996-04-12', 'personal information writes the private row');

select throws_ok(
  $$ select public.update_profile_details(
       'A', 'Karachi', '', date '1996-04-12', null, 'weekly') $$,
  '22023', null,
  'personal information rejects a name the UI would refuse');

select public.change_profile_username('ayesha.k');

select is(
  (select username from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'ayesha.k', 'the username RPC is the only path that renames a member');

set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated"}';

select throws_ok(
  $$ select public.change_profile_username('AYESHA.K') $$,
  '23505', null,
  'usernames stay unique ignoring case across members');

-- ── sports preferences ──────────────────────────────────────────────────────
select public.replace_profile_sports(
  '[{"sport_key":"cricket","level":"intermediate","position":"Batter"},
    {"sport_key":"padel","level":null,"position":null}]'::jsonb
);

select is(
  (select count(*)::int from public.profile_sports
    where profile_id = '22222222-2222-2222-2222-222222222222'),
  2, 'sports preferences replace the whole set');

select throws_ok(
  $$ select public.replace_profile_sports('[]'::jsonb) $$,
  '22023', null,
  'an empty sport set is refused');

select throws_ok(
  $$ select public.replace_profile_sports(
       '[{"sport_key":"cricket"},{"sport_key":"cricket"}]'::jsonb) $$,
  '22023', null,
  'a duplicate sport is refused');

-- ── account settings ────────────────────────────────────────────────────────
select public.update_user_preferences(null, false, null);

select is(
  (select invites from public.user_preferences
    where profile_id = '22222222-2222-2222-2222-222222222222'),
  false, 'account settings write the preference row');

-- ── anonymous ───────────────────────────────────────────────────────────────
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok(
  'select * from public.official_scorer_assignments', '42501', null,
  'an anonymous visitor cannot read scorer assignments');

select throws_ok(
  $$ select public.claim_tournament_organizer('t-3') $$,
  '42501', null,
  'an anonymous visitor cannot claim a tournament');

select * from finish();
rollback;
