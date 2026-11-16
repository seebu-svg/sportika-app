-- Sportika discovery module: tournaments, tournament entries, community pickup
-- games and teams.
--
-- Until now the four sports' discovery surfaces existed only in the device
-- document, so a server-backed build showed live identity next to seeded
-- fiction. This migration gives those aggregates a home and keeps the same
-- conventions as 0007/0012:
--
--   * RLS is enabled but never forced, so the `security definer` RPCs and
--     triggers below can write while PostgREST clients stay policy-gated.
--   * Clients only ever hold SELECT. Every write is an RPC that derives the
--     actor from auth.uid() and takes no actor id.
--   * Ids stay TEXT because the Flutter models (`Tournament.id`, `Entry.id`,
--     `Fixture.id`) are strings generated on the client in demo builds.
--
-- A tournament fixture is NOT a table here: it is a `public.matches` row with
-- `tournament_id`/`fixture_id` (0008 already added the columns and the partial
-- unique index that keeps one match per fixture). Sides, venue, the scorer, the
-- event log, results and disputes therefore reuse the match module end to end.
--
-- `is_demo` marks content created for preview/testing. It exists on every table
-- here and on `matches`; it never exists on `profiles`, so demo content can be
-- deleted without touching a member, and a real member's rows are never marked.
--
-- 0015's tournament notification triggers target a different, unbuilt aggregate
-- (`tournament_entries.user_id`, `tournament_matches`, `tournament_staff`), so
-- they stay dormant; this file emits the two notifications a member needs.
begin;

-- ── parked legacy aggregate ─────────────────────────────────────────────────
-- The hosted project predates this file with an unfinished tournament module
-- (uuid ids, one entry row per user, a `tournament_matches` bracket table and
-- its own RPCs). No migration in this repository creates it, no Dart code reads
-- it, and it holds no rows; it can only collide with the aggregate below
-- (`tournaments.starts_at` and friends). It is moved, not dropped: the tables
-- keep their rows and the helpers are renamed, so nothing is lost and the two
-- shapes can no longer be confused. Re-running this file skips the block.
do $$
#variable_conflict use_variable
declare
  v_fn record;
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'tournaments'
                and column_name = 'created_by')
     and not exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'tournaments'
                and column_name = 'organizer_id') then
    create schema if not exists legacy;

    -- Children first so the foreign keys travel with their parents.
    if to_regclass('public.tournament_matches') is not null then
      alter table public.tournament_matches set schema legacy;
    end if;
    if to_regclass('public.tournament_staff') is not null then
      alter table public.tournament_staff set schema legacy;
    end if;
    if to_regclass('public.tournament_entries') is not null then
      alter table public.tournament_entries set schema legacy;
    end if;
    alter table public.tournaments set schema legacy;

    -- The helpers keep their bodies and stop sharing a name with the RPCs this
    -- file introduces.
    for v_fn in
      select p.oid::regprocedure as signature, p.proname
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in ('create_tournament', 'create_tournament_draw',
                           'manage_tournament_entry', 'is_tournament_manager',
                           'is_tournament_scorer',
                           'enforce_tournament_registration_window')
    loop
      execute format('alter function %s rename to %I',
                     v_fn.signature, 'legacy_' || v_fn.proname);
    end loop;
  end if;
end $$;

-- ── matches: demo marker ────────────────────────────────────────────────────
alter table public.matches
  add column if not exists is_demo boolean not null default false;

create index if not exists matches_demo on public.matches (is_demo)
  where is_demo;

-- ── tournaments ─────────────────────────────────────────────────────────────
create table if not exists public.tournaments (
  id                 text primary key,
  organizer_id       uuid not null references public.profiles (id) on delete cascade,
  name               text not null,
  city               text not null default 'Karachi',
  venue              text not null default '',
  sport_key          text not null references public.sports (key),
  format_label       text not null default '',
  format             text not null default 'knockout',
  entry_type         text not null default 'team',
  starts_at          timestamptz not null,
  ends_at            timestamptz not null,
  registration_limit int  not null default 8,
  entry_fee          text not null default 'PKR 0',
  match_rules        text not null default '',
  rules              jsonb not null default '{}'::jsonb,
  banner_url         text,
  status             text not null default 'draft',
  is_demo            boolean not null default false,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  constraint tournaments_name_len    check (char_length(name) between 3 and 80),
  constraint tournaments_city_len    check (char_length(city) <= 80),
  constraint tournaments_venue_len   check (char_length(venue) <= 120),
  constraint tournaments_fee_len     check (char_length(entry_fee) <= 40),
  constraint tournaments_rules_len   check (char_length(match_rules) <= 2000),
  constraint tournaments_limit       check (registration_limit between 2 and 128),
  constraint tournaments_window      check (ends_at > starts_at),
  -- Vocabulary mirrors TournamentFormat / EntryType / TournamentStatus in
  -- lib/shared/models/enums.dart; a value the client does not know would parse
  -- as `knockout` / `team` / `draft` and hide the record behind a wrong label.
  constraint tournaments_format      check (format in ('knockout', 'group')),
  constraint tournaments_entry_type  check (entry_type in ('individual', 'pair', 'team')),
  constraint tournaments_status
    check (status in ('draft', 'open', 'inProgress', 'completed'))
);

