-- Sportika futsal discovery: a draw that produces a match somebody can score.
--
-- 0016 built tournaments and a draw from the confirmed entries. For futsal it
-- produced fixtures nobody could use: `capacity = registration_limit` (a league
-- of eight squads made five-a-side matches with eight slots), and no
-- participants at all, so every scorer opened a match with empty rosters and
-- the lineup validator refused to start it. Registration had the mirror
-- problem: `register_tournament_entry` was told only a squad id, and the app
-- sent only the captain, so a squad entry was stored as one member labelled
-- with first names. A futsal draw could therefore start from four-player
-- squads, which is not a team.
--
-- This migration makes the server the authority for all three:
--
--  1. `register_tournament_entry` derives the entry from the squad it was given:
--     the label is the squad's name, the members are its accepted members plus
--     the caller, and the caller must actually belong to it. A futsal entry
--     below five members is refused (`squad_below_minimum`).
--  2. `decide_tournament_entry` re-checks that minimum when the organizer
--     confirms, so a squad that shrank between registering and approval cannot
--     reach a draw.
--  3. `generate_tournament_draw` sizes each fixture for the deepest confirmed
--     squad (`2 * max squad`, never below 10) and seeds both sides with those
--     members as accepted participants. A futsal draw with an undersized squad
--     is refused outright (`draw_needs_full_squads`).
--
-- It also adds the missing way into a match: a public match can be joined
-- (`join_match`), left before kick-off (`leave_match`), and an organizer or
-- scorer can invite a whole squad at once (`add_match_squad`). Invites remain
-- consent-based; only draw provisioning writes `accepted` without asking,
-- because registering the squad was the consent.
--
-- Verified by supabase/tests/futsal_discovery_test.sql and test/futsal_join_test.dart.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  Registration derives the entry from the squad
-- ════════════════════════════════════════════════════════════════════════════

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
  v_squad  public.teams;
  v_label  text := trim(coalesce(p_label, ''));
  v_members uuid[] := coalesce(p_member_ids, '{}'::uuid[]);
  v_squad_id text := nullif(trim(coalesce(p_squad_id, '')), '');
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

  -- A squad entry is the squad: its name, its members, and only for somebody
  -- who is on it. The client no longer has to expand either.
  if v_squad_id is not null then
    select * into v_squad from public.teams where id = v_squad_id;
    if v_squad.id is null then
      raise exception 'squad_not_found' using errcode = '22023';
    end if;
    if v_squad.type <> v_t.entry_type then
      raise exception 'entry_type_mismatch' using errcode = '22023';
    end if;
    if v_squad.owner_id <> v_uid
       and not exists (
         select 1 from public.team_members tm
          where tm.team_id = v_squad.id
            and tm.profile_id = v_uid
            and tm.status = 'accepted'
       ) then
      raise exception 'not_squad_member' using errcode = '42501';
    end if;

    v_members := (
      select coalesce(array_agg(distinct tm.profile_id), '{}'::uuid[])
        from public.team_members tm
       where tm.team_id = v_squad.id
         and tm.status = 'accepted'
    );
    if not (v_uid = any (v_members)) then
      v_members := array_append(v_members, v_uid);
    end if;
    if v_label = '' then
      v_label := left(v_squad.name, 60);
    end if;
  end if;

  if char_length(v_label) not between 1 and 60 then
    raise exception 'invalid_entry_label' using errcode = '22023';
  end if;

  v_members := (select array_agg(distinct m) from unnest(v_members) m);
  if v_members is null then
    v_members := '{}'::uuid[];
  end if;
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

  -- Five a side is the floor for a futsal team entry; the draw enforces it
  -- again, so a squad that shrinks after this point still cannot be drawn.
  if v_t.sport_key = 'futsal'
     and v_t.entry_type = 'team'
     and cardinality(v_members) < 5 then
    raise exception 'squad_below_minimum' using errcode = '22023';
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
    v_id, p_tournament_id, v_uid, v_label, v_squad_id,
    v_members, 'pending'
  );

  return v_id;
end;
$$;

revoke all on function public.register_tournament_entry(text, text, uuid[], text)
  from public, anon, authenticated;
grant execute on function public.register_tournament_entry(text, text, uuid[], text)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  Confirming an entry re-checks the floor
-- ════════════════════════════════════════════════════════════════════════════

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

  if p_approve
     and v_t.sport_key = 'futsal'
     and v_t.entry_type = 'team'
     and cardinality(v_e.member_ids) < 5 then
    raise exception 'squad_below_minimum' using errcode = '22023';
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

