-- Sportika match module: standalone matches, participants, official event log
-- and published results.
--
-- A match is its own aggregate, separate from a tournament fixture. Any member
-- may create one; the creator is its organizer and the only member who can edit
-- it, invite players, assign or transfer the official scorer, publish, correct
-- or cancel. The assigned scorer (or the organizer) records the event log and
-- submits the result, and publication stays with the organizer, mirroring the
-- tournament rules the app already follows.
--
-- Conventions match 0002/0006: RLS is enabled but never forced, every write goes
-- through a `security definer` function that derives the actor from auth.uid(),
-- and each function takes no actor id. Clients only ever hold a SELECT grant.
begin;

-- ── matches ─────────────────────────────────────────────────────────────────
create table if not exists public.matches (
  id             uuid primary key default gen_random_uuid(),
  sport_key      text not null references public.sports (key),
  format_label   text not null,
  rules          jsonb not null default '{}'::jsonb,
  title          text not null,
  venue          text not null default '',
  scheduled_at   timestamptz not null,
  visibility     text not null default 'public',
  organizer_id   uuid not null references public.profiles (id) on delete cascade,
  scorer_id      uuid references public.profiles (id) on delete set null,
  status         text not null default 'upcoming',

  -- Side names are editable until the first event, then frozen by the RPCs.
  side_a_name    text not null default 'Side A',
  side_b_name    text not null default 'Side B',

  -- singles | doubles for the racket sports, team for cricket and futsal.
  discipline     text,
  capacity       int  not null default 10,

  started_at     timestamptz,
  submitted_at   timestamptz,
  completed_at   timestamptz,
  published_at   timestamptz,

  -- Highest sequence number handed out. It only ever moves forward, so a voided
  -- event can never be resurrected by a late retry.
  event_count    bigint not null default 0,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint matches_format_len  check (char_length(format_label) between 1 and 60),
  constraint matches_title_len   check (char_length(title) between 2 and 80),
  constraint matches_venue_len   check (char_length(venue) <= 80),
  constraint matches_side_len    check (char_length(side_a_name) between 1 and 40
                                        and char_length(side_b_name) between 1 and 40),
  constraint matches_visibility  check (visibility in ('public', 'invite')),
  constraint matches_status      check (status in ('upcoming', 'live', 'submitted',
                                                   'published', 'walkover', 'cancelled')),
  constraint matches_discipline  check (discipline is null
                                        or discipline in ('singles', 'doubles', 'team')),
  constraint matches_capacity    check (capacity between 2 and 100),
  constraint matches_event_count check (event_count >= 0)
);

alter table public.matches enable row level security;
revoke all on public.matches from public, anon, authenticated;
grant select on public.matches to authenticated;

create index if not exists matches_organizer on public.matches (organizer_id, scheduled_at desc);
create index if not exists matches_scorer    on public.matches (scorer_id, scheduled_at desc);
create index if not exists matches_schedule  on public.matches (scheduled_at desc);
create index if not exists matches_status    on public.matches (status);

drop trigger if exists matches_touch on public.matches;
create trigger matches_touch
  before update on public.matches
  for each row execute function public.touch_updated_at();

-- ── participants ────────────────────────────────────────────────────────────
create table if not exists public.match_participants (
  match_id    uuid not null references public.matches (id) on delete cascade,
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  side        smallint not null,
  status      text not null default 'invited',
  invited_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  primary key (match_id, profile_id),
  constraint match_participants_side   check (side in (0, 1)),
  constraint match_participants_status check (status in ('invited', 'accepted',
                                                         'declined', 'removed'))
);

alter table public.match_participants enable row level security;
revoke all on public.match_participants from public, anon, authenticated;
grant select on public.match_participants to authenticated;

create index if not exists match_participants_profile
  on public.match_participants (profile_id, status);

drop trigger if exists match_participants_touch on public.match_participants;
create trigger match_participants_touch
  before update on public.match_participants
  for each row execute function public.touch_updated_at();

