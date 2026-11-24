-- Sportika cricket result authority: the delivery log decides, not the device.
--
-- Padel (0008/0013/0020), futsal (0021) and badminton (0024) each own a fold, a
-- refusal helper and a submit branch. Cricket was left on "the generic door":
-- record_match_event accepted any kind with any payload for a cricket match,
-- submit_match_result stored whatever two strings, totals and winner the caller
-- sent, and nothing stopped a live client publishing an arbitrary score.
--
-- The shared fold (lib/features/personal_games/scoring/cricket/cricket.dart)
-- also carries one confirmed correctness bug this migration fixes on the server:
-- the "won by N wickets" margin was computed from the FIRST innings' wicket cap
-- (`first.maxWickets - second.wickets`) instead of the chasing side's own cap
-- (`second.maxWickets - second.wickets`), so the margin is wrong whenever the
-- two innings have different named-XI wicket caps. It is invisible while both
-- sides share a cap, which is why no existing test caught it.
--
-- This migration gives cricket the same shape the other three sports have,
-- without inventing a second rule book:
--
--   * `_cricket_fold_detail(uuid)` is the SQL mirror of CricketEngine.evaluate:
--     lineup-seeded wicket caps, the toss, innings open/close (explicit, on the
--     over limit, all out, target passed, or a batting side switching without a
--     close), the extras ledger (wide/no-ball penalty vs bye/leg-bye legal
--     deliveries), wickets, per-side run totals and the winner. It reads the
--     same `rules` keys the engine reads (`oversPerInnings`, `wicketsPerInnings`,
--     `innings`). Its `winnerSide`, `scoreValues` and `scoreDisplay` agree with
--     the engine for every legal log so a genuine submit is never refused; its
--     `resultLabel`/`headline` carry the CORRECTED wicket margin.
--   * `_cricket_event_refusal(...)` is the SQL twin of the cricket branch of
--     MatchScoringValidator: one function, called by record_match_event, that
--     answers "may this entry exist in this state?". It also closes the audit's
--     innings-end gap: the client validator returned no check for `innings_end`,
--     so the server now refuses one when no innings is open (the workspace only
--     ever offers that action while one is, so no genuine scorer is affected).
--   * `record_match_event` refuses a cricket entry the fold cannot accept,
--     closes the match when the fold finishes (both innings closed, or an
--     explicit end), and refuses anything after that until it is undone.
--   * `void_match_event` reopens a completed cricket match when undo makes the
--     fold incomplete again.
--   * `submit_match_result` derives the cricket result: an unfinished log is
--     refused (`match_not_complete`), the run totals and winner must match the
--     fold (`score_payload_mismatch`), and the per-side score strings AND the
--     headline are written from the fold, never from the caller — which is where
--     the wicket-margin fix lands on the official record.
--
-- Deliberately unchanged: padel's, futsal's and badminton's branches,
-- `correct_match_result` (the organizer's manual authority), and the walkover
-- path. `headline`/`detail` stay caller text for the other sports; only cricket
-- derives its headline, because that is the one field the engine bug touched.
--
-- Event contract (the official workspace sends exactly these):
--   toss           side, {decision: bat|bowl}         (before the first ball)
--   lineup         side, {players: [profileId x2..11]} (before the first ball)
--   innings_start  side, {}                           (side must bat next)
--   ball           side, {runs 0..6, extra?, wicket?, dismissal?, striker?,
--                         nonStriker?, bowler?, dismissedBatter?}
--   innings_end    side, {reason?}                    (only while an innings is open)
--   match_end      null, {reason?}                    (abandonment / early end)
--
-- Verified by supabase/tests/cricket_scoring_test.sql and, for fold parity, by
-- test/cricket_authority_test.dart, which fold the same literal sequences.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  The fold
-- ════════════════════════════════════════════════════════════════════════════
-- Returns the aggregate the server needs to score a cricket match, plus a
-- `state` object whose keys match CricketEngine's MatchProgress.state so a
-- screen can fold either side and read the same innings, batting side, open
-- flag and target. Side indexes stay 0/1 in payloads; the arrays are 1-based
-- internally because PL/pgSQL arrays are.

create or replace function public._cricket_fold_detail(p_match_id uuid)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_rules      jsonb;
  v_sides      text[];
  -- rules
  v_overs      int;
  v_maxw       int;
  v_maxin      int;
  v_ball_limit int;
  -- lineup-seeded wicket caps (index 1 = side 0, 2 = side 1)
  v_size       int[] := '{0,0}';
  -- innings accumulator, up to 2 innings (cricket is always one or two)
  v_ni         int  := 0;
  v_i_side     int[] := '{-1,-1}';
  v_i_maxw     int[] := '{0,0}';
  v_i_runs     int[] := '{0,0}';
  v_i_wick     int[] := '{0,0}';
  v_i_legal    int[] := '{0,0}';
  v_i_closed   boolean[] := '{false,false}';
  v_i_reason   text[] := array[''::text, ''::text];
  v_hasball    boolean[] := '{false,false}';
  -- lifecycle
  v_firstbat   int  := null;
  v_toss_win   int  := null;
  v_toss_dec   text := null;
  v_ended      boolean := false;
  -- loop cursors
  v_ev         record;
  v_side       int;
  v_cur        int;
  v_runs       int;
  v_extra      text;
  v_wicket     boolean;
  v_target     int;
  -- derived
  v_finished   boolean;
  v_current    int := null;
  v_batside    int;
  v_next       int;
  v_win        int := -1;
  v_result     text := '';
  v_disp       text[] := array['-'::text, '-'::text];
  v_batted     boolean[] := '{false,false}';
  v_inn        int;
  v_arr        jsonb := '[]'::jsonb;
  v_state      jsonb;
  i            int;
begin
  select rules, array[side_a_name, side_b_name]
    into v_rules, v_sides
    from public.matches
   where id = p_match_id;
  if v_rules is null then
    return '{}'::jsonb;
  end if;

  v_overs      := coalesce((v_rules->>'oversPerInnings')::int, 10);
  v_maxw       := coalesce((v_rules->>'wicketsPerInnings')::int, 10);
  v_maxin      := coalesce((v_rules->>'innings')::int, 2);
  v_ball_limit := v_overs * 6;

  for v_ev in
    select kind, side, data
      from public.match_events
     where match_id = p_match_id
       and not voided
     order by seq
  loop
    if v_ended then
      exit;
    end if;

    if v_ev.kind = 'lineup' then
      v_side := v_ev.side;
      if v_side in (0, 1) then
        if jsonb_typeof(v_ev.data->'players') = 'array'
           and jsonb_array_length(v_ev.data->'players') >= 2 then
          v_size[v_side + 1] := jsonb_array_length(v_ev.data->'players');
        end if;
      end if;

    elsif v_ev.kind = 'toss' then
      v_side := v_ev.side;
      if v_side in (0, 1) and v_firstbat is null and v_ni = 0 then
        v_toss_win := v_side;
        v_toss_dec := case when v_ev.data->>'decision' = 'bowl'
                           then 'bowl' else 'bat' end;
        v_firstbat := case when v_ev.data->>'decision' = 'bowl'
                          then 1 - v_side else v_side end;
      end if;

    elsif v_ev.kind = 'innings_start' then
      v_side := v_ev.side;
      if v_side in (0, 1)
         and v_ni < v_maxin
         and (v_ni = 0 or v_i_closed[v_ni])
         and not (v_ni >= 1 and v_i_side[1] = v_side)
         and not (v_ni >= 2 and v_i_side[2] = v_side) then
        v_ni := v_ni + 1;
        v_i_side[v_ni]   := v_side;
        v_i_maxw[v_ni]   := case when v_size[v_side + 1] < 2 then v_maxw
                                 else least(v_size[v_side + 1] - 1, v_maxw) end;
        v_i_runs[v_ni]   := 0;
        v_i_wick[v_ni]   := 0;
        v_i_legal[v_ni]  := 0;
        v_i_closed[v_ni] := false;
        v_i_reason[v_ni] := '';
        v_hasball[v_ni]  := false;
      end if;

    elsif v_ev.kind = 'match_end' then
      if v_ni >= 1 and not v_i_closed[v_ni] then
        v_i_closed[v_ni] := true;
        v_i_reason[v_ni] := coalesce(
          nullif(trim(coalesce(v_ev.data->>'reason', '')), ''), 'Match ended');
      end if;
      v_ended := true;

    elsif v_ev.kind = 'innings_end' then
      if v_ni >= 1 and not v_i_closed[v_ni] then
        v_i_closed[v_ni] := true;
        v_i_reason[v_ni] := coalesce(
          nullif(v_ev.data->>'reason', ''), 'Innings closed');
      end if;

    elsif v_ev.kind = 'ball' then
      v_side := coalesce(v_ev.side, 0);

      if v_ni = 0 then
        v_ni := 1;
        v_i_side[1]   := v_side;
        v_i_maxw[1]   := case when v_size[v_side + 1] < 2 then v_maxw
                              else least(v_size[v_side + 1] - 1, v_maxw) end;
        v_i_runs[1]   := 0;
        v_i_wick[1]   := 0;
        v_i_legal[1]  := 0;
        v_i_closed[1] := false;
        v_i_reason[1] := '';
        v_hasball[1]  := false;
      elsif v_i_closed[v_ni] then
        if v_ni < v_maxin then
          v_ni := v_ni + 1;
          v_i_side[v_ni]   := v_side;
          v_i_maxw[v_ni]   := case when v_size[v_side + 1] < 2 then v_maxw
                                   else least(v_size[v_side + 1] - 1, v_maxw) end;
          v_i_runs[v_ni]   := 0;
          v_i_wick[v_ni]   := 0;
          v_i_legal[v_ni]  := 0;
          v_i_closed[v_ni] := false;
          v_i_reason[v_ni] := '';
          v_hasball[v_ni]  := false;
        else
          continue;
        end if;
      elsif v_i_side[v_ni] <> v_side and v_hasball[v_ni] then
        v_i_closed[v_ni] := true;
        v_i_reason[v_ni] := 'Innings ended';
        if v_ni < v_maxin then
          v_ni := v_ni + 1;
          v_i_side[v_ni]   := v_side;
          v_i_maxw[v_ni]   := case when v_size[v_side + 1] < 2 then v_maxw
                                   else least(v_size[v_side + 1] - 1, v_maxw) end;
          v_i_runs[v_ni]   := 0;
          v_i_wick[v_ni]   := 0;
          v_i_legal[v_ni]  := 0;
          v_i_closed[v_ni] := false;
          v_i_reason[v_ni] := '';
          v_hasball[v_ni]  := false;
        else
          continue;
        end if;
      end if;

      v_cur    := v_ni;
      v_i_side[v_cur] := v_side;
      v_runs   := coalesce((v_ev.data->>'runs')::int, 0);
      v_extra  := v_ev.data->>'extra';
      v_wicket := coalesce((v_ev.data->>'wicket')::boolean, false);
      v_hasball[v_cur] := true;

      if v_extra = 'wide' then
        v_i_runs[v_cur]  := v_i_runs[v_cur] + 1 + v_runs;
      elsif v_extra = 'noball' then
        v_i_runs[v_cur]  := v_i_runs[v_cur] + 1 + v_runs;
      elsif v_extra = 'bye' then
        v_i_runs[v_cur]  := v_i_runs[v_cur] + v_runs;
        v_i_legal[v_cur] := v_i_legal[v_cur] + 1;
      elsif v_extra = 'legbye' then
        v_i_runs[v_cur]  := v_i_runs[v_cur] + v_runs;
        v_i_legal[v_cur] := v_i_legal[v_cur] + 1;
      else
        v_i_runs[v_cur]  := v_i_runs[v_cur] + v_runs;
        v_i_legal[v_cur] := v_i_legal[v_cur] + 1;
      end if;

      if v_wicket then
        v_i_wick[v_cur] := v_i_wick[v_cur] + 1;
      end if;

      v_target := case when v_ni = 2 then v_i_runs[1] + 1 else null end;
      if not v_i_closed[v_cur] then
        if v_i_legal[v_cur] >= v_ball_limit then
          v_i_closed[v_cur] := true; v_i_reason[v_cur] := 'Overs complete';
        elsif v_i_wick[v_cur] >= v_i_maxw[v_cur] then
          v_i_closed[v_cur] := true; v_i_reason[v_cur] := 'All out';
        elsif v_target is not null and v_i_runs[v_cur] >= v_target then
          v_i_closed[v_cur] := true; v_i_reason[v_cur] := 'Target passed';
        end if;
      end if;
    end if;
  end loop;

  -- ── Derived state ────────────────────────────────────────────────────────
  -- Mirrors CricketEngine: `ended || (innings.length >= maxInnings && every
  -- innings closed)`. With the two-slot cap this is "both innings closed".
  v_finished := v_ended
    or (v_ni >= v_maxin and v_ni >= 1 and v_i_closed[1]
        and (v_ni < 2 or v_i_closed[2]));

  if v_ni >= 1 and not v_i_closed[v_ni] then
    v_current := v_ni;
  end if;

  if v_current is not null then
    v_batside := v_i_side[v_current];
  elsif v_ni >= 1 then
    v_batside := v_i_side[v_ni];
  else
    v_batside := -1;
  end if;

  if v_current is not null then
    v_next := v_i_side[v_current];
  elsif v_finished then
    v_next := -1;
  elsif v_ni >= 1 then
    v_next := 1 - v_i_side[v_ni];
  else
    v_next := coalesce(v_firstbat, -1);
  end if;

  -- Winner and result label. The margin for a chase win is measured against the
  -- CHASING innings' own wicket cap (v_i_maxw[2]), the fix for the engine bug.
  if v_finished and v_ni >= 2 then
    if v_i_runs[2] > v_i_runs[1] then
      v_win := v_i_side[2];
      v_result := v_sides[v_i_side[2] + 1] || ' won by '
        || (v_i_maxw[2] - v_i_wick[2])::text || ' wickets';
    elsif v_i_runs[2] < v_i_runs[1] then
      v_win := v_i_side[1];
      v_result := v_sides[v_i_side[1] + 1] || ' won by '
        || (v_i_runs[1] - v_i_runs[2])::text || ' runs';
    else
      v_result := 'Match tied';
    end if;
  end if;

  -- Per-side display: each side's most recent innings, '-' when yet to bat.
  for i in 1 .. v_ni loop
    if v_i_side[i] in (0, 1) then
      v_disp[v_i_side[i] + 1]   := v_i_runs[i]::text || '/' || v_i_wick[i]::text;
      v_batted[v_i_side[i] + 1] := true;
    end if;
  end loop;

  for i in 1 .. v_ni loop
    v_arr := v_arr || jsonb_build_array(jsonb_build_object(
      'batSide',      v_i_side[i],
      'runs',         v_i_runs[i],
      'wickets',      v_i_wick[i],
      'legalBalls',   v_i_legal[i],
      'maxWickets',   v_i_maxw[i],
      'closed',       v_i_closed[i],
      'closeReason',  v_i_reason[i]
    ));
  end loop;

  v_state := jsonb_build_object(
    'innings',    v_ni,
    'batSide',    v_batside,
    'nextBatSide', v_next,
    'open',       v_current is not null,
    'ended',      v_ended,
    'target',     case when v_ni >= 1 and v_i_closed[1] then v_i_runs[1] + 1 else null end,
    'battingSize', jsonb_build_array(v_size[1], v_size[2])
  );
  if v_toss_win is not null then
    v_state := jsonb_set(
      v_state, '{toss}',
      jsonb_build_object(
        'winner', v_toss_win,
        'decision', v_toss_dec,
        'batSide', coalesce(v_firstbat, v_toss_win)),
      true);
  end if;

  return jsonb_build_object(
    'state',        v_state,
    'innings',      v_arr,
    'scoreValues',  jsonb_build_array(
      case when v_batted[1] then (select coalesce(sum((e->>'runs')::int), 0)
                                    from jsonb_array_elements(v_arr) e
                                   where (e->>'batSide')::int = 0) else 0 end,
      case when v_batted[2] then (select coalesce(sum((e->>'runs')::int), 0)
                                    from jsonb_array_elements(v_arr) e
                                   where (e->>'batSide')::int = 1) else 0 end
    ),
    'scoreDisplay', jsonb_build_array(v_disp[1], v_disp[2]),
    'isComplete',   v_finished,
    'winnerSide',   v_win,
    'resultLabel',  v_result,
    'maxInnings',   v_maxin,
    'oversLimit',   v_overs
  );
end;
$$;

revoke all on function public._cricket_fold_detail(uuid)
  from public, anon, authenticated;

create or replace function public._cricket_fold(p_match_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(public._cricket_fold_detail(p_match_id)->'state', '{}'::jsonb);
$$;

revoke all on function public._cricket_fold(uuid)
  from public, anon, authenticated;

-- The one builder of the two display strings every surface prints, matching
-- CricketEngine.scoreDisplay: the last innings each side played as "runs/
-- wickets", or '-' when that side has not batted.
create or replace function public._cricket_derived_scores(p_match_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(
    public._cricket_fold_detail(p_match_id)->'scoreDisplay',
    '["-", "-"]'::jsonb);
$$;

revoke all on function public._cricket_derived_scores(uuid)
  from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  Is this entry allowed in this state?
-- ════════════════════════════════════════════════════════════════════════════
-- Pure: the folded state and the candidate payload in, a reason out (null when
-- the entry is acceptable). This mirrors MatchScoringValidator._cricket so the
-- genuine workspace is never refused, and adds the innings-end guard the client
-- validator was missing.

create or replace function public._cricket_event_refusal(
  p_state jsonb,
  p_kind  text,
  p_side  int,
  p_data  jsonb
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_innings  int  := coalesce((p_state->>'innings')::int, 0);
  v_open     boolean := coalesce((p_state->>'open')::boolean, false);
  v_finished boolean := coalesce((p_state->>'isComplete')::boolean, false);
  v_batside  int  := (p_state->>'batSide')::int;
  v_next     int  := (p_state->>'nextBatSide')::int;
  v_runs     int;
  v_extra    text;
begin
  if v_finished then
    return 'match_complete';
  end if;

  if p_kind = 'toss' then
    if v_innings > 0 or p_state ? 'toss' then
      return 'toss_already_recorded';
    end if;
    if p_side is null or p_side not in (0, 1) then
      return 'invalid_event_side';
    end if;
    if p_data->>'decision' not in ('bat', 'bowl') then
      return 'invalid_toss_decision';
    end if;
    return null;
  end if;

  if p_kind = 'lineup' then
    if v_innings > 0 then
      return 'lineup_after_first_ball';
    end if;
    if p_side is null or p_side not in (0, 1) then
      return 'invalid_event_side';
    end if;
    if jsonb_typeof(p_data->'players') <> 'array'
       or jsonb_array_length(p_data->'players') not between 2 and 11 then
      return 'invalid_lineup';
    end if;
    return null;
  end if;

  if p_kind = 'innings_start' then
    if v_open or v_innings >= 2 then
      return 'innings_cannot_open';
    end if;
    if not (p_state ? 'toss') then
      return 'toss_required';
    end if;
    if v_next is null or v_next < 0 or p_side is distinct from v_next then
      return 'side_not_due_to_bat';
    end if;
    return null;
  end if;

  if p_kind = 'match_end' then
    if v_innings = 0 then
      return 'innings_not_started';
    end if;
    return null;
  end if;

  if p_kind = 'innings_end' then
    -- The gap the client validator never closed: an innings can only be ended
    -- while one is open. The workspace only offers this action then, so no
    -- genuine scorer is affected; a crafted call is now refused.
    if not v_open then
      return 'no_innings_open';
    end if;
    return null;
  end if;

  if p_kind = 'ball' then
    if p_side is null or p_side not in (0, 1) then
      return 'invalid_event_side';
    end if;
    if v_open and v_batside is not null and v_batside >= 0
       and p_side <> v_batside then
      return 'wrong_batting_side';
    end if;
    if (p_data->>'runs') is null
       or (p_data->>'runs') !~ '^-?[0-9]+$' then
      return 'invalid_runs';
    end if;
    v_runs := (p_data->>'runs')::int;
    if v_runs < 0 or v_runs > 6 then
      return 'invalid_runs';
    end if;
    v_extra := p_data->>'extra';
    if v_extra is not null
       and v_extra not in ('wide', 'noball', 'bye', 'legbye') then
      return 'invalid_extra';
    end if;
    if (p_data->>'wicket') is not null
       and p_data->>'wicket' not in ('true', 'false') then
      return 'invalid_wicket';
    end if;
    if (p_data->>'wicket') = 'true' then
      if p_data->>'dismissal' not in (
           'Bowled', 'Caught', 'LBW', 'Run out', 'Stumped',
           'Caught & bowled', 'Hit wicket') then
        return 'invalid_dismissal';
      end if;
    end if;
    return null;
  end if;

  return 'invalid_event_kind';
end;
$$;

revoke all on function public._cricket_event_refusal(jsonb, text, int, jsonb)
  from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  record_match_event grows a cricket branch
-- ════════════════════════════════════════════════════════════════════════════
-- Body is 0024's, with a cricket branch beside futsal and badminton. It keeps
-- cricket on the inline organizer/scorer check the generic path already used
-- (no authz expansion to can_score_match), refuses any entry the fold cannot
-- accept, and closes the match the moment the fold finishes so nothing more can
-- be recorded until it is undone.

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
  v_detail  jsonb;
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

  if v_match.sport_key = 'cricket' then
    -- Cricket keeps the generic path's organizer/scorer authority.
    if v_uid <> v_match.organizer_id
       and (v_match.scorer_id is null or v_uid <> v_match.scorer_id) then
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

    select * into v_row
      from public.match_events
     where match_id = p_match_id and client_event_id = v_client;
    if v_row.id is not null then
      return v_row;
    end if;

    -- The refusal helper reads `isComplete` off the state it is handed, but
    -- `_cricket_fold` returns only the engine-shaped subset, so fold once and
    -- merge the completion flag onto it.
    v_detail := public._cricket_fold_detail(p_match_id);
    v_state  := coalesce(v_detail->'state', '{}'::jsonb) || jsonb_build_object(
      'isComplete', v_detail->'isComplete',
      'winnerSide', v_detail->'winnerSide');

    v_refusal := public._cricket_event_refusal(v_state, v_kind, v_side, v_data);
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

    v_detail := public._cricket_fold_detail(p_match_id);

    if coalesce((v_detail->>'isComplete')::boolean, false) then
      update public.matches
         set completed_at = now()
       where id = p_match_id
         and completed_at is null;
      perform public.log_match_action(
        p_match_id, v_uid, 'cricket_auto_complete',
        jsonb_build_object(
          'innings',    v_detail->'state'->>'innings',
          'runs',       v_detail->'scoreValues',
          'winnerSide', v_detail->>'winnerSide',
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
-- 4.  void_match_event reopens a completed cricket match
-- ════════════════════════════════════════════════════════════════════════════
-- Body is 0024's, with a cricket reopen block beside futsal and badminton: undo
-- of the entry that finished the log makes it scorable again.

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
  if p_reason is not null and char_length(p_reason) not between 3 and 200 then
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
         void_reason = coalesce(p_reason, 'Undo last entry')
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

  if v_match.sport_key = 'cricket' and v_match.completed_at is not null then
    v_fold := public._cricket_fold_detail(p_match_id);
    if not coalesce((v_fold->>'isComplete')::boolean, false) then
      update public.matches
         set completed_at = null
       where id = p_match_id;
      perform public.log_match_action(
        p_match_id, v_uid, 'match_reopened',
        jsonb_build_object(
          'innings', v_fold->'state'->>'innings',
          'seq',     v_row.seq
        )
      );
    end if;
  end if;

  perform public.log_match_action(
    p_match_id, v_uid, 'event_undone',
    jsonb_build_object('seq', v_row.seq, 'kind', v_row.kind, 'reason', p_reason)
  );

  return v_row;
end;
$$;

revoke all on function public.void_match_event(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.void_match_event(uuid, uuid, text)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  submit_match_result derives the cricket result
-- ════════════════════════════════════════════════════════════════════════════
-- Body is 0024's, with a cricket branch beside padel and futsal. An unfinished
-- log is refused; the run totals and winner must agree with the fold; and the
-- per-side score strings AND the headline are written from the fold, never from
-- the caller, which is where the corrected wicket-margin reaches the record.

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

  if v_match.sport_key = 'cricket' then
    v_fold := public._cricket_fold_detail(p_match_id);
    if not coalesce((v_fold->>'isComplete')::boolean, false)
       or v_match.completed_at is null then
      raise exception 'match_not_complete' using errcode = '22023';
    end if;
    -- Run totals per side and the winner are the two values the engine bug
    -- never touched, so a genuine client always agrees with the fold here.
    v_derived := v_fold->'scoreValues';
    if p_side_values is distinct from v_derived
       or p_winner_index is distinct from coalesce((v_fold->>'winnerSide')::int, -1) then
      raise exception 'score_payload_mismatch' using errcode = '22023';
    end if;
    -- The score strings and the headline come from the fold. This overwrite is
    -- the whole point: the corrected "won by N wickets" margin replaces whatever
    -- margin the (unmodified) client computed.
    p_side_scores := public._cricket_derived_scores(p_match_id);
    p_headline    := coalesce(nullif(v_fold->>'resultLabel', ''), p_headline);
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
      'derived',  v_match.sport_key in ('padel', 'futsal', 'badminton', 'cricket')
    )
  );

  return v_row;
end;
$$;

revoke all on function public.submit_match_result(uuid, text, text, jsonb, jsonb, int)
  from public, anon, authenticated;
grant execute on function public.submit_match_result(uuid, text, text, jsonb, jsonb, int)
  to authenticated;

commit;