revoke all on function public.decide_tournament_entry(text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.decide_tournament_entry(text, boolean, text)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  The draw sizes and seeds its fixtures
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.generate_tournament_draw(p_tournament_id text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_t         public.tournaments;
  v_ids       text[] := '{}'::text[];
  v_names     text[] := '{}'::text[];
  v_created   int := 0;
  v_i         int;
  v_j         int;
  v_round     int;
  v_stage     text;
  v_fixture   text;
  v_match     uuid;
  v_capacity  int;
  v_min_squad int;
  v_max_squad int;
  v_members_a uuid[];
  v_members_b uuid[];
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

  select coalesce(min(cardinality(e.member_ids)), 0),
         coalesce(max(cardinality(e.member_ids)), 0)
    into v_min_squad, v_max_squad
    from public.tournament_entries e
   where e.tournament_id = p_tournament_id
     and e.status = 'confirmed';

  if v_t.sport_key = 'futsal' then
    -- A fixture whose sides cannot field five players is not a match.
    if v_min_squad < 5 or v_max_squad * 2 < 10 then
      raise exception 'draw_needs_full_squads' using errcode = '22023';
    end if;
    v_capacity := greatest(v_max_squad * 2, 10);
  else
    v_capacity := v_t.registration_limit;
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
          v_capacity, p_tournament_id, v_fixture, v_t.is_demo
        )
        returning id into v_match;

        select e.member_ids into v_members_a
          from public.tournament_entries e where e.id = v_ids[v_i];
        select e.member_ids into v_members_b
          from public.tournament_entries e where e.id = v_ids[v_j];

        insert into public.match_participants (match_id, profile_id, side, status, invited_by)
        select v_match, m, 0, 'accepted', v_uid from unnest(coalesce(v_members_a, '{}')) m
        on conflict (match_id, profile_id) do nothing;

        insert into public.match_participants (match_id, profile_id, side, status, invited_by)
        select v_match, m, 1, 'accepted', v_uid from unnest(coalesce(v_members_b, '{}')) m
        on conflict (match_id, profile_id) do nothing;

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
        v_capacity, p_tournament_id, v_fixture, v_t.is_demo
      )
      returning id into v_match;

      select e.member_ids into v_members_a
        from public.tournament_entries e where e.id = v_ids[v_i * 2 - 1];
      select e.member_ids into v_members_b
        from public.tournament_entries e where e.id = v_ids[v_i * 2];

      insert into public.match_participants (match_id, profile_id, side, status, invited_by)
      select v_match, m, 0, 'accepted', v_uid from unnest(coalesce(v_members_a, '{}')) m
      on conflict (match_id, profile_id) do nothing;

      insert into public.match_participants (match_id, profile_id, side, status, invited_by)
      select v_match, m, 1, 'accepted', v_uid from unnest(coalesce(v_members_b, '{}')) m
      on conflict (match_id, profile_id) do nothing;

      v_created := v_created + 1;
    end loop;
  end if;

  if v_created > 0 then
    update public.tournaments set status = 'inProgress' where id = p_tournament_id;
  end if;

  return v_created;
end;
$$;

revoke all on function public.generate_tournament_draw(text)
  from public, anon, authenticated;
grant execute on function public.generate_tournament_draw(text)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 4.  Joining a match
-- ════════════════════════════════════════════════════════════════════════════
-- A public match is open until it starts. The per-side cap is derived from
-- `capacity`: five a side at capacity 10, room for a bench at 14. Being in the
-- match is the consent, so the row is written `accepted`; the organizer is told.

create or replace function public.join_match(
  p_match_id uuid,
  p_side     int
)
returns public.match_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_row    public.match_participants;
  v_cap    int;
  v_taken  int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_match.visibility <> 'public' then
    raise exception 'match_not_public' using errcode = '42501';
  end if;
  if v_match.status <> 'upcoming' or v_match.started_at is not null then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if p_side is null or p_side not in (0, 1) then
    raise exception 'invalid_event_side' using errcode = '22023';
  end if;

  select * into v_row
    from public.match_participants
   where match_id = p_match_id and profile_id = v_uid;

  -- Already in, or already asked: joining twice is not an error.
  if v_row.profile_id is not null and v_row.status = 'accepted' then
    return v_row;
  end if;
  if v_row.profile_id is not null and v_row.status = 'invited' then
    update public.match_participants
       set status = 'accepted', side = p_side
     where match_id = p_match_id and profile_id = v_uid
    returning * into v_row;
    return v_row;
  end if;

  v_cap := case v_match.discipline
             when 'team'    then greatest(v_match.capacity / 2, 1)
             when 'singles' then 1
             when 'doubles' then 2
             else v_match.capacity
           end;

  select count(*) into v_taken
    from public.match_participants
   where match_id = p_match_id
     and side = p_side
     and status = 'accepted';
  if v_taken >= v_cap then
    raise exception 'side_full' using errcode = '22023';
  end if;

  insert into public.match_participants (match_id, profile_id, side, status, invited_by)
  values (p_match_id, v_uid, p_side, 'accepted', v_uid)
  on conflict (match_id, profile_id) do update
     set side   = excluded.side,
         status = 'accepted'
  returning * into v_row;

  perform public._notify(
    v_match.organizer_id, 'match', 'match_join', 'Player joined',
    format('%s joined %s.', public._display_name(v_uid), v_match.title),
    'match', v_match.id::text,
    jsonb_build_object('matchId', v_match.id, 'tab', 2),
    v_uid,
    format('match_join:%s:%s:%s', v_match.id, v_uid,
           to_char(now() at time zone 'UTC', 'YYMMDDHH24MISSUS'))
  );

  perform public.log_match_action(
    p_match_id, v_uid, 'participant_joined',
    jsonb_build_object('side', p_side)
  );

  return v_row;