-- ── event log ───────────────────────────────────────────────────────────────
-- One row per recorded score. `client_event_id` is the client's idempotency key:
-- a tap retried after a dropped connection lands once, because the RPC returns
-- the existing row instead of inserting a second one.
create table if not exists public.match_events (
  id              uuid primary key default gen_random_uuid(),
  match_id        uuid not null references public.matches (id) on delete cascade,
  seq             bigint not null,
  client_event_id text not null,
  kind            text not null,
  side            smallint,
  data            jsonb not null default '{}'::jsonb,
  recorded_by     uuid not null references public.profiles (id) on delete cascade,
  recorded_at     timestamptz not null default now(),
  voided          boolean not null default false,

  constraint match_events_unique_client unique (match_id, client_event_id),
  constraint match_events_unique_seq    unique (match_id, seq),
  constraint match_events_seq_positive  check (seq > 0),
  constraint match_events_kind_len      check (char_length(kind) between 1 and 40),
  constraint match_events_client_len    check (char_length(client_event_id) between 1 and 80),
  constraint match_events_side          check (side is null or side in (0, 1)),
  constraint match_events_data_object   check (jsonb_typeof(data) = 'object')
);

alter table public.match_events enable row level security;
revoke all on public.match_events from public, anon, authenticated;
grant select on public.match_events to authenticated;

create index if not exists match_events_log on public.match_events (match_id, seq);
create index if not exists match_events_live
  on public.match_events (match_id, recorded_at desc);

-- ── results ─────────────────────────────────────────────────────────────────
create table if not exists public.match_results (
  match_id     uuid primary key references public.matches (id) on delete cascade,
  side_scores  jsonb not null,
  side_values  jsonb not null,
  winner_index int  not null default -1,
  headline     text not null default '',
  detail       text not null default '',
  walkover     boolean not null default false,
  published_by uuid not null references public.profiles (id) on delete cascade,
  published_at timestamptz not null default now(),

  constraint match_results_payload check (jsonb_typeof(side_scores) = 'array'
                                          and jsonb_typeof(side_values) = 'array'
                                          and jsonb_array_length(side_scores) = 2
                                          and jsonb_array_length(side_values) = 2),
  constraint match_results_winner  check (winner_index between -1 and 1)
);

alter table public.match_results enable row level security;
revoke all on public.match_results from public, anon, authenticated;
grant select on public.match_results to authenticated;

-- A correction keeps the previous result, the reason and who changed it, so a
-- published match never loses its history.
create table if not exists public.match_result_corrections (
  id         uuid primary key default gen_random_uuid(),
  match_id   uuid not null references public.matches (id) on delete cascade,
  previous   jsonb not null,
  current    jsonb not null,
  reason     text not null,
  changed_by uuid not null references public.profiles (id) on delete cascade,
  at         timestamptz not null default now()
);

alter table public.match_result_corrections enable row level security;
revoke all on public.match_result_corrections from public, anon, authenticated;
grant select on public.match_result_corrections to authenticated;

create index if not exists match_corrections_match
  on public.match_result_corrections (match_id, at desc);

-- Every state change lands here. It is the audit trail behind a transferred
-- scorer, a cancelled match and a corrected result.
create table if not exists public.match_lifecycle_log (
  id       uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  actor_id uuid references public.profiles (id) on delete set null,
  action   text not null,
  detail   jsonb not null default '{}'::jsonb,
  at       timestamptz not null default now()
);

alter table public.match_lifecycle_log enable row level security;
revoke all on public.match_lifecycle_log from public, anon, authenticated;
grant select on public.match_lifecycle_log to authenticated;

create index if not exists match_lifecycle_match
  on public.match_lifecycle_log (match_id, at desc);

-- ── visibility ──────────────────────────────────────────────────────────────
-- A security-definer predicate, so the policies below can look at participants
-- without recursing into the policies of `matches` (which reference it back).
create or replace function public.can_view_match(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.matches m
     where m.id = p_match_id
       and (
         m.visibility = 'public'
         or m.organizer_id = auth.uid()
         or m.scorer_id = auth.uid()
         or exists (
           select 1
             from public.match_participants p
            where p.match_id = m.id
              and p.profile_id = auth.uid()
              and p.status in ('invited', 'accepted')
         )
       )
  );
$$;

revoke all on function public.can_view_match(uuid) from public, anon, authenticated;
grant execute on function public.can_view_match(uuid) to authenticated;

drop policy if exists matches_select_visible on public.matches;
create policy matches_select_visible on public.matches
  for select to authenticated
  using (public.can_view_match(id));

drop policy if exists match_participants_select_visible on public.match_participants;
create policy match_participants_select_visible on public.match_participants
  for select to authenticated
  using (public.can_view_match(match_id));

