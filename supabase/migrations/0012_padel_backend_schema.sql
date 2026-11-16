-- Sportika padel backend, part 1: the state the generic match aggregate lacks.
--
-- 0007 built one shared match aggregate for all four sports; 0008 added the
-- server-side padel fold on top of it. What a racket sport still needs and the
-- shared tables cannot express is here, and nothing already working is
-- recreated:
--
--   * pause/resume, modelled as paused_at + paused_by on `matches` rather than a
--     new `status` value. The Flutter enum FixtureStatusX.fromKey falls back to
--     `upcoming` for anything it does not know, so a `paused` status would make
--     a paused match render as Upcoming and silently regain its Start button.
--   * an auditable undo: who withdrew the entry, when, and why.
--   * padel_match_state - the current scoreboard as one row, so a scoreboard read
--     is one row instead of a fold over the whole log, and Realtime can broadcast
--     a single ordered revision per point.
--   * padel_match_sets - one immutable record per completed set.
--   * match_disputes - result disputes with their resolution trail.
--
-- Conventions are 0007's: RLS is enabled and never forced (security-definer
-- functions write, clients only ever hold SELECT), every write goes through an
-- RPC, and no table below takes an actor id from the caller.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  Pause / resume
-- ════════════════════════════════════════════════════════════════════════════

alter table public.matches
  add column if not exists paused_at     timestamptz,
  add column if not exists paused_by     uuid references public.profiles (id) on delete set null,
  add column if not exists pause_reason  text;

comment on column public.matches.paused_at is
  'Set while the official scorer has paused a live match; null when running.';

alter table public.matches drop constraint if exists matches_pause_reason_len;
alter table public.matches add constraint matches_pause_reason_len
  check (pause_reason is null or char_length(pause_reason) <= 200);

-- A paused match is still `live` for lifecycle purposes (undo, submit), so the
-- only invariant worth enforcing is that the reason cannot outlive the pause.
alter table public.matches drop constraint if exists matches_pause_reason_requires_pause;
alter table public.matches add constraint matches_pause_reason_requires_pause
  check (pause_reason is null or paused_at is not null);

create index if not exists matches_paused
  on public.matches (paused_at)
  where paused_at is not null;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  Auditable undo on the event log
-- ════════════════════════════════════════════════════════════════════════════

alter table public.match_events
  add column if not exists voided_by   uuid references public.profiles (id) on delete set null,
  add column if not exists voided_at   timestamptz,
  add column if not exists void_reason text;

alter table public.match_events drop constraint if exists match_events_void_reason_len;
alter table public.match_events add constraint match_events_void_reason_len
  check (void_reason is null or char_length(void_reason) between 3 and 200);

-- The log is append-only. A void is a compensating change, not an edit: the
-- scoring payload may never move, and a withdrawn entry may never be restored.
create or replace function public.guard_match_event_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Deletion is the backend's own cleanup path (an admin purge, a match delete
  -- cascading, an account removal taking profiles with it), so it is refused
  -- for the two roles a client request can ever run as and allowed for the
  -- service/database roles. Rewriting history is refused for everybody.
  if tg_op = 'DELETE' then
    if current_user in ('anon', 'authenticated') then
      raise exception 'match_events_are_immutable' using errcode = '42501';
    end if;
    return old;
  end if;

  if new.match_id        is distinct from old.match_id
     or new.seq          is distinct from old.seq
     or new.client_event_id is distinct from old.client_event_id
     or new.kind         is distinct from old.kind
     or new.side         is distinct from old.side
     or new.data         is distinct from old.data
     or new.recorded_by  is distinct from old.recorded_by
     or new.recorded_at  is distinct from old.recorded_at then
    raise exception 'match_events_are_immutable' using errcode = '42501';
  end if;

  if old.voided and not new.voided then
    raise exception 'match_event_cannot_be_restored' using errcode = '42501';
  end if;

  if new.voided and not old.voided then
    new.voided_at := coalesce(new.voided_at, now());
  end if;

  return new;
end;
$$;

revoke all on function public.guard_match_event_write()
  from public, anon, authenticated;

drop trigger if exists match_events_guard on public.match_events;
create trigger match_events_guard
  before update or delete on public.match_events
  for each row execute function public.guard_match_event_write();

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  Current padel scoreboard
-- ════════════════════════════════════════════════════════════════════════════
-- A projection of match_events, never an independent source of truth: every
-- scoring RPC writes the event and the projection in one transaction, and
-- _padel_rebuild_state can regenerate the row from the log at any time. `revision`
-- increments per mutation so a client can order broadcasts and drop duplicates.

create table if not exists public.padel_match_state (
  match_id         uuid primary key references public.matches (id) on delete cascade,
  revision         bigint not null default 1,
  status           text   not null default 'not_started',

  points           jsonb  not null default '[0, 0]'::jsonb,
  games            jsonb  not null default '[0, 0]'::jsonb,
  tiebreak_points  jsonb  not null default '[0, 0]'::jsonb,
  sets_won         jsonb  not null default '[0, 0]'::jsonb,

  in_tiebreak      boolean not null default false,
  decider_tiebreak boolean not null default false,
  serving_side     smallint not null default 0,
  serving_member   smallint not null default 0,

  point_count      int not null default 0,
  is_complete      boolean not null default false,
  winner_side      smallint,

  updated_at       timestamptz not null default now(),

  constraint padel_state_status
    check (status in ('not_started', 'live', 'paused', 'complete')),
  constraint padel_state_points_pair
    check (jsonb_typeof(points) = 'array' and jsonb_array_length(points) = 2),
  constraint padel_state_games_pair
    check (jsonb_typeof(games) = 'array' and jsonb_array_length(games) = 2),
  constraint padel_state_tiebreak_pair
    check (jsonb_typeof(tiebreak_points) = 'array' and jsonb_array_length(tiebreak_points) = 2),
  constraint padel_state_sets_pair
    check (jsonb_typeof(sets_won) = 'array' and jsonb_array_length(sets_won) = 2),
  constraint padel_state_sides
    check (serving_side in (0, 1) and serving_member in (0, 1)),
  constraint padel_state_winner
    check (winner_side is null or winner_side in (0, 1)),
  constraint padel_state_counters
    check (revision >= 1 and point_count >= 0)
);

