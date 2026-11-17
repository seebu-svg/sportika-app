-- Behaviour and row-level security for the tournament discovery module
-- (migration 0016) and the notification triggers repaired by 0018.
--
-- Run with `.tmp/local_pg/apply.sh --test supabase/tests/discovery_tournament_test.sql`
-- against the scratch stack, or through `supabase test db` where the real pgTAP
-- extension takes over. Everything happens inside one transaction and rolls
-- back: the suite seeds five members, drives every client-facing tournament
-- RPC, and reads the notifications each one leaves behind.
--
-- Why this suite exists: the 0016 RPCs had no coverage at all, which is how the
-- 0017 trigger regression shipped through every gate. On the old bodies,
-- register_tournament_entry aborted with `record "v_t" has no field
-- "created_by"` and reject/withdraw aborted with `record "new" has no field
-- "user_id"` — only an approval passed. Every assertion below that ends in a
-- notification row doubles as proof of the 0018 repairs: the organizer hears
-- about registrations and withdrawals from the trigger, the captain hears about
-- approvals and rejections from the RPC, and the event keys stay disjoint.
--
-- Omar organizes. Arif, Basit and Usman captain entries. Zafar is an
-- uninvolved bystander for the RLS checks.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(47);

-- ── fixtures ────────────────────────────────────────────────────────────────
-- Seeded the way module_media_permissions seeds: skipped entirely once a
-- database already has members, otherwise turned into profile rows by the
-- signup trigger.
do $$begin
  if (select count(*) from public.profiles) < 5 then
    insert into auth.users
      (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
       created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
    values
      ('66666666-6666-6666-6666-666666666666',
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'omar@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
       now(), now(), '{"provider":"email","providers":["email"]}',
       '{"display_name":"Omar Farooq"}'),
      ('77777777-7777-7777-7777-777777777777',
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'arif@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
       now(), now(), '{"provider":"email","providers":["email"]}',
       '{"display_name":"Arif Khan"}'),
      ('88888888-8888-8888-8888-888888888888',
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'basit@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
       now(), now(), '{"provider":"email","providers":["email"]}',
       '{"display_name":"Basit Ahmed"}'),
      ('99999999-9999-9999-9999-999999999999',
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'usman@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
       now(), now(), '{"provider":"email","providers":["email"]}',
       '{"display_name":"Usman Chaudhry"}'),
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'zafar@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
       now(), now(), '{"provider":"email","providers":["email"]}',
       '{"display_name":"Zafar Iqbal"}')
    on conflict (id) do nothing;
  end if;
end$$;

select is(
  (select count(*)::int from public.profiles
    where id in ('66666666-6666-6666-6666-666666666666',
                 '77777777-7777-7777-7777-777777777777',
                 '88888888-8888-8888-8888-888888888888',
                 '99999999-9999-9999-9999-999999999999',
                 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  5, 'the five tournament members are seeded as real profiles');

-- ── create_tournament: draft vs publish_now, drafts are organizer-only ──────
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select public.create_tournament(
         'Ramadan Padel Cup', 'Karachi', 'padel', 'knockout',
         'Knockout · Best of 3', 'pair',
         now() + interval '7 days', now() + interval '14 days',
         8, 'PKR 2000', 'Best of 3', '{"bestOf":3}'::jsonb, false) as t1 \gset
select public.create_tournament(
         'Karachi Padel League', 'Karachi', 'padel', 'knockout',
         'Knockout · Best of 3', 'pair',
         now() + interval '7 days', now() + interval '14 days',
         8, 'PKR 2000', 'Best of 3', '{"bestOf":3}'::jsonb, true) as t2 \gset

select is(left(:'t1', 5), 'tour-',
  'create_tournament returns a tour- id');
select is(
  (select status from public.tournaments where id = :'t1'), 'draft',
  'publish_now=false leaves the tournament in draft');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '77777777-7777-7777-7777-777777777777',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select throws_ok(
  'select public.register_tournament_entry(' || quote_literal(:'t1')
    || ', ''Too early'', array[''77777777-7777-7777-7777-777777777777'']::uuid[], null)',
  '22023', 'registration_closed',
  'a draft tournament accepts no registrations');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select is(
  (select count(*)::int from public.tournaments where id = :'t1'), 0,
  'a draft is hidden from another member by RLS');
select is(
  (select count(*)::int from public.tournaments where id = :'t2'), 1,
  'an open tournament is visible to another member');

-- ── register_tournament_entry: success, guards, and the repaired trigger ────
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '77777777-7777-7777-7777-777777777777',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select public.register_tournament_entry(
         :'t2', 'Cup entry A',
         array['77777777-7777-7777-7777-777777777777',
               '88888888-8888-8888-8888-888888888888']::uuid[], null) as a2 \gset

select is(left(:'a2', 6), 'entry-',
  'a pair entry registers and returns an entry- id');

reset role;
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '66666666-6666-6666-6666-666666666666'
      and type = 'tournament_registration_received'
      and event_key = 'tournament_entry_new:' || :'a2'),
  1, 'the repaired entry trigger announces the registration to the organizer');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '77777777-7777-7777-7777-777777777777',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select throws_ok(
  'select public.register_tournament_entry(' || quote_literal(:'t2')
    || ', ''Cup entry A again'', array[''77777777-7777-7777-7777-777777777777'',
        ''88888888-8888-8888-8888-888888888888'']::uuid[], null)',
  '23505', 'already_registered',
  'registering the same members twice is refused');
