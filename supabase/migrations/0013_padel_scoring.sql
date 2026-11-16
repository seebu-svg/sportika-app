-- Sportika padel backend, part 2: the deterministic scoring engine.
--
-- 0008 introduced _padel_fold (a SQL mirror of lib/features/personal_games/
-- scoring/padel/padel.dart) and made record_match_event auto-complete a padel
-- match. What it did not do is make scoring server-authoritative end to end:
-- any `kind` was accepted, a null side silently became side A, the completion
-- had no derived result, there was no pause, no configurable service order, no
-- durable scoreboard and no audited correction. This migration closes those
-- gaps without adding a second rules implementation:
--
--   * _padel_fold_detail is the only place the rules live. _padel_fold keeps its
--     old signature and returns detail->'state', so every existing caller and
--     the Dart engine see the same keys.
--   * _padel_rebuild_state projects the fold into padel_match_state /
--     padel_match_sets inside the same transaction as the event insert.
--   * award_padel_point is the scoring entry point. record_match_event delegates
--     to it for padel, so the app's existing call path becomes rule-checked
--     without a client change, and there is no second way in.
--   * Undo, correction and reopen are compensating operations: the original row
--     is never edited, only flagged, and the fold ignores it.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  Who may score this match
-- ════════════════════════════════════════════════════════════════════════════
-- Organizer, the match's own assigned scorer, or a tournament scorer assigned
-- to the fixture this match was generated from. The third clause is the bridge
-- to 0006's official_scorer_assignments, which is keyed by tournament/fixture
-- text ids and predates matches.

create or replace function public.can_score_match(
  p_match_id uuid,
  p_uid      uuid
)
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
       and p_uid is not null
       and (
         m.organizer_id = p_uid
         or m.scorer_id = p_uid
         or (
           m.tournament_id is not null
           and m.fixture_id is not null
           and exists (
             select 1
               from public.official_scorer_assignments a
              where a.tournament_id     = m.tournament_id
                and a.fixture_id        = m.fixture_id
                and a.scorer_profile_id = p_uid
                and a.status in ('assigned', 'accepted')
           )
         )
       )
  );
$$;

