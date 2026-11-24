-- Sportika padel result authority: no official padel score is the device's to write.
--
-- Migration 0013 made the padel payload checked rather than believed: a
-- submit_match_result whose set totals or winner disagree with the server fold
-- raises score_payload_mismatch. What it still stored verbatim was
-- `p_side_scores`, and those two strings are what every surface reads - the
-- result card, the scoreboard tile, the shared vs-card, the history row and the
-- live feed. So a caller with the right totals and invented set lines, or an
-- installed build whose engine folded one string for both sides (the defect
-- fixed in the Dart engine on 2026-11-17), could still put a score on the
-- official record that the recorded points do not add up to.
--
-- Two changes, both confined to padel:
--
--  1. `_padel_derived_scores(uuid)` builds the per-side set strings from the
--     fold - side A reads its own pairs first, side B every pair reversed - and
--     becomes the only builder of that string in the database. One builder is
--     the point: 0013 spelled the same aggregation out twice, which is how a
--     per-side value drifts out of sync with its sibling.
--  2. `complete_padel_match` calls it instead of inlining the aggregation, and
--     `submit_match_result` overwrites the caller's array with it after the
--     existing totals/winner guard passes. The generic door stays usable for
--     cricket, futsal and badminton, whose results the app still folds, and for
--     a padel build that has not been updated yet: such a call still succeeds,
--     and is stored with the server's strings.
--
-- Not touched on purpose:
--  * `headline`/`detail` stay the caller's text (0013's stated scope, and the
--    app's own wording is what members read on the review sheet);
--  * `correct_match_result` keeps the organizer's manual authority, because a
--    published padel result may legitimately be corrected after a walkover,
--    where the point log is empty by design;
--  * the scoring rules, the fold and the event log are unchanged.
--
-- Verified by supabase/tests/padel_result_authority_test.sql, which asserts the
-- two doors now agree on the same rows, and by the Dart side in
-- test/padel_result_authority_test.dart.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  The one builder of the per-side set strings
-- ════════════════════════════════════════════════════════════════════════════
-- ['A's own order', 'B's own order'] for the completed sets of the fold, in the
-- set order they were finished. Stable and definer-visible only: like the other
-- underscore helpers of 0013, it is revoked from every client role.

create or replace function public._padel_derived_scores(p_match_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_array(
           coalesce(string_agg((rec->>'a') || '-' || (rec->>'b'), ', '
                               order by (rec->>'index')::int), ''),
           coalesce(string_agg((rec->>'b') || '-' || (rec->>'a'), ', '
                               order by (rec->>'index')::int), '')
         )
    from jsonb_array_elements(
           coalesce(public._padel_fold_detail(p_match_id)->'sets', '[]'::jsonb)
         ) rec;
$$;

revoke all on function public._padel_derived_scores(uuid)
  from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  Both doors read the derived strings
-- ════════════════════════════════════════════════════════════════════════════
-- Bodies are 0013's, with the aggregation replaced by the helper (and, for the
-- generic door, the padel branch extended). Nothing else about either RPC
-- changes: same authorization, same lifecycle rules, same writes.

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

  v_scores := public._padel_derived_scores(p_match_id);

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
    -- 0020: the totals may not disagree with the log, and neither may the two
    -- strings every surface prints. Whatever arrived is replaced by what the
    -- fold says, in both reading orders, so this door derives exactly what
    -- complete_padel_match derives.
    p_side_scores := public._padel_derived_scores(p_match_id);
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

commit;