alter table public.padel_match_state enable row level security;
revoke all on public.padel_match_state from public, anon, authenticated;
grant select on public.padel_match_state to authenticated;

drop policy if exists padel_state_select_visible on public.padel_match_state;
create policy padel_state_select_visible on public.padel_match_state
  for select to authenticated
  using (public.can_view_match(match_id));

drop trigger if exists padel_state_touch on public.padel_match_state;
create trigger padel_state_touch
  before update on public.padel_match_state
  for each row execute function public.touch_updated_at();

-- ════════════════════════════════════════════════════════════════════════════
-- 4.  Completed sets
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.padel_match_sets (
  id               uuid primary key default gen_random_uuid(),
  match_id         uuid not null references public.matches (id) on delete cascade,
  set_index        int  not null,
  side_a_games     int  not null,
  side_b_games     int  not null,
  winner_side      smallint not null,
  tiebreak         boolean not null default false,
  tiebreak_points  jsonb,
  point_seq_start  bigint,
  point_seq_end    bigint,
  created_at       timestamptz not null default now(),

  constraint padel_sets_unique     unique (match_id, set_index),
  constraint padel_sets_index      check (set_index between 0 and 4),
  constraint padel_sets_games      check (side_a_games between 0 and 30
                                          and side_b_games between 0 and 30),
  constraint padel_sets_winner     check (winner_side in (0, 1)),
  constraint padel_sets_tiebreak   check (tiebreak_points is null
                                          or (jsonb_typeof(tiebreak_points) = 'array'
                                              and jsonb_array_length(tiebreak_points) = 2)),
  constraint padel_sets_sequence   check (point_seq_start is null
                                          or point_seq_end is null
                                          or point_seq_end >= point_seq_start)
);

alter table public.padel_match_sets enable row level security;
revoke all on public.padel_match_sets from public, anon, authenticated;
grant select on public.padel_match_sets to authenticated;

drop policy if exists padel_sets_select_visible on public.padel_match_sets;
create policy padel_sets_select_visible on public.padel_match_sets
  for select to authenticated
  using (public.can_view_match(match_id));

create index if not exists padel_sets_match
  on public.padel_match_sets (match_id, set_index);

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  Result disputes
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.match_disputes (
  id           uuid primary key default gen_random_uuid(),
  match_id     uuid not null references public.matches (id) on delete cascade,
  raised_by    uuid not null references public.profiles (id) on delete cascade,
  reason       text not null,
  status       text not null default 'open',
  resolution   text,
  resolved_by  uuid references public.profiles (id) on delete set null,
  resolved_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint match_disputes_reason_len
    check (char_length(reason) between 5 and 500),
  constraint match_disputes_status
    check (status in ('open', 'under_review', 'resolved', 'rejected')),
  constraint match_disputes_resolution_len
    check (resolution is null or char_length(resolution) between 3 and 500),
  -- A closed dispute must say how it was closed; an open one must not pretend to.
  constraint match_disputes_resolution_pair
    check ((status in ('resolved', 'rejected')) = (resolution is not null))
);

alter table public.match_disputes enable row level security;
revoke all on public.match_disputes from public, anon, authenticated;
grant select on public.match_disputes to authenticated;

-- Anyone who may read the match may read its disputes: a published result and
-- the challenge against it are one public record. Only the organizer can write,
-- and only through resolve_match_dispute.
drop policy if exists match_disputes_select_visible on public.match_disputes;
create policy match_disputes_select_visible on public.match_disputes
  for select to authenticated
  using (public.can_view_match(match_id));

create index if not exists match_disputes_match
  on public.match_disputes (match_id, created_at desc);
create index if not exists match_disputes_raised_by
  on public.match_disputes (raised_by, created_at desc);

-- One live challenge per member per match; a resolved one may be raised again.
create unique index if not exists match_disputes_one_open
  on public.match_disputes (match_id, raised_by)
  where status in ('open', 'under_review');

drop trigger if exists match_disputes_touch on public.match_disputes;
create trigger match_disputes_touch
  before update on public.match_disputes
  for each row execute function public.touch_updated_at();

-- ════════════════════════════════════════════════════════════════════════════
-- 6.  Realtime
-- ════════════════════════════════════════════════════════════════════════════
-- The scoreboard is broadcast as one row per point, not as a stream of derived
-- columns. REPLICA IDENTITY FULL is required for the subscriber's RLS policy to
-- be evaluated against the changed row rather than only its key.

alter table public.padel_match_state replica identity full;
alter table public.match_disputes    replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'padel_match_state'
    ) then
      alter publication supabase_realtime add table public.padel_match_state;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'padel_match_sets'
    ) then
      alter publication supabase_realtime add table public.padel_match_sets;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'match_disputes'
    ) then
      alter publication supabase_realtime add table public.match_disputes;
    end if;
  end if;
end;
$$;

commit;
