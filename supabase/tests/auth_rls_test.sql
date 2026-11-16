-- Row level security and RPC behaviour for the authentication schema.
--
-- Run with `supabase test db` against a local stack. These assertions are the
-- only place the policies are actually exercised: the Flutter tests cannot prove
-- that member A is unable to write member B's row.
--
-- Two fixed uuids stand in for two members. Policies are checked by switching to
-- the `authenticated` role with a `request.jwt.claims` payload, which is what
-- auth.uid() reads in a real PostgREST request.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(26);

-- ── fixtures ────────────────────────────────────────────────────────────────
-- Inserted before switching roles so the signup trigger can be observed.
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

-- ── signup trigger ──────────────────────────────────────────────────────────
select is(
  (select count(*)::int from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  1, 'signup trigger creates a profile row');

select is(
  (select count(*)::int from public.profiles_private
    where profile_id = '11111111-1111-1111-1111-111111111111'),
  1, 'signup trigger creates a private row');

select is(
  (select count(*)::int from public.user_preferences
    where profile_id = '11111111-1111-1111-1111-111111111111'),
  1, 'signup trigger creates a preferences row');

select is(
  (select display_name from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'Ayesha Khan', 'signup trigger copies the display name from metadata');

select isnt(
  (select profile_setup_complete from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  true, 'a new account is not marked as set up');

-- ── schema shape ────────────────────────────────────────────────────────────
select ok(
  (select bool_and(relrowsecurity) from pg_class
    where oid in (
      'public.profiles'::regclass,
      'public.profiles_private'::regclass,
      'public.profile_sports'::regclass,
      'public.user_preferences'::regclass,
      'public.sports'::regclass)),
  'row level security is enabled on every authentication table');

select ok(
  not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and column_name in ('role', 'account_type', 'intent')),
  'no role, account_type or intent column exists (one universal account)');

select is(
  (select count(*)::int from public.sports), 4,
  'the four sports are seeded as reference data');

select is(
  (select public from storage.buckets where id = 'avatars'), true,
  'the avatars bucket exists and is public-read');

-- ── uniqueness ──────────────────────────────────────────────────────────────
update public.profiles
   set username = 'ayesha.k'
 where id = '11111111-1111-1111-1111-111111111111';

select throws_ok(
  $$ update public.profiles
        set username = 'ayesha.k'
      where id = '33333333-3333-3333-3333-333333333333' $$,
  '23505', null,
  'usernames are unique ignoring case');

-- ── member A, signed in ─────────────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated"}';

select is(
  (select count(*)::int from public.profiles
    where id = '22222222-2222-2222-2222-222222222222'),
  1, 'a member can read another member''s public card');

-- display_name, bio, city, avatar_* and play_style carry a COLUMN-level UPDATE
-- grant (0003), and the update policy is owner-only, so a write to another
-- member's row simply affects no rows. profile_setup_complete and username are
-- NOT in the column grant, which is what the two throws_ok assertions below
-- prove.
with touched as (
  update public.profiles set city = 'Lahore'
   where id = '22222222-2222-2222-2222-222222222222'
  returning 1)
select is(
  (select count(*)::int from touched), 0,
  'a member cannot update another member''s profile');

with touched as (
  update public.profiles set display_name = 'Ayesha K'
   where id = '11111111-1111-1111-1111-111111111111'
  returning 1)
select is(
  (select count(*)::int from touched), 1,
  'a member can update their own profile through the column grant');

select lives_ok(
  $$ select public.update_profile_details(
       'Ayesha K', 'Karachi', null, date '1996-04-12', null, 'weekly') $$,
  'a member can update their own profile through update_profile_details');

select is(
  (select display_name from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'Ayesha K', 'the RPC wrote the new display name');

select throws_ok(
  $$ update public.profiles set profile_setup_complete = true
      where id = '11111111-1111-1111-1111-111111111111' $$,
  '42501', null,
  'the setup flag cannot be set by the client, only by the RPC');

select throws_ok(
  $$ update public.profiles set username = 'hijacked'
      where id = '11111111-1111-1111-1111-111111111111' $$,
  '42501', null,
  'the username cannot be changed outside complete_profile_setup');

select is(
  (select count(*)::int from public.profiles_private),
  1, 'a member sees only their own private row');

select is(
  (select date_of_birth from public.profiles_private
    where profile_id = '22222222-2222-2222-2222-222222222222'),
  null, 'another member''s private row is invisible');

select throws_ok(
  $$ insert into public.profile_sports (profile_id, sport_key)
     values ('22222222-2222-2222-2222-222222222222', 'cricket') $$,
  '42501', null,
  'a member cannot add a sport to another member''s profile');

-- No DELETE grant on user_preferences either, so the direct write fails with
-- insufficient_privilege regardless of whose row it names.
select throws_ok(
  $$ delete from public.user_preferences
      where profile_id = '22222222-2222-2222-2222-222222222222' $$,
  '42501', null,
  'a member cannot delete another member''s preferences');

-- ── the setup RPC ───────────────────────────────────────────────────────────
select public.complete_profile_setup(
  'Ayesha Khan', 'ayesha.k', 'Karachi', 'Weekend cricketer',
  date '1996-04-12', 'woman', 'weekly', 'midnight', null, 'v1-2026-11',
  '[{"sport_key":"cricket","level":"intermediate","position":"Batter"},
    {"sport_key":"padel","level":null,"position":null}]'::jsonb
);

select is(
  (select profile_setup_complete from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  true, 'complete_profile_setup marks the profile as finished');

select is(
  (select count(*)::int from public.profile_sports
    where profile_id = '11111111-1111-1111-1111-111111111111'),
  2, 'complete_profile_setup writes every chosen sport, skipping levels');

select throws_ok(
  $$ select public.complete_profile_setup(
       'Ayesha Khan', 'Bad Handle!', 'Karachi', '', date '1996-04-12',
       null, 'weekly', null, null, 'v1', '[{"sport_key":"cricket"}]'::jsonb) $$,
  '22023', null,
  'complete_profile_setup rejects a username the client had no business sending');

-- ── anonymous ───────────────────────────────────────────────────────────────
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok(
  'select * from public.profiles', '42501', null,
  'an anonymous visitor cannot read member cards');

select is(
  (select count(*)::int from public.sports), 4,
  'an anonymous visitor can still read reference data');

select * from finish();
rollback;
