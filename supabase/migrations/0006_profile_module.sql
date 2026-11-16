-- Sportika profile module, part 1: granular profile writes and official scorers.
--
-- `complete_profile_setup` is all-or-nothing because it finishes onboarding.
-- The Me module edits one section at a time, so each section gets its own
-- security-definer function that derives the subject from auth.uid() and takes
-- no profile id. The client can never name the row it writes.
--
-- The tournament catalogue is still device-local in this MVP, so the server
-- cannot inspect a draw to learn who organized it. It can record the claim and
-- make every scorer assignment depend on that claim: a tournament id can be
-- claimed once, and only the claimant may assign or revoke a scorer for its
-- matches. A second member therefore cannot take over another organizer's
-- match even from a modified client.
begin;

-- ── organizer claims ────────────────────────────────────────────────────────
create table if not exists public.match_organizer_claims (
  tournament_id text primary key,
  organizer_id  uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now()
);

alter table public.match_organizer_claims enable row level security;
revoke all on public.match_organizer_claims from public, anon, authenticated;
grant select on public.match_organizer_claims to authenticated;

drop policy if exists organizer_claims_select_self on public.match_organizer_claims;
create policy organizer_claims_select_self on public.match_organizer_claims
  for select to authenticated
  using (organizer_id = (select auth.uid()));

create index if not exists organizer_claims_owner
  on public.match_organizer_claims (organizer_id);

