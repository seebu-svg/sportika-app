-- ─────────────────────────────────────────────────────────────────────────────
-- 0008_padel_module.sql
-- Adds tournament/fixture links, server-side padel fold, automatic completion,
-- and point-history RPC.  Does not remove or rename any existing object.
-- ─────────────────────────────────────────────────────────────────────────────

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  Tournament / fixture columns on matches
-- ════════════════════════════════════════════════════════════════════════════

alter table public.matches
  add column if not exists tournament_id text,
  add column if not exists fixture_id    text;

comment on column public.matches.tournament_id is
  'Tournament key when this match was generated from a draw; null for a standalone friendly.';
comment on column public.matches.fixture_id is
  'Fixture key within tournament_id; null for a standalone friendly.';

-- One match per fixture.  NULL values are not indexed so friendly matches
-- (both ids null) are unconstrained.
create unique index if not exists matches_fixture_unique
  on public.matches (tournament_id, fixture_id)
  where tournament_id is not null and fixture_id is not null;

-- Fast lookup when opening a fixture workspace.
create index if not exists matches_tournament_idx
  on public.matches (tournament_id)
  where tournament_id is not null;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  create_match – add optional tournament / fixture parameters
-- ════════════════════════════════════════════════════════════════════════════
-- The new parameters default to null, so every existing caller keeps working.

create or replace function public.create_match(
  p_sport_key     text,
  p_format_label  text,
  p_rules         jsonb,
  p_title         text,
  p_venue         text,
  p_scheduled_at  timestamptz,
  p_visibility    text,
  p_side_a        text,
  p_side_b        text,
  p_capacity      int,
  p_discipline    text,
  p_scorer_id     uuid    default null,
  p_tournament_id text    default null,
  p_fixture_id    text    default null
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
  v_tournament text := nullif(trim(coalesce(p_tournament_id, '')), '');
  v_fixture    text := nullif(trim(coalesce(p_fixture_id   , '')), '');
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
  if char_length(v_a) not between 1 and 40
     or char_length(v_b) not between 1 and 40 then
    raise exception 'invalid_side_name' using errcode = '22023';
  end if;
  if p_capacity is null or p_capacity not between 2 and 100 then
    raise exception 'invalid_capacity' using errcode = '22023';
  end if;
  if jsonb_typeof(v_rules) <> 'object' then
    raise exception 'invalid_rules' using errcode = '22023';
  end if;

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

  -- Tournament and fixture ids must both be present or both be absent.
  if (v_tournament is null) <> (v_fixture is null) then
    raise exception 'incomplete_fixture_link' using errcode = '22023';
  end if;
  -- Reject ids that are too long (defensive).
  if v_tournament is not null and char_length(v_tournament) > 80 then
    raise exception 'invalid_tournament_id' using errcode = '22023';
  end if;
  if v_fixture is not null and char_length(v_fixture) > 80 then
    raise exception 'invalid_fixture_id' using errcode = '22023';
  end if;

  v_rules := v_rules || jsonb_build_object('discipline', v_disc);

  insert into public.matches
    (sport_key, format_label, rules, title, venue, scheduled_at, visibility,
     organizer_id, scorer_id, side_a_name, side_b_name, discipline, capacity,
     tournament_id, fixture_id)
  values
    (v_sport, v_format, v_rules, v_title, v_venue, p_scheduled_at, v_vis,
     v_uid, p_scorer_id, v_a, v_b, v_disc, p_capacity,
     v_tournament, v_fixture)
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
      'sport',      v_sport,
      'format',     v_format,
      'scorer_id',  p_scorer_id,
      'tournament', v_tournament,
      'fixture',    v_fixture
    )
  );

  return v_row;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  _padel_fold  –  server-side reducer
