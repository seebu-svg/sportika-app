-- Sportika team invitation repairs: consent for the picked, a voice for every
-- roster event, and a live roster.
--
-- Three defects surfaced by the 2026-11-16 team audit (create → invite →
-- answer), all latent on the hosted project — 0 teams, 0 members, 0 team
-- notifications live — so the repair is definitional, no data migration.
--
--  1. create_team inserted every p_member_ids pick as 'accepted'. The client
--     (create_team_screen) sends picks expecting invitations — its own comment
--     says "Members picked here have not answered yet, so they are invitations
--     rather than silent additions" — and then re-invites each one. Reproduced
--     on scratch: the pick lands accepted with no notification, the follow-up
--     invite_team_member keeps them accepted (its upsert case) while still
--     sending a "Team invitation" notification, and tapping accept aborts with
--     `no_team_invite` because respond_team_invite demands status='invited'.
--     Every invitation the screen generates is a dead end, and no picked
--     player ever consents. The rewrite makes the captain the only accepted
--     member and turns each pick into a real invitation under the SAME event
--     key invite_team_member uses (team_invite:<team>:<profile>), so the
--     screen's redundant follow-up dedupes to one inbox row while non-client
--     callers still get a complete invitation.
--
--  2. Every other roster event was silent: respond (accept/decline), remove,
--     leave, transfer and delete notified nobody. The device store already
--     announces all of these; the server now matches. Repeatable events (the
--     same person can join → leave → join) carry a stamped event key so each
--     occurrence delivers; the invitation key stays unstamped and stable —
--     decline deletes the member row but leaves the inbox copy, so a
--     re-invite dedupes to the invitation that already exists.
--
--  3. invite_team_member had no roster cap (create_team stops at 40, invite
--     was unbounded) and happily "re-invited" accepted members, which produced
--     the dead invitations above; it now raises already_accepted for an
--     accepted row and team_full at the cap.
--
-- Also closes the realtime gap: the supabase_realtime publication carried
-- teams but not team_members, so no device could watch a roster change.
--
-- Forward-only, like 0017/0018: 0015/0016/0017/0018 are not edited and
-- `migration repair` is not used. create or replace keeps the functions' oids
-- and grants (all seven stay granted to authenticated — they are the client
-- write surface); recorded statement hashes are unaffected.
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  create_team: picks are invitations, the captain is the only accepted
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.create_team(
  p_name       text,
  p_sport_key  text,
  p_type       text,
  p_member_ids uuid[] default '{}'::uuid[]
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_name    text := trim(coalesce(p_name, ''));
  v_members uuid[] := coalesce(p_member_ids, '{}'::uuid[]);
  v_member  uuid;
  v_id      text := 'team-' || replace(gen_random_uuid()::text, '-', '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_name) not between 2 and 60 then
    raise exception 'invalid_team_name' using errcode = '22023';
  end if;
  if not exists (select 1 from public.sports s where s.key = p_sport_key) then
    raise exception 'invalid_sport' using errcode = '22023';
  end if;
  if coalesce(p_type, 'team') not in ('individual', 'pair', 'team') then
    raise exception 'invalid_entry_type' using errcode = '22023';
  end if;

  v_members := (select array_agg(distinct m) from unnest(array_append(v_members, v_uid)) m);
  if cardinality(v_members) > 40 then
    raise exception 'invalid_team_members' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(v_members) m
     where not exists (select 1 from public.profiles p where p.id = m)
  ) then
    raise exception 'invalid_team_members' using errcode = '22023';
  end if;

  insert into public.teams (id, owner_id, name, sport_key, type)
  values (v_id, v_uid, v_name, p_sport_key, coalesce(p_type, 'team'));

  -- A fresh team cannot hold duplicate member rows (v_members is distinct),
  -- so the old upsert has nothing to conflict with. Picks hear the same
  -- team_invite notification invite_team_member sends, under the same event
  -- key, so a client that follow-up-invites every pick stays at one row.
  foreach v_member in array v_members loop
    insert into public.team_members (team_id, profile_id, status, invited_by)
    values (v_id, v_member,
            case when v_member = v_uid then 'accepted' else 'invited' end,
            v_uid);

    if v_member <> v_uid then
      perform public._notify(
        v_member, 'team', 'team_invite',
        'Team invitation',
        format('%s invited you to %s.', public._display_name(v_uid), v_name),
        'team', v_id,
        jsonb_build_object('teamId', v_id, 'tab', 3),
        v_uid,
        format('team_invite:%s:%s', v_id, v_member)
      );
    end if;
  end loop;

  return v_id;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  invite_team_member: no dead invitations, no unbounded roster
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.invite_team_member(
  p_team_id    text,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_team   public.teams;
  v_status public.team_members.status%type;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if v_team.owner_id <> v_uid then
    raise exception 'not_team_captain' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_profile_id) then
    raise exception 'player_not_found' using errcode = '22023';
  end if;

  select status into v_status
    from public.team_members
   where team_id = p_team_id and profile_id = p_profile_id;

  -- An accepted member is not a candidate for invitation; announcing one was
  -- the dead-invitation defect (the notify fired, the answer could not).
  if v_status = 'accepted' then
    raise exception 'already_accepted' using errcode = '23505';
  end if;

  if v_status is null then
    -- A fresh seat: the cap counts every row, held or pending.
    if (select count(*) from public.team_members
         where team_id = p_team_id) >= 40 then
      raise exception 'team_full' using errcode = '22023';
    end if;

    insert into public.team_members (team_id, profile_id, status, invited_by)
    values (p_team_id, p_profile_id, 'invited', v_uid);
  end if;

  -- Re-invites keep the pending row and dedupe to the inbox copy the first
  -- invite already left (same event key, existence check).
  perform public._notify(
    p_profile_id, 'team', 'team_invite',
    'Team invitation',
    format('%s invited you to %s.', public._display_name(v_uid), v_team.name),
    'team', p_team_id,
    jsonb_build_object('teamId', p_team_id, 'tab', 3),
    v_uid,
    format('team_invite:%s:%s', p_team_id, p_profile_id)
  );
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 3.  respond_team_invite: the captain hears the answer
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.respond_team_invite(
  p_team_id text,
  p_accept  boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_team  public.teams;
  v_stamp text := to_char(now() at time zone 'UTC', 'YYMMDDHH24MISSUS');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.team_members m
     where m.team_id = p_team_id and m.profile_id = v_uid and m.status = 'invited'
  ) then
    raise exception 'no_team_invite' using errcode = '22023';
  end if;

  if p_accept then
    update public.team_members
       set status = 'accepted'
     where team_id = p_team_id and profile_id = v_uid;

    perform public._notify(
      v_team.owner_id, 'team', 'team_member_joined',
      'Team member joined',
      format('%s accepted your invitation to %s.',
             public._display_name(v_uid), v_team.name),
      'team', p_team_id,
      jsonb_build_object('teamId', p_team_id, 'tab', 3),
      v_uid,
      format('team_joined:%s:%s:%s', p_team_id, v_uid, v_stamp)
    );
  else
    delete from public.team_members
     where team_id = p_team_id and profile_id = v_uid;

    perform public._notify(
      v_team.owner_id, 'team', 'team_invite_declined',
      'Invitation declined',
      format('%s declined the invitation to %s.',
             public._display_name(v_uid), v_team.name),
      'team', p_team_id,
      jsonb_build_object('teamId', p_team_id, 'tab', 3),
      v_uid,
      format('team_declined:%s:%s:%s', p_team_id, v_uid, v_stamp)
    );
  end if;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 4.  remove_team_member: the person removed or uninvited hears it
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.remove_team_member(
  p_team_id    text,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_team   public.teams;
  v_status public.team_members.status%type;
  v_stamp  text := to_char(now() at time zone 'UTC', 'YYMMDDHH24MISSUS');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if v_team.owner_id <> v_uid then
    raise exception 'not_team_captain' using errcode = '42501';
  end if;
  if p_profile_id = v_uid then
    raise exception 'captain_cannot_leave' using errcode = '22023';
  end if;

  select status into v_status
    from public.team_members
   where team_id = p_team_id and profile_id = p_profile_id;

  delete from public.team_members
   where team_id = p_team_id and profile_id = p_profile_id;

  -- Both removal flavours announce themselves; cancelSquadInvite lands here
  -- with an 'invited' row.
  if v_status = 'accepted' then
    perform public._notify(
      p_profile_id, 'team', 'team_member_removed',
      'Removed from team',
      format('%s removed you from %s.',
             public._display_name(v_uid), v_team.name),
      'team', p_team_id,
      jsonb_build_object('teamId', p_team_id, 'tab', 3),
      v_uid,
      format('team_removed:%s:%s:%s', p_team_id, p_profile_id, v_stamp)
    );
  elsif v_status = 'invited' then
    perform public._notify(
      p_profile_id, 'team', 'team_invite_cancelled',
      'Invitation withdrawn',
      format('%s withdrew your invitation to %s.',
             public._display_name(v_uid), v_team.name),
      'team', p_team_id,
      jsonb_build_object('teamId', p_team_id, 'tab', 3),
      v_uid,
      format('team_invite_cancelled:%s:%s:%s', p_team_id, p_profile_id, v_stamp)
    );
  end if;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 5.  leave_team: the captain hears who walked
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.leave_team(p_team_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_team  public.teams;
  v_stamp text := to_char(now() at time zone 'UTC', 'YYMMDDHH24MISSUS');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if v_team.owner_id = v_uid then
    raise exception 'captain_must_transfer' using errcode = '22023';
  end if;

  delete from public.team_members
   where team_id = p_team_id and profile_id = v_uid;

  perform public._notify(
    v_team.owner_id, 'team', 'team_member_left',
    'Left the team',
    format('%s left %s.', public._display_name(v_uid), v_team.name),
    'team', p_team_id,
    jsonb_build_object('teamId', p_team_id, 'tab', 3),
    v_uid,
    format('team_left:%s:%s:%s', p_team_id, v_uid, v_stamp)
  );
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 6.  transfer_team_captain: the incoming captain hears it
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.transfer_team_captain(
  p_team_id    text,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_team  public.teams;
  v_stamp text := to_char(now() at time zone 'UTC', 'YYMMDDHH24MISSUS');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = '22023';
  end if;
  if v_team.owner_id <> v_uid then
    raise exception 'not_team_captain' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.team_members m
     where m.team_id = p_team_id and m.profile_id = p_profile_id
       and m.status = 'accepted'
  ) then
    raise exception 'player_not_in_team' using errcode = '22023';
  end if;

  update public.teams set owner_id = p_profile_id where id = p_team_id;

  perform public._notify(
    p_profile_id, 'team', 'team_captain_changed',
    'You now captain the team',
    format('%s made you the captain of %s.',
           public._display_name(v_uid), v_team.name),
    'team', p_team_id,
    jsonb_build_object('teamId', p_team_id, 'tab', 3),
    v_uid,
    format('team_captain:%s:%s:%s', p_team_id, p_profile_id, v_stamp)
  );
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 7.  delete_team: accepted members hear the squad is gone
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.delete_team(p_team_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_team  public.teams;
  v_row   record;
  v_stamp text := to_char(now() at time zone 'UTC', 'YYMMDDHH24MISSUS');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_team from public.teams where id = p_team_id;
  if v_team.id is null then
    return;
  end if;
  if v_team.owner_id <> v_uid then
    raise exception 'not_team_captain' using errcode = '42501';
  end if;

  -- The cascade takes the member rows; announce before it fires. Invited
  -- members are skipped: their inbox already holds the invitation, and the
  -- squad they never joined going away is not roster news.
  for v_row in
    select profile_id
      from public.team_members
     where team_id = p_team_id and status = 'accepted'
       and profile_id <> v_uid
  loop
    perform public._notify(
      v_row.profile_id, 'team', 'team_deleted',
      'Team deleted',
      format('%s deleted %s.', public._display_name(v_uid), v_team.name),
      'team', p_team_id,
      jsonb_build_object('teamId', p_team_id, 'tab', 3),
      v_uid,
      format('team_deleted:%s:%s:%s', p_team_id, v_row.profile_id, v_stamp)
    );
  end loop;

  delete from public.teams where id = p_team_id;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 8.  Realtime: let devices watch the roster
-- ════════════════════════════════════════════════════════════════════════════

-- The publication carried teams but not team_members, so invites, answers and
-- removals never reached a second device. Realtime respects RLS (SELECT is
-- `using (true)` for authenticated), the same guarantee the discovery cards
-- already rely on.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'team_members'
    ) then
alter publication supabase_realtime add table public.team_members;
    end if;
  end if;
end $$;

commit;