select throws_ok(
  'select public.register_tournament_entry(' || quote_literal(:'t2')
    || ', ''Too many players'', array[''77777777-7777-7777-7777-777777777777'',
        ''88888888-8888-8888-8888-888888888888'',
        ''99999999-9999-9999-9999-999999999999'']::uuid[], null)',
  '22023', 'entry_type_mismatch',
  'a pair tournament refuses a three-player entry');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '99999999-9999-9999-9999-999999999999',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select throws_ok(
  'select public.register_tournament_entry(' || quote_literal(:'t2')
    || ', ''cup ENTRY a'', array[''99999999-9999-9999-9999-999999999999'']::uuid[], null)',
  '23505', 'entry_label_taken',
  'labels are unique case-insensitively');
select public.register_tournament_entry(
         :'t2', 'Cup entry C',
         array['99999999-9999-9999-9999-999999999999']::uuid[], null) as c2 \gset

select is(left(:'c2', 6), 'entry-',
  'a fresh label registers the same captain who was refused before');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select public.create_tournament(
         'Futsal Open Nights', 'Karachi', 'futsal', 'knockout',
         'Knockout · 5 a side', 'individual',
         now() + interval '7 days', now() + interval '14 days',
         2, 'PKR 500', 'Street rules', '{}'::jsonb, true) as t3 \gset

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '77777777-7777-7777-7777-777777777777',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select public.register_tournament_entry(
         :'t3', 'Solo A', array['77777777-7777-7777-7777-777777777777']::uuid[], null) as a3 \gset

select is(left(:'a3', 6), 'entry-',
  'the first individual entry registers');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '88888888-8888-8888-8888-888888888888',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select public.register_tournament_entry(
         :'t3', 'Solo B', array['88888888-8888-8888-8888-888888888888']::uuid[], null) as b3 \gset

select is(left(:'b3', 6), 'entry-',
  'the second individual entry registers');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '99999999-9999-9999-9999-999999999999',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select throws_ok(
  'select public.register_tournament_entry(' || quote_literal(:'t3')
    || ', ''Solo C'', array[''99999999-9999-9999-9999-999999999999'']::uuid[], null)',
  '22023', 'tournament_full',
  'the limit counts pending entries, exactly like the server');

-- ── decide_tournament_entry: the RPC announces, the trigger stays silent ────
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  'select public.decide_tournament_entry(' || quote_literal(:'a2') || ', true, null)',
  'the organizer approves the entry');

reset role;
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '77777777-7777-7777-7777-777777777777'
      and event_key = 'tournament_entry:' || :'a2' || ':confirmed'),
  1, 'the captain is told about the approval once, under the RPC event key');
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '77777777-7777-7777-7777-777777777777'),
  1, 'no trigger joins in on the approval, so the captain is not told twice');
select is(
  (select status from public.tournament_entries where id = :'a2'), 'confirmed',
  'the approved entry is confirmed');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  'select public.decide_tournament_entry(' || quote_literal(:'c2')
    || ', false, ''Roster incomplete'')',
  'the organizer rejects the entry with a note');

reset role;
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '99999999-9999-9999-9999-999999999999'
      and event_key = 'tournament_entry:' || :'c2' || ':rejected'),
  1, 'the captain is told about the rejection once');
select is(
  (select status from public.tournament_entries where id = :'c2'), 'rejected',
  'the rejected entry carries the decision');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  'select public.decide_tournament_entry(' || quote_literal(:'c2') || ', false, null)',
  're-deciding an already-decided entry is a no-op');

reset role;
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '99999999-9999-9999-9999-999999999999'),
  1, 'the no-op decision does not re-notify the captain');

-- ── withdraw_tournament_entry: the trigger tells the organizer ──────────────
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '77777777-7777-7777-7777-777777777777',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  'select public.withdraw_tournament_entry(' || quote_literal(:'a2') || ')',
  'the captain withdraws the confirmed entry');

