-- Sportika tournament notification repairs: the trigger bodies 0017 re-attached.
--
-- Two defects surfaced by the 2026-11-16 tournament audit:
--
--  1. 0015 wrote notify_tournament_entry_change() against an aggregate that
--     never existed in this chain (public.tournaments with created_by,
--     tournament_entries with user_id and an 'approved' status). On the hosted
--     project those functions attached to the pre-repo tables, which 0016 then
--     moved to schema legacy together with their triggers, leaving the NEW
--     discovery family trigger-less: registration worked, silently without
--     notifications. 0017 then recreated the triggers on the new tables —
--     still with the old bodies. Reproduced on scratch:
--     register_tournament_entry aborts with `record "v_t" has no field
--     "created_by"`; a rejection or withdrawal aborts with `record "new" has
--     no field "user_id"`. Only an approval passes, because the new status
--     vocabulary ('confirmed') matches none of the old branches. This file
--     replaces the body: the organizer hears about registrations and
--     withdrawals, the RPC keeps announcing approvals and rejections, and the
--     event keys stay disjoint so nothing double-sends.
--
--  2. notify_tournament_change() is dead-but-armed: its branches fire only for
--     'cancelled' / 'draw_created', statuses the 0016 vocabulary
--     ('draft','open','inProgress','completed') can never hold, and they read
--     e.user_id. Worse, the one status change members care about on the draw
--     path — generate_tournament_draw flips the tournament to 'inProgress'
--     with a bare UPDATE — announced nobody. The replacement notifies
--     confirmed captains on 'inProgress' (sharing set_tournament_status's
--     tournament_started event key, so the RPC path and the draw path
--     deduplicate to one notification) and on 'completed', and keeps the
--     registration-date branch with the current column and status names.
--
-- Forward-only, like 0017: 0015/0016/0017 are not edited and `migration
-- repair` is not used. create or replace keeps the functions' oids, so the
-- triggers 0017 installed stay attached untouched; recorded statement hashes
-- are unaffected.
--
-- registration_closes_at stays server-set: nothing in the client or the RPCs
-- writes it, so the schedule-change branch arms only once an organizer populates
-- it (the dispatch pass in 0017 already reads it the same way).
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  Entry lifecycle: the organizer learns what no RPC announces
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.notify_tournament_entry_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t record;
begin
  select * into v_t from public.tournaments where id = new.tournament_id;
  if v_t.id is null then
    return null;
  end if;

  -- A fresh registration is news for the organizer, not for the entrant.
  if tg_op = 'INSERT' then
    if new.status = 'pending' then
      perform public._notify(
        v_t.organizer_id, 'tournament', 'tournament_registration_received',
        'New tournament registration',
        format('%s registered for %s.',
               public._display_name(new.captain_id), v_t.name),
        'tournament', v_t.id::text,
        jsonb_build_object('tournamentId', v_t.id, 'entryId', new.id, 'tab', 1),
        new.captain_id,
        format('tournament_entry_new:%s', new.id)
      );
    end if;
    return null;
  end if;

  if new.status is not distinct from old.status then
    return null;
  end if;

  -- Approvals and rejections are announced by decide_tournament_entry itself
  -- (key tournament_entry:<entry id>:<status>). The trigger adds only what no
  -- RPC announces, so a captain is never told twice.
  if new.status = 'withdrawn' then
    perform public._notify(
      v_t.organizer_id, 'tournament', 'tournament_entry_withdrawn',
      'Entry withdrawn',
      format('%s withdrew from %s.',
             public._display_name(new.captain_id), v_t.name),
      'tournament', v_t.id::text,
      jsonb_build_object('tournamentId', v_t.id, 'entryId', new.id, 'tab', 1),
      auth.uid(),
      format('tournament_entry_withdrawn:%s', new.id)
    );
  end if;

  return null;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  Tournament status: one notification per captain, whichever path fires
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.notify_tournament_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row   record;
  v_stamp text := to_char(now() at time zone 'UTC', 'YYMMDDHH24MISSUS');
begin
  -- The RPC (set_tournament_status) and the draw (a bare UPDATE to
  -- 'inProgress') share this event key, so a member is told once no matter
  -- which path ran first.
  if new.status is distinct from old.status
     and new.status = 'inProgress' then
    for v_row in
      select e.id, e.captain_id
        from public.tournament_entries e
       where e.tournament_id = new.id
         and e.status = 'confirmed'
    loop
      perform public._notify(
        v_row.captain_id, 'tournament', 'tournament_started',
        'Tournament is under way',
        format('%s has started.', new.name),
        'tournament', new.id::text,
        jsonb_build_object('tournamentId', new.id, 'tab', 1),
        auth.uid(),
        format('tournament_started:%s:%s', new.id, v_row.id)
      );
    end loop;
  end if;

  if new.status is distinct from old.status
     and new.status = 'completed' then
    for v_row in
      select e.id, e.captain_id
        from public.tournament_entries e
       where e.tournament_id = new.id
         and e.status = 'confirmed'
    loop
      perform public._notify(
        v_row.captain_id, 'tournament', 'tournament_completed',
        'Tournament completed',
        format('%s has finished; the results are in.', new.name),
        'tournament', new.id::text,
        jsonb_build_object('tournamentId', new.id, 'tab', 1),
        auth.uid(),
        format('tournament_completed:%s:%s', new.id, v_row.id)
      );
    end loop;
  end if;

  -- Registration dates moved: tell members still in the running.
  if new.registration_closes_at is distinct from old.registration_closes_at then
    for v_row in
      select distinct e.captain_id
        from public.tournament_entries e
       where e.tournament_id = new.id
         and e.status in ('pending', 'confirmed')
    loop
      perform public._notify(
        v_row.captain_id, 'tournament', 'tournament_schedule_changed',
        'Tournament schedule changed',
        format('Registration dates for %s changed.', new.name),
        'tournament', new.id::text,
        jsonb_build_object('tournamentId', new.id, 'tab', 1),
        auth.uid(),
        format('tournament_schedule:%s:%s:%s', new.id, v_row.captain_id, v_stamp)
      );
    end loop;
  end if;

  return null;
end;
$$;

-- Trigger invocation needs no EXECUTE privilege; the revoke keeps the notify
-- functions from being called directly, mirroring 0015.
revoke all on function public.notify_tournament_entry_change()
  from public, anon, authenticated;
revoke all on function public.notify_tournament_change()
  from public, anon, authenticated;

commit;