create or replace function public.claim_tournament_organizer(p_tournament_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id  text := trim(coalesce(p_tournament_id, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_id) not between 1 and 120 then
    raise exception 'invalid_tournament' using errcode = '22023';
  end if;

  -- First writer wins. A conflicting claim is a refusal, never a takeover.
  insert into public.match_organizer_claims (tournament_id, organizer_id)
  values (v_id, v_uid)
  on conflict (tournament_id) do nothing;

  if not exists (
    select 1 from public.match_organizer_claims
     where tournament_id = v_id and organizer_id = v_uid
  ) then
    raise exception 'tournament_already_claimed' using errcode = '42501';
  end if;
end;
$$;

-- ── official scorer assignments ─────────────────────────────────────────────
-- One row per (match, scorer). `authorized_by` is the organizer who made the
-- call; the scorer sees their own assignments, the organizer sees the ones they
-- created, and nobody else sees either.
create table if not exists public.official_scorer_assignments (
  id                uuid primary key default gen_random_uuid(),
  tournament_id     text not null,
  fixture_id        text not null,
  scorer_profile_id uuid not null references public.profiles (id) on delete cascade,
  authorized_by     uuid not null references public.profiles (id) on delete cascade,
  status            text not null default 'assigned',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint scorer_assignment_unique unique (fixture_id, scorer_profile_id),
  constraint scorer_assignment_status
    check (status in ('assigned', 'accepted', 'declined', 'revoked')),
  constraint scorer_assignment_ids
    check (char_length(tournament_id) between 1 and 120
           and char_length(fixture_id) between 1 and 120)
);

alter table public.official_scorer_assignments enable row level security;
-- Reads are user-scoped. There is deliberately no insert/update/delete grant:
-- every write goes through the functions below, which re-check the claim.
revoke all on public.official_scorer_assignments from public, anon, authenticated;
grant select on public.official_scorer_assignments to authenticated;

drop policy if exists scorer_assignments_select_self on public.official_scorer_assignments;
create policy scorer_assignments_select_self on public.official_scorer_assignments
  for select to authenticated
  using (
    scorer_profile_id = (select auth.uid())
    or authorized_by = (select auth.uid())
  );

create index if not exists scorer_assignments_scorer
  on public.official_scorer_assignments (scorer_profile_id, created_at desc);
create index if not exists scorer_assignments_tournament
  on public.official_scorer_assignments (tournament_id);

drop trigger if exists scorer_assignments_touch on public.official_scorer_assignments;
create trigger scorer_assignments_touch
  before update on public.official_scorer_assignments
  for each row execute function public.touch_updated_at();

create or replace function public.assign_official_scorer(
  p_tournament_id text,
  p_fixture_id    text,
  p_scorer_id     uuid
)
returns public.official_scorer_assignments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_tid   text := trim(coalesce(p_tournament_id, ''));
  v_fid   text := trim(coalesce(p_fixture_id, ''));
  v_owner uuid;
  v_row   public.official_scorer_assignments;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_tid) not between 1 and 120
     or char_length(v_fid) not between 1 and 120
     or p_scorer_id is null then
    raise exception 'invalid_assignment' using errcode = '22023';
  end if;

  select organizer_id into v_owner
    from public.match_organizer_claims
   where tournament_id = v_tid;

  if v_owner is null or v_owner <> v_uid then
    raise exception 'not_match_organizer' using errcode = '42501';
  end if;

  if not exists (select 1 from public.profiles where id = p_scorer_id) then
    raise exception 'scorer_not_found' using errcode = '22023';
  end if;

  insert into public.official_scorer_assignments
    (tournament_id, fixture_id, scorer_profile_id, authorized_by)
  values (v_tid, v_fid, p_scorer_id, v_uid)
  on conflict (fixture_id, scorer_profile_id) do update
     set status        = 'assigned',
         tournament_id = excluded.tournament_id,
         authorized_by = excluded.authorized_by,
         updated_at    = now()
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function public.revoke_official_scorer(
  p_fixture_id text,
  p_scorer_id  uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fid text := trim(coalesce(p_fixture_id, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  update public.official_scorer_assignments
     set status = 'revoked'
   where fixture_id = v_fid
     and scorer_profile_id = p_scorer_id
     and authorized_by = v_uid;

  if not found then
    raise exception 'not_assignment_owner' using errcode = '42501';
  end if;
end;
$$;

-- Accepting or declining belongs to the scorer, not the organizer, so it cannot
-- share the update policy above.
create or replace function public.respond_to_scorer_assignment(
  p_assignment_id uuid,
  p_accept        boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  update public.official_scorer_assignments
     set status = case when p_accept then 'accepted' else 'declined' end
   where id = p_assignment_id
     and scorer_profile_id = v_uid
     and status in ('assigned', 'accepted', 'declined');

  if not found then
    raise exception 'assignment_not_found' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.claim_tournament_organizer(text)
  from public, anon, authenticated;
revoke all on function public.assign_official_scorer(text, text, uuid)
  from public, anon, authenticated;
revoke all on function public.revoke_official_scorer(text, uuid)
  from public, anon, authenticated;
revoke all on function public.respond_to_scorer_assignment(uuid, boolean)
  from public, anon, authenticated;

grant execute on function public.claim_tournament_organizer(text) to authenticated;
grant execute on function public.assign_official_scorer(text, text, uuid) to authenticated;
grant execute on function public.revoke_official_scorer(text, uuid) to authenticated;
grant execute on function public.respond_to_scorer_assignment(uuid, boolean) to authenticated;

-- ── personal information ────────────────────────────────────────────────────
-- Mirrors validateProfileIdentity. Username and sports are separate calls so a
-- single screen cannot silently rewrite the unique handle or the sport set.
create or replace function public.update_profile_details(
  p_display_name  text,
  p_city          text,
  p_bio           text,
  p_date_of_birth date,
  p_gender        text,
  p_play_style    text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := trim(coalesce(p_display_name, ''));
  v_city text := trim(coalesce(p_city, ''));
  v_bio  text := trim(coalesce(p_bio, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_name) not between 2 and 80 then
    raise exception 'invalid_display_name' using errcode = '22023';
  end if;
  if char_length(v_city) not between 1 and 80 then
    raise exception 'invalid_city' using errcode = '22023';
  end if;
  if char_length(v_bio) > 120 then
    raise exception 'invalid_bio' using errcode = '22023';
  end if;
  if p_date_of_birth is null
     or p_date_of_birth < date '1900-01-01'
     or p_date_of_birth > current_date then
    raise exception 'invalid_date_of_birth' using errcode = '22023';
  end if;
  if p_gender is not null
     and p_gender not in ('woman', 'man', 'non_binary', 'prefer_not_to_say') then
    raise exception 'invalid_gender' using errcode = '22023';
  end if;
  if p_play_style not in ('social', 'weekly', 'competitive') then
    raise exception 'invalid_play_style' using errcode = '22023';
  end if;

  update public.profiles
     set display_name = v_name,
         city         = v_city,
         bio          = v_bio,
         play_style   = p_play_style
   where id = v_uid;

  if not found then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  insert into public.profiles_private (profile_id, date_of_birth, gender)
  values (v_uid, p_date_of_birth, p_gender)
  on conflict (profile_id) do update
     set date_of_birth = excluded.date_of_birth,
         gender        = excluded.gender;
end;
$$;

create or replace function public.change_profile_username(p_username text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := lower(trim(coalesce(p_username, '')));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_name !~ '^[a-z0-9._]{3,30}$' then
    raise exception 'invalid_username' using errcode = '22023';
  end if;

  -- The unique index on lower(username) is the authority; it raises 23505.
  update public.profiles set username = v_name where id = v_uid;
  if not found then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;
  return v_name;
end;
$$;

-- The sport set is replaced wholesale, like the setup RPC: a retry after an
-- interrupted save converges instead of duplicating rows.
create or replace function public.replace_profile_sports(p_sports jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_sports is null
     or jsonb_typeof(p_sports) <> 'array'
     or jsonb_array_length(p_sports) = 0 then
    raise exception 'sports_required' using errcode = '22023';
  end if;
  if (select count(distinct s ->> 'sport_key')
        from jsonb_array_elements(p_sports) as s)
     <> jsonb_array_length(p_sports) then
    raise exception 'duplicate_sport' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_sports) as s
     where nullif(s ->> 'level', '') is not null
       and (s ->> 'level') not in ('beginner', 'intermediate', 'advanced', 'pro')
  ) then
    raise exception 'invalid_level' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_sports) as s
     where char_length(coalesce(s ->> 'position', '')) > 40
  ) then
    raise exception 'invalid_position' using errcode = '22023';
  end if;

  delete from public.profile_sports where profile_id = v_uid;

  insert into public.profile_sports (profile_id, sport_key, level, position)
  select v_uid,
         s ->> 'sport_key',
         nullif(s ->> 'level', ''),
         nullif(s ->> 'position', '')
    from jsonb_array_elements(p_sports) as s;
end;
$$;

-- ── account settings ────────────────────────────────────────────────────────
create or replace function public.update_user_preferences(
  p_reminders      boolean,
  p_invites        boolean,
  p_public_profile boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  insert into public.user_preferences as up
    (profile_id, reminders, invites, public_profile)
  values
    (v_uid, coalesce(p_reminders, true), coalesce(p_invites, true),
     coalesce(p_public_profile, true))
  on conflict (profile_id) do update
     set reminders      = coalesce(p_reminders, up.reminders),
         invites        = coalesce(p_invites, up.invites),
         public_profile = coalesce(p_public_profile, up.public_profile);
end;
$$;

revoke all on function public.update_profile_details(text, text, text, date, text, text)
  from public, anon, authenticated;
revoke all on function public.change_profile_username(text)
  from public, anon, authenticated;
revoke all on function public.replace_profile_sports(jsonb)
  from public, anon, authenticated;
revoke all on function public.update_user_preferences(boolean, boolean, boolean)
  from public, anon, authenticated;

grant execute on function public.update_profile_details(text, text, text, date, text, text)
  to authenticated;
grant execute on function public.change_profile_username(text) to authenticated;
grant execute on function public.replace_profile_sports(jsonb) to authenticated;
grant execute on function public.update_user_preferences(boolean, boolean, boolean)
  to authenticated;

commit;
