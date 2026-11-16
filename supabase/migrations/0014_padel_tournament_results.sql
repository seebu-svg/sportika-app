-- Sportika padel backend, part 3: the tournament seam, results and disputes.
--
-- 0008 let any authenticated member create a match with any tournament_id and
-- any fixture_id, and exposed match_of_fixture as a security-definer read with
-- no visibility filter, so a guessed pair of text ids returned an invite-only
-- match. 0006 already owns the two pieces the tournament boundary needs -
-- match_organizer_claims and official_scorer_assignments - so this migration
-- wires them in instead of inventing a parallel structure:
--
--   * create_match v3 refuses a fixture link the caller has not claimed.
--   * assign_fixture_scorer / revoke_fixture_scorer are the tournament-facing
--     names; they reuse official_scorer_assignments and mirror the decision onto
--     matches.scorer_id when the fixture already has a match, so the existing
--     per-match authorization path keeps working unchanged.
--   * published_fixture_results is the read the organizer's device needs to draw
--     a bracket and advance a winner. It is deliberately a read: the draw itself
--     remains device-local in this MVP, so there is no server bracket to update.
--   * raise_match_dispute / resolve_match_dispute close the loop on a result.
--
-- No payment or entitlement check appears anywhere here: scoring, publishing a
-- result and disputing one are free by product decision.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  create_match – only the tournament's claim owner may generate a fixture
-- ════════════════════════════════════════════════════════════════════════════
-- Same fourteen-argument signature as 0008, so no client changes. The added
-- guards are the tournament claim and the duplicate-fixture mapping; every
-- other validation is byte-for-byte what 0008 enforced.

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
  if v_tournament is not null and char_length(v_tournament) > 80 then
    raise exception 'invalid_tournament_id' using errcode = '22023';
  end if;
  if v_fixture is not null and char_length(v_fixture) > 80 then
    raise exception 'invalid_fixture_id' using errcode = '22023';
  end if;

  -- A fixture belongs to a tournament, and a tournament belongs to the member
  -- who claimed it (0006). Linking a match to somebody else's tournament would
  -- otherwise let any member publish results into another organizer's draw.
  if v_tournament is not null then
    if not exists (
      select 1 from public.match_organizer_claims c
       where c.tournament_id = v_tournament
         and c.organizer_id  = v_uid
    ) then
      raise exception 'not_tournament_organizer' using errcode = '42501';
    end if;

    if exists (
      select 1 from public.matches m
       where m.tournament_id = v_tournament
         and m.fixture_id    = v_fixture
    ) then
      raise exception 'fixture_already_linked' using errcode = '23505';
    end if;
  end if;

  v_rules := v_rules || jsonb_build_object('discipline', v_disc);

  begin
    insert into public.matches
      (sport_key, format_label, rules, title, venue, scheduled_at, visibility,
       organizer_id, scorer_id, side_a_name, side_b_name, discipline, capacity,
       tournament_id, fixture_id)
    values
      (v_sport, v_format, v_rules, v_title, v_venue, p_scheduled_at, v_vis,
       v_uid, p_scorer_id, v_a, v_b, v_disc, p_capacity,
       v_tournament, v_fixture)
    returning * into v_row;
  exception
    -- Two taps on "generate fixture" can pass the check above concurrently; the
    -- partial unique index is the real arbiter, and its error is translated so
    -- the app sees one stable code instead of a constraint name.
    when unique_violation then
      raise exception 'fixture_already_linked' using errcode = '23505';
  end;

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

