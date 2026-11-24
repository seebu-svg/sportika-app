-- Sportika futsal result authority: the log decides, not the device.
--
-- 0013 made padel server-authoritative and left the generic door open for
-- cricket, futsal and badminton "whose results the app still folds" (0020's
-- header). For futsal that meant any `kind` was accepted with any payload, no
-- fold existed on the server, `submit_match_result` stored whatever two strings
-- the caller sent, and an unfinished match could be submitted as if it were
-- full time. `void_match_event` also stopped clearing `completed_at` in the
-- 0013 rewrite, so undoing the `end_match` entry left a match permanently
-- unscorable.
--
-- This migration gives futsal the same shape padel has, without inventing a
-- second rule book:
--
--   * `_futsal_fold_detail(uuid)` is the SQL mirror of FutsalEngine: clock
--     phases, half and extra-time transitions, goals by half, and the
--     best-of-five / sudden-death shootout. Clock elapsed is measured from
--     `recorded_at`, exactly the timestamps the Dart engine folds, so both
--     readers agree.
--   * `_futsal_event_refusal(...)` is the SQL twin of the futsal branch of
--     MatchScoringValidator: one function, called by record_match_event, that
--     answers "may this entry exist in this state?".
--   * record_match_event refuses a futsal entry the fold cannot accept, closes
--     the match when the fold reaches full time, and refuses anything after
--     that until it is undone.
--   * submit_match_result derives the futsal result: incomplete matches are
--     refused (`match_not_complete`), totals and winner must match the fold
--     (`score_payload_mismatch`), and the per-side display strings are written
--     from the fold, never from the caller.
--
-- Deliberately unchanged:
--   * `headline`/`detail` stay the caller's text (0020's stated scope);
--   * padel's branch, and the cricket/badminton generic path, keep their
--     behaviour;
--   * `correct_match_result` keeps the organizer's manual authority, which is
--     what a walkover needs;
--   * no `futsal_match_state` projection table: nothing in the app would read
--     it, realtime already syncs `match_events`, and the fold is recomputed at
--     submit. A durable second copy of a derivable score is one more thing that
--     can drift.
--
-- Event contract (the official workspace sends exactly these):
--   goal         side, {half, goalType: regular|penalty|ownGoal, player?, playerId?}
--   clock        null, {action: start|stop|resume|end_half|end_match}
--   penalty      side, {scored}                       (shootout only)
--   card         side, {colour: yellow|red, half, player?, playerId?}
--   foul         side, {half}
--   substitution side, {inId, outId, half}
--   lineup       side, {players: [profileId x5]}      (before kick-off only)
--
-- Capacity note: a futsal match is five a side, so `capacity` (the total
-- accepted participant slots) must be at least 10; the per-side cap used by
-- join_match in 0022 is capacity / 2.
--
-- Verified by supabase/tests/futsal_scoring_test.sql and, for fold parity, by
-- test/futsal_authority_test.dart, which fold the same literal sequences.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  The fold
-- ════════════════════════════════════════════════════════════════════════════
-- Returns { lastSeq, goals, byHalf, state }. `state` carries the same keys the
-- Dart engine puts in MatchProgress.state, so a screen can fold either side and
-- read the same phase, half and clock.

create or replace function public._futsal_fold_detail(p_match_id uuid)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  -- rules
  v_rules        jsonb;
  v_half_minutes int;
  v_halves       int;
  v_winner_req   boolean;
  v_shootout_ok  boolean;
  v_extra_time   boolean;
  v_extra_min    int;
  v_total        int;
  -- state (side indexes are 1-based internally: [1] = A, [2] = B)
  v_phase        text := 'pre';
  v_half_index   int  := 0;
  v_regulation   int  := 2;
  v_elapsed      int[];
  v_h_a          int[];
  v_h_b          int[];
  v_resume_at    timestamptz;
  v_goals        int[] := '{0,0}';
  v_shoot        int[] := '{0,0}';
  v_taken        int[] := '{0,0}';
  v_winner       int  := -1;
  v_reason       text := '';
  v_last_seq     bigint := 0;
  -- loop
  v_ev           record;
  v_s            int;
  v_h            int;
  v_action       text;
  v_end_reg      boolean;
  v_decide       boolean;
  v_i            int;
