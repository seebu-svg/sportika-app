-- Sportika match-backend repairs: a convergent follow-up to 0012, 0013 and 0015.
--
-- Three defects surfaced by the 2026-11-16 backend audit:
--
--  1. 0015_notifications.sql was written against a `public.tournaments` shape
--     that did not exist at its point in the chain (0016 creates tournaments,
--     and without a registration_closes_at column). The four tournament notify
--     triggers were therefore silently skipped on first apply, and
--     dispatch_due_notifications() — the function the pg_cron job
--     sportika_due_notifications calls every five minutes — selects
--     t.registration_closes_at, so it raised `column does not exist` on every
--     run and due notifications never dispatched. This file adds the column
--     and recreates the two triggers whose tables live in `public` (entry and
--     tournament status). The fixture and staff triggers stay guarded no-ops
--     on purpose: their tables (tournament_matches, tournament_staff) exist
--     only in the legacy schema 0016 parked them in, and fixture results
--     already notify through notify_match_change on public.matches.
--
--  2. 0012 and 0013 were edited AFTER their successful push, so two live
--     function bodies are stale: guard_match_event_write refuses DELETE for
--     every role (any cascading delete of a match or a user aborts with
--     match_events_are_immutable), and award_padel_point derives its
--     deduplicated flag from a pre-lock count. This file replaces both bodies
--     with the current file content. Forward-only on purpose: the recorded
--     statements hashes for 0012/0013 intentionally remain stale, and
--     `migration repair` is not used.
--
--  3. Roster changes never reached watchers: match_participants was missing
--     from the supabase_realtime publication, so a second device only saw an
--     invite/accept after a manual refresh.
--
-- Scope note: the intentionally dormant RPC surface is documented in
-- docs/MATCH_MODULE.md and unchanged here — the nine padel RPCs
-- (award_padel_point, configure_padel_match, start_padel_match,
-- complete_padel_match, undo_last_padel_point, correct_padel_event,
-- reopen_padel_match, get_padel_scoreboard, get_padel_point_history) stay
-- granted as a server-verified verification/admin surface behind the
-- record_match_event front door, and publish_tournament / set_tournament_status
-- remain server-only.
--
-- Replay note: on a database populated BEFORE this file exists, replaying
-- 0015 alone still fails at its notify_tournament_change trigger, because the
-- column only appears later in the chain (here). Apply 0017 once first; every
-- replay after that, fresh or two-pass, is clean.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  The column 0015 assumed
-- ════════════════════════════════════════════════════════════════════════════

alter table public.tournaments
  add column if not exists registration_closes_at timestamptz;

comment on column public.tournaments.registration_closes_at is
  'When entries stop being accepted; the due-notification pass warns entrants 24 hours ahead. NULL keeps registration open until the tournament starts.';

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  The tournament notify triggers 0015 could never create (DDL from 0015)
-- ════════════════════════════════════════════════════════════════════════════

do $$
begin
  if to_regclass('public.tournament_entries') is not null then
    execute 'drop trigger if exists notify_tournament_entry_change
               on public.tournament_entries';
    execute 'create trigger notify_tournament_entry_change
               after insert or update of status on public.tournament_entries
               for each row
               execute function public.notify_tournament_entry_change()';
  end if;

  if to_regclass('public.tournaments') is not null then
    execute 'drop trigger if exists notify_tournament_change
               on public.tournaments';
    execute 'create trigger notify_tournament_change
               after update of status, registration_closes_at
               on public.tournaments
               for each row execute function public.notify_tournament_change()';
  end if;

  if to_regclass('public.tournament_staff') is not null then
    execute 'drop trigger if exists notify_tournament_staff_change
               on public.tournament_staff';
    execute 'create trigger notify_tournament_staff_change
               after insert on public.tournament_staff
               for each row
               execute function public.notify_tournament_staff_change()';
  end if;
  -- Two blocks are expected to stay skipped here: notify_tournament_fixture_change
  -- (its table, public.tournament_matches, was parked in the legacy schema by
  -- 0016; fixture results already notify through notify_match_change on
  -- public.matches) and notify_tournament_staff_change (public.tournament_staff
  -- does not exist either — 0016 created no staff table, so staff notifications
  -- have no source until one is designed). Both guards make this file a no-op
  -- rather than an error until those tables exist.
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  The two drifted function bodies, replaced forward-only (DDL from 0012/0013)
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.guard_match_event_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Deletion is the backend's own cleanup path (an admin purge, a match delete
  -- cascading, an account removal taking profiles with it), so it is refused
  -- for the two roles a client request can ever run as and allowed for the
  -- service/database roles. Rewriting history is refused for everybody.
  if tg_op = 'DELETE' then
    if current_user in ('anon', 'authenticated') then
      raise exception 'match_events_are_immutable' using errcode = '42501';
    end if;
    return old;
  end if;

  if new.match_id        is distinct from old.match_id
     or new.seq          is distinct from old.seq
     or new.client_event_id is distinct from old.client_event_id
     or new.kind         is distinct from old.kind
     or new.side         is distinct from old.side
     or new.data         is distinct from old.data
     or new.recorded_by  is distinct from old.recorded_by
     or new.recorded_at  is distinct from old.recorded_at then
    raise exception 'match_events_are_immutable' using errcode = '42501';
  end if;

  if old.voided and not new.voided then
    raise exception 'match_event_cannot_be_restored' using errcode = '42501';
  end if;

  if new.voided and not old.voided then
    new.voided_at := coalesce(new.voided_at, now());
  end if;

  return new;
