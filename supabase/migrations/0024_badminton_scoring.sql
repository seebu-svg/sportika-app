-- Sportika badminton result authority: the rally log decides.
--
-- 0021 gave futsal a fold and left badminton on the generic door, where any
-- `kind` was accepted with any side, `submit_match_result` stored whatever two
-- strings and a winner the caller sent, and an unfinished match could be
-- published as if it were decided. The live data already shows the result: one
-- badminton match is published with `winner_index = -1`, `side_values [0,0]`
-- and nine rallies that never completed a game.
--
-- This migration gives badminton the same shape padel (0008/0013/0020) and
-- futsal (0021) have, without inventing a second rule book:
--
--   * `_badminton_fold_detail(uuid)` is the SQL mirror of BadmintonEngine:
--     rally-by-rally points, games to 21 win-by-two, the 30-point cap, best of
--     three or five, the current server and the service court. It reads the
--     same `rules` keys the engine reads (`gamesToWin`, `pointsToWinGame`,
--     `cap`, `firstServer`).
--   * `record_match_event` refuses a badminton entry the fold cannot accept,
--     closes the match when the fold reaches the winning game, and refuses a
--     rally after that until it is undone.
--   * `submit_match_result` derives the result: an unfinished match is refused
--     (`match_not_complete`), the games and winner must match the fold
--     (`score_payload_mismatch`), and the per-side strings are written from the
--     fold, never from the caller.
--   * `void_match_event` reopens a completed match when undo makes the fold
--     incomplete again.
--   * `retire_match` is the audited way out of a match that will not finish:
--     the scorer or the organizer names the winner and a reason, and the
--     partial score is taken from the fold.
--   * `generate_tournament_draw` writes a real racket discipline
--     (`singles`/`doubles`) and the capacity that discipline implies instead
--     of copying the entry type and the registration limit.
--
-- Deliberately unchanged: padel's and futsal's branches, cricket's generic
-- door, `correct_match_result`, and the walkover path, which stays
-- organizer-only and unreachable once a result is published.
--
-- Event contract (the official workspace and the Match Center send exactly
-- this): rally  side, {}  — the side that won the rally scores one point and
-- serves next.
--
-- Verified by supabase/tests/badminton_scoring_test.sql, which folds the same
-- literal sequences as test/scoring_test.dart.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  The fold
-- ════════════════════════════════════════════════════════════════════════════
-- Returns the engine's state keys plus `isComplete`, `winnerSide` and
-- `lastSeq`. Side indexes stay 0/1 in the payload; the arrays are 1-based
-- internally because PL/pgSQL arrays are.

create or replace function public._badminton_fold_detail(p_match_id uuid)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_rules        jsonb;
  v_games_to_win int;
  v_to_win       int;
  v_cap          int;
  v_points       int[] := '{0,0}';
  v_games        int[] := '{0,0}';
  v_completed    jsonb := '[]'::jsonb;
  v_done         boolean := false;
  v_winner       int := -1;
  v_server       int;
  v_last_seq     bigint := 0;
  v_ev           record;
  v_s            int;
  v_p            int;
  v_q            int;