alter table public.tournaments enable row level security;
revoke all on public.tournaments from public, anon, authenticated;
grant select on public.tournaments to authenticated;

create index if not exists tournaments_status on public.tournaments (status, starts_at);
create index if not exists tournaments_sport  on public.tournaments (sport_key, status);
create index if not exists tournaments_org   on public.tournaments (organizer_id);

drop trigger if exists tournaments_touch on public.tournaments;
create trigger tournaments_touch
  before update on public.tournaments
  for each row execute function public.touch_updated_at();

-- ── tournament entries ──────────────────────────────────────────────────────
create table if not exists public.tournament_entries (
  id            text primary key,
  tournament_id text not null references public.tournaments (id) on delete cascade,
  captain_id    uuid not null references public.profiles (id) on delete cascade,
  label         text not null,
  squad_id      text,
  member_ids    uuid[] not null default '{}'::uuid[],
  status        text not null default 'pending',
  decision_note text,
  is_demo       boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint entries_label_len check (char_length(label) between 1 and 60),
  constraint entries_note_len  check (character_length(coalesce(decision_note, '')) <= 200),
  constraint entries_members   check (cardinality(member_ids) between 1 and 40),
  constraint entries_status
    check (status in ('pending', 'confirmed', 'rejected', 'withdrawn')),
  unique (tournament_id, label)
);

alter table public.tournament_entries enable row level security;
revoke all on public.tournament_entries from public, anon, authenticated;
grant select on public.tournament_entries to authenticated;

create index if not exists entries_tournament on public.tournament_entries (tournament_id, status);
create index if not exists entries_members    on public.tournament_entries using gin (member_ids);

drop trigger if exists tournament_entries_touch on public.tournament_entries;
create trigger tournament_entries_touch
  before update on public.tournament_entries
  for each row execute function public.touch_updated_at();

-- ── community pickup games ──────────────────────────────────────────────────
create table if not exists public.community_games (
  id            text primary key,
  organizer_id  uuid not null references public.profiles (id) on delete cascade,
  title         text not null,
  sport_key     text not null references public.sports (key),
  venue         text not null default '',
  city          text not null default 'Karachi',
  at            timestamptz not null,
  capacity      int  not null default 10,
  category      text not null default 'Friendly',
  format        text not null default 'Standard',
  description   text not null default '',
  visibility    text not null default 'Public',
  is_demo       boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint games_title_len  check (char_length(title) between 3 and 80),
  constraint games_venue_len  check (char_length(venue) <= 120),
  constraint games_capacity   check (capacity between 2 and 100),
  constraint games_visibility check (visibility in ('Public', 'Invite'))
);