reset role;
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '66666666-6666-6666-6666-666666666666'
      and type = 'tournament_entry_withdrawn'
      and event_key = 'tournament_entry_withdrawn:' || :'a2'),
  1, 'the repaired trigger tells the organizer about the withdrawal');
select is(
  (select status from public.tournament_entries where id = :'a2'), 'withdrawn',
  'the withdrawn entry keeps its history');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '77777777-7777-7777-7777-777777777777',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  'select public.withdraw_tournament_entry(' || quote_literal(:'a2') || ')',
  'withdrawing twice is accepted');

reset role;
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '66666666-6666-6666-6666-666666666666'
      and event_key = 'tournament_entry_withdrawn:' || :'a2'),
  1, 'the idempotent withdrawal does not re-notify the organizer');

-- ── set_tournament_status: one tournament_started per captain ───────────────
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  'select public.decide_tournament_entry(' || quote_literal(:'a3') || ', true, null)',
  'the organizer confirms the first entry');
select lives_ok(
  'select public.decide_tournament_entry(' || quote_literal(:'b3') || ', true, null)',
  'the organizer confirms the second entry');

reset role;
select is(
  (select count(*)::int from public.tournament_entries
    where tournament_id = :'t3' and status = 'confirmed'),
  2, 'both futsal entries are confirmed');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  'select public.set_tournament_status(' || quote_literal(:'t3') || ', ''inProgress'')',
  'the organizer starts the tournament');

reset role;
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '77777777-7777-7777-7777-777777777777'
      and event_key = 'tournament_started:' || :'t3' || ':' || :'a3'),
  1, 'the start is announced once: the RPC and the trigger share one event key');
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '88888888-8888-8888-8888-888888888888'
      and event_key = 'tournament_started:' || :'t3' || ':' || :'b3'),
  1, 'every confirmed captain hears about the start once');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  'select public.set_tournament_status(' || quote_literal(:'t3') || ', ''inProgress'')',
  'starting an already-running tournament is accepted');

reset role;
select is(
  (select count(*)::int from public.notifications
    where recipient_id = '77777777-7777-7777-7777-777777777777'
      and event_key = 'tournament_started:' || :'t3' || ':' || :'a3'),
  1, 'starting twice does not re-notify the captain');
select is(
  (select status from public.tournaments where id = :'t3'), 'inProgress',
  'the tournament is under way');

-- ── generate_tournament_draw: fixtures, status flip, trigger notification ───
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select public.create_tournament(
         'Cricket Tape Ball Cup', 'Karachi', 'cricket', 'knockout',
         'Knockout · 8 overs', 'individual',
         now() + interval '7 days', now() + interval '14 days',
         4, 'PKR 300', 'Tape ball rules', '{}'::jsonb, true) as t4 \gset

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '77777777-7777-7777-7777-777777777777',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select public.register_tournament_entry(
         :'t4', 'Draw A', array['77777777-7777-7777-7777-777777777777']::uuid[], null) as a4 \gset

select is(left(:'a4', 6), 'entry-',
  'the first draw entry registers');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '88888888-8888-8888-8888-888888888888',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select public.register_tournament_entry(
         :'t4', 'Draw B', array['88888888-8888-8888-8888-888888888888']::uuid[], null) as b4 \gset

select is(left(:'b4', 6), 'entry-',
  'the second draw entry registers');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  'select public.decide_tournament_entry(' || quote_literal(:'a4') || ', true, null)',
  'the organizer confirms the first draw entry');
select lives_ok(
  'select public.decide_tournament_entry(' || quote_literal(:'b4') || ', true, null)',
  'the organizer confirms the second draw entry');
select public.generate_tournament_draw(:'t4') as dc \gset

reset role;
select is((:'dc')::int, 1,
  'two confirmed entries draw one knockout fixture');
select is(
  (select count(*)::int from public.matches where tournament_id = :'t4'),
  1, 'the fixture is a matches row the match module owns');
select is(
  (select status from public.tournaments where id = :'t4'), 'inProgress',
  'the bare status flip from the draw is caught by the trigger');
select is(
  (select count(*)::int from public.notifications
    where recipient_id in ('77777777-7777-7777-7777-777777777777',
                           '88888888-8888-8888-8888-888888888888')
      and event_key like 'tournament_started:' || :'t4' || ':%'),
  2, 'the draw path alone notifies both captains, through the trigger');

reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666',
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
select throws_ok(
  'select public.generate_tournament_draw(' || quote_literal(:'t4') || ')',
  '23505', 'draw_exists',
  'the draw cannot be generated twice');

select * from finish();
rollback;