begin
  select rules into v_rules from public.matches where id = p_match_id;
  if v_rules is null then
    return '{}'::jsonb;
  end if;

  v_games_to_win := coalesce((v_rules->>'gamesToWin')::int, 2);
  v_to_win       := coalesce((v_rules->>'pointsToWinGame')::int, 21);
  v_cap          := coalesce((v_rules->>'cap')::int, 30);
  v_server       := coalesce((v_rules->>'firstServer')::int, 0);
  if v_server not in (0, 1) then v_server := 0; end if;

  for v_ev in
    select side, seq
      from public.match_events
     where match_id = p_match_id
       and not voided
       and kind = 'rally'
     order by seq
  loop
    exit when v_done;
    v_s := v_ev.side;
    -- A rally without a side is not a point for anybody. The Dart engine skips
    -- the same rows, so a legacy log folds identically on both sides.
    if v_s is null or v_s not in (0, 1) then
      continue;
    end if;
    v_server := v_s;
    v_points[v_s + 1] := v_points[v_s + 1] + 1;
    v_p := v_points[v_s + 1];
    v_q := v_points[2 - v_s];
    if (v_p >= v_to_win and v_p - v_q >= 2) or v_p >= v_cap then
      v_completed := v_completed
        || jsonb_build_array(jsonb_build_array(v_points[1], v_points[2]));
      v_games[v_s + 1] := v_games[v_s + 1] + 1;
      v_points := '{0,0}';
      if v_games[v_s + 1] >= v_games_to_win then
        v_done := true;
        v_winner := v_s;
      end if;
    end if;
    v_last_seq := v_ev.seq;
  end loop;

  return jsonb_build_object(
    'isComplete',     v_done,
    'winnerSide',     v_winner,
    'points',         jsonb_build_array(v_points[1], v_points[2]),
    'gamesWon',       jsonb_build_array(v_games[1], v_games[2]),
    'completedGames', v_completed,
    'game',           jsonb_array_length(v_completed) + 1,
    'server',         v_server,
    'serveCourt',     case
                        when ((case when v_server = 0 then v_points[1]
                                    else v_points[2] end) % 2) = 0
                        then 'right' else 'left' end,
    'toWin',          v_to_win,
    'cap',            v_cap,
    'lastSeq',        v_last_seq
  );
end;
$$;

revoke all on function public._badminton_fold_detail(uuid)
  from public, anon, authenticated;