--
--   Mirrors PadelEngine._applyPoint exactly.
--   STABLE: reads only; safe to call in the same transaction after the
--   latest INSERT (the new event row is visible inside the function).
--
--   Returns a JSONB object with the same keys as MatchProgress.state.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public._padel_fold(p_match_id uuid)
returns jsonb
language plpgsql stable
set search_path = public
as $$
declare
  -- rules
  v_rules       jsonb;
  v_format      text;
  v_no_ad       boolean;
  v_match_tb    boolean;
  v_sets_to_win int;
  v_games_to_win int;
  v_tb_at       int;   -- tiebreakAt: both at this count → tiebreak
  v_tb_points   int;   -- regular tiebreak target
  v_final_tb    int;   -- decider/super-tiebreak target
  -- loop
  v_event       record;
  s             int;   -- winner side 0-based
  o             int;
  diff          int;
  need          int;
  total         int;
  v_won         boolean;
  -- state (1-indexed: [1]=side A, [2]=side B)
  v_pts         int[] := '{0,0}';
  v_games       int[] := '{0,0}';
  v_tb          int[] := '{0,0}';
  v_sets_won    int[] := '{0,0}';
  v_turns       int[] := '{0,0}';
  v_completed   jsonb := '[]';
  v_in_tb       boolean := false;
  v_dec_tb      boolean := false;
  v_done        boolean := false;
  v_winner      int     := -1;
  v_serving     int     := 0;   -- 0 or 1
  v_pt_count    int     := 0;
  v_sets_done   int     := 0;