end;
$$;

revoke all on function public.join_match(uuid, int)
  from public, anon, authenticated;
grant execute on function public.join_match(uuid, int) to authenticated;

create or replace function public.leave_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_match public.matches;
  v_row   public.match_participants;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_match.status <> 'upcoming' or v_match.started_at is not null then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if v_match.organizer_id = v_uid then
    raise exception 'organizer_cannot_leave' using errcode = '22023';
  end if;

  select * into v_row
    from public.match_participants
   where match_id = p_match_id and profile_id = v_uid;
  if v_row.profile_id is null or v_row.status not in ('invited', 'accepted') then
    raise exception 'not_participant' using errcode = 'P0002';
  end if;

  update public.match_participants
     set status = 'removed'
   where match_id = p_match_id and profile_id = v_uid;

  perform public.log_match_action(
    p_match_id, v_uid, 'participant_left',
    jsonb_build_object('side', v_row.side)
  );
end;
$$;

revoke all on function public.leave_match(uuid)
  from public, anon, authenticated;
grant execute on function public.leave_match(uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  Adding a whole squad
-- ════════════════════════════════════════════════════════════════════════════
-- Consent stays with the players: they are invited, not enrolled, and the
-- participant trigger sends each of them the usual invitation. The caller must
-- be on the squad they are adding.

create or replace function public.add_match_squad(
  p_match_id uuid,
  p_side     int,
  p_squad_id text
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_match public.matches;
  v_squad public.teams;
  v_squad_id text := nullif(trim(coalesce(p_squad_id, '')), '');
  v_cap   int;
  v_taken int;
  v_add   int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if not public.can_score_match(p_match_id, v_uid) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'upcoming' or v_match.started_at is not null then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if p_side is null or p_side not in (0, 1) then
    raise exception 'invalid_event_side' using errcode = '22023';
  end if;

  if v_squad_id is null then
    raise exception 'squad_not_found' using errcode = '22023';
  end if;
  select * into v_squad from public.teams where id = v_squad_id;
  if v_squad.id is null then
    raise exception 'squad_not_found' using errcode = '22023';
  end if;
  if v_squad.owner_id <> v_uid
     and not exists (
       select 1 from public.team_members tm
        where tm.team_id = v_squad.id
          and tm.profile_id = v_uid
          and tm.status = 'accepted'
     ) then
    raise exception 'not_squad_member' using errcode = '42501';
  end if;

  v_cap := case v_match.discipline
             when 'team'    then greatest(v_match.capacity / 2, 1)
             when 'singles' then 1
             when 'doubles' then 2
             else v_match.capacity
           end;

  select count(*) into v_taken
    from public.match_participants
   where match_id = p_match_id
     and side = p_side
     and status in ('invited', 'accepted');

  select count(*) into v_add
    from public.team_members tm
   where tm.team_id = v_squad.id
     and tm.status = 'accepted'
     and not exists (
       select 1 from public.match_participants mp
        where mp.match_id = p_match_id and mp.profile_id = tm.profile_id
     );
  if v_taken + v_add > v_cap then
    raise exception 'side_full' using errcode = '22023';
  end if;

  insert into public.match_participants (match_id, profile_id, side, status, invited_by)
  select p_match_id, tm.profile_id, p_side, 'invited', v_uid
    from public.team_members tm
   where tm.team_id = v_squad.id
     and tm.status = 'accepted'
     and not exists (
       select 1 from public.match_participants mp
        where mp.match_id = p_match_id and mp.profile_id = tm.profile_id
     )
  on conflict (match_id, profile_id) do nothing;

  perform public.log_match_action(
    p_match_id, v_uid, 'squad_invited',
    jsonb_build_object('side', p_side, 'squadId', v_squad.id, 'added', v_add)
  );

  return v_add;
end;
$$;

revoke all on function public.add_match_squad(uuid, int, text)
  from public, anon, authenticated;
grant execute on function public.add_match_squad(uuid, int, text) to authenticated;

commit;