create or replace function public._badminton_fold(p_match_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select public._badminton_fold_detail(p_match_id) - 'lastSeq';
$$;

revoke all on function public._badminton_fold(uuid)
  from public, anon, authenticated;

-- The one builder of the two display strings every surface prints. Matches
-- MatchProgress.scoreDisplay: completed games from that side's perspective,
-- the game in progress appended while the match is live, '-' when nothing has
-- been scored.
create or replace function public._badminton_derived_scores(p_match_id uuid)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_fold      jsonb := public._badminton_fold(p_match_id);
  v_completed jsonb;
  v_points    jsonb;
  v_done      boolean;
  v_text      text[] := array['', ''];
  v_side      int;
  v_game      jsonb;
  v_part      text;
begin
  v_completed := coalesce(v_fold->'completedGames', '[]'::jsonb);
  v_points    := coalesce(v_fold->'points', '[0,0]'::jsonb);
  v_done      := coalesce((v_fold->>'isComplete')::boolean, false);

  for v_side in 0 .. 1 loop
    for v_game in select jsonb_array_elements(v_completed) loop
      v_part := case when v_side = 0
                     then (v_game->>0) || '-' || (v_game->>1)
                     else (v_game->>1) || '-' || (v_game->>0) end;
      v_text[v_side + 1] := case when v_text[v_side + 1] = '' then v_part
                                 else v_text[v_side + 1] || ', ' || v_part end;
    end loop;
    if not v_done
       and ((v_points->>0)::int > 0 or (v_points->>1)::int > 0) then
      v_part := case when v_side = 0
                     then (v_points->>0) || '-' || (v_points->>1)
                     else (v_points->>1) || '-' || (v_points->>0) end;
      v_text[v_side + 1] := case when v_text[v_side + 1] = '' then v_part
                                 else v_text[v_side + 1] || ', ' || v_part end;
    end if;
    if v_text[v_side + 1] = '' then
      v_text[v_side + 1] := '-';
    end if;
  end loop;

  return to_jsonb(v_text);
end;
$$;

revoke all on function public._badminton_derived_scores(uuid)
  from public, anon, authenticated;

-- One mapping for both racket sports: a tournament entry type is not a match
-- discipline, and `pair` is not a value the matches table accepts.
create or replace function public._racket_discipline(p_entry_type text)
returns text
language sql
immutable
set search_path = public
as $$
  select case coalesce(p_entry_type, '')
           when 'individual' then 'singles'
           when 'pair'       then 'doubles'
           else 'team'
         end;
$$;

revoke all on function public._racket_discipline(text)
  from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  record_match_event gains a badminton branch
-- ════════════════════════════════════════════════════════════════════════════
-- Body is 0021's, with one branch inserted before the generic path. Padel still
-- delegates to _padel_award_point, futsal keeps its fold, and cricket keeps the
-- generic door.

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
  v_uid     uuid := auth.uid();
  v_match   public.matches;
  v_client  text := trim(coalesce(p_client_event_id, ''));
  v_kind    text := trim(coalesce(p_kind, ''));
  v_data    jsonb := coalesce(p_data, '{}'::jsonb);
  v_side    smallint := p_side;
  v_seq     bigint;
  v_row     public.match_events;
  v_state   jsonb;
  v_refusal text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
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

  if v_match.sport_key = 'padel' then
    if v_kind <> 'point' then
      raise exception 'invalid_event_kind' using errcode = '22023';
    end if;
    return public._padel_award_point(p_match_id, v_side, v_client);
  end if;

  if v_match.sport_key = 'futsal' then
    if not public.can_score_match(p_match_id, v_uid) then
      raise exception 'not_match_scorer' using errcode = '42501';
    end if;
    if v_match.status <> 'live' then
      raise exception 'invalid_match_transition' using errcode = '22023';
    end if;
    if v_match.completed_at is not null then
      raise exception 'match_complete' using errcode = '22023';
    end if;
    -- A lifecycle pause freezes the log, but the match must still be endable.
    if v_match.paused_at is not null and v_kind <> 'clock' then
      raise exception 'match_paused' using errcode = '22023';
    end if;

    select * into v_row
      from public.match_events
     where match_id = p_match_id and client_event_id = v_client;
    if v_row.id is not null then
      return v_row;
    end if;

    v_state := public._futsal_fold(p_match_id);
    v_refusal := public._futsal_event_refusal(
      v_state, v_kind, v_side, v_data, p_match_id);
    if v_refusal is not null then
      raise exception '%', v_refusal using errcode = '22023';
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

    v_state := public._futsal_fold(p_match_id);

    if coalesce((v_state->>'isComplete')::boolean, false) then
      update public.matches
         set completed_at = now()
       where id = p_match_id
         and completed_at is null;
      perform public.log_match_action(
        p_match_id, v_uid, 'futsal_auto_complete',
        jsonb_build_object(
          'phase',      v_state->>'phase',
          'goals',      public._futsal_fold_detail(p_match_id)->'goals',
          'winnerSide', v_state->>'winnerSide',
          'seq',        v_seq
        )
      );
    end if;

    return v_row;
  end if;

  if v_match.sport_key = 'badminton' then
    if not public.can_score_match(p_match_id, v_uid) then
      raise exception 'not_match_scorer' using errcode = '42501';
    end if;
    if v_match.status <> 'live' then
      raise exception 'invalid_match_transition' using errcode = '22023';
    end if;
    if v_match.completed_at is not null then
      raise exception 'match_complete' using errcode = '22023';
    end if;
    if v_match.paused_at is not null then
      raise exception 'match_paused' using errcode = '22023';
    end if;
    if v_kind <> 'rally' then
      raise exception 'invalid_event_kind' using errcode = '22023';
    end if;
    if v_side is null or v_side not in (0, 1) then
      raise exception 'invalid_rally_side' using errcode = '22023';
    end if;

    select * into v_row
      from public.match_events
     where match_id = p_match_id and client_event_id = v_client;
    if v_row.id is not null then
      return v_row;
    end if;

    v_state := public._badminton_fold(p_match_id);
    if coalesce((v_state->>'isComplete')::boolean, false) then
      raise exception 'match_complete' using errcode = '22023';
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

    v_state := public._badminton_fold(p_match_id);

    if coalesce((v_state->>'isComplete')::boolean, false) then
      update public.matches
         set completed_at = now()
       where id = p_match_id
         and completed_at is null;
      perform public.log_match_action(
        p_match_id, v_uid, 'badminton_complete',
        jsonb_build_object(
          'game',           v_state->>'game',
          'games',          v_state->'gamesWon',
          'completedGames', v_state->'completedGames',
          'winnerSide',     v_state->>'winnerSide',
          'seq',            v_seq
        )
      );
    end if;

    return v_row;
  end if;

  if v_uid <> v_match.organizer_id
     and (v_match.scorer_id is null or v_uid <> v_match.scorer_id) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if v_match.paused_at is not null then
    raise exception 'match_paused' using errcode = '22023';
  end if;

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

revoke all on function public.record_match_event(uuid, text, text, int, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_match_event(uuid, text, text, int, jsonb)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  Undo reopens a completed badminton match
-- ════════════════════════════════════════════════════════════════════════════
-- Body is 0021's, with badminton beside futsal: the entry that completed the
-- match is the one a scorer most often wants back, and withdrawing it must make
-- the log scorable again.

create or replace function public.void_match_event(
  p_match_id uuid,
  p_event_id uuid,
  p_reason   text default null
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

  if v_match.sport_key = 'futsal' then
    if not public.can_score_match(p_match_id, v_uid) then
      raise exception 'not_match_scorer' using errcode = '42501';
    end if;
  elsif v_uid <> v_match.organizer_id
     and (v_match.scorer_id is null or v_uid <> v_match.scorer_id) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if v_match.submitted_at is not null then
    raise exception 'result_already_submitted' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) not between 3 and 200 then
    raise exception 'invalid_void_reason' using errcode = '22023';
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
     set voided      = true,
         voided_by   = v_uid,
         void_reason = coalesce(v_reason, 'Undo last entry')
   where id = p_event_id
  returning * into v_row;

  if v_match.sport_key = 'futsal' and v_match.completed_at is not null then
    v_fold := public._futsal_fold(p_match_id);
    if not coalesce((v_fold->>'isComplete')::boolean, false) then
      update public.matches
         set completed_at = null
       where id = p_match_id;
      perform public.log_match_action(
        p_match_id, v_uid, 'match_reopened',
        jsonb_build_object('phase', v_fold->>'phase', 'seq', v_row.seq)
      );
    end if;
  end if;

  if v_match.sport_key = 'badminton' and v_match.completed_at is not null then
    v_fold := public._badminton_fold(p_match_id);
    if not coalesce((v_fold->>'isComplete')::boolean, false) then
      update public.matches
         set completed_at = null
       where id = p_match_id;
      perform public.log_match_action(
        p_match_id, v_uid, 'match_reopened',
        jsonb_build_object(
          'games',  v_fold->'gamesWon',
          'points', v_fold->'points',
          'seq',    v_row.seq
        )
      );
    end if;
  end if;

  perform public.log_match_action(
    p_match_id, v_uid, 'event_undone',
    jsonb_build_object('seq', v_row.seq, 'kind', v_row.kind, 'reason', v_reason)
  );

  return v_row;
end;
$$;

revoke all on function public.void_match_event(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.void_match_event(uuid, uuid, text)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 4.  submit_match_result derives the badminton result
-- ════════════════════════════════════════════════════════════════════════════
-- Body is 0021's, with a badminton branch beside padel and futsal.

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
  v_uid     uuid := auth.uid();
  v_match   public.matches;
  v_row     public.match_results;
  v_fold    jsonb;
  v_derived jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_uid <> v_match.organizer_id
     and (v_match.scorer_id is null or v_uid <> v_match.scorer_id)
     and not (v_match.sport_key in ('padel', 'futsal', 'badminton')
              and public.can_score_match(p_match_id, v_uid)) then
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

  if v_match.sport_key = 'padel' then
    v_fold := public._padel_fold(p_match_id);
    if not coalesce((v_fold->>'isComplete')::boolean, false) then
      raise exception 'match_not_complete' using errcode = '22023';
    end if;
    v_derived := v_fold->'setsWon';
    if p_side_values is distinct from v_derived
       or p_winner_index is distinct from coalesce((v_fold->>'winnerSide')::int, -1) then
      raise exception 'score_payload_mismatch' using errcode = '22023';
    end if;
    p_side_scores := public._padel_derived_scores(p_match_id);
  end if;

  if v_match.sport_key = 'futsal' then
    v_fold := public._futsal_fold(p_match_id);
    if not coalesce((v_fold->>'isComplete')::boolean, false)
       or v_match.completed_at is null then
      raise exception 'match_not_complete' using errcode = '22023';
    end if;
    v_derived := public._futsal_fold_detail(p_match_id)->'goals';
    if p_side_values is distinct from v_derived
       or p_winner_index is distinct from coalesce((v_fold->>'winnerSide')::int, -1) then
      raise exception 'score_payload_mismatch' using errcode = '22023';
    end if;
    -- Whatever arrived is replaced by what the fold says.
    p_side_scores := public._futsal_derived_scores(p_match_id);
  end if;

  if v_match.sport_key = 'badminton' then
    v_fold := public._badminton_fold(p_match_id);
    if not coalesce((v_fold->>'isComplete')::boolean, false)
       or v_match.completed_at is null then
      raise exception 'match_not_complete' using errcode = '22023';
    end if;
    v_derived := v_fold->'gamesWon';
    if p_side_values is distinct from v_derived
       or p_winner_index is distinct from coalesce((v_fold->>'winnerSide')::int, -1) then
      raise exception 'score_payload_mismatch' using errcode = '22023';
    end if;
    p_side_scores := public._badminton_derived_scores(p_match_id);
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
         submitted_at = now(),
         completed_at = coalesce(completed_at, now())
   where id = p_match_id;

  if v_match.sport_key = 'padel' then
    perform public._padel_rebuild_state(p_match_id);
  end if;

  perform public.log_match_action(
    p_match_id, v_uid, 'result_submitted',
    jsonb_build_object(
      'headline', coalesce(p_headline, ''),
      'derived',  v_match.sport_key in ('padel', 'futsal', 'badminton')
    )
  );

  return v_row;
end;
$$;

revoke all on function public.submit_match_result(uuid, text, text, jsonb, jsonb, int)
  from public, anon, authenticated;
grant execute on function public.submit_match_result(uuid, text, text, jsonb, jsonb, int)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  Retire / concede
-- ════════════════════════════════════════════════════════════════════════════
-- A match that will not reach the winning game still needs a decision: a walk
-- off, an injury, a player who has to leave. The organizer's walkover cannot
-- cover it — it starts from any status and carries no score — so this is the
-- scorer's door. The partial score comes from the fold, never from the caller,
-- and the result is written with the existing `walkover` terminal status so the
-- bracket and the review queue keep working without a new state.

create or replace function public.retire_match(
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
  v_uid        uuid := auth.uid();
  v_match      public.matches;
  v_reason     text := trim(coalesce(p_reason, ''));
  v_fold       jsonb;
  v_scores     jsonb;
  v_values     jsonb;
  v_headline   text;
  v_detail     text;
  v_partial    text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_match.sport_key <> 'badminton' then
    raise exception 'wrong_sport' using errcode = '22023';
  end if;
  if v_match.organizer_id <> v_uid
     and not public.can_score_match(p_match_id, v_uid) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if v_match.completed_at is not null then
    raise exception 'match_complete' using errcode = '22023';
  end if;
  if p_winner_index is null or p_winner_index not in (0, 1) then
    raise exception 'invalid_result_payload' using errcode = '22023';
  end if;
  if char_length(v_reason) not between 3 and 200 then
    raise exception 'invalid_retire_reason' using errcode = '22023';
  end if;

  v_fold   := public._badminton_fold(p_match_id);
  v_values := coalesce(v_fold->'gamesWon', '[0,0]'::jsonb);
  v_scores := public._badminton_derived_scores(p_match_id);
  v_partial := case
                 when (v_scores->>0) = '-' then 'no game completed'
                 else (v_scores->>0) || ' / ' || (v_scores->>1)
               end;
  v_headline := (case when p_winner_index = 0
                      then v_match.side_a_name else v_match.side_b_name end)
                || ' won by retirement';
  v_detail := 'Retired at ' || v_partial || ' · ' || v_reason;

  insert into public.match_results as mr
    (match_id, side_scores, side_values, winner_index, headline, detail,
     walkover, published_by)
  values
    (p_match_id, v_scores, v_values, p_winner_index, v_headline, v_detail,
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
         submitted_at = coalesce(submitted_at, now()),
         completed_at = now()
   where id = p_match_id
  returning * into v_match;

  perform public.log_match_action(
    p_match_id, v_uid, 'retire',
    jsonb_build_object(
      'winner_index', p_winner_index,
      'reason',       v_reason,
      'scores',       v_scores,
      'games',        v_values
    )
  );

  return v_match;
end;
$$;

revoke all on function public.retire_match(uuid, int, text)
  from public, anon, authenticated;
grant execute on function public.retire_match(uuid, int, text)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 6.  The draw writes a real discipline and capacity
-- ════════════════════════════════════════════════════════════════════════════
-- Body is 0022's. A badminton tournament registers `individual` or `pair`
-- entries, neither of which is a matches.discipline, and `registration_limit`
-- is how many entries may register, not how many players sit on one side. Both
-- made every generated badminton fixture read as a doubles match with room for
-- the whole field. Padel keeps its existing shape.

create or replace function public.generate_tournament_draw(p_tournament_id text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_t          public.tournaments;
  v_ids        text[] := '{}'::text[];
  v_names      text[] := '{}'::text[];
  v_created    int := 0;
  v_i          int;
  v_j          int;
  v_round      int;
  v_stage      text;
  v_fixture    text;
  v_match      uuid;
  v_capacity   int;
  v_discipline text;
  v_min_squad  int;
  v_max_squad  int;
  v_members_a  uuid[];
  v_members_b  uuid[];
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

  v_discipline := case when v_t.sport_key = 'padel' then 'doubles' else 'team' end;

  if v_t.sport_key = 'futsal' then
    -- A fixture whose sides cannot field five players is not a match.
    if v_min_squad < 5 or v_max_squad * 2 < 10 then
      raise exception 'draw_needs_full_squads' using errcode = '22023';
    end if;
    v_capacity := greatest(v_max_squad * 2, 10);
  elsif v_t.sport_key = 'badminton' then
    v_discipline := public._racket_discipline(v_t.entry_type);
    v_capacity := case v_discipline when 'singles' then 2 else 4 end;
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
          v_t.sport_key, v_t.format_label,
          v_t.rules || jsonb_build_object('discipline', v_discipline),
          format('%s · %s vs %s', v_t.name, v_names[v_i], v_names[v_j]),
          v_t.venue, v_t.starts_at + (v_created * interval '2 hours'), 'public',
          v_uid, null, left(v_names[v_i], 40), left(v_names[v_j], 40),
          v_discipline,
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
        v_t.sport_key, v_t.format_label,
        v_t.rules || jsonb_build_object('discipline', v_discipline),
        format('%s · %s vs %s', v_t.name, v_names[v_i * 2 - 1], v_names[v_i * 2]),
        v_t.venue, v_t.starts_at + ((v_i - 1) * interval '2 hours'), 'public',
        v_uid, null, left(v_names[v_i * 2 - 1], 40), left(v_names[v_i * 2], 40),
        v_discipline,
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
-- 7.  Integrity backstops
-- ════════════════════════════════════════════════════════════════════════════
-- A badminton side is one player or two, so the only workable participant
-- totals are 2 and 4, and the discipline must be one the engine scores.

do $$
begin
  alter table public.matches
    add constraint matches_badminton_capacity
    check (sport_key <> 'badminton' or capacity in (2, 4));
exception
  when duplicate_object then null;
end;
$$;

do $$
begin
  alter table public.matches
    add constraint matches_badminton_discipline
    check (sport_key <> 'badminton'
           or discipline in ('singles', 'doubles'));
exception
  when duplicate_object then null;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 8.  Repair the one badminton result the generic door published
-- ════════════════════════════════════════════════════════════════════════════
-- Nine rallies that never finished a game were published with no winner. A
-- badminton result now only exists when the fold produces one, so this row is
-- withdrawn and the match returns to live for its scorer to finish. Exact-id
-- and payload guarded: a second run changes nothing, and a re-scored match is
-- never touched.

delete from public.match_results
 where match_id = 'ddbdd9ca-516a-49ba-b3b6-6d17f8e84981'
   and winner_index = -1;

update public.matches
   set status       = 'live',
       submitted_at = null,
       completed_at = null
 where id = 'ddbdd9ca-516a-49ba-b3b6-6d17f8e84981'
   and sport_key = 'badminton'
   and status = 'published'
   and not exists (
     select 1 from public.match_results r where r.match_id = matches.id
   );

commit;