create table if not exists public.community_game_members (
  game_id    text not null references public.community_games (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  status     text not null default 'accepted',
  joined_at  timestamptz not null default now(),

  primary key (game_id, profile_id),
  constraint game_members_status check (status in ('invited', 'accepted'))
);

alter table public.community_games enable row level security;
alter table public.community_game_members enable row level security;
revoke all on public.community_games from public, anon, authenticated;
revoke all on public.community_game_members from public, anon, authenticated;
grant select on public.community_games to authenticated;
grant select on public.community_game_members to authenticated;

create index if not exists games_schedule on public.community_games (at);
create index if not exists games_demo     on public.community_games (is_demo) where is_demo;

drop trigger if exists community_games_touch on public.community_games;
create trigger community_games_touch
  before update on public.community_games
  for each row execute function public.touch_updated_at();

-- ── teams ───────────────────────────────────────────────────────────────────
create table if not exists public.teams (
  id         text primary key,
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  name       text not null,
  sport_key  text not null references public.sports (key),
  type       text not null default 'team',
  is_demo    boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint teams_name_len check (char_length(name) between 2 and 60),
  constraint teams_type     check (type in ('individual', 'pair', 'team'))
);

create table if not exists public.team_members (
  team_id    text not null references public.teams (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  status     text not null default 'accepted',
  invited_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),

  primary key (team_id, profile_id),
  constraint team_members_status check (status in ('invited', 'accepted'))
);

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
revoke all on public.teams from public, anon, authenticated;
revoke all on public.team_members from public, anon, authenticated;
grant select on public.teams to authenticated;
grant select on public.team_members to authenticated;

create index if not exists teams_owner on public.teams (owner_id);
create index if not exists teams_demo  on public.teams (is_demo) where is_demo;
create index if not exists team_members_profile on public.team_members (profile_id, status);

drop trigger if exists teams_touch on public.teams;
create trigger teams_touch
  before update on public.teams
  for each row execute function public.touch_updated_at();

-- ════════════════════════════════════════════════════════════════════════════
-- Visibility helpers
-- ════════════════════════════════════════════════════════════════════════════
-- Security definer so a policy on one table can ask about another without the
-- two policies recursing into each other. Each helper answers for the caller
-- only; it never takes an actor id.

create or replace function public.is_tournament_visible(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.tournaments t
     where t.id = p_id
       and (t.organizer_id = auth.uid()
            or t.status in ('open', 'inProgress', 'completed'))
  );
$$;

create or replace function public.is_game_participant(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.community_game_members m
     where m.game_id = p_id and m.profile_id = auth.uid()
  );
$$;

create or replace function public.is_game_organizer(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.community_games g
     where g.id = p_id and g.organizer_id = auth.uid()
  );
$$;

create or replace function public.is_team_member(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.team_members m
     where m.team_id = p_id and m.profile_id = auth.uid()
  );
$$;

revoke all on function public.is_tournament_visible(text) from public, anon;
revoke all on function public.is_game_participant(text) from public, anon;
revoke all on function public.is_game_organizer(text) from public, anon;
revoke all on function public.is_team_member(text) from public, anon;
grant execute on function public.is_tournament_visible(text) to authenticated;
grant execute on function public.is_game_participant(text) to authenticated;
grant execute on function public.is_game_organizer(text) to authenticated;
grant execute on function public.is_team_member(text) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- Policies
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists tournaments_select_visible on public.tournaments;
create policy tournaments_select_visible on public.tournaments
  for select to authenticated
  using (public.is_tournament_visible(id));

drop policy if exists tournament_entries_select_visible on public.tournament_entries;
create policy tournament_entries_select_visible on public.tournament_entries
  for select to authenticated
  using (public.is_tournament_visible(tournament_id));

drop policy if exists community_games_select_visible on public.community_games;
create policy community_games_select_visible on public.community_games
  for select to authenticated
  using (
    visibility = 'Public'
    or organizer_id = auth.uid()
    or public.is_game_participant(id)
  );

drop policy if exists community_game_members_select_visible on public.community_game_members;
create policy community_game_members_select_visible on public.community_game_members
  for select to authenticated
  using (profile_id = auth.uid() or public.is_game_organizer(game_id));

-- Teams are public discovery objects: a roster is visible exactly like a
-- profile card is (0003 grants every signed-in member the profile directory).
drop policy if exists teams_select_members on public.teams;
create policy teams_select_members on public.teams
  for select to authenticated
  using (true);

drop policy if exists team_members_select_members on public.team_members;
create policy team_members_select_members on public.team_members
  for select to authenticated
  using (true);

-- ════════════════════════════════════════════════════════════════════════════
-- Tournaments: write surface
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.create_tournament(
  p_name               text,
  p_city               text,
  p_sport_key          text,
  p_format             text,
  p_format_label       text,
  p_entry_type         text,
  p_starts_at          timestamptz,
  p_ends_at            timestamptz,
  p_registration_limit int,
  p_entry_fee          text,
  p_match_rules        text,
  p_rules              jsonb,
  p_publish_now        boolean,
  p_venue              text default '',
  p_banner_url         text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_id   text := 'tour-' || replace(gen_random_uuid()::text, '-', '');
  v_name text := trim(coalesce(p_name, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if char_length(v_name) not between 3 and 80 then
    raise exception 'invalid_tournament_name' using errcode = '22023';
  end if;
  if p_ends_at <= p_starts_at then
    raise exception 'invalid_tournament_window' using errcode = '22023';
  end if;
  if p_registration_limit not between 2 and 128 then
    raise exception 'invalid_registration_limit' using errcode = '22023';
  end if;
  if not exists (select 1 from public.sports s where s.key = p_sport_key) then
    raise exception 'invalid_sport' using errcode = '22023';
  end if;
  if coalesce(p_format, 'knockout') not in ('knockout', 'group') then
    raise exception 'invalid_format' using errcode = '22023';
  end if;
  if coalesce(p_entry_type, 'team') not in ('individual', 'pair', 'team') then
    raise exception 'invalid_entry_type' using errcode = '22023';
  end if;

  insert into public.tournaments (
    id, organizer_id, name, city, venue, sport_key, format_label, format,
    entry_type, starts_at, ends_at, registration_limit, entry_fee,
    match_rules, rules, banner_url, status
  ) values (
    v_id, v_uid, v_name, coalesce(nullif(trim(p_city), ''), 'Karachi'),
    coalesce(trim(p_venue), ''), p_sport_key,
    left(coalesce(trim(p_format_label), ''), 60),
    coalesce(p_format, 'knockout'), coalesce(p_entry_type, 'team'),
    p_starts_at, p_ends_at, p_registration_limit,
    left(coalesce(trim(p_entry_fee), 'PKR 0'), 40),
    left(coalesce(p_match_rules, ''), 2000),
    case when jsonb_typeof(coalesce(p_rules, '{}'::jsonb)) = 'object'
         then coalesce(p_rules, '{}'::jsonb) else '{}'::jsonb end,
    nullif(trim(coalesce(p_banner_url, '')), ''),
    case when p_publish_now then 'open' else 'draft' end
  );

  -- The organizer claim is what lets create_match accept a tournament fixture
  -- id (0014). It is first-writer-wins, and this id was just generated, so the
  -- insert cannot race anybody.
  insert into public.match_organizer_claims (tournament_id, organizer_id)
  values (v_id, v_uid)
  on conflict (tournament_id) do nothing;

  return v_id;
end;
$$;

create or replace function public.publish_tournament(p_tournament_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_t   public.tournaments;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_t from public.tournaments where id = p_tournament_id;
  if v_t.id is null then
    raise exception 'tournament_not_found' using errcode = '22023';
  end if;
  if v_t.organizer_id <> v_uid then
    raise exception 'not_tournament_organizer' using errcode = '42501';
  end if;
  if v_t.status <> 'draft' then
    return;
  end if;

  update public.tournaments
     set status = 'open'
   where id = v_t.id;
end;
$$;

create or replace function public.set_tournament_status(
  p_tournament_id text,
  p_status        text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_status text := trim(coalesce(p_status, ''));
  v_row    record;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_status not in ('draft', 'open', 'inProgress', 'completed') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;

  select * into v_row from public.tournaments where id = p_tournament_id;
  if v_row.id is null then
    raise exception 'tournament_not_found' using errcode = '22023';
  end if;
  if v_row.organizer_id <> v_uid then
    raise exception 'not_tournament_organizer' using errcode = '42501';
  end if;

  update public.tournaments set status = v_status where id = v_row.id;

  -- Starting a tournament is news for everybody whose place is confirmed.
  if v_status = 'inProgress' and v_row.status <> 'inProgress' then
    for v_row in
      select e.id, e.captain_id, e.label
        from public.tournament_entries e
       where e.tournament_id = p_tournament_id
         and e.status = 'confirmed'
    loop
      perform public._notify(
        v_row.captain_id, 'tournament', 'tournament_started',
        'Tournament is under way',
        format('%s has started.', (select name from public.tournaments where id = p_tournament_id)),
        'tournament', p_tournament_id,
        jsonb_build_object('tournamentId', p_tournament_id, 'tab', 1),
        v_uid,
        format('tournament_started:%s:%s', p_tournament_id, v_row.id)
      );
    end loop;
  end if;
end;
$$;

create or replace function public.register_tournament_entry(
  p_tournament_id text,
  p_label         text,
  p_member_ids    uuid[],
  p_squad_id      text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_t      public.tournaments;
  v_label  text := trim(coalesce(p_label, ''));
  v_members uuid[] := coalesce(p_member_ids, '{}'::uuid[]);
  v_count  int;
  v_id     text := 'entry-' || replace(gen_random_uuid()::text, '-', '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_t from public.tournaments where id = p_tournament_id;
  if v_t.id is null then
    raise exception 'tournament_not_found' using errcode = '22023';
  end if;
  if v_t.status <> 'open' then
    raise exception 'registration_closed' using errcode = '22023';
  end if;
  if v_t.ends_at <= now() then
    raise exception 'registration_closed' using errcode = '22023';
  end if;

  if char_length(v_label) not between 1 and 60 then
    raise exception 'invalid_entry_label' using errcode = '22023';
  end if;

  v_members := (select array_agg(distinct m) from unnest(v_members) m);
  if not (v_uid = any (v_members)) then
    v_members := array_append(v_members, v_uid);
  end if;
  if cardinality(v_members) > 40 then
    raise exception 'invalid_entry_members' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(v_members) m
     where not exists (select 1 from public.profiles p where p.id = m)
  ) then
    raise exception 'invalid_entry_members' using errcode = '22023';
  end if;

  if v_t.entry_type = 'individual' and cardinality(v_members) <> 1 then
    raise exception 'entry_type_mismatch' using errcode = '22023';
  end if;
  if v_t.entry_type = 'pair' and cardinality(v_members) > 2 then
    raise exception 'entry_type_mismatch' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.tournament_entries e
     where e.tournament_id = p_tournament_id
       and e.status <> 'withdrawn'
       and e.member_ids && v_members
  ) then
    raise exception 'already_registered' using errcode = '23505';
  end if;

  select count(*) into v_count
    from public.tournament_entries e
   where e.tournament_id = p_tournament_id
     and e.status in ('pending', 'confirmed');
  if v_count >= v_t.registration_limit then
    raise exception 'tournament_full' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.tournament_entries e
     where e.tournament_id = p_tournament_id and lower(e.label) = lower(v_label)
  ) then
    raise exception 'entry_label_taken' using errcode = '23505';
  end if;

  insert into public.tournament_entries (
    id, tournament_id, captain_id, label, squad_id, member_ids, status
  ) values (
    v_id, p_tournament_id, v_uid, v_label, nullif(trim(coalesce(p_squad_id, '')), ''),
    v_members, 'pending'
  );

  return v_id;
end;
$$;

create or replace function public.withdraw_tournament_entry(p_entry_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_e   public.tournament_entries;
  v_t   public.tournaments;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_e from public.tournament_entries where id = p_entry_id;
  if v_e.id is null then
    raise exception 'entry_not_found' using errcode = '22023';
  end if;
  select * into v_t from public.tournaments where id = v_e.tournament_id;

  if v_e.captain_id <> v_uid and v_t.organizer_id <> v_uid then
    raise exception 'not_entry_captain' using errcode = '42501';
  end if;
  if v_t.status in ('inProgress', 'completed') then
    raise exception 'tournament_started' using errcode = '22023';
  end if;
  if v_e.status = 'withdrawn' then
    return;
  end if;

  update public.tournament_entries
     set status = 'withdrawn'
   where id = v_e.id;
end;
$$;

create or replace function public.decide_tournament_entry(
  p_entry_id text,
  p_approve  boolean,
  p_note     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_e   public.tournament_entries;
  v_t   public.tournaments;
  v_new text := case when p_approve then 'confirmed' else 'rejected' end;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_e from public.tournament_entries where id = p_entry_id;
  if v_e.id is null then
    raise exception 'entry_not_found' using errcode = '22023';
  end if;
  select * into v_t from public.tournaments where id = v_e.tournament_id;
  if v_t.organizer_id <> v_uid then
    raise exception 'not_tournament_organizer' using errcode = '42501';
  end if;
  if v_e.status = v_new then
    return;
  end if;

  update public.tournament_entries
     set status = v_new,
         decision_note = nullif(left(trim(coalesce(p_note, '')), 200), '')
   where id = v_e.id;

  perform public._notify(
    v_e.captain_id, 'tournament', 'tournament_entry_decision',
    case when p_approve then 'Entry confirmed' else 'Entry declined' end,
    format('Your entry %s for %s was %s.',
           v_e.label, v_t.name, case when p_approve then 'confirmed' else 'declined' end),
    'tournament', v_t.id,
    jsonb_build_object('tournamentId', v_t.id, 'entryId', v_e.id, 'tab', 1),
    v_uid,
    format('tournament_entry:%s:%s', v_e.id, v_new)
  );
end;
$$;

-- Round one of a draw, as tournament fixtures. Knockout pairs the confirmed
-- entries once; group play is a round robin inside each group of four. Each
-- fixture becomes a `matches` row, which is where its event log and result
-- live from here on.
create or replace function public.generate_tournament_draw(p_tournament_id text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_t     public.tournaments;
  v_ids   text[] := '{}'::text[];
  v_names text[] := '{}'::text[];
  v_created int := 0;
  v_i     int;
  v_j     int;
  v_round int;
  v_stage text;
  v_fixture text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_t from public.tournaments where id = p_tournament_id;
  if v_t.id is null then
    raise exception 'tournament_not_found' using errcode = '22023';
  end if;
  if v_t.organizer_id <> v_uid then
    raise exception 'not_tournament_organizer' using errcode = '42501';
  end if;

  if exists (select 1 from public.matches m where m.tournament_id = p_tournament_id) then
    raise exception 'draw_exists' using errcode = '23505';
  end if;

  select array_agg(e.id order by e.created_at), array_agg(e.label order by e.created_at)
    into v_ids, v_names
    from public.tournament_entries e
   where e.tournament_id = p_tournament_id
     and e.status = 'confirmed';

  if coalesce(cardinality(v_ids), 0) < 2 then
    raise exception 'draw_needs_entries' using errcode = '22023';
  end if;

  if v_t.format = 'group' and cardinality(v_ids) >= 4 then
    -- Round robin in blocks of four; every pair meets once.
    v_round := 1;
    v_stage := 'Group stage · Round 1';
    for v_i in 1 .. cardinality(v_ids) loop
      for v_j in v_i + 1 .. cardinality(v_ids) loop
        if ((v_i - 1) / 4) <> ((v_j - 1) / 4) then
          continue;
        end if;
        v_fixture := 'fx-' || replace(gen_random_uuid()::text, '-', '');
        insert into public.matches (
          sport_key, format_label, rules, title, venue, scheduled_at, visibility,
          organizer_id, scorer_id, side_a_name, side_b_name, discipline, capacity,
          tournament_id, fixture_id, is_demo
        ) values (
          v_t.sport_key, v_t.format_label, v_t.rules || jsonb_build_object('discipline', v_t.entry_type),
          format('%s · %s vs %s', v_t.name, v_names[v_i], v_names[v_j]),
          v_t.venue, v_t.starts_at + (v_created * interval '2 hours'), 'public',
          v_uid, null, left(v_names[v_i], 40), left(v_names[v_j], 40),
          case when v_t.sport_key in ('padel', 'badminton') then 'doubles' else 'team' end,
          v_t.registration_limit, p_tournament_id, v_fixture, v_t.is_demo
        );
        v_created := v_created + 1;
      end loop;
    end loop;
  else
    -- Knockout: consecutive pairs; the highest entry gets a bye when odd.
    for v_i in 1 .. (cardinality(v_ids) / 2) loop
      v_fixture := 'fx-' || replace(gen_random_uuid()::text, '-', '');
      insert into public.matches (
        sport_key, format_label, rules, title, venue, scheduled_at, visibility,
        organizer_id, scorer_id, side_a_name, side_b_name, discipline, capacity,
        tournament_id, fixture_id, is_demo
      ) values (
        v_t.sport_key, v_t.format_label, v_t.rules || jsonb_build_object('discipline', v_t.entry_type),
        format('%s · %s vs %s', v_t.name, v_names[v_i * 2 - 1], v_names[v_i * 2]),
        v_t.venue, v_t.starts_at + ((v_i - 1) * interval '2 hours'), 'public',
        v_uid, null, left(v_names[v_i * 2 - 1], 40), left(v_names[v_i * 2], 40),
        case when v_t.sport_key in ('padel', 'badminton') then 'doubles' else 'team' end,
        v_t.registration_limit, p_tournament_id, v_fixture, v_t.is_demo
      );
      v_created := v_created + 1;
    end loop;
  end if;

  if v_created > 0 then
    update public.tournaments set status = 'inProgress' where id = p_tournament_id;
  end if;

  return v_created;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- Community games: write surface
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.create_community_game(
  p_title       text,
  p_sport_key   text,
  p_venue       text,
  p_at          timestamptz,
  p_capacity    int,
  p_category    text default 'Friendly',
  p_format      text default 'Standard',
  p_description text default '',
  p_visibility  text default 'Public'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_title text := trim(coalesce(p_title, ''));
  v_id    text := 'game-' || replace(gen_random_uuid()::text, '-', '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_title) not between 3 and 80 then
    raise exception 'invalid_game_title' using errcode = '22023';
  end if;
  if not exists (select 1 from public.sports s where s.key = p_sport_key) then
    raise exception 'invalid_sport' using errcode = '22023';
  end if;
  if p_capacity not between 2 and 100 then
    raise exception 'invalid_capacity' using errcode = '22023';
  end if;
  if coalesce(p_visibility, 'Public') not in ('Public', 'Invite') then
    raise exception 'invalid_visibility' using errcode = '22023';
  end if;

  insert into public.community_games (
    id, organizer_id, title, sport_key, venue, at, capacity, category,
    format, description, visibility
  ) values (
    v_id, v_uid, v_title, p_sport_key, left(coalesce(trim(p_venue), ''), 120),
    p_at, p_capacity, left(coalesce(trim(p_category), 'Friendly'), 30),
    left(coalesce(trim(p_format), 'Standard'), 40),
    left(coalesce(p_description, ''), 400),
    coalesce(p_visibility, 'Public')
  );

  insert into public.community_game_members (game_id, profile_id, status)
  values (v_id, v_uid, 'accepted')
  on conflict (game_id, profile_id) do nothing;

  return v_id;
end;
$$;

create or replace function public.toggle_game_join(p_game_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_game public.community_games;
  v_joined boolean;
  v_count  int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_game from public.community_games where id = p_game_id;
  if v_game.id is null then
    raise exception 'game_not_found' using errcode = '22023';
  end if;

  select exists (
    select 1 from public.community_game_members m
     where m.game_id = p_game_id and m.profile_id = v_uid
  ) into v_joined;

  if v_joined then
    delete from public.community_game_members
     where game_id = p_game_id and profile_id = v_uid;
    return;
  end if;

  if v_game.visibility = 'Invite' and v_game.organizer_id <> v_uid then
    raise exception 'game_is_invite_only' using errcode = '42501';
  end if;

  select count(*) into v_count
    from public.community_game_members m
   where m.game_id = p_game_id;

  if v_count >= v_game.capacity then
    raise exception 'game_is_full' using errcode = '22023';
  end if;
  if v_game.at <= now() then
    raise exception 'game_already_started' using errcode = '22023';
  end if;

  insert into public.community_game_members (game_id, profile_id, status)
  values (p_game_id, v_uid, 'accepted')
  on conflict (game_id, profile_id) do update set status = 'accepted';
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- Teams: write surface
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.create_team(
  p_name       text,
  p_sport_key  text,
  p_type       text,
  p_member_ids uuid[] default '{}'::uuid[]
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_name    text := trim(coalesce(p_name, ''));
  v_members uuid[] := coalesce(p_member_ids, '{}'::uuid[]);
  v_member  uuid;
  v_id      text := 'team-' || replace(gen_random_uuid()::text, '-', '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_name) not between 2 and 60 then
    raise exception 'invalid_team_name' using errcode = '22023';
  end if;
  if not exists (select 1 from public.sports s where s.key = p_sport_key) then
    raise exception 'invalid_sport' using errcode = '22023';
  end if;
  if coalesce(p_type, 'team') not in ('individual', 'pair', 'team') then
    raise exception 'invalid_entry_type' using errcode = '22023';
  end if;

  v_members := (select array_agg(distinct m) from unnest(array_append(v_members, v_uid)) m);
  if cardinality(v_members) > 40 then
    raise exception 'invalid_team_members' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(v_members) m
     where not exists (select 1 from public.profiles p where p.id = m)
  ) then
    raise exception 'invalid_team_members' using errcode = '22023';
  end if;

  insert into public.teams (id, owner_id, name, sport_key, type)
  values (v_id, v_uid, v_name, p_sport_key, coalesce(p_type, 'team'));

  foreach v_member in array v_members loop
    insert into public.team_members (team_id, profile_id, status, invited_by)
    values (v_id, v_member, 'accepted', v_uid)
    on conflict (team_id, profile_id) do update set status = 'accepted';
  end loop;

  return v_id;
end;
$$;

create or replace function public.invite_team_member(
  p_team_id    text,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if v_team.owner_id <> v_uid then
    raise exception 'not_team_captain' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_profile_id) then
    raise exception 'player_not_found' using errcode = '22023';
  end if;

  insert into public.team_members (team_id, profile_id, status, invited_by)
  values (p_team_id, p_profile_id, 'invited', v_uid)
  on conflict (team_id, profile_id) do update
     set status = case when public.team_members.status = 'accepted'
                       then 'accepted' else 'invited' end;

  perform public._notify(
    p_profile_id, 'team', 'team_invite',
    'Team invitation',
    format('%s invited you to %s.', public._display_name(v_uid), v_team.name),
    'team', p_team_id,
    jsonb_build_object('teamId', p_team_id, 'tab', 3),
    v_uid,
    format('team_invite:%s:%s', p_team_id, p_profile_id)
  );
end;
$$;

create or replace function public.respond_team_invite(
  p_team_id text,
  p_accept  boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.team_members m
     where m.team_id = p_team_id and m.profile_id = v_uid and m.status = 'invited'
  ) then
    raise exception 'no_team_invite' using errcode = '22023';
  end if;

  if p_accept then
    update public.team_members
       set status = 'accepted'
     where team_id = p_team_id and profile_id = v_uid;
  else
    delete from public.team_members
     where team_id = p_team_id and profile_id = v_uid;
  end if;
end;
$$;

create or replace function public.remove_team_member(
  p_team_id    text,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if v_team.owner_id <> v_uid then
    raise exception 'not_team_captain' using errcode = '42501';
  end if;
  if p_profile_id = v_uid then
    raise exception 'captain_cannot_leave' using errcode = '22023';
  end if;

  delete from public.team_members
   where team_id = p_team_id and profile_id = p_profile_id;
end;
$$;

create or replace function public.transfer_team_captain(
  p_team_id    text,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if v_team.owner_id <> v_uid then
    raise exception 'not_team_captain' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.team_members m
     where m.team_id = p_team_id and m.profile_id = p_profile_id
       and m.status = 'accepted'
  ) then
    raise exception 'player_not_in_team' using errcode = '22023';
  end if;

  update public.teams set owner_id = p_profile_id where id = p_team_id;
end;
$$;

create or replace function public.leave_team(p_team_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if v_team.owner_id = v_uid then
    raise exception 'captain_must_transfer' using errcode = '22023';
  end if;

  delete from public.team_members
   where team_id = p_team_id and profile_id = v_uid;
end;
$$;

create or replace function public.delete_team(p_team_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    return;
  end if;
  if v_team.owner_id <> v_uid then
    raise exception 'not_team_captain' using errcode = '42501';
  end if;

  delete from public.teams where id = p_team_id;
end;
$$;

-- ── grants ──────────────────────────────────────────────────────────────────
revoke all on function public.create_tournament(
  text, text, text, text, text, text, timestamptz, timestamptz, int, text, text,
  jsonb, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.create_tournament(
  text, text, text, text, text, text, timestamptz, timestamptz, int, text, text,
  jsonb, boolean, text, text
) to authenticated;

revoke all on function public.publish_tournament(text) from public, anon, authenticated;
revoke all on function public.set_tournament_status(text, text) from public, anon, authenticated;
revoke all on function public.register_tournament_entry(text, text, uuid[], text) from public, anon, authenticated;
revoke all on function public.withdraw_tournament_entry(text) from public, anon, authenticated;
revoke all on function public.decide_tournament_entry(text, boolean, text) from public, anon, authenticated;
revoke all on function public.generate_tournament_draw(text) from public, anon, authenticated;
revoke all on function public.create_community_game(
  text, text, text, timestamptz, int, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.toggle_game_join(text) from public, anon, authenticated;
revoke all on function public.create_team(text, text, text, uuid[]) from public, anon, authenticated;
revoke all on function public.invite_team_member(text, uuid) from public, anon, authenticated;
revoke all on function public.respond_team_invite(text, boolean) from public, anon, authenticated;
revoke all on function public.remove_team_member(text, uuid) from public, anon, authenticated;
revoke all on function public.transfer_team_captain(text, uuid) from public, anon, authenticated;
revoke all on function public.leave_team(text) from public, anon, authenticated;
revoke all on function public.delete_team(text) from public, anon, authenticated;

grant execute on function public.publish_tournament(text) to authenticated;
grant execute on function public.set_tournament_status(text, text) to authenticated;
grant execute on function public.register_tournament_entry(text, text, uuid[], text) to authenticated;
grant execute on function public.withdraw_tournament_entry(text) to authenticated;
grant execute on function public.decide_tournament_entry(text, boolean, text) to authenticated;
grant execute on function public.generate_tournament_draw(text) to authenticated;
grant execute on function public.create_community_game(
  text, text, text, timestamptz, int, text, text, text, text
) to authenticated;
grant execute on function public.toggle_game_join(text) to authenticated;
grant execute on function public.create_team(text, text, text, uuid[]) to authenticated;
grant execute on function public.invite_team_member(text, uuid) to authenticated;
grant execute on function public.respond_team_invite(text, boolean) to authenticated;
grant execute on function public.remove_team_member(text, uuid) to authenticated;
grant execute on function public.transfer_team_captain(text, uuid) to authenticated;
grant execute on function public.leave_team(text) to authenticated;
grant execute on function public.delete_team(text) to authenticated;

-- ── realtime ────────────────────────────────────────────────────────────────
-- Discovery cards must appear for a second device without a manual refresh.
-- Realtime respects RLS, so a member still receives only rows they can SELECT.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'tournaments'
    ) then
      alter publication supabase_realtime add table public.tournaments;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'tournament_entries'
    ) then
      alter publication supabase_realtime add table public.tournament_entries;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'community_games'
    ) then
      alter publication supabase_realtime add table public.community_games;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'teams'
    ) then
      alter publication supabase_realtime add table public.teams;
    end if;
  end if;
end $$;

commit;