begin
  select rules into v_rules from public.matches where id = p_match_id;
  if v_rules is null then
    return '{}'::jsonb;
  end if;

  v_half_minutes := coalesce((v_rules->>'halfMinutes')::int, 20);
  v_halves       := coalesce((v_rules->>'halves')::int, 2);
  v_winner_req   := coalesce((v_rules->>'winnerRequired')::boolean, false);
  v_shootout_ok  := coalesce((v_rules->>'shootout')::boolean, false);
  v_extra_time   := coalesce((v_rules->>'extraTime')::boolean, false);
  v_extra_min    := coalesce((v_rules->>'extraHalfMinutes')::int, 5);

  -- The engine clamps a nonsensical period count to at least one.
  if v_halves < 1 then v_halves := 1; end if;
  v_regulation := v_halves;
  v_total      := v_halves + (case when v_extra_time then 2 else 0 end);

  v_elapsed := array_fill(0, array[v_total]);
  v_h_a     := array_fill(0, array[v_total]);
  v_h_b     := array_fill(0, array[v_total]);

  for v_ev in
    select seq, kind, side, data, recorded_at
      from public.match_events
     where match_id = p_match_id
       and not voided
     order by seq
  loop
    v_last_seq := v_ev.seq;
    v_end_reg  := false;
    v_decide   := false;

    if v_ev.kind = 'goal' then
      if v_phase in ('shootout', 'complete') then continue; end if;
      v_s := coalesce(v_ev.side, 0);
      v_h := coalesce((v_ev.data->>'half')::int, v_half_index);
      if v_s not in (0, 1) or v_h < 0 or v_h >= v_total then continue; end if;
      v_goals[v_s + 1] := v_goals[v_s + 1] + 1;
      if v_s = 0 then
        v_h_a[v_h + 1] := v_h_a[v_h + 1] + 1;
      else
        v_h_b[v_h + 1] := v_h_b[v_h + 1] + 1;
      end if;

    elsif v_ev.kind = 'penalty' then
      if v_phase <> 'shootout' then continue; end if;
      v_s := coalesce(v_ev.side, 0);
      if v_s not in (0, 1) then continue; end if;
      v_taken[v_s + 1] := v_taken[v_s + 1] + 1;
      if coalesce((v_ev.data->>'scored')::boolean, false) then
        v_shoot[v_s + 1] := v_shoot[v_s + 1] + 1;
      end if;

      -- Best of five, decided early when the remaining kicks cannot catch up.
      if v_taken[1] <= 5 and v_taken[2] <= 5 then
        if v_shoot[1] > v_shoot[2] + (5 - v_taken[2]) then
          v_phase := 'complete'; v_winner := 0; v_reason := 'Won on penalties';
        elsif v_shoot[2] > v_shoot[1] + (5 - v_taken[1]) then
          v_phase := 'complete'; v_winner := 1; v_reason := 'Won on penalties';
        end if;
      end if;
      if v_phase <> 'complete'
         and v_taken[1] = v_taken[2]
         and v_taken[1] >= 5
         and v_shoot[1] <> v_shoot[2] then
        v_phase := 'complete';
        v_winner := case when v_shoot[1] > v_shoot[2] then 0 else 1 end;
        v_reason := 'Won on penalties';
      end if;

    elsif v_ev.kind = 'clock' then
      v_action := v_ev.data->>'action';

      if v_action = 'start' then
        v_phase := 'running';
        v_half_index := 0;
        v_resume_at := v_ev.recorded_at;

      elsif v_action = 'resume' then
        if v_phase in ('paused', 'halfTime') then
          if v_phase = 'halfTime' then
            v_half_index := least(v_half_index + 1, v_total - 1);
          end if;
          v_phase := 'running';
          v_resume_at := v_ev.recorded_at;
        end if;

      elsif v_action = 'stop' then
        if v_resume_at is not null then
          v_elapsed[v_half_index + 1] := v_elapsed[v_half_index + 1]
            + least(greatest(
                trunc(extract(epoch from (v_ev.recorded_at - v_resume_at)))::int,
                0), 86400);
          v_resume_at := null;
        end if;
        v_phase := 'paused';

      elsif v_action = 'end_half' then
        if v_phase = 'running' and v_resume_at is not null then
          v_elapsed[v_half_index + 1] := v_elapsed[v_half_index + 1]
            + least(greatest(
                trunc(extract(epoch from (v_ev.recorded_at - v_resume_at)))::int,
                0), 86400);
          v_resume_at := null;
        end if;
        -- The Dart engine's first branch here (halfTime and every regulation
        -- half already played) ended a two-half match at half time; it is dead
        -- in the official validator and dropped on both sides.
        if v_half_index = v_regulation - 1
           and (v_goals[1] <> v_goals[2] or not v_winner_req) then
          v_end_reg := true;
        elsif v_half_index < v_total - 1 then
          v_phase := 'halfTime';
        else
          v_end_reg := true;
        end if;

      elsif v_action = 'end_match' then
        if v_phase = 'running' and v_resume_at is not null then
          v_elapsed[v_half_index + 1] := v_elapsed[v_half_index + 1]
            + least(greatest(
                trunc(extract(epoch from (v_ev.recorded_at - v_resume_at)))::int,
                0), 86400);
          v_resume_at := null;
        end if;
        v_phase := 'complete';
        v_reason := 'Match ended by scorer/organizer';
        v_decide := true;
      end if;
    end if;

    if v_end_reg then
      if v_goals[1] <> v_goals[2] or not v_winner_req then
        v_phase := 'complete';
        v_reason := 'Regulation complete';
        v_decide := true;
      elsif v_shootout_ok then
        v_phase := 'shootout';
      else
        v_phase := 'complete';
        v_reason := 'Regulation complete';
        v_decide := true;
      end if;
    end if;

    if v_decide then
      if v_taken[1] + v_taken[2] > 0 and v_shoot[1] <> v_shoot[2] then
        v_winner := case when v_shoot[1] > v_shoot[2] then 0 else 1 end;
      elsif v_goals[1] > v_goals[2] then
        v_winner := 0;
      elsif v_goals[2] > v_goals[1] then
        v_winner := 1;
      else
        v_winner := -1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'lastSeq', v_last_seq,
    'goals',   jsonb_build_array(v_goals[1], v_goals[2]),
    'byHalf',  (
      select coalesce(jsonb_agg(jsonb_build_array(v_h_a[i], v_h_b[i]) order by i), '[]'::jsonb)
        from generate_series(1, v_total) i
    ),
    'state', jsonb_build_object(
      'phase',            v_phase,
      'half',             v_half_index + 1,
      'periodElapsed',    v_elapsed[v_half_index + 1],
      'periodMinutes',    case when v_half_index >= v_regulation
                               then v_extra_min else v_half_minutes end,
      'periods',          v_total,
      'regulationHalves', v_regulation,
      'resumeAt',         v_resume_at,
      'running',          v_phase = 'running',
      'elapsed',          (select coalesce(sum(x), 0) from unnest(v_elapsed) x),
      'extraTime',        v_half_index >= v_regulation,
      'shootoutTaken',    jsonb_build_array(v_taken[1], v_taken[2]),
      'shootoutScores',   jsonb_build_array(v_shoot[1], v_shoot[2]),
      'isComplete',       v_phase = 'complete',
      'winnerSide',       v_winner,
      'completionReason', v_reason
    )
  );