end;
$$;

revoke all on function public.guard_match_event_write()
  from public, anon, authenticated;

drop trigger if exists match_events_guard on public.match_events;
create trigger match_events_guard
  before update or delete on public.match_events
  for each row execute function public.guard_match_event_write();

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

-- ── 3b. The due-notification pass itself ──
-- 0015 wrote the registration-closing branch against the OLD tournament
-- vocabulary (tournaments.registration_closes_at, entries.user_id, status
-- 'approved'). The first two made every cron run fail outright; the third
-- would have filtered every entry out silently. 0016's shape is
-- tournament_entries.captain_id with status pending/confirmed, so the branch
-- is re-targeted here. The match-starting branch is unchanged from 0015.
create or replace function public.dispatch_due_notifications()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row   record;
  v_count int := 0;
begin
  -- A match starting inside the next hour: players, organizer and scorer.
  for v_row in
    select m.id,
           m.title,
           m.scheduled_at,
           r.recipient_id,
           bool_or(r.recipient_id = m.scorer_id) as scoring
      from public.matches m
      cross join lateral public._match_recipients(m.id) r
     where m.status = 'upcoming'
       and m.scheduled_at > now()
       and m.scheduled_at <= now() + interval '60 minutes'
     group by m.id, m.title, m.scheduled_at, r.recipient_id
  loop
    if public._notify(
         v_row.recipient_id,
         case when v_row.scoring then 'scorer' else 'match' end,
         'match_starting_soon',
         case when v_row.scoring then 'Scoring duty starts soon'
              else 'Match starting soon' end,
         case when v_row.scoring
              then format('You are scoring %s, and it starts within the hour.',
                          v_row.title)
              else format('%s starts within the hour.', v_row.title)
         end,
         'match', v_row.id::text,
         jsonb_build_object('matchId', v_row.id, 'tab', 2),
         null,
         format('match_soon:%s:%s', v_row.id, v_row.recipient_id)
       ) is not null then
      v_count := v_count + 1;
    end if;
  end loop;

  -- Registration closing within the next day, for the captain of every entry
  -- still in play. 0016's entries carry a captain (uuid) and a status of
  -- pending/confirmed, not the user_id/approved pair 0015 assumed.
  if to_regclass('public.tournaments') is not null
     and to_regclass('public.tournament_entries') is not null then
    for v_row in
      select t.id, t.name, e.captain_id as user_id
        from public.tournaments t
        join public.tournament_entries e on e.tournament_id = t.id
       where t.status = 'registration_open'
         and t.registration_closes_at is not null
         and t.registration_closes_at > now()
         and t.registration_closes_at <= now() + interval '24 hours'
         and e.status in ('pending', 'confirmed')
    loop
      if public._notify(
           v_row.user_id, 'tournament', 'tournament_registration_closing',
           'Registration closes soon',
           format('Registration for %s closes within a day.', v_row.name),
           'tournament', v_row.id::text,
           jsonb_build_object('tournamentId', v_row.id, 'tab', 1),
           null,
           format('tournament_closing:%s:%s', v_row.id, v_row.user_id)
         ) is not null then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;

  -- The 0015 scorer-duty branch stays guarded on public.tournament_matches,
  -- which lives in legacy, so it keeps contributing nothing until that table
  -- is redesigned — same stance as the trigger blocks above.
  if to_regclass('public.tournament_matches') is not null then
    for v_row in
      select tm.id, t.name, tm.scorer_user_id
        from public.tournament_matches tm
        join public.tournaments t on t.id = tm.tournament_id
       where tm.status = 'scheduled'
         and tm.scorer_user_id is not null
         and tm.created_at <= now() + interval '24 hours'
    loop
      if public._notify(
           v_row.scorer_user_id, 'scorer', 'scorer_duty_reminder',
           'Upcoming scoring duty',
           format('You have a scheduled fixture to score at %s.', v_row.name),
           'fixture', v_row.id::text,
           jsonb_build_object('tournamentId', v_row.id, 'fixtureId', v_row.id,
                              'tab', 2),
           null,
           format('scorer_duty:%s', v_row.id)
         ) is not null then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;

  return v_count;
end;
$$;

revoke all on function public.dispatch_due_notifications()
  from public, anon, authenticated;
grant execute on function public.dispatch_due_notifications() to service_role;

-- ════════════════════════════════════════════════════════════════════════════
-- 4.  Realtime roster
-- ════════════════════════════════════════════════════════════════════════════

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'match_participants'
    ) then
      alter publication supabase_realtime add table public.match_participants;
    end if;
  end if;
end;
$$;

commit;