revoke all on function public.can_score_match(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.can_score_match(uuid, uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  The fold
-- ════════════════════════════════════════════════════════════════════════════
-- _padel_fold_detail returns {state, sets, lastSeq}. `state` is byte-for-byte
-- the map PadelEngine.evaluate puts in MatchProgress.state (plus firstServer
-- keys the engine now reads), and `sets` is the per-set record the projection
-- needs. Stable: it only reads, and the just-inserted event row is visible to it
-- inside the calling transaction.

create or replace function public._padel_fold_detail(p_match_id uuid)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  -- rules
  v_rules        jsonb;
  v_format       text;
  v_no_ad        boolean;
  v_match_tb     boolean;
  v_sets_to_win  int;
  v_games_to_win int;
  v_tb_at        int;
  v_tb_points    int;
  v_final_tb     int;
  v_first_side   int;
  v_first_member int;
  -- loop
  v_event        record;
  s              int;
  o              int;
  diff           int;
  need           int;
  total          int;
  v_won          boolean;
  -- state (1-indexed: [1] = side A, [2] = side B)
  v_pts          int[] := '{0,0}';
  v_games        int[] := '{0,0}';
  v_tb           int[] := '{0,0}';
  v_sets_won     int[] := '{0,0}';
  v_turns        int[] := '{0,0}';
  v_completed    jsonb := '[]';
  v_set_records  jsonb := '[]';
  v_in_tb        boolean := false;
  v_dec_tb       boolean := false;
  v_set_tb       boolean := false;
  v_done         boolean := false;
  v_winner       int     := -1;
  v_serving      int     := 0;
  v_pt_count     int     := 0;
  v_sets_done    int     := 0;
  v_set_start    bigint;
  v_last_seq     bigint  := 0;
  v_tb_final     jsonb;
begin
  select rules, format_label into v_rules, v_format
    from public.matches where id = p_match_id;

  if v_rules is null then
    return '{}'::jsonb;
  end if;

  v_no_ad        := coalesce((v_rules->>'noAd')::boolean,          false);
  v_match_tb     := coalesce((v_rules->>'matchTiebreak')::boolean, false);
  v_sets_to_win  := coalesce((v_rules->>'setsToWin')::int,
                              case v_format
                                when '1 set · first to 6' then 1
                                when 'Best of 5 sets'     then 3
                                else 2
                              end);
  v_games_to_win := coalesce((v_rules->>'gamesToWinSet')::int,  6);
  v_tb_at        := coalesce((v_rules->>'tiebreakAt')::int,     v_games_to_win);
  v_tb_points    := coalesce((v_rules->>'tiebreakPoints')::int, 7);
  v_final_tb     := coalesce((v_rules->>'finalSetTiebreakPoints')::int, 10);
  v_first_side   := coalesce((v_rules->>'firstServerSide')::int,   0);
  v_first_member := coalesce((v_rules->>'firstServerMember')::int, 0);

  -- Seeding the completed-turn counter is how a configured first server is
  -- expressed: servingMember is turns[servingSide] % 2, and a side alternates
  -- its two players every service game.
  v_serving := case when v_first_side in (0, 1) then v_first_side else 0 end;
  v_turns[v_serving + 1] := case when v_first_member in (0, 1) then v_first_member else 0 end;

  for v_event in
    select seq, side
      from public.match_events
     where match_id = p_match_id
       and kind     = 'point'
       and not voided
     order by seq
  loop
    if v_done then exit; end if;

    v_last_seq := v_event.seq;
    if v_set_start is null then
      v_set_start := v_event.seq;
    end if;

    s := coalesce(v_event.side, 0);
    o := 1 - s;
    v_pt_count := v_pt_count + 1;

    if v_in_tb then
      -- ── tie-break point ────────────────────────────────────────────────
      v_tb[s+1] := v_tb[s+1] + 1;
      total     := v_tb[1] + v_tb[2];
      -- Service in a tie-break changes after the first point, then every two.
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
        v_tb_final := jsonb_build_array(v_tb[1], v_tb[2]);
        v_tb       := '{0,0}';
        v_in_tb    := false;
        v_games[s+1] := v_games[s+1] + 1;   -- 6→7 for a regular TB, 0→1 for a super TB
        v_set_tb   := true;
        v_completed := v_completed
          || jsonb_build_array(jsonb_build_array(v_games[1], v_games[2]));
        v_set_records := v_set_records || jsonb_build_array(jsonb_build_object(
          'index',  v_sets_done,
          'a',      v_games[1],
          'b',      v_games[2],
          'winner', s,
          'tiebreak', true,
          'tb',     v_tb_final,
          'seqStart', v_set_start,
          'seqEnd',   v_event.seq));
        v_sets_won[s+1] := v_sets_won[s+1] + 1;
        v_games     := '{0,0}';
        v_pts       := '{0,0}';
        v_sets_done := v_sets_done + 1;
        v_set_start := null;
        v_set_tb    := false;
        v_dec_tb    := false;
        v_tb_final  := null;

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
      -- ── normal game point ──────────────────────────────────────────────
      v_pts[s+1] := v_pts[s+1] + 1;
      diff := v_pts[s+1] - v_pts[o+1];
      v_won := case
                 when v_no_ad then v_pts[s+1] >= 4 and diff >= 1
                 else              v_pts[s+1] >= 4 and diff >= 2
               end;
      if not v_won then continue; end if;

      v_pts := '{0,0}';
      v_games[s+1] := v_games[s+1] + 1;
      v_turns[v_serving+1] := v_turns[v_serving+1] + 1;
      v_serving := 1 - v_serving;

      if v_games[s+1] >= v_games_to_win
         and v_games[s+1] - v_games[o+1] >= 2 then
        v_completed := v_completed
          || jsonb_build_array(jsonb_build_array(v_games[1], v_games[2]));
        v_set_records := v_set_records || jsonb_build_array(jsonb_build_object(
          'index',  v_sets_done,
          'a',      v_games[1],
          'b',      v_games[2],
          'winner', s,
          'tiebreak', false,
          'tb',     null,
          'seqStart', v_set_start,
          'seqEnd',   v_event.seq));
        v_sets_won[s+1] := v_sets_won[s+1] + 1;
        v_games     := '{0,0}';
        v_pts       := '{0,0}';
        v_tb        := '{0,0}';
        v_in_tb     := false;
        v_sets_done := v_sets_done + 1;
        v_set_start := null;

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
        v_in_tb := true;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'lastSeq', v_last_seq,
    'sets',    v_set_records,
    'state',   jsonb_build_object(
      'completedSets',   v_completed,
      'points',          jsonb_build_array(v_pts[1],      v_pts[2]),
      'tiebreakPoints',  jsonb_build_array(v_tb[1],       v_tb[2]),
      'setsWon',         jsonb_build_array(v_sets_won[1], v_sets_won[2]),
      'games',           jsonb_build_array(v_games[1],    v_games[2]),
      'inTiebreak',      v_in_tb,
      'deciderTiebreak', v_dec_tb,
      'matchTiebreak',   v_match_tb,
      'noAd',            v_no_ad,
      'setsToWin',       v_sets_to_win,
      'gamesToWinSet',   v_games_to_win,
      'servingSide',     v_serving,
      'servingMember',   mod(v_turns[v_serving+1], 2),
      'firstServerSide',   v_first_side,
      'firstServerMember', v_first_member,
      'pointCount',      v_pt_count,
      'setsCompleted',   v_sets_done,
      'isComplete',      v_done,
      'winnerSide',      v_winner
    )
  );
end;
$$;

revoke all on function public._padel_fold_detail(uuid)
  from public, anon, authenticated;

-- The 0008 contract, unchanged for every existing caller.
create or replace function public._padel_fold(p_match_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(public._padel_fold_detail(p_match_id)->'state', '{}'::jsonb);
$$;

revoke all on function public._padel_fold(uuid) from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  Projection
-- ════════════════════════════════════════════════════════════════════════════
-- Writes the scoreboard row and the completed-set rows from the log. Called
-- inside every scoring mutation, in the same transaction, after the event row
-- is in place. Returns the new snapshot pieces (without the match join).

create or replace function public._padel_rebuild_state(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match    public.matches;
  v_detail   jsonb;
  v_state    jsonb;
  v_status   text;
  v_revision bigint;
begin
  select * into v_match from public.matches where id = p_match_id;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  v_detail := public._padel_fold_detail(p_match_id);
  v_state  := coalesce(v_detail->'state', '{}'::jsonb);

  v_status := case
                when coalesce((v_state->>'isComplete')::boolean, false) then 'complete'
                when v_match.status in ('submitted', 'published', 'walkover') then 'complete'
                when v_match.paused_at is not null and v_match.status = 'live' then 'paused'
                when v_match.status = 'live' then 'live'
                else 'not_started'
              end;

  insert into public.padel_match_state as st (
    match_id, revision, status, points, games, tiebreak_points, sets_won,
    in_tiebreak, decider_tiebreak, serving_side, serving_member,
    point_count, is_complete, winner_side
  )
  values (
    p_match_id, 1, v_status,
    coalesce(v_state->'points',         '[0, 0]'::jsonb),
    coalesce(v_state->'games',          '[0, 0]'::jsonb),
    coalesce(v_state->'tiebreakPoints', '[0, 0]'::jsonb),
    coalesce(v_state->'setsWon',        '[0, 0]'::jsonb),
    coalesce((v_state->>'inTiebreak')::boolean, false),
    coalesce((v_state->>'deciderTiebreak')::boolean, false),
    coalesce((v_state->>'servingSide')::int, 0),
    coalesce((v_state->>'servingMember')::int, 0),
    coalesce((v_state->>'pointCount')::int, 0),
    coalesce((v_state->>'isComplete')::boolean, false),
    nullif(v_state->>'winnerSide', '-1')::smallint
  )
  on conflict (match_id) do update
     set revision         = st.revision + 1,
         status           = excluded.status,
         points           = excluded.points,
         games            = excluded.games,
         tiebreak_points  = excluded.tiebreak_points,
         sets_won         = excluded.sets_won,
         in_tiebreak      = excluded.in_tiebreak,
         decider_tiebreak = excluded.decider_tiebreak,
         serving_side     = excluded.serving_side,
         serving_member   = excluded.serving_member,
         point_count      = excluded.point_count,
         is_complete      = excluded.is_complete,
         winner_side      = excluded.winner_side
  returning revision into v_revision;

  delete from public.padel_match_sets where match_id = p_match_id;
  insert into public.padel_match_sets (
    match_id, set_index, side_a_games, side_b_games, winner_side,
    tiebreak, tiebreak_points, point_seq_start, point_seq_end
  )
  select p_match_id,
         coalesce((rec->>'index')::int, 0),
         coalesce((rec->>'a')::int, 0),
         coalesce((rec->>'b')::int, 0),
         coalesce((rec->>'winner')::int, 0)::smallint,
         coalesce((rec->>'tiebreak')::boolean, false),
         case when jsonb_typeof(rec->'tb') = 'array' then rec->'tb' else null end,
         nullif(rec->>'seqStart', '')::bigint,
         nullif(rec->>'seqEnd',   '')::bigint
    from jsonb_array_elements(coalesce(v_detail->'sets', '[]'::jsonb)) rec;

  return jsonb_build_object(
    'revision', v_revision,
    'state',    v_state,
    'sets',     coalesce(v_detail->'sets', '[]'::jsonb)
  );
end;
$$;

revoke all on function public._padel_rebuild_state(uuid)
  from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 4.  Snapshot
-- ════════════════════════════════════════════════════════════════════════════
-- One authoritative read for a reconnecting client: current state, completed
-- sets, the active point log, the published result and any disputes, all from
-- the same revision. The fold is recomputed rather than trusted from the cache,
-- so a stale projection can never be served.

create or replace function public._padel_snapshot(
  p_match_id uuid,
  p_uid      uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_match    public.matches;
  v_detail   jsonb;
  v_sets     jsonb;
  v_state    jsonb;
  v_revision bigint;
  v_result   public.match_results;
  v_serving  int;
  v_member   int;
  v_can      boolean := false;
begin
  select * into v_match from public.matches where id = p_match_id;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  v_detail := public._padel_fold_detail(p_match_id);
  v_sets   := coalesce(v_detail->'sets', '[]'::jsonb);
  v_state  := coalesce(v_detail->'state', '{}'::jsonb);
  v_serving := coalesce((v_state->>'servingSide')::int, 0);
  v_member  := coalesce((v_state->>'servingMember')::int, 0);

  -- The engine's completedSets is a list of [a, b] pairs; keep that shape.
  v_state := v_state || jsonb_build_object(
    'completedSets',
    coalesce(
      (select jsonb_agg(jsonb_build_array((rec->>'a')::int, (rec->>'b')::int) order by (rec->>'index')::int)
         from jsonb_array_elements(v_sets) rec),
      '[]'::jsonb
    )
  );

  select revision into v_revision
    from public.padel_match_state where match_id = p_match_id;
  v_revision := coalesce(v_revision, 0);

  select * into v_result from public.match_results where match_id = p_match_id;

  if p_uid is not null then
    v_can := public.can_score_match(p_match_id, p_uid);
  end if;

  return jsonb_build_object(
    'matchId',  v_match.id,
    'revision', v_revision,
    'state',    v_state,
    'sets',     v_sets,
    'serving',  jsonb_build_object(
      'side',   v_serving,
      'member', v_member,
      'name',   case when v_serving = 0 then v_match.side_a_name else v_match.side_b_name end
    ),
    'events', coalesce(
      (select jsonb_agg(jsonb_build_object(
                'seq',  e.seq,
                'side', e.side,
                'at',   e.recorded_at,
                'by',   e.recorded_by)
              order by e.seq)
         from public.match_events e
        where e.match_id = p_match_id
          and e.kind     = 'point'
          and not e.voided),
      '[]'::jsonb),
    'result', case when v_result.match_id is null then null else jsonb_build_object(
                'sideScores',  v_result.side_scores,
                'sideValues',  v_result.side_values,
                'winnerIndex', v_result.winner_index,
                'headline',    v_result.headline,
                'detail',      v_result.detail,
                'walkover',    v_result.walkover,
                'publishedAt', v_result.published_at)
              end,
    'disputes', coalesce(
      (select jsonb_agg(jsonb_build_object(
                'id',         d.id,
                'status',     d.status,
                'reason',     d.reason,
                'raisedBy',   d.raised_by,
                'resolution', d.resolution,
                'resolvedAt', d.resolved_at,
                'createdAt',  d.created_at)
              order by d.created_at desc)
         from public.match_disputes d
        where d.match_id = p_match_id),
      '[]'::jsonb),
    'canScore',   v_can,
    'isComplete', coalesce((v_state->>'isComplete')::boolean, false),
    'winnerSide', coalesce((v_state->>'winnerSide')::int, -1)
  );
end;
$$;

revoke all on function public._padel_snapshot(uuid, uuid)
  from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  Award one point
-- ════════════════════════════════════════════════════════════════════════════
-- The single mutation behind padel scoring. Locks the match row first, so two
-- scorers cannot interleave; then authorizes, validates, inserts, reprojects
-- and returns the row. A replayed client id returns the original event without
-- touching the log (deduplicated = true in award_padel_point's payload).

create or replace function public._padel_award_point(
  p_match_id uuid,
  p_side     int,
  p_client   text
)
returns public.match_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_client text := trim(coalesce(p_client, ''));
  v_side   smallint := p_side;
  v_seq    bigint;
  v_row    public.match_events;
  v_fold   jsonb;
  v_state  jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  if v_match.sport_key <> 'padel' then
    raise exception 'wrong_sport' using errcode = '22023';
  end if;

  if not public.can_score_match(p_match_id, v_uid) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;

  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  if v_match.paused_at is not null then
    raise exception 'match_paused' using errcode = '22023';
  end if;

  if v_match.paused_at is null and v_match.completed_at is not null then
    raise exception 'match_complete' using errcode = '22023';
  end if;

  if v_side is null or v_side not in (0, 1) then
    raise exception 'invalid_event_side' using errcode = '22023';
  end if;

  if char_length(v_client) not between 1 and 80 then
    raise exception 'invalid_client_event' using errcode = '22023';
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
    (p_match_id, v_seq, v_client, 'point', v_side, '{}'::jsonb, v_uid)
  returning * into v_row;

  update public.matches
     set event_count = v_seq
   where id = p_match_id;

  perform public._padel_rebuild_state(p_match_id);

  v_fold  := public._padel_fold(p_match_id);
  v_state := v_fold;

  if coalesce((v_state->>'isComplete')::boolean, false) then
    update public.matches
       set completed_at = now()
     where id = p_match_id
       and completed_at is null;
    perform public.log_match_action(
      p_match_id, v_uid, 'padel_auto_complete',
      jsonb_build_object(
        'winner_side', v_state->>'winnerSide',
        'sets_won',    v_state->'setsWon',
        'seq',         v_seq
      )
    );
  end if;

  return v_row;
end;
$$;

revoke all on function public._padel_award_point(uuid, int, text)
  from public, anon, authenticated;

create or replace function public.award_padel_point(
  p_match_id        uuid,
  p_side            int,
  p_client_event_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_event  public.match_events;
  v_before bigint;
  v_after  bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Take the match lock here, before measuring anything. Counting the log from
  -- outside the lock made a concurrent retry look like a fresh point: both
  -- sessions measured zero events, then only one of them inserted. event_count
  -- is bumped inside _padel_award_point only when a row really is written, so
  -- measured under the same lock it is an exact dedupe signal.
  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  v_before := v_match.event_count;

  v_event := public._padel_award_point(p_match_id, p_side, p_client_event_id);

  select event_count into v_after from public.matches where id = p_match_id;

  return public._padel_snapshot(p_match_id, v_uid) || jsonb_build_object(
    'event',        to_jsonb(v_event),
    'deduplicated', v_after is not distinct from v_before
  );
end;
$$;

revoke all on function public.award_padel_point(uuid, int, text)
  from public, anon, authenticated;
grant execute on function public.award_padel_point(uuid, int, text) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 6.  record_match_event becomes a padel-aware front door
-- ════════════════════════════════════════════════════════════════════════════
-- The app already calls this for every sport. For padel it must not become a
-- second, unvalidated way in, so a point is handed to _padel_award_point and
-- any other kind is refused: padel's log is a point log, and the workspace
-- sends exactly one kind. Non-padel behaviour is unchanged except that a paused
-- match refuses new events and the void audit columns stay authoritative.

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
    -- Returns the stored row for a replayed client id, exactly like before.
    return public._padel_award_point(p_match_id, v_side, v_client);
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
-- 7.  Pause and resume
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.pause_match(
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
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
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
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) not between 3 and 200 then
    raise exception 'invalid_pause_reason' using errcode = '22023';
  end if;

  -- Pausing a paused match is a no-op rather than an error: a double tap on a
  -- slow connection must not fail in the scorer's face.
  if v_match.paused_at is not null then
    return v_match;
  end if;

  update public.matches
     set paused_at     = now(),
         paused_by     = v_uid,
         pause_reason  = v_reason
   where id = p_match_id
  returning * into v_match;

  if v_match.sport_key = 'padel' then
    perform public._padel_rebuild_state(p_match_id);
  end if;

  perform public.log_match_action(
    p_match_id, v_uid, 'paused', jsonb_build_object('reason', v_reason)
  );

  return v_match;
end;
$$;

create or replace function public.resume_match(p_match_id uuid)
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

  if not public.can_score_match(p_match_id, v_uid) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  if v_match.paused_at is null then
    return v_match;
  end if;

  update public.matches
     set paused_at    = null,
         paused_by    = null,
         pause_reason = null
   where id = p_match_id
  returning * into v_match;

  if v_match.sport_key = 'padel' then
    perform public._padel_rebuild_state(p_match_id);
  end if;

  perform public.log_match_action(p_match_id, v_uid, 'resumed', '{}'::jsonb);

  return v_match;
end;
$$;

revoke all on function public.pause_match(uuid, text)
  from public, anon, authenticated;
revoke all on function public.resume_match(uuid)
  from public, anon, authenticated;
grant execute on function public.pause_match(uuid, text) to authenticated;
grant execute on function public.resume_match(uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 8.  Undo
-- ════════════════════════════════════════════════════════════════════════════
-- 0008 voided the newest active entry and cleared completed_at. This keeps that
-- semantics and adds who/why plus a rebuild, so the scoreboard row follows.

create or replace function public.undo_last_padel_point(
  p_match_id uuid,
  p_reason   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_row    public.match_events;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
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
  if v_match.sport_key <> 'padel' then
    raise exception 'wrong_sport' using errcode = '22023';
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

  select * into v_row
    from public.match_events
   where match_id = p_match_id
     and kind     = 'point'
     and not voided
   order by seq desc
   limit 1;

  if v_row.id is null then
    raise exception 'nothing_to_undo' using errcode = 'P0002';
  end if;

  update public.match_events
     set voided      = true,
         voided_by   = v_uid,
         void_reason = coalesce(v_reason, 'Undo last point')
   where id = v_row.id;

  perform public._padel_rebuild_state(p_match_id);

  -- A completed padel match is undoable until the result is submitted; clearing
  -- completed_at is what re-opens scoring (0008 established this contract).
  if not coalesce((public._padel_fold(p_match_id)->>'isComplete')::boolean, false) then
    update public.matches
       set completed_at = null
     where id = p_match_id;
  end if;

  perform public.log_match_action(
    p_match_id, v_uid, 'point_undone',
    jsonb_build_object('seq', v_row.seq, 'reason', v_reason)
  );

  return public._padel_snapshot(p_match_id, v_uid);
end;
$$;

revoke all on function public.undo_last_padel_point(uuid, text)
  from public, anon, authenticated;
grant execute on function public.undo_last_padel_point(uuid, text) to authenticated;

-- void_match_event keeps its job for the other sports and gains the audit
-- columns. The two-argument version is dropped first: adding a defaulted
-- parameter creates an overload, and a two-argument call would then be ambiguous.
drop function if exists public.void_match_event(uuid, uuid);

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
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  if v_match.sport_key = 'padel' then
    -- Padel undo is "withdraw the newest point"; the id is honoured so a stale
    -- screen cannot withdraw a different row than the one it tapped.
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

  if v_uid <> v_match.organizer_id
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
-- 9.  Authorized correction
-- ════════════════════════════════════════════════════════════════════════════
-- Undo is "the newest point"; correction is "this point, and here is why". The
-- organizer alone may reach back into the log, the row is flagged rather than
-- edited (guard_match_event_write enforces that), and the projection is rebuilt
-- so the published scoreboard can never disagree with the log.

create or replace function public.correct_padel_event(
  p_match_id uuid,
  p_event_id uuid,
  p_reason   text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_row    public.match_events;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.sport_key <> 'padel' then
    raise exception 'wrong_sport' using errcode = '22023';
  end if;
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if v_match.submitted_at is not null then
    raise exception 'result_already_submitted' using errcode = '22023';
  end if;
  if char_length(v_reason) not between 3 and 200 then
    raise exception 'invalid_correction_reason' using errcode = '22023';
  end if;

  select * into v_row
    from public.match_events
   where id = p_event_id and match_id = p_match_id;

  if v_row.id is null then
    raise exception 'event_not_found' using errcode = 'P0002';
  end if;
  if v_row.voided then
    raise exception 'event_already_voided' using errcode = '22023';
  end if;

  update public.match_events
     set voided      = true,
         voided_by   = v_uid,
         void_reason = v_reason
   where id = p_event_id;

  perform public._padel_rebuild_state(p_match_id);

  if not coalesce((public._padel_fold(p_match_id)->>'isComplete')::boolean, false) then
    update public.matches
       set completed_at = null
     where id = p_match_id;
  end if;

  perform public.log_match_action(
    p_match_id, v_uid, 'score_corrected',
    jsonb_build_object('seq', v_row.seq, 'reason', v_reason)
  );

  return public._padel_snapshot(p_match_id, v_uid);
end;
$$;

revoke all on function public.correct_padel_event(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.correct_padel_event(uuid, uuid, text) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 10.  Reopen a submitted or published result
-- ════════════════════════════════════════════════════════════════════════════
-- The only legal route back into a closed match. The previous result is copied
-- into match_result_corrections before the match returns to `live`, so the
-- history keeps the score that had been published and the reason it was undone.

create or replace function public.reopen_padel_match(
  p_match_id uuid,
  p_reason   text
)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_prev   public.match_results;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_match.sport_key <> 'padel' then
    raise exception 'wrong_sport' using errcode = '22023';
  end if;
  if v_match.status not in ('submitted', 'published', 'walkover') then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if char_length(v_reason) not between 3 and 200 then
    raise exception 'invalid_correction_reason' using errcode = '22023';
  end if;

  select * into v_prev from public.match_results where match_id = p_match_id;

  if v_prev.match_id is not null then
    insert into public.match_result_corrections
      (match_id, previous, current, reason, changed_by)
    values
      (p_match_id,
       jsonb_build_object(
         'sideScores',  v_prev.side_scores,
         'sideValues',  v_prev.side_values,
         'winnerIndex', v_prev.winner_index,
         'headline',    v_prev.headline,
         'detail',      v_prev.detail,
         'walkover',    v_prev.walkover,
         'publishedById', v_prev.published_by,
         'publishedAt',   v_prev.published_at),
       jsonb_build_object('status', 'live', 'reason', v_reason),
       v_reason, v_uid);
  end if;

  update public.matches
     set status       = 'live',
         submitted_at = null,
         published_at = null,
         completed_at = null,
         paused_at    = null,
         paused_by    = null,
         pause_reason = null
   where id = p_match_id
  returning * into v_match;

  perform public._padel_rebuild_state(p_match_id);

  -- If the log still says the match is finished, keep the completion stamp: the
  -- organizer reopened it to correct a point, and re-completion is one tap away.
  if coalesce((public._padel_fold(p_match_id)->>'isComplete')::boolean, false) then
    update public.matches set completed_at = now() where id = p_match_id;
  end if;

  perform public.log_match_action(
    p_match_id, v_uid, 'reopened', jsonb_build_object('reason', v_reason)
  );

  select * into v_match from public.matches where id = p_match_id;
  return v_match;
end;
$$;

revoke all on function public.reopen_padel_match(uuid, text)
  from public, anon, authenticated;
grant execute on function public.reopen_padel_match(uuid, text) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 11.  Derive and submit the official result
-- ════════════════════════════════════════════════════════════════════════════
-- The scorer never supplies a score here: sets won, the set lines and the
-- winner all come from the fold and from padel_match_sets.

create or replace function public.complete_padel_match(p_match_id uuid)
returns public.match_results
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_match    public.matches;
  v_fold     jsonb;
  v_sets     jsonb;
  v_values   jsonb;
  v_scores   jsonb;
  v_winner   int;
  v_headline text;
  v_detail   text;
  v_row      public.match_results;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_match.sport_key <> 'padel' then
    raise exception 'wrong_sport' using errcode = '22023';
  end if;
  if not public.can_score_match(p_match_id, v_uid) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'live' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  v_fold := public._padel_fold(p_match_id);
  if not coalesce((v_fold->>'isComplete')::boolean, false) then
    raise exception 'match_not_complete' using errcode = '22023';
  end if;

  v_sets   := public._padel_fold_detail(p_match_id)->'sets';
  v_values := v_fold->'setsWon';
  v_winner := coalesce((v_fold->>'winnerSide')::int, -1);

  select jsonb_build_array(
           coalesce(string_agg((rec->>'a') || '-' || (rec->>'b'), ', '
                               order by (rec->>'index')::int), ''),
           coalesce(string_agg((rec->>'b') || '-' || (rec->>'a'), ', '
                               order by (rec->>'index')::int), ''))
    into v_scores
    from jsonb_array_elements(v_sets) rec;

  select coalesce(string_agg(
           'Set ' || ((rec->>'index')::int + 1) || ': '
           || (rec->>'a') || '-' || (rec->>'b'), ' · '
           order by (rec->>'index')::int), '')
    into v_detail
    from jsonb_array_elements(v_sets) rec;

  v_headline := case when v_winner = 0 then v_match.side_a_name else v_match.side_b_name end
                || ' won ' || (v_values->>0) || '-' || (v_values->>1);

  insert into public.match_results as mr
    (match_id, side_scores, side_values, winner_index, headline, detail,
     walkover, published_by)
  values
    (p_match_id, v_scores, v_values, v_winner, v_headline, v_detail, false, v_uid)
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

  perform public._padel_rebuild_state(p_match_id);

  perform public.log_match_action(
    p_match_id, v_uid, 'result_submitted',
    jsonb_build_object('headline', v_headline, 'derived', true)
  );

  return v_row;
end;
$$;

revoke all on function public.complete_padel_match(uuid)
  from public, anon, authenticated;
grant execute on function public.complete_padel_match(uuid) to authenticated;

-- submit_match_result stays the generic door (the app calls it with the values
-- its own engine folded). For padel the payload is now checked against the
-- server fold rather than believed: the text fields stay the client's, the
-- winner and the set totals may not disagree with the log.
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
     and not (v_match.sport_key = 'padel' and public.can_score_match(p_match_id, v_uid)) then
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

  if v_match.sport_key = 'padel' then
    perform public._padel_rebuild_state(p_match_id);
  end if;

  perform public.log_match_action(
    p_match_id, v_uid, 'result_submitted',
    jsonb_build_object('headline', coalesce(p_headline, ''))
  );

  return v_row;
end;
$$;

revoke all on function public.submit_match_result(uuid, text, text, jsonb, jsonb, int)
  from public, anon, authenticated;
grant execute on function public.submit_match_result(uuid, text, text, jsonb, jsonb, int)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 12.  Configuration and start
-- ════════════════════════════════════════════════════════════════════════════
-- The padel rule set lives in matches.rules, which is where the Dart engine has
-- always read it from. configure_padel_match is the only writer: it merges the
-- caller's map, validates every key the fold depends on, and writes one
-- normalised object back. No second configuration table exists on purpose.

create or replace function public.configure_padel_match(
  p_match_id  uuid,
  p_rules     jsonb,
  p_discipline text default null
)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_match     public.matches;
  v_rules     jsonb := coalesce(p_rules, '{}'::jsonb);
  v_sets      int;
  v_games     int;
  v_tb_points int;
  v_final_tb  int;
  v_no_ad     boolean;
  v_match_tb  boolean;
  v_first_s   int;
  v_first_m   int;
  v_disc      text := nullif(lower(trim(coalesce(p_discipline, ''))), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform public.require_match_organizer(p_match_id, v_uid);

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_match.sport_key <> 'padel' then
    raise exception 'wrong_sport' using errcode = '22023';
  end if;
  if v_match.status <> 'upcoming' or v_match.event_count > 0 then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;
  if jsonb_typeof(v_rules) <> 'object' then
    raise exception 'invalid_padel_rules' using errcode = '22023';
  end if;

  v_rules := coalesce(v_match.rules, '{}'::jsonb) || v_rules;

  v_sets      := coalesce((v_rules->>'setsToWin')::int, 2);
  v_games     := coalesce((v_rules->>'gamesToWinSet')::int, 6);
  v_tb_points := coalesce((v_rules->>'tiebreakPoints')::int, 7);
  v_final_tb  := coalesce((v_rules->>'finalSetTiebreakPoints')::int,
                          case when v_sets = 1 then 7 else 10 end);
  v_no_ad     := coalesce((v_rules->>'noAd')::boolean, false);
  v_match_tb  := coalesce((v_rules->>'matchTiebreak')::boolean, false);
  v_first_s   := coalesce((v_rules->>'firstServerSide')::int, 0);
  v_first_m   := coalesce((v_rules->>'firstServerMember')::int, 0);

  if v_sets not in (1, 2, 3) then
    raise exception 'invalid_padel_rules' using errcode = '22023';
  end if;
  if v_games not between 4 and 6 then
    raise exception 'invalid_padel_rules' using errcode = '22023';
  end if;
  if v_tb_points not between 5 and 10 then
    raise exception 'invalid_padel_rules' using errcode = '22023';
  end if;
  if v_final_tb not in (7, 10) then
    raise exception 'invalid_padel_rules' using errcode = '22023';
  end if;
  -- A match tie-break replaces a deciding set, so it needs one to replace.
  if v_match_tb and v_sets < 2 then
    raise exception 'invalid_padel_rules' using errcode = '22023';
  end if;
  if v_first_s not in (0, 1) or v_first_m not in (0, 1) then
    raise exception 'invalid_padel_rules' using errcode = '22023';
  end if;
  if v_disc is not null and v_disc not in ('singles', 'doubles') then
    raise exception 'invalid_discipline' using errcode = '22023';
  end if;

  -- Tie-breaks only happen at level games, so tiebreakAt follows the set length.
  v_rules := v_rules || jsonb_build_object(
    'setsToWin',             v_sets,
    'gamesToWinSet',         v_games,
    'tiebreakAt',            v_games,
    'tiebreakPoints',        v_tb_points,
    'finalSetTiebreakPoints',v_final_tb,
    'noAd',                  v_no_ad,
    'matchTiebreak',         v_match_tb,
    'firstServerSide',       v_first_s,
    'firstServerMember',     v_first_m
  );

  update public.matches
     set rules      = v_rules,
         discipline = coalesce(v_disc, discipline)
   where id = p_match_id
  returning * into v_match;

  perform public.log_match_action(
    p_match_id, v_uid, 'padel_configured', v_rules
  );

  return v_match;
end;
$$;

revoke all on function public.configure_padel_match(uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.configure_padel_match(uuid, jsonb, text)
  to authenticated;

-- start_match keeps working for every sport; for padel it now also seeds the
-- scoreboard row and accepts the tournament-scorer bridge.
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
  if not public.can_score_match(p_match_id, v_uid) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'upcoming' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  update public.matches
     set status     = 'live',
         started_at = now(),
         paused_at  = null,
         paused_by  = null,
         pause_reason = null
   where id = p_match_id
  returning * into v_match;

  if v_match.sport_key = 'padel' then
    perform public._padel_rebuild_state(p_match_id);
  end if;

  perform public.log_match_action(p_match_id, v_uid, 'started', '{}'::jsonb);

  return v_match;
end;
$$;

revoke all on function public.start_match(uuid)
  from public, anon, authenticated;
grant execute on function public.start_match(uuid) to authenticated;

-- The padel-specific start adds what the generic one cannot: a roster sanity
-- check for the discipline and a configured first server. It never requires a
-- full roster: the MVP lets an organizer start while invites are pending, and
-- that contract is already relied on by the app and its tests.
create or replace function public.start_padel_match(
  p_match_id            uuid,
  p_first_server_side   int default null,
  p_first_server_member int default null
)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_disc   text;
  v_side_a int;
  v_side_b int;
  v_limit  int;
  v_rules  jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if v_match.sport_key <> 'padel' then
    raise exception 'wrong_sport' using errcode = '22023';
  end if;
  if not public.can_score_match(p_match_id, v_uid) then
    raise exception 'not_match_scorer' using errcode = '42501';
  end if;
  if v_match.status <> 'upcoming' then
    raise exception 'invalid_match_transition' using errcode = '22023';
  end if;

  v_disc := coalesce(v_match.discipline, v_match.rules->>'discipline');
  if v_disc is null or v_disc not in ('singles', 'doubles') then
    raise exception 'invalid_discipline' using errcode = '22023';
  end if;

  v_limit := case when v_disc = 'doubles' then 2 else 1 end;

  select count(*) filter (where side = 0), count(*) filter (where side = 1)
    into v_side_a, v_side_b
    from public.match_participants
   where match_id = p_match_id and status = 'accepted';

  if v_side_a > v_limit or v_side_b > v_limit then
    raise exception 'roster_overflow' using errcode = '22023';
  end if;
  if v_side_a = 0 or v_side_b = 0 then
    raise exception 'roster_incomplete' using errcode = '22023';
  end if;

  v_rules := coalesce(v_match.rules, '{}'::jsonb);

  if p_first_server_side is not null or p_first_server_member is not null then
    if p_first_server_side is null or p_first_server_side not in (0, 1)
       or coalesce(p_first_server_member, 0) not in (0, 1) then
      raise exception 'invalid_padel_rules' using errcode = '22023';
    end if;
    v_rules := v_rules || jsonb_build_object(
      'firstServerSide',   p_first_server_side,
      'firstServerMember', coalesce(p_first_server_member, 0)
    );
  end if;

  update public.matches
     set status      = 'live',
         started_at  = now(),
         rules       = v_rules,
         paused_at   = null,
         paused_by   = null,
         pause_reason = null
   where id = p_match_id
  returning * into v_match;

  perform public._padel_rebuild_state(p_match_id);

  perform public.log_match_action(
    p_match_id, v_uid, 'padel_started',
    jsonb_build_object('discipline', v_disc, 'rules', v_rules)
  );

  return v_match;
end;
$$;

revoke all on function public.start_padel_match(uuid, int, int)
  from public, anon, authenticated;
grant execute on function public.start_padel_match(uuid, int, int)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 13.  Read surface
-- ════════════════════════════════════════════════════════════════════════════
-- The reconnection contract: the app calls this after the channel comes back and
-- replaces whatever it was showing with this snapshot.

create or replace function public.get_padel_scoreboard(p_match_id uuid)
returns jsonb
language plpgsql
stable
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
  if not public.can_view_match(p_match_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into v_match from public.matches where id = p_match_id;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;

  return public._padel_snapshot(p_match_id, v_uid) || jsonb_build_object(
    'match', to_jsonb(v_match),
    'paused', v_match.paused_at is not null,
    'pauseReason', v_match.pause_reason
  );
end;
$$;

revoke all on function public.get_padel_scoreboard(uuid)
  from public, anon, authenticated;
grant execute on function public.get_padel_scoreboard(uuid) to authenticated;

commit;