begin
  select rules, format_label into v_rules, v_format
    from public.matches where id = p_match_id;

  if v_rules is null then
    return '{}'::jsonb;
  end if;

  v_no_ad        := coalesce((v_rules->>'noAd')::boolean,              false);
  v_match_tb     := coalesce((v_rules->>'matchTiebreak')::boolean,     false);
  v_sets_to_win  := coalesce((v_rules->>'setsToWin')::int,
                              case v_format
                                when '1 set · first to 6' then 1
                                when 'Best of 5 sets'     then 3
                                else 2   -- best of 3, golden point, super tie-break
                              end);
  v_games_to_win := coalesce((v_rules->>'gamesToWinSet')::int,  6);
  v_tb_at        := coalesce((v_rules->>'tiebreakAt')::int,     v_games_to_win);
  v_tb_points    := coalesce((v_rules->>'tiebreakPoints')::int, 7);
  v_final_tb     := coalesce((v_rules->>'finalSetTiebreakPoints')::int, 10);

  for v_event in
    select side
      from public.match_events
     where match_id = p_match_id
       and kind     = 'point'
       and not voided
     order by seq
  loop
    if v_done then exit; end if;

    s := coalesce(v_event.side, 0);
    o := 1 - s;
    v_pt_count := v_pt_count + 1;

    if v_in_tb then
      -- ── tiebreak point ──────────────────────────────────────────────────
      v_tb[s+1] := v_tb[s+1] + 1;
      total     := v_tb[1] + v_tb[2];
      -- Service in a tiebreak: alternates when total is odd.
      if total % 2 = 1 then
        v_turns[v_serving+1] := v_turns[v_serving+1] + 1;
        v_serving := 1 - v_serving;
      end if;
      need := case
                when v_dec_tb then v_final_tb
                when v_sets_won[1] = v_sets_to_win - 1
                 and v_sets_won[2] = v_sets_to_win - 1 then v_final_tb
                else v_tb_points
              end;
      if v_tb[s+1] >= need and v_tb[s+1] - v_tb[o+1] >= 2 then
        -- Tiebreak won → set complete
        v_tb      := '{0,0}';
        v_in_tb   := false;
        v_games[s+1] := v_games[s+1] + 1;  -- 6→7 or 0→1
        -- Complete set
        v_completed := v_completed
          || jsonb_build_array(jsonb_build_array(v_games[1], v_games[2]));
        v_sets_won[s+1] := v_sets_won[s+1] + 1;
        v_games  := '{0,0}';
        v_pts    := '{0,0}';
        v_sets_done := v_sets_done + 1;
        -- Was this the deciding super tiebreak?
        v_dec_tb := false;
        -- Match or new set?
        if v_sets_won[s+1] >= v_sets_to_win then
          v_done   := true;
          v_winner := s;
        elsif v_match_tb
              and v_sets_to_win > 1
              and v_sets_won[1] = v_sets_to_win - 1
              and v_sets_won[2] = v_sets_to_win - 1 then
          v_in_tb  := true;
          v_dec_tb := true;
        end if;
      end if;

    else
      -- ── normal game point ────────────────────────────────────────────────
      v_pts[s+1] := v_pts[s+1] + 1;
      diff := v_pts[s+1] - v_pts[o+1];
      v_won := case
                 when v_no_ad then v_pts[s+1] >= 4 and diff >= 1
                 else              v_pts[s+1] >= 4 and diff >= 2
               end;
      if not v_won then continue; end if;

      v_pts := '{0,0}';
      v_games[s+1] := v_games[s+1] + 1;
      -- End service turn after each game
      v_turns[v_serving+1] := v_turns[v_serving+1] + 1;
      v_serving := 1 - v_serving;

      if v_games[s+1] >= v_games_to_win
         and v_games[s+1] - v_games[o+1] >= 2 then
        -- Set won outright
        v_completed := v_completed
          || jsonb_build_array(jsonb_build_array(v_games[1], v_games[2]));
        v_sets_won[s+1] := v_sets_won[s+1] + 1;
        v_games     := '{0,0}';
        v_pts       := '{0,0}';
        v_tb        := '{0,0}';
        v_in_tb     := false;
        v_sets_done := v_sets_done + 1;
        if v_sets_won[s+1] >= v_sets_to_win then
          v_done   := true;
          v_winner := s;
        elsif v_match_tb
              and v_sets_to_win > 1
              and v_sets_won[1] = v_sets_to_win - 1
              and v_sets_won[2] = v_sets_to_win - 1 then
          v_in_tb  := true;
          v_dec_tb := true;
        end if;

      elsif v_games[1] = v_tb_at and v_games[2] = v_tb_at then
        -- 6-6 → tiebreak
        v_in_tb := true;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'completedSets',   v_completed,
    'points',          jsonb_build_array(v_pts[1],   v_pts[2]),
    'tiebreakPoints',  jsonb_build_array(v_tb[1],    v_tb[2]),
    'setsWon',         jsonb_build_array(v_sets_won[1], v_sets_won[2]),
    'games',           jsonb_build_array(v_games[1], v_games[2]),
    'inTiebreak',      v_in_tb,
    'deciderTiebreak', v_dec_tb,
    'matchTiebreak',   v_match_tb,
    'noAd',            v_no_ad,
    'setsToWin',       v_sets_to_win,
    'gamesToWinSet',   v_games_to_win,
    'servingSide',     v_serving,
    'servingMember',   mod(v_turns[v_serving+1], 2),
    'pointCount',      v_pt_count,
    'setsCompleted',   v_sets_done,
    'isComplete',      v_done,
    'winnerSide',      v_winner
  );
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 4.  record_match_event – padel completion gate + auto-complete
--
--   Replaces the 0007 version.  The signature is identical; existing Dart
--   calls are unaffected.  Two new behaviours for padel:
--   a) A point event is rejected when completed_at is already set.
--   b) After a point is inserted the fold is replayed; when the fold says
--      the match is done we stamp completed_at and write a pending
--      match_results row (status stays 'live' so the scorer can still undo
--      until they explicitly submit).
-- ════════════════════════════════════════════════════════════════════════════

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
  v_fold   jsonb;
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

  -- Padel: once completed_at is set the scorer must undo before adding points.
  if v_match.sport_key = 'padel' and v_match.completed_at is not null then
    raise exception 'match_complete' using errcode = '22023';
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

  -- Idempotent: retried taps return the existing row.
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

  -- Padel: replay the fold after every point; stamp completion when done.
  if v_match.sport_key = 'padel' and v_kind = 'point' then
    v_fold := public._padel_fold(p_match_id);
    if (v_fold->>'isComplete')::boolean then
      update public.matches
         set completed_at = now()
       where id = p_match_id
         and completed_at is null;
      perform public.log_match_action(
        p_match_id, v_uid, 'padel_auto_complete',
        jsonb_build_object(
          'winner_side', v_fold->>'winnerSide',
          'sets_won',    v_fold->'setsWon'
        )
      );
    end if;
  end if;

  return v_row;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  void_match_event – clear completed_at when the padel fold reopens