end;
$$;

revoke all on function public._futsal_fold_detail(uuid)
  from public, anon, authenticated;

create or replace function public._futsal_fold(p_match_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(public._futsal_fold_detail(p_match_id)->'state', '{}'::jsonb);
$$;

revoke all on function public._futsal_fold(uuid) from public, anon, authenticated;

-- The one builder of the two display strings every surface prints.
create or replace function public._futsal_derived_scores(p_match_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_array(
           (public._futsal_fold_detail(p_match_id)->'goals'->>0)::text,
           (public._futsal_fold_detail(p_match_id)->'goals'->>1)::text
         );
$$;

revoke all on function public._futsal_derived_scores(uuid)
  from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  Is this entry allowed in this state?
-- ════════════════════════════════════════════════════════════════════════════
-- Pure: the folded state and the candidate payload in, a reason out (null when
-- the entry is acceptable). The Dart validator answers the same questions for
-- the scorer's own screen; this is the copy a crafted call cannot skip.

create or replace function public._futsal_event_refusal(
  p_state    jsonb,
  p_kind     text,
  p_side     int,
  p_data     jsonb,
  p_match_id uuid
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_phase  text := coalesce(p_state->>'phase', 'pre');
  v_action text := p_data->>'action';
  v_type   text := coalesce(p_data->>'goalType', 'regular');
  v_colour text := p_data->>'colour';
  v_taken  jsonb := coalesce(p_state->'shootoutTaken', '[0,0]'::jsonb);
  v_next   int;
  v_count  int;
  v_players jsonb;
  v_bad    int;
begin
  if p_kind = 'goal' then
    if p_side is null or p_side not in (0, 1) then
      return 'invalid_event_side';
    end if;
    if v_phase in ('shootout', 'complete') then
      return 'invalid_event_phase';
    end if;
    if v_type not in ('regular', 'penalty', 'ownGoal') then
      return 'invalid_goal_type';
    end if;
    if nullif(p_data->>'playerId', '') is not null then
      -- An own goal is credited to the opposing roster.
      select count(*) into v_bad
        from public.match_participants mp
       where mp.match_id = p_match_id
         and mp.profile_id = (p_data->>'playerId')::uuid
         and mp.status = 'accepted'
         and mp.side = case when v_type = 'ownGoal' then 1 - p_side else p_side end;
      if v_bad = 0 then
        return 'invalid_event_player';
      end if;
    end if;
    return null;
  end if;

  if p_kind = 'clock' then
    if v_action is null
       or v_action not in ('start', 'stop', 'resume', 'end_half', 'end_match') then
      return 'invalid_clock_action';
    end if;
    if v_phase = 'pre' and v_action <> 'start' then
      return 'invalid_clock_action';
    end if;
    if v_phase = 'running' and v_action not in ('stop', 'end_half', 'end_match') then
      return 'invalid_clock_action';
    end if;
    if v_phase = 'paused' and v_action not in ('resume', 'end_half', 'end_match') then
      return 'invalid_clock_action';
    end if;
    if v_phase = 'halfTime' and v_action not in ('resume', 'end_match') then
      return 'invalid_clock_action';
    end if;
    if v_phase in ('shootout', 'complete') then
      return 'invalid_clock_action';
    end if;
    return null;
  end if;

  if p_kind = 'penalty' then
    if p_side is null or p_side not in (0, 1) then
      return 'invalid_event_side';
    end if;
    if v_phase <> 'shootout' then
      return 'invalid_event_phase';
    end if;
    v_next := case when (v_taken->>0)::int <= (v_taken->>1)::int then 0 else 1 end;
    if p_side <> v_next then
      return 'invalid_kick_turn';
    end if;
    return null;
  end if;

  if p_kind in ('card', 'foul', 'substitution') then
    if p_side is null or p_side not in (0, 1) then
      return 'invalid_event_side';
    end if;
    if v_phase not in ('running', 'paused', 'halfTime') then
      return 'invalid_event_phase';
    end if;
    if p_kind = 'card' and (v_colour is null or v_colour not in ('yellow', 'red')) then
      return 'invalid_card_colour';
    end if;
    if p_kind = 'substitution' then
      if nullif(p_data->>'inId', '') is null or nullif(p_data->>'outId', '') is null then
        return 'invalid_substitution';
      end if;
      if p_data->>'inId' = p_data->>'outId' then
        return 'invalid_substitution';
      end if;
      select count(*) into v_bad
        from public.match_participants mp
       where mp.match_id = p_match_id
         and mp.status = 'accepted'
         and mp.side = p_side
         and mp.profile_id in ((p_data->>'inId')::uuid, (p_data->>'outId')::uuid);
      if v_bad <> 2 then
        return 'invalid_substitution';
      end if;
    end if;
    return null;
  end if;

  if p_kind = 'lineup' then
    if p_side is null or p_side not in (0, 1) then
      return 'invalid_event_side';
    end if;
    if v_phase <> 'pre' then
      return 'invalid_event_phase';
    end if;
    v_players := p_data->'players';
    if v_players is null
       or jsonb_typeof(v_players) <> 'array'
       or jsonb_array_length(v_players) <> 5 then
      return 'lineup_incomplete';
    end if;
    select count(distinct x) into v_count
      from jsonb_array_elements_text(v_players) x;
    if v_count <> 5 then
      return 'lineup_incomplete';
    end if;
    select count(*) into v_bad
      from jsonb_array_elements_text(v_players) x
     where not exists (
       select 1
         from public.match_participants mp
        where mp.match_id = p_match_id
          and mp.profile_id = x::uuid
          and mp.status = 'accepted'
          and mp.side = p_side
     );
    if v_bad > 0 then
      return 'lineup_incomplete';
    end if;
    return null;
  end if;

  return 'invalid_event_kind';
end;
$$;

revoke all on function public._futsal_event_refusal(jsonb, text, int, jsonb, uuid)
  from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  record_match_event gains a futsal branch
-- ════════════════════════════════════════════════════════════════════════════
-- Body is 0013's, with one branch inserted before the generic path. Padel still
-- delegates to _padel_award_point; cricket and badminton keep the generic door.

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
-- 4.  Undo reopens a completed futsal match
-- ════════════════════════════════════════════════════════════════════════════
-- 0008 cleared completed_at on undo; 0013's rewrite dropped it for the generic
-- path, so an undone `end_match` left the log closed. This restores the
-- contract for futsal and leaves padel's delegated branch untouched.

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
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_fold   jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  if v_match.sport_key = 'padel' then
    select * into v_row
      from public.match_events
     where id = p_event_id and match_id = p_match_id;
    if v_row.id is null then
      raise exception 'event_not_found' using errcode = 'P0002';
    end if;
    select * into v_row
      from public.match_events
     where match_id = p_match_id and kind = 'point' and not voided
     order by seq desc
     limit 1;
    if v_row.id is null or v_row.id <> p_event_id then
      raise exception 'not_last_event' using errcode = '22023';
    end if;

    perform public.undo_last_padel_point(p_match_id, v_reason);

    select * into v_row from public.match_events where id = p_event_id;
    return v_row;
  end if;

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

  perform public.log_match_action(
    p_match_id, v_uid, 'event_undone',
    jsonb_build_object('seq', v_row.seq, 'kind', v_row.kind, 'reason', v_reason)
  );

  return v_row;
end;
$$;

revoke all on function public.void_match_event(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.void_match_event(uuid, uuid, text) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  submit_match_result derives the futsal result
-- ════════════════════════════════════════════════════════════════════════════
-- Body is 0020's, with a futsal branch beside the padel one: an unfinished match
-- cannot be submitted, the payload must agree with the fold, and the strings
-- every surface prints are built from the fold.

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
     and not (v_match.sport_key = 'padel' and public.can_score_match(p_match_id, v_uid))
     and not (v_match.sport_key = 'futsal' and public.can_score_match(p_match_id, v_uid)) then
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
      'derived',  v_match.sport_key in ('padel', 'futsal')
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
-- 6.  Integrity backstops
-- ════════════════════════════════════════════════════════════════════════════
-- Constraints rather than a create_match rewrite: futsal is always a team game
-- with room for five a side on both benches.

alter table public.matches  drop constraint if exists matches_futsal_team;
alter table public.matches  drop constraint if exists matches_futsal_capacity;
alter table public.tournaments drop constraint if exists tournaments_futsal_team;

alter table public.matches
  add constraint matches_futsal_team
  check (sport_key <> 'futsal' or discipline = 'team') not valid;

alter table public.matches
  add constraint matches_futsal_capacity
  check (sport_key <> 'futsal' or capacity >= 10) not valid;

alter table public.tournaments
  add constraint tournaments_futsal_team
  check (sport_key <> 'futsal' or entry_type = 'team') not valid;

alter table public.matches  validate constraint matches_futsal_team;
alter table public.matches  validate constraint matches_futsal_capacity;
alter table public.tournaments validate constraint tournaments_futsal_team;

commit;