revoke all on function public.create_match(
  text, text, jsonb, text, text, timestamptz, text,
  text, text, int, text, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.create_match(
  text, text, jsonb, text, text, timestamptz, text,
  text, text, int, text, uuid, text, text
) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  Fixture scorer assignment
-- ════════════════════════════════════════════════════════════════════════════
-- 0006's assign_official_scorer is keyed by tournament/fixture text ids and
-- predates matches. These two wrappers add the thing a tournament draw needs:
-- when the fixture already has a match, the assignment is mirrored onto
-- matches.scorer_id so can_score_match, the lifecycle bar and the Flutter
-- "you are scoring" path all agree without a second lookup.

create or replace function public.assign_fixture_scorer(
  p_tournament_id text,
  p_fixture_id    text,
  p_scorer_id     uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_row      public.official_scorer_assignments;
  v_match_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Re-checks its own tournament claim; raises not_match_organizer.
  v_row := public.assign_official_scorer(p_tournament_id, p_fixture_id, p_scorer_id);

  update public.matches
     set scorer_id = p_scorer_id
   where tournament_id = p_tournament_id
     and fixture_id    = p_fixture_id
  returning id into v_match_id;

  -- The fixture may not have a match yet; only a linked match gets an entry.
  if v_match_id is not null then
    perform public.log_match_action(
      v_match_id, v_uid, 'scorer_assigned',
      jsonb_build_object(
        'scorer_id',     p_scorer_id,
        'tournament_id', p_tournament_id,
        'fixture_id',    p_fixture_id,
        'source',        'fixture'
      )
    );
  end if;

  return jsonb_build_object(
    'assignment', to_jsonb(v_row),
    'matchId',    v_match_id
  );
end;
$$;

create or replace function public.revoke_fixture_scorer(
  p_tournament_id text,
  p_fixture_id    text,
  p_scorer_id     uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_match_id uuid;
  v_cleared  uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.match_organizer_claims c
     where c.tournament_id = trim(coalesce(p_tournament_id, ''))
       and c.organizer_id  = v_uid
  ) then
    raise exception 'not_match_organizer' using errcode = '42501';
  end if;

  perform public.revoke_official_scorer(p_fixture_id, p_scorer_id);

  -- Only clear the mirror when it still points at the scorer being revoked: an
  -- organizer may have replaced the match scorer directly since the assignment.
  update public.matches
     set scorer_id = null
   where tournament_id = p_tournament_id
     and fixture_id    = p_fixture_id
     and scorer_id     = p_scorer_id
  returning id into v_match_id;

  select id into v_cleared from public.matches
   where tournament_id = p_tournament_id
     and fixture_id    = p_fixture_id;

  if coalesce(v_match_id, v_cleared) is not null then
    perform public.log_match_action(
      coalesce(v_match_id, v_cleared), v_uid, 'scorer_revoked',
      jsonb_build_object(
        'scorer_id',     p_scorer_id,
        'tournament_id', p_tournament_id,
        'fixture_id',    p_fixture_id,
        'source',        'fixture'
      )
    );
  end if;

  return jsonb_build_object(
    'matchId', coalesce(v_match_id, v_cleared),
    'revoked', p_scorer_id
  );
end;
$$;

revoke all on function public.assign_fixture_scorer(text, text, uuid)
  from public, anon, authenticated;
revoke all on function public.revoke_fixture_scorer(text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.assign_fixture_scorer(text, text, uuid) to authenticated;
grant execute on function public.revoke_fixture_scorer(text, text, uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  Published results, keyed by fixture
-- ════════════════════════════════════════════════════════════════════════════
-- The organizer's device owns the draw (0006 documents this MVP boundary), so
-- the server's job is to hand back the official result for each fixture it has
-- one for, and to refuse anything the caller could not read directly.

create or replace function public.published_fixture_results(p_tournament_id text)
returns table (
  fixture_id    text,
  match_id      uuid,
  winner_side   int,
  side_scores   jsonb,
  side_values   jsonb,
  headline      text,
  published_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_tid text := nullif(trim(coalesce(p_tournament_id, '')), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_tid is null or char_length(v_tid) > 80 then
    raise exception 'invalid_tournament_id' using errcode = '22023';
  end if;

  return query
    select m.fixture_id,
           m.id,
           r.winner_index,
           r.side_scores,
           r.side_values,
           r.headline,
           coalesce(m.published_at, r.published_at)
      from public.matches m
      join public.match_results r on r.match_id = m.id
     where m.tournament_id = v_tid
       and m.fixture_id   is not null
       and m.status       in ('published', 'walkover')
       and public.can_view_match(m.id)
     order by m.fixture_id;
end;
$$;

revoke all on function public.published_fixture_results(text)
  from public, anon, authenticated;
grant execute on function public.published_fixture_results(text) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 4.  Result disputes
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.raise_match_dispute(
  p_match_id uuid,
  p_reason   text
)
returns public.match_disputes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_match  public.matches;
  v_reason text := trim(coalesce(p_reason, ''));
  v_row    public.match_disputes;
  v_allowed boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if v_match.id is null then
    raise exception 'match_not_found' using errcode = 'P0002';
  end if;
  if not public.can_view_match(p_match_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  -- There is nothing to dispute before a result exists.
  if not exists (select 1 from public.match_results r where r.match_id = p_match_id) then
    raise exception 'no_result_to_dispute' using errcode = '22023';
  end if;

  if char_length(v_reason) not between 5 and 500 then
    raise exception 'invalid_dispute_reason' using errcode = '22023';
  end if;

  -- Organizer, scoring staff, an accepted/invited participant, or the owner of
  -- the tournament this fixture belongs to. Not a passing spectator.
  v_allowed := v_match.organizer_id = v_uid
            or v_match.scorer_id    = v_uid
            or public.can_score_match(p_match_id, v_uid)
            or exists (
                 select 1 from public.match_participants p
                  where p.match_id  = p_match_id
                    and p.profile_id = v_uid
                    and p.status in ('invited', 'accepted')
               )
            or (v_match.tournament_id is not null and exists (
                 select 1 from public.match_organizer_claims c
                  where c.tournament_id = v_match.tournament_id
                    and c.organizer_id  = v_uid
               ));

  if not v_allowed then
    raise exception 'not_match_stakeholder' using errcode = '42501';
  end if;

  begin
    insert into public.match_disputes (match_id, raised_by, reason)
    values (p_match_id, v_uid, v_reason)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'dispute_already_open' using errcode = '23505';
  end;

  perform public.log_match_action(
    p_match_id, v_uid, 'dispute_raised',
    jsonb_build_object('dispute_id', v_row.id, 'reason', v_reason)
  );

  return v_row;
end;
$$;

create or replace function public.resolve_match_dispute(
  p_dispute_id uuid,
  p_resolution text,
  p_status     text
)
returns public.match_disputes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_dispute public.match_disputes;
  v_match  public.matches;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_res    text := nullif(trim(coalesce(p_resolution, '')), '');
  v_row    public.match_disputes;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_dispute from public.match_disputes where id = p_dispute_id for update;
  if v_dispute.id is null then
    raise exception 'dispute_not_found' using errcode = 'P0002';
  end if;

  select * into v_match from public.matches where id = v_dispute.match_id for update;

  -- The organizer answers; the tournament claim owner may also answer, because
  -- a fixture's dispute is a tournament matter.
  if not (
    v_match.organizer_id = v_uid
    or (v_match.tournament_id is not null and exists (
         select 1 from public.match_organizer_claims c
          where c.tournament_id = v_match.tournament_id
            and c.organizer_id  = v_uid
       ))
  ) then
    raise exception 'not_match_organizer' using errcode = '42501';
  end if;

  if v_status not in ('under_review', 'resolved', 'rejected') then
    raise exception 'invalid_dispute_status' using errcode = '22023';
  end if;
  if v_status in ('resolved', 'rejected')
     and (v_res is null or char_length(v_res) not between 3 and 500) then
    raise exception 'invalid_dispute_resolution' using errcode = '22023';
  end if;
  if v_status = 'under_review' and v_res is not null then
    raise exception 'invalid_dispute_resolution' using errcode = '22023';
  end if;
  if v_dispute.status in ('resolved', 'rejected') then
    raise exception 'dispute_already_closed' using errcode = '22023';
  end if;

  update public.match_disputes
     set status      = v_status,
         resolution  = v_res,
         resolved_by = v_uid,
         resolved_at = case when v_status in ('resolved', 'rejected') then now() end
   where id = p_dispute_id
  returning * into v_row;

  perform public.log_match_action(
    v_dispute.match_id, v_uid, 'dispute_' || v_status,
    jsonb_build_object('dispute_id', p_dispute_id, 'resolution', v_res)
  );

  return v_row;
end;
$$;

revoke all on function public.raise_match_dispute(uuid, text)
  from public, anon, authenticated;
revoke all on function public.resolve_match_dispute(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.raise_match_dispute(uuid, text) to authenticated;
grant execute on function public.resolve_match_dispute(uuid, text, text) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  match_of_fixture no longer bypasses RLS
-- ════════════════════════════════════════════════════════════════════════════
-- 0008 defined this security definer with no visibility filter, so any member
-- who guessed a tournament/fixture pair could read an invite-only match. The
-- predicate is evaluated as the definer, so it must be applied inside the body.
-- A composite-returning function cannot yield zero rows from SQL, so the
-- contract is "the id is null when the caller may not see the fixture"; callers
-- must test the id, not the row count.

create or replace function public.match_of_fixture(
  p_tournament_id text,
  p_fixture_id    text
)
returns public.matches
language sql stable
security definer
set search_path = public
as $$
  select m.*
    from public.matches m
   where m.tournament_id = p_tournament_id
     and m.fixture_id    = p_fixture_id
     and public.can_view_match(m.id)
   limit 1;
$$;

revoke all on function public.match_of_fixture(text, text)
  from public, anon, authenticated;
grant execute on function public.match_of_fixture(text, text) to authenticated;

commit;