--
--   Replaces the 0007 version.  The signature is identical.
--   After voiding the last event we re-run the fold; if it no longer reports
--   the match as complete we clear completed_at so new points can be added.
-- ════════════════════════════════════════════════════════════════════════════

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
  v_fold   jsonb;
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
  -- void is allowed while live AND while auto-completed (padel),
  -- but not after the result has been formally submitted.
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if v_match.submitted_at is not null then
    raise exception 'result_already_submitted' using errcode = '22023';
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
  if v_row.seq <> v_last then
    raise exception 'not_last_event' using errcode = '22023';
  end if;

  update public.match_events
     set voided = true
   where id = p_event_id
  returning * into v_row;

  -- Padel: re-fold and clear completed_at if the match is no longer done.
  if v_match.sport_key = 'padel' then
    v_fold := public._padel_fold(p_match_id);
    if not (v_fold->>'isComplete')::boolean then
      update public.matches
         set completed_at = null
       where id = p_match_id;
    end if;
  end if;

  return v_row;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 6.  get_padel_point_history
--
--   Returns a JSONB array of point-by-point records using the same fold as
--   PadelEngine.pointHistory().  The workspace reads this when a scorer wants
--   to review the full log without replaying events client-side.
--
--   The fold is the single source of truth; this function only formats output.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.get_padel_point_history(p_match_id uuid)
returns jsonb
language plpgsql stable
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
  select * into v_match from public.matches where id = p_match_id;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if not public.can_view_match(p_match_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'fold',       public._padel_fold(p_match_id),
    'events',     (
      select coalesce(
               jsonb_agg(
                 jsonb_build_object(
                   'seq',   e.seq,
                   'side',  e.side,
                   'at',    e.created_at,
                   'by',    e.recorded_by,
                   'voided', e.voided
                 )
                 order by e.seq
               ),
               '[]'::jsonb
             )
        from public.match_events e
       where e.match_id = p_match_id
         and e.kind     = 'point'
         and not e.voided
    )
  );
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 7.  matchOfFixture lookup helper
--
--   Used by SupabaseMatchRepository.matchOfFixture().
--   Returns null when no match exists for the given tournament + fixture.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.match_of_fixture(
  p_tournament_id text,
  p_fixture_id    text
)
returns public.matches
language sql stable
security definer
set search_path = public
as $$
  select * from public.matches
   where tournament_id = p_tournament_id
     and fixture_id    = p_fixture_id
   limit 1;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 8.  Grants
-- ════════════════════════════════════════════════════════════════════════════

-- Internal helper: not callable from PostgREST (leading underscore).
revoke all on function public._padel_fold(uuid) from public;

-- record_match_event and void_match_event keep their existing grants.
revoke all on function public.record_match_event(uuid, text, text, int, jsonb)
  from anon;
grant  execute on function public.record_match_event(uuid, text, text, int, jsonb)
  to authenticated;

revoke all on function public.void_match_event(uuid, uuid) from anon;
grant  execute on function public.void_match_event(uuid, uuid) to authenticated;

revoke all on function public.get_padel_point_history(uuid) from anon;
grant  execute on function public.get_padel_point_history(uuid) to authenticated;

revoke all on function public.match_of_fixture(text, text) from anon;
grant  execute on function public.match_of_fixture(text, text) to authenticated;

-- create_match has a new signature; revoke old and grant new.
-- The signature below must list all fourteen parameters in declaration order
-- (text, text, jsonb, ...): an earlier draft dropped the second text and the
-- whole migration aborted on "function does not exist".
-- The twelve-parameter version from 0007 must also go: Postgres keeps both
-- overloads, and a twelve-argument call (which is exactly what the app and the
-- pgTAP suite make) then fails with "function is not unique" because the new
-- parameters are defaulted.
drop function if exists public.create_match(
  text, text, jsonb, text, text, timestamptz, text, text, text, int, text, uuid
);
revoke all on function public.create_match(
  text, text, jsonb, text, text, timestamptz, text,
  text, text, int, text, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.create_match(
  text, text, jsonb, text, text, timestamptz, text,
  text, text, int, text, uuid, text, text
) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 9.  Add new columns to the Realtime publication
--     (the matches table is already published from 0007, but the new columns
--      are not automatically re-added — verify this is a no-op on re-run).
-- ════════════════════════════════════════════════════════════════════════════
-- No additional action needed: the entire table is already in the publication.
