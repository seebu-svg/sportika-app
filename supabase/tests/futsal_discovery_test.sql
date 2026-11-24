-- The futsal discovery authority: registration, the draw, and the three ways
-- into a match.
--
-- Everything runs through the same RPCs the app calls, so every assertion below
-- is about server-derived state: the entry `register_tournament_entry` built
-- from a squad, the fixture `generate_tournament_draw` sized and seeded, and the
-- participant rows `join_match`/`leave_match`/`add_match_squad` write.
--
-- `_tap_user(1)` organizes both tournaments and every match. Users 2-6 are the
-- Falcons, 7-11 the Hawks, 15-18 fill the organizer's own squad. 12 is a
-- signed-in stranger, 13 the owner of a two-player squad and the assigned
-- scorer of one match, 14 joins that two-player squad.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(44);

-- ── members, logins and small writers ───────────────────────────────────────
create or replace function public._tap_user(p_n int)
returns uuid
language sql
immutable
as $$ select ('b0000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid $$;

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
security definer
set search_path = public
as $$ select id from public.matches where title = p_title $$;

create or replace function public._tap_tournament(p_name text)
returns text
language sql
stable
as $$ select id from public.tournaments where name = p_name $$;

create or replace function public._tap_team(p_name text)
returns text
language sql
stable
as $$ select id from public.teams where name = p_name $$;

-- The registration and match RPCs are called through these wrappers so the
-- expected-error assertions stay plain literals (no interpolated ids).
create or replace function public._tap_register(
  p_tournament text, p_label text, p_squad text
)
returns text
language sql
as $$
  select public.register_tournament_entry(
    public._tap_tournament(p_tournament), p_label, '{}'::uuid[],
    public._tap_team(p_squad));
$$;

create or replace function public._tap_register_members(
  p_tournament text, p_label text, p_members uuid[]
)
returns text
language sql
as $$
  select public.register_tournament_entry(
    public._tap_tournament(p_tournament), p_label, p_members, null);
$$;

create or replace function public._tap_decide(
  p_tournament text, p_label text, p_approve boolean
)
returns void
language sql
as $$
  select public.decide_tournament_entry(
    (select e.id
       from public.tournament_entries e
       join public.tournaments t on t.id = e.tournament_id
      where t.name = p_tournament and e.label = p_label),
    p_approve, null);
$$;

create or replace function public._tap_register_squad(p_squad text)
returns void
language sql
as $$ select public.respond_team_invite(public._tap_team(p_squad), true) $$;

create or replace function public._tap_join(p_title text, p_side int)
returns text
language sql
as $$
  select (public.join_match(public._tap_match(p_title), p_side)).status;
$$;

create or replace function public._tap_join_side(p_title text, p_side int)
returns int
language sql
as $$
  select (public.join_match(public._tap_match(p_title), p_side)).side;
$$;

create or replace function public._tap_leave(p_title text)
returns void
language sql
as $$ select public.leave_match(public._tap_match(p_title)) $$;

create or replace function public._tap_add_squad(
  p_title text, p_side int, p_squad text
)
returns int
language sql
as $$
  select public.add_match_squad(
    public._tap_match(p_title), p_side, public._tap_team(p_squad));
$$;

-- Readers. These are security definer so the suite sees the rows the server
-- wrote regardless of which member's claims are current.
create or replace function public._tap_entry_members(
  p_tournament text, p_label text
)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select (select array_agg(m order by m) from unnest(e.member_ids) m)
    from public.tournament_entries e
    join public.tournaments t on t.id = e.tournament_id
   where t.name = p_tournament and e.label = p_label;
$$;

create or replace function public._tap_entry_status(
  p_tournament text, p_label text
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select e.status
    from public.tournament_entries e
    join public.tournaments t on t.id = e.tournament_id
   where t.name = p_tournament and e.label = p_label;
$$;

create or replace function public._tap_parts(
  p_title text, p_side int, p_status text, p_user uuid
)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.match_participants mp
   where mp.match_id = public._tap_match(p_title)
     and (p_side   is null or mp.side   = p_side)
     and (p_status is null or mp.status = p_status)
     and (p_user   is null or mp.profile_id = p_user);
$$;

create or replace function public._tap_participant_status(
  p_title text, p_user uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select mp.status from public.match_participants mp
   where mp.match_id = public._tap_match(p_title)
     and mp.profile_id = p_user;
$$;

create or replace function public._tap_draw_parts(
  p_tournament text, p_side int, p_status text
)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.match_participants mp
    join public.matches m      on m.id = mp.match_id
    join public.tournaments t  on t.id = m.tournament_id
   where t.name = p_tournament and mp.side = p_side and mp.status = p_status;
$$;

create or replace function public._tap_draw_capacity(p_tournament text)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select m.capacity
    from public.matches m
    join public.tournaments t on t.id = m.tournament_id
   where t.name = p_tournament
   limit 1;
$$;

-- ── fixtures ────────────────────────────────────────────────────────────────
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
select
  public._tap_user(i),
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'discovery' || i || '@sportika.test', '$2a$10$notarealhashnotarealhashno',
  now(), now(), now(), '{"provider":"email","providers":["email"]}',
  jsonb_build_object('display_name', 'Discovery Player ' || i)
from generate_series(1, 18) i;

-- ── schema shape ────────────────────────────────────────────────────────────
select ok(
  has_function_privilege('authenticated', 'public.join_match(uuid, int)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.leave_match(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.add_match_squad(uuid, int, text)', 'EXECUTE'),
  'signed-in members may join, leave and invite a squad');

select ok(
  not has_function_privilege('anon', 'public.join_match(uuid, int)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.leave_match(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.add_match_squad(uuid, int, text)', 'EXECUTE'),
  'anonymous visitors cannot');

select ok(
  (select bool_and(prosecdef) from pg_proc
    where oid in ('public.join_match(uuid,int)'::regprocedure,
                  'public.leave_match(uuid)'::regprocedure,
                  'public.add_match_squad(uuid,int,text)'::regprocedure)),
  'the three doors are security definer like every other write path');

-- ── the organizer's world ───────────────────────────────────────────────────
set local role authenticated;
select public._tap_login(1);

select public.create_tournament(
  p_name => 'Futsal League', p_city => 'Karachi', p_sport_key => 'futsal',
  p_format => 'knockout', p_format_label => 'Knockout', p_entry_type => 'team',
  p_starts_at => '2027-01-05 18:00+05', p_ends_at => '2027-01-06 18:00+05',
  p_registration_limit => 8, p_entry_fee => 'PKR 0',
  p_match_rules => '2 x 20 min',
  p_rules => '{"halves":2,"halfMinutes":20}'::jsonb,
  p_publish_now => true, p_venue => 'Futsal Arena');

select public.create_tournament(
  p_name => 'Futsal Undersized', p_city => 'Karachi', p_sport_key => 'futsal',
  p_format => 'knockout', p_format_label => 'Knockout', p_entry_type => 'team',
  p_starts_at => '2027-02-05 18:00+05', p_ends_at => '2027-02-06 18:00+05',
  p_registration_limit => 8, p_entry_fee => 'PKR 0',
  p_match_rules => '2 x 20 min',
  p_rules => '{"halves":2,"halfMinutes":20}'::jsonb,
  p_publish_now => true, p_venue => 'Futsal Arena');

select public.create_match(
  p_sport_key => 'futsal', p_format_label => '2 x 20 min',
  p_rules => '{"halves":2,"halfMinutes":20}'::jsonb,
  p_title => 'Join Night', p_venue => 'Court J',
  p_scheduled_at => '2027-01-07 18:00+05', p_visibility => 'public',
  p_side_a => 'North', p_side_b => 'South',
  p_capacity => 10, p_discipline => 'team');

select public.create_match(
  p_sport_key => 'futsal', p_format_label => '2 x 20 min',
  p_rules => '{"halves":2,"halfMinutes":20}'::jsonb,
  p_title => 'Invite Only', p_venue => 'Court K',
  p_scheduled_at => '2027-01-07 19:00+05', p_visibility => 'invite',
  p_side_a => 'East', p_side_b => 'West',
  p_capacity => 10, p_discipline => 'team');

select public.create_match(
  p_sport_key => 'futsal', p_format_label => '2 x 20 min',
  p_rules => '{"halves":2,"halfMinutes":20}'::jsonb,
  p_title => 'Kickoff Soon', p_venue => 'Court L',
  p_scheduled_at => '2027-01-07 20:00+05', p_visibility => 'public',
  p_side_a => 'Harbour', p_side_b => 'Valley',
  p_capacity => 10, p_discipline => 'team');

select public.create_match(
  p_sport_key => 'futsal', p_format_label => '2 x 20 min',
  p_rules => '{"halves":2,"halfMinutes":20}'::jsonb,
  p_title => 'Squad Night', p_venue => 'Court M',
  p_scheduled_at => '2027-01-08 18:00+05', p_visibility => 'public',
  p_side_a => 'Ridge', p_side_b => 'Meadow',
  p_capacity => 10, p_discipline => 'team');

select public.create_match(
  p_sport_key => 'futsal', p_format_label => '2 x 20 min',
  p_rules => '{"halves":2,"halfMinutes":20}'::jsonb,
  p_title => 'Scored Night', p_venue => 'Court N',
  p_scheduled_at => '2027-01-08 19:00+05', p_visibility => 'public',
  p_side_a => 'Lake', p_side_b => 'Park',
  p_capacity => 10, p_discipline => 'team',
  p_scorer_id => public._tap_user(13));

select public.create_match(
  p_sport_key => 'futsal', p_format_label => '2 x 20 min',
  p_rules => '{"halves":2,"halfMinutes":20}'::jsonb,
  p_title => 'Squad Cap', p_venue => 'Court O',
  p_scheduled_at => '2027-01-08 20:00+05', p_visibility => 'public',
  p_side_a => 'Hill', p_side_b => 'Dale',
  p_capacity => 10, p_discipline => 'team');

-- One match is already under way, so the three "before kick-off" guards have
-- something to refuse.
select public.start_match(public._tap_match('Kickoff Soon'));

reset role;
-- A four-player entry cannot be produced by the RPC (it refuses), which is the
-- point; these rows exist to prove the two other guards also refuse one.
insert into public.tournament_entries
  (id, tournament_id, captain_id, label, member_ids, status)
values
  ('entry-thin-a', public._tap_tournament('Futsal Undersized'),
   public._tap_user(2), 'Thin A',
   array[public._tap_user(2), public._tap_user(3),
         public._tap_user(4), public._tap_user(5)], 'pending'),
  ('entry-thin-b', public._tap_tournament('Futsal Undersized'),
   public._tap_user(7), 'Thin B',
   array[public._tap_user(7), public._tap_user(8),
         public._tap_user(9), public._tap_user(10)], 'confirmed'),
  ('entry-thin-c', public._tap_tournament('Futsal Undersized'),
   public._tap_user(11), 'Thin C',
   array[public._tap_user(11), public._tap_user(12),
         public._tap_user(15), public._tap_user(16)], 'confirmed');
set local role authenticated;

-- ── the squads ──────────────────────────────────────────────────────────────
select public._tap_login(2);
select public.create_team(
  'Falcons', 'futsal', 'team',
  array[public._tap_user(3), public._tap_user(4),
        public._tap_user(5), public._tap_user(6)]);

select public._tap_login(3);
select public._tap_register_squad('Falcons');
select public._tap_login(4);
select public._tap_register_squad('Falcons');
select public._tap_login(5);
select public._tap_register_squad('Falcons');
select public._tap_login(6);
select public._tap_register_squad('Falcons');

select public._tap_login(7);
select public.create_team(
  'Hawks', 'futsal', 'team',
  array[public._tap_user(8), public._tap_user(9),
        public._tap_user(10), public._tap_user(11)]);

select public._tap_login(8);
select public._tap_register_squad('Hawks');
select public._tap_login(9);
select public._tap_register_squad('Hawks');
select public._tap_login(10);
select public._tap_register_squad('Hawks');
select public._tap_login(11);
select public._tap_register_squad('Hawks');

select public._tap_login(1);
select public.create_team(
  'Riverside', 'futsal', 'team',
  array[public._tap_user(15), public._tap_user(16),
        public._tap_user(17), public._tap_user(18)]);

select public._tap_login(15);
select public._tap_register_squad('Riverside');
select public._tap_login(16);
select public._tap_register_squad('Riverside');
select public._tap_login(17);
select public._tap_register_squad('Riverside');
select public._tap_login(18);
select public._tap_register_squad('Riverside');

select public._tap_login(13);
select public.create_team(
  'Sparse', 'futsal', 'team', array[public._tap_user(14)]);

select public._tap_login(14);
select public._tap_register_squad('Sparse');

select public._tap_login(12);
select public.create_team('Solo', 'futsal', 'individual');

-- ════════════════════════════════════════════════════════════════════════════
-- R: registration is derived from the squad
-- ════════════════════════════════════════════════════════════════════════════
select public._tap_login(2);
select public._tap_register('Futsal League', '', 'Falcons');

select is(
  public._tap_entry_status('Futsal League', 'Falcons'),
  'pending',
  'a squad entry still waits for the organizer');

select is(
  public._tap_entry_members('Futsal League', 'Falcons'),
  array[public._tap_user(2), public._tap_user(3), public._tap_user(4),
        public._tap_user(5), public._tap_user(6)],
  'the entry carries the whole squad, not just the captain who sent it');

select public._tap_login(12);
select throws_ok(
  $$ select public._tap_register('Futsal League', 'Outsider', 'Falcons') $$,
  '42501', null,
  'only somebody on the squad may enter it');

select public._tap_login(13);
select throws_ok(
  $$ select public._tap_register('Futsal League', '', 'Sparse') $$,
  '22023', null,
  'a two-player squad cannot enter a futsal tournament');

select public._tap_login(12);
select throws_ok(
  $$ select public._tap_register('Futsal League', '', 'Solo') $$,
  '22023', null,
  'an individual squad cannot enter a team tournament');

select throws_ok(
  $$ select public._tap_register_members(
       'Futsal League', 'Handpicked',
       array[public._tap_user(12), public._tap_user(15),
             public._tap_user(16)]) $$,
  '22023', null,
  'the five-a-side floor also applies to an entry built by hand');

select public._tap_login(7);
select public._tap_register('Futsal League', '', 'Hawks');

select is(
  public._tap_entry_members('Futsal League', 'Hawks'),
  array[public._tap_user(7), public._tap_user(8), public._tap_user(9),
        public._tap_user(10), public._tap_user(11)],
  'the second squad arrives the same way');

-- ════════════════════════════════════════════════════════════════════════════
-- C: confirming re-checks the floor
-- ════════════════════════════════════════════════════════════════════════════
select public._tap_login(1);
select throws_ok(
  $$ select public._tap_decide('Futsal Undersized', 'Thin A', true) $$,
  '22023', null,
  'confirming a four-player squad is refused, so it can never reach a draw');

select public._tap_decide('Futsal League', 'Falcons', true);
select public._tap_decide('Futsal League', 'Hawks', true);

select is(
  (select array_agg(e.label order by e.label)
     from public.tournament_entries e
     join public.tournaments t on t.id = e.tournament_id
    where t.name = 'Futsal League' and e.status = 'confirmed'),
  array['Falcons', 'Hawks'],
  'confirming both full squads is what a draw can start from');

-- ════════════════════════════════════════════════════════════════════════════
-- D: the draw sizes and seeds its fixtures
-- ════════════════════════════════════════════════════════════════════════════
select is(
  public.generate_tournament_draw(public._tap_tournament('Futsal League')),
  1,
  'two confirmed squads make one fixture');

select is(
  public._tap_draw_capacity('Futsal League'),
  10,
  'the fixture is sized for five a side, not for the registration limit');

select is(
  public._tap_draw_parts('Futsal League', 0, 'accepted'),
  5,
  'side A is provisioned with its full squad');

select is(
  public._tap_draw_parts('Futsal League', 1, 'accepted'),
  5,
  'side B is provisioned with its full squad');

select is(
  public._tap_draw_parts('Futsal League', 0, 'accepted')
  + public._tap_draw_parts('Futsal League', 1, 'accepted'),
  10,
  'draw provisioning is the one write that needs no invitation');

select is(
  (select status from public.tournaments where name = 'Futsal League'),
  'inProgress',
  'a created fixture moves the tournament on');

select throws_ok(
  $$ select public.generate_tournament_draw(
       public._tap_tournament('Futsal League')) $$,
  '23505', null,
  'a second draw is refused');

select throws_ok(
  $$ select public.generate_tournament_draw(
       public._tap_tournament('Futsal Undersized')) $$,
  '22023', null,
  'a draw cannot start from a four-player squad');

-- ════════════════════════════════════════════════════════════════════════════
-- J: joining a public match
-- ════════════════════════════════════════════════════════════════════════════
select public._tap_login(2);
select is(
  public._tap_join('Join Night', 1),
  'accepted',
  'joining is the consent, so the row is written accepted');

select is(
  public._tap_join_side('Join Night', 0),
  1,
  'joining again is a no-op that keeps the side already held');

select is(
  public._tap_parts('Join Night', null, null, public._tap_user(2)),
  1,
  'the second join did not write a second row');

select public._tap_login(1);
select is(
  public._tap_join('Join Night', 0),
  'accepted',
  'the organizer joining their own match finds the seat they already hold');

select public._tap_login(3);
select public._tap_join('Join Night', 1);
select public._tap_login(4);
select public._tap_join('Join Night', 1);
select public._tap_login(5);
select public._tap_join('Join Night', 1);
select public._tap_login(6);
select public._tap_join('Join Night', 1);

select is(
  public._tap_parts('Join Night', 1, 'accepted', null),
  5,
  'a side accepts exactly half the capacity: five of ten');

select public._tap_login(15);
select throws_ok(
  $$ select public._tap_join('Join Night', 1) $$,
  '22023', null,
  'a full side refuses the next player');

select public._tap_login(16);
select throws_ok(
  $$ select public._tap_join('Join Night', 2) $$,
  '22023', null,
  'a side index outside zero and one is refused');

select public._tap_login(2);
select throws_ok(
  $$ select public._tap_join('Invite Only', 1) $$,
  '42501', null,
  'a private match cannot be joined, only invited into');

select throws_ok(
  $$ select public._tap_join('Kickoff Soon', 1) $$,
  '22023', null,
  'a match that has kicked off takes no joiners');

-- ════════════════════════════════════════════════════════════════════════════
-- L: leaving before kick-off
-- ════════════════════════════════════════════════════════════════════════════
select public._tap_leave('Join Night');

select is(
  public._tap_participant_status('Join Night', public._tap_user(2)),
  'removed',
  'leaving marks the row removed instead of deleting the audit');

select is(
  public._tap_parts('Join Night', 1, 'accepted', null),
  4,
  'the side the player left frees the slot');

select is(
  public._tap_join('Join Night', 1),
  'accepted',
  'a removed player can come back, and the same row flips to accepted');

select public._tap_login(1);
select throws_ok(
  $$ select public._tap_leave('Join Night') $$,
  '22023', null,
  'the organizer cannot walk out of their own match');

select public._tap_login(12);
select throws_ok(
  $$ select public._tap_leave('Join Night') $$,
  'P0002', null,
  'a stranger has nothing to leave');

select public._tap_login(2);
select throws_ok(
  $$ select public._tap_leave('Kickoff Soon') $$,
  '22023', null,
  'nobody leaves after kick-off');

-- ════════════════════════════════════════════════════════════════════════════
-- A: adding a whole squad
-- ════════════════════════════════════════════════════════════════════════════
select public._tap_login(1);
select is(
  public._tap_add_squad('Squad Night', 1, 'Riverside'),
  4,
  'the squad members who are not already in the match are invited');

select is(
  public._tap_parts('Squad Night', 1, 'invited', null),
  4,
  'squad members are invited, not enrolled: consent stays with the player');

select is(
  public._tap_parts('Squad Night', 0, 'accepted', null),
  1,
  'the organizer was not moved off their own side');

select is(
  public._tap_add_squad('Squad Night', 1, 'Riverside'),
  0,
  'adding the same squad twice adds nobody');

select public._tap_login(12);
select throws_ok(
  $$ select public._tap_add_squad('Squad Night', 1, 'Riverside') $$,
  '42501', null,
  'only the organizer or the assigned scorer may add a squad');

select public._tap_login(13);
select throws_ok(
  $$ select public._tap_add_squad('Scored Night', 1, 'Riverside') $$,
  '42501', null,
  'the caller must belong to the squad they are adding');

select public._tap_login(2);
select public._tap_join('Squad Cap', 1);
select public._tap_login(3);
select public._tap_join('Squad Cap', 1);

select public._tap_login(1);
select throws_ok(
  $$ select public._tap_add_squad('Squad Cap', 1, 'Riverside') $$,
  '22023', null,
  'a squad that does not fit the side is refused before anything is written');

select is(
  public._tap_parts('Squad Cap', 1, 'invited', null),
  0,
  'the refused squad left nothing behind');

select throws_ok(
  $$ select public._tap_add_squad('Kickoff Soon', 1, 'Riverside') $$,
  '22023', null,
  'a started match takes no new squad');

select finish();
rollback;