drop policy if exists match_events_select_visible on public.match_events;
create policy match_events_select_visible on public.match_events
  for select to authenticated
  using (public.can_view_match(match_id));

drop policy if exists match_results_select_visible on public.match_results;
create policy match_results_select_visible on public.match_results
  for select to authenticated
  using (public.can_view_match(match_id));

drop policy if exists match_corrections_select_visible
  on public.match_result_corrections;
create policy match_corrections_select_visible on public.match_result_corrections
  for select to authenticated
  using (public.can_view_match(match_id));

drop policy if exists match_lifecycle_select_visible on public.match_lifecycle_log;
create policy match_lifecycle_select_visible on public.match_lifecycle_log
  for select to authenticated
  using (public.can_view_match(match_id));

-- ── internal helpers ────────────────────────────────────────────────────────
create or replace function public.log_match_action(
  p_match_id uuid,
  p_actor_id uuid,
  p_action   text,
  p_detail   jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.match_lifecycle_log (match_id, actor_id, action, detail)
  values (p_match_id, p_actor_id, p_action, coalesce(p_detail, '{}'::jsonb));
$$;

revoke all on function public.log_match_action(uuid, uuid, text, jsonb)
  from public, anon, authenticated;

-- Shared guard: the caller must be the organizer of p_match.
create or replace function public.require_match_organizer(
  p_match_id uuid,
  p_uid      uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organizer uuid;
begin
  select organizer_id into v_organizer
    from public.matches
   where id = p_match_id;

  if v_organizer is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_organizer <> p_uid then
    raise exception 'not_match_organizer' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.require_match_organizer(uuid, uuid)
  from public, anon, authenticated;

-- ── creation and scheduling ─────────────────────────────────────────────────
create or replace function public.create_match(
  p_sport_key    text,
  p_format_label text,
  p_rules        jsonb,
  p_title        text,
  p_venue        text,
  p_scheduled_at timestamptz,
  p_visibility   text,
  p_side_a       text,
  p_side_b       text,
  p_capacity     int,
  p_discipline   text,
  p_scorer_id    uuid default null
)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_sport  text := lower(trim(coalesce(p_sport_key, '')));
  v_title  text := trim(coalesce(p_title, ''));
  v_venue  text := trim(coalesce(p_venue, ''));
  v_vis    text := lower(trim(coalesce(p_visibility, 'public')));
  v_a      text := trim(coalesce(p_side_a, ''));
  v_b      text := trim(coalesce(p_side_b, ''));
  v_format text := trim(coalesce(p_format_label, ''));
  v_disc   text := nullif(lower(trim(coalesce(p_discipline, ''))), '');
  v_rules  jsonb := coalesce(p_rules, '{}'::jsonb);
  v_row    public.matches;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not exists (select 1 from public.sports where key = v_sport) then
    raise exception 'invalid_sport' using errcode = '22023';
  end if;
  if char_length(v_format) not between 1 and 60 then
    raise exception 'invalid_format' using errcode = '22023';
  end if;
  if char_length(v_title) not between 2 and 80 then
    raise exception 'invalid_match_title' using errcode = '22023';
  end if;
  if char_length(v_venue) > 80 then
    raise exception 'invalid_venue' using errcode = '22023';
  end if;
  if p_scheduled_at is null then
    raise exception 'invalid_schedule' using errcode = '22023';
  end if;
  if v_vis not in ('public', 'invite') then
    raise exception 'invalid_visibility' using errcode = '22023';
  end if;
  if char_length(v_a) not between 1 and 40 or char_length(v_b) not between 1 and 40 then
    raise exception 'invalid_side_name' using errcode = '22023';
  end if;
  if p_capacity is null or p_capacity not between 2 and 100 then
    raise exception 'invalid_capacity' using errcode = '22023';
  end if;
  if jsonb_typeof(v_rules) <> 'object' then
    raise exception 'invalid_rules' using errcode = '22023';
  end if;

  -- Cricket and futsal are team games; the racket sports must say whether the
  -- match is singles or doubles, because their engines read it.
  if v_sport in ('padel', 'badminton') then
    if v_disc is null or v_disc not in ('singles', 'doubles') then
      raise exception 'invalid_discipline' using errcode = '22023';
    end if;
  else
    if v_disc is null then
      v_disc := 'team';
    elsif v_disc <> 'team' then
      raise exception 'invalid_discipline' using errcode = '22023';
    end if;
  end if;

  if p_scorer_id is not null
     and not exists (select 1 from public.profiles where id = p_scorer_id) then
    raise exception 'scorer_not_found' using errcode = '22023';
  end if;

  v_rules := v_rules || jsonb_build_object('discipline', v_disc);

  insert into public.matches
    (sport_key, format_label, rules, title, venue, scheduled_at, visibility,
     organizer_id, scorer_id, side_a_name, side_b_name, discipline, capacity)
  values
    (v_sport, v_format, v_rules, v_title, v_venue, p_scheduled_at, v_vis,
     v_uid, p_scorer_id, v_a, v_b, v_disc, p_capacity)
  returning * into v_row;

  -- The organizer is a participant from the start, on side A.
  insert into public.match_participants (match_id, profile_id, side, status, invited_by)
  values (v_row.id, v_uid, 0, 'accepted', v_uid)
  on conflict (match_id, profile_id) do update
     set side   = 0,
         status = 'accepted';

  perform public.log_match_action(
    v_row.id, v_uid, 'created',
    jsonb_build_object(
      'sport', v_sport,
      'format', v_format,
      'scorer_id', p_scorer_id
    )
  );

  return v_row;
end;
$$;

create or replace function public.update_match(
  p_match_id     uuid,
  p_title        text,
  p_venue        text,
  p_scheduled_at timestamptz,
  p_side_a       text,
  p_side_b       text,
  p_capacity     int
)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_title text := trim(coalesce(p_title, ''));
  v_venue text := trim(coalesce(p_venue, ''));
  v_a     text := trim(coalesce(p_side_a, ''));
  v_b     text := trim(coalesce(p_side_b, ''));
  v_row   public.matches;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_row from public.matches where id = p_match_id for update;
  if v_row.status <> 'upcoming' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  if char_length(v_title) not between 2 and 80 then
    raise exception 'invalid_match_title' using errcode = '22023';
  end if;
  if char_length(v_venue) > 80 then
    raise exception 'invalid_venue' using errcode = '22023';
  end if;
  if char_length(v_a) not between 1 and 40 or char_length(v_b) not between 1 and 40 then
    raise exception 'invalid_side_name' using errcode = '22023';
  end if;
  if p_capacity is null or p_capacity not between 2 and 100 then
    raise exception 'invalid_capacity' using errcode = '22023';
  end if;
  if p_scheduled_at is null then
    raise exception 'invalid_schedule' using errcode = '22023';
  end if;

  update public.matches
     set title        = v_title,
         venue        = v_venue,
         scheduled_at = p_scheduled_at,
         side_a_name  = v_a,
         side_b_name  = v_b,
         capacity     = p_capacity
   where id = p_match_id
  returning * into v_row;

  perform public.log_match_action(p_match_id, v_uid, 'updated', '{}'::jsonb);

  return v_row;
end;
$$;

-- ── participants ────────────────────────────────────────────────────────────
create or replace function public.invite_match_participant(
  p_match_id   uuid,
  p_profile_id uuid,
  p_side       int default 1
)
returns public.match_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_match     public.matches;
  v_accepted  int;
  v_side      smallint := coalesce(p_side, 1);
  v_row       public.match_participants;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.status not in ('upcoming', 'live') then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  if p_profile_id is null
     or not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception 'player_not_found' using errcode = '22023';
  end if;
  if p_profile_id = v_match.organizer_id then
    raise exception 'organizer_already_joined' using errcode = '22023';
  end if;
  if v_side not in (0, 1) then
    raise exception 'invalid_side' using errcode = '22023';
  end if;

  select count(*) into v_accepted
    from public.match_participants
   where match_id = p_match_id
     and status = 'accepted';
  if v_accepted >= v_match.capacity then
    raise exception 'match_full' using errcode = '22023';
  end if;

  insert into public.match_participants as mp
    (match_id, profile_id, side, status, invited_by)
  values
    (p_match_id, p_profile_id, v_side, 'invited', v_uid)
  on conflict (match_id, profile_id) do update
     set side       = excluded.side,
         status     = case when mp.status = 'accepted'
                           then 'accepted' else 'invited' end,
         invited_by = excluded.invited_by
  returning * into v_row;

  perform public.log_match_action(
    p_match_id, v_uid, 'participant_invited',
    jsonb_build_object('profile_id', p_profile_id, 'side', v_side)
  );

  return v_row;
end;
$$;

create or replace function public.respond_match_invite(
  p_match_id uuid,
  p_accept   boolean
)
returns public.match_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_match    public.matches;
  v_row      public.match_participants;
  v_accepted int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  select * into v_row
    from public.match_participants
   where match_id = p_match_id and profile_id = v_uid
   for update;

  if v_row.match_id is null or v_row.status not in ('invited', 'accepted') then
    raise exception 'invite_not_found' using errcode = '42501';
  end if;

  if p_accept then
    select count(*) into v_accepted
      from public.match_participants
     where match_id = p_match_id
       and status = 'accepted'
       and profile_id <> v_uid;
    if v_accepted >= v_match.capacity then
      raise exception 'match_full' using errcode = '22023';
    end if;
  end if;

  update public.match_participants
     set status = case when p_accept then 'accepted' else 'declined' end
   where match_id = p_match_id and profile_id = v_uid
  returning * into v_row;

  perform public.log_match_action(
    p_match_id, v_uid,
    case when p_accept then 'participant_accepted' else 'participant_declined' end,
    '{}'::jsonb
  );

  return v_row;
end;
$$;

create or replace function public.remove_match_participant(
  p_match_id   uuid,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_match public.matches;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  if v_uid <> v_match.organizer_id and v_uid <> p_profile_id then
    raise exception 'not_match_organizer' using errcode = '42501';
  end if;
  if p_profile_id = v_match.organizer_id then
    raise exception 'cannot_remove_organizer' using errcode = '22023';
  end if;
  if v_match.status not in ('upcoming', 'live') then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  update public.match_participants
     set status = 'removed'
   where match_id = p_match_id and profile_id = p_profile_id;

  if not found then
    raise exception 'participant_not_found' using errcode = 'P0002';
  end if;

  perform public.log_match_action(
    p_match_id, v_uid, 'participant_removed',
    jsonb_build_object('profile_id', p_profile_id)
  );
end;
$$;

-- ── official scorer ─────────────────────────────────────────────────────────
create or replace function public.assign_match_scorer(
  p_match_id uuid,
  p_scorer_id uuid
)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_match   public.matches;
  v_previous uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.status not in ('upcoming', 'live') then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  if p_scorer_id is null
     or not exists (select 1 from public.profiles where id = p_scorer_id) then
    raise exception 'scorer_not_found' using errcode = '22023';
  end if;

  -- Reassignment never touches the recorded log, so a transferred scorer
  -- resumes from exactly where the previous one stopped.
  v_previous := v_match.scorer_id;

  update public.matches
     set scorer_id = p_scorer_id
   where id = p_match_id
  returning * into v_match;

  perform public.log_match_action(
    p_match_id, v_uid, 'scorer_assigned',
    jsonb_build_object(
      'scorer_id', p_scorer_id,
      'previous_scorer_id', v_previous,
      'events_so_far', v_match.event_count
    )
  );

  return v_match;
end;
$$;

create or replace function public.revoke_match_scorer(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_match public.matches;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.status not in ('upcoming', 'live') then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  update public.matches set scorer_id = null where id = p_match_id
  returning * into v_match;

  perform public.log_match_action(
    p_match_id, v_uid, 'scorer_revoked', '{}'::jsonb
  );

  return v_match;
end;
$$;

-- ── lifecycle ───────────────────────────────────────────────────────────────
create or replace function public.start_match(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_match public.matches;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_uid <> v_match.organizer_id
     and (v_match.scorer_id is null or v_uid <> v_match.scorer_id) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'upcoming' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  update public.matches
     set status     = 'live',
         started_at = now()
   where id = p_match_id
  returning * into v_match;

  perform public.log_match_action(p_match_id, v_uid, 'started', '{}'::jsonb);

  return v_match;
end;
$$;

create or replace function public.cancel_match(
  p_match_id uuid,
  p_reason   text default null
)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.status not in ('upcoming', 'live') then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  update public.matches
     set status       = 'cancelled',
         completed_at = now()
   where id = p_match_id
  returning * into v_match;

  perform public.log_match_action(
    p_match_id, v_uid, 'cancelled', jsonb_build_object('reason', v_reason)
  );

  return v_match;
end;
$$;

-- ── scoring log ─────────────────────────────────────────────────────────────
create or replace function public.record_match_event(
  p_match_id        uuid,
  p_client_event_id text,
  p_kind            text,
  p_side            int,
  p_data            jsonb
)
returns public.match_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_client text := trim(coalesce(p_client_event_id, ''));
  v_kind   text := trim(coalesce(p_kind, ''));
  v_data   jsonb := coalesce(p_data, '{}'::jsonb);
  v_side   smallint := p_side;
  v_seq    bigint;
  v_row    public.match_events;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- The row lock serialises sequence assignment for this match, so two taps
  -- arriving together cannot share a seq.
  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  if v_uid <> v_match.organizer_id
     and (v_match.scorer_id is null or v_uid <> v_match.scorer_id) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  if char_length(v_client) not between 1 and 80 then
    raise exception 'invalid_client_event' using errcode = '22023';
  end if;
  if char_length(v_kind) not between 1 and 40 then
    raise exception 'invalid_event_kind' using errcode = '22023';
  end if;
  if v_side is not null and v_side not in (0, 1) then
    raise exception 'invalid_event_side' using errcode = '22023';
  end if;
  if jsonb_typeof(v_data) <> 'object' then
    raise exception 'invalid_event_data' using errcode = '22023';
  end if;

  -- A retried tap is not an error: the same client id always maps to one row.
  select * into v_row
    from public.match_events
   where match_id = p_match_id and client_event_id = v_client;
  if v_row.id is not null then
    return v_row;
  end if;

  v_seq := v_match.event_count + 1;

  insert into public.match_events
    (match_id, seq, client_event_id, kind, side, data, recorded_by)
  values
    (p_match_id, v_seq, v_client, v_kind, v_side, v_data, v_uid)
  returning * into v_row;

  update public.matches
     set event_count = v_seq
   where id = p_match_id;

  return v_row;
end;
$$;

create or replace function public.void_match_event(
  p_match_id uuid,
  p_event_id uuid
)
returns public.match_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_row    public.match_events;
  v_last   bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_uid <> v_match.organizer_id
     and (v_match.scorer_id is null or v_uid <> v_match.scorer_id) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  select max(seq) into v_last
    from public.match_events
   where match_id = p_match_id and not voided;

  select * into v_row
    from public.match_events
   where id = p_event_id and match_id = p_match_id;

  if v_row.id is null then
    raise exception 'event_not_found' using errcode = 'P0002';
  end if;
  if v_row.voided then
    return v_row;
  end if;
  -- Undo is exact: only the newest active entry may be withdrawn, so the fold
  -- can never skip over a later score.
  if v_row.seq <> v_last then
    raise exception 'not_last_event' using errcode = '22023';
  end if;

  update public.match_events
     set voided = true
   where id = p_event_id
  returning * into v_row;

  return v_row;
end;
$$;

-- ── results ─────────────────────────────────────────────────────────────────
create or replace function public.submit_match_result(
  p_match_id     uuid,
  p_headline     text,
  p_detail       text,
  p_side_scores  jsonb,
  p_side_values  jsonb,
  p_winner_index int
)
returns public.match_results
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_row    public.match_results;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_uid <> v_match.organizer_id
     and (v_match.scorer_id is null or v_uid <> v_match.scorer_id) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  if p_side_scores is null or jsonb_typeof(p_side_scores) <> 'array'
     or jsonb_array_length(p_side_scores) <> 2 then
    raise exception 'invalid_result_payload' using errcode = '22023';
  end if;
  if p_side_values is null or jsonb_typeof(p_side_values) <> 'array'
     or jsonb_array_length(p_side_values) <> 2 then
    raise exception 'invalid_result_payload' using errcode = '22023';
  end if;
  if p_winner_index is null or p_winner_index not between -1 and 1 then
    raise exception 'invalid_result_payload' using errcode = '22023';
  end if;

  insert into public.match_results as mr
    (match_id, side_scores, side_values, winner_index, headline, detail,
     walkover, published_by)
  values
    (p_match_id, p_side_scores, p_side_values, p_winner_index,
     coalesce(p_headline, ''), coalesce(p_detail, ''), false, v_uid)
  on conflict (match_id) do update
     set side_scores  = excluded.side_scores,
         side_values  = excluded.side_values,
         winner_index = excluded.winner_index,
         headline     = excluded.headline,
         detail       = excluded.detail,
         walkover     = false,
         published_by = excluded.published_by,
         published_at = now()
  returning * into v_row;

  update public.matches
     set status       = 'submitted',
         submitted_at = now()
   where id = p_match_id;

  perform public.log_match_action(
    p_match_id, v_uid, 'result_submitted',
    jsonb_build_object('headline', coalesce(p_headline, ''))
  );

  return v_row;
end;
$$;

create or replace function public.publish_match_result(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_match public.matches;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.status <> 'submitted' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if not exists (select 1 from public.match_results where match_id = p_match_id) then
    raise exception 'result_missing' using errcode = 'P0002';
  end if;

  update public.match_results
     set published_by = v_uid,
         published_at = now()
   where match_id = p_match_id;

  update public.matches
     set status       = 'published',
         published_at = now(),
         completed_at = coalesce(completed_at, now())
   where id = p_match_id
  returning * into v_match;

  perform public.log_match_action(p_match_id, v_uid, 'result_published', '{}'::jsonb);

  return v_match;
end;
$$;

create or replace function public.correct_match_result(
  p_match_id     uuid,
  p_headline     text,
  p_detail       text,
  p_side_scores  jsonb,
  p_side_values  jsonb,
  p_winner_index int,
  p_reason       text
)
returns public.match_results
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_match   public.matches;
  v_prev    public.match_results;
  v_row     public.match_results;
  v_reason  text := trim(coalesce(p_reason, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.status <> 'published' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if char_length(v_reason) < 3 then
    raise exception 'invalid_correction_reason' using errcode = '22023';
  end if;
  if p_side_scores is null or jsonb_typeof(p_side_scores) <> 'array'
     or jsonb_array_length(p_side_scores) <> 2
     or p_side_values is null or jsonb_typeof(p_side_values) <> 'array'
     or jsonb_array_length(p_side_values) <> 2
     or p_winner_index is null or p_winner_index not between -1 and 1 then
    raise exception 'invalid_result_payload' using errcode = '22023';
  end if;

  select * into v_prev from public.match_results where match_id = p_match_id;
  if v_prev.match_id is null then
    raise exception 'result_missing' using errcode = 'P0002';
  end if;

  insert into public.match_result_corrections
    (match_id, previous, current, reason, changed_by)
  values
    (p_match_id,
     jsonb_build_object(
       'sideScores', v_prev.side_scores,
       'sideValues', v_prev.side_values,
       'winnerIndex', v_prev.winner_index,
       'headline', v_prev.headline,
       'detail', v_prev.detail,
       'walkover', v_prev.walkover,
       'publishedById', v_prev.published_by,
       'publishedAt', v_prev.published_at
     ),
     jsonb_build_object(
       'sideScores', p_side_scores,
       'sideValues', p_side_values,
       'winnerIndex', p_winner_index,
       'headline', coalesce(p_headline, ''),
       'detail', coalesce(p_detail, ''),
       'walkover', false,
       'publishedById', v_uid,
       'publishedAt', now()
     ),
     v_reason, v_uid);

  update public.match_results
     set side_scores  = p_side_scores,
         side_values  = p_side_values,
         winner_index = p_winner_index,
         headline     = coalesce(p_headline, ''),
         detail       = coalesce(p_detail, ''),
         walkover     = false,
         published_by = v_uid,
         published_at = now()
   where match_id = p_match_id
  returning * into v_row;

  perform public.log_match_action(
    p_match_id, v_uid, 'result_corrected', jsonb_build_object('reason', v_reason)
  );

  return v_row;
end;
$$;

create or replace function public.record_match_walkover(
  p_match_id     uuid,
  p_winner_index int,
  p_reason       text
)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_reason text := trim(coalesce(p_reason, ''));
  v_scores jsonb;
  v_values jsonb;
  v_headline text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.status not in ('upcoming', 'live', 'submitted') then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if p_winner_index is null or p_winner_index not in (0, 1) then
    raise exception 'invalid_result_payload' using errcode = '22023';
  end if;

  v_scores := case when p_winner_index = 0
    then jsonb_build_array('W', 'L')
    else jsonb_build_array('L', 'W') end;
  v_values := case when p_winner_index = 0
    then jsonb_build_array(1, 0)
    else jsonb_build_array(0, 1) end;
  v_headline := (case when p_winner_index = 0
                   then v_match.side_a_name else v_match.side_b_name end)
                || ' won by walkover';

  insert into public.match_results as mr
    (match_id, side_scores, side_values, winner_index, headline, detail,
     walkover, published_by)
  values
    (p_match_id, v_scores, v_values, p_winner_index, v_headline,
     case when v_reason = '' then 'Walkover' else 'Walkover · ' || v_reason end,
     true, v_uid)
  on conflict (match_id) do update
     set side_scores  = excluded.side_scores,
         side_values  = excluded.side_values,
         winner_index = excluded.winner_index,
         headline     = excluded.headline,
         detail       = excluded.detail,
         walkover     = true,
         published_by = excluded.published_by,
         published_at = now();

  update public.matches
     set status       = 'walkover',
         completed_at = now()
   where id = p_match_id
  returning * into v_match;

  perform public.log_match_action(
    p_match_id, v_uid, 'walkover',
    jsonb_build_object('winner_index', p_winner_index, 'reason', v_reason)
  );

  return v_match;
end;
$$;

-- ── grants ──────────────────────────────────────────────────────────────────
revoke all on function public.create_match(
  text, text, jsonb, text, text, timestamptz, text, text, text, int, text, uuid
) from public, anon, authenticated;
revoke all on function public.update_match(
  uuid, text, text, timestamptz, text, text, int
) from public, anon, authenticated;
revoke all on function public.invite_match_participant(uuid, uuid, int)
  from public, anon, authenticated;
revoke all on function public.respond_match_invite(uuid, boolean)
  from public, anon, authenticated;
revoke all on function public.remove_match_participant(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.assign_match_scorer(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.revoke_match_scorer(uuid)
  from public, anon, authenticated;
revoke all on function public.start_match(uuid) from public, anon, authenticated;
revoke all on function public.cancel_match(uuid, text) from public, anon, authenticated;
revoke all on function public.record_match_event(uuid, text, text, int, jsonb)
  from public, anon, authenticated;
revoke all on function public.void_match_event(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.submit_match_result(
  uuid, text, text, jsonb, jsonb, int
) from public, anon, authenticated;
revoke all on function public.publish_match_result(uuid)
  from public, anon, authenticated;
revoke all on function public.correct_match_result(
  uuid, text, text, jsonb, jsonb, int, text
) from public, anon, authenticated;
revoke all on function public.record_match_walkover(uuid, int, text)
  from public, anon, authenticated;

grant execute on function public.create_match(
  text, text, jsonb, text, text, timestamptz, text, text, text, int, text, uuid
) to authenticated;
grant execute on function public.update_match(
  uuid, text, text, timestamptz, text, text, int
) to authenticated;
grant execute on function public.invite_match_participant(uuid, uuid, int)
  to authenticated;
grant execute on function public.respond_match_invite(uuid, boolean)
  to authenticated;
grant execute on function public.remove_match_participant(uuid, uuid)
  to authenticated;
grant execute on function public.assign_match_scorer(uuid, uuid)
  to authenticated;
grant execute on function public.revoke_match_scorer(uuid) to authenticated;
grant execute on function public.start_match(uuid) to authenticated;
grant execute on function public.cancel_match(uuid, text) to authenticated;
grant execute on function public.record_match_event(uuid, text, text, int, jsonb)
  to authenticated;
grant execute on function public.void_match_event(uuid, uuid) to authenticated;
grant execute on function public.submit_match_result(
  uuid, text, text, jsonb, jsonb, int
) to authenticated;
grant execute on function public.publish_match_result(uuid) to authenticated;
grant execute on function public.correct_match_result(
  uuid, text, text, jsonb, jsonb, int, text
) to authenticated;
grant execute on function public.record_match_walkover(uuid, int, text)
  to authenticated;

-- ── realtime ────────────────────────────────────────────────────────────────
-- Postgres Changes runs each subscriber's read under its own RLS policies, so a
-- member only ever receives matches they are allowed to see.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'matches'
    ) then
      alter publication supabase_realtime add table public.matches;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'match_events'
    ) then
      alter publication supabase_realtime add table public.match_events;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'match_results'
    ) then
      alter publication supabase_realtime add table public.match_results;
    end if;
  end if;
end;
$$;

commit;
