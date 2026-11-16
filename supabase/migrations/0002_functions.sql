-- Sportika authentication schema, part 2: triggers and functions.
--
-- Every function below either fires from `auth.users` or derives its owner from
-- `auth.uid()`. None of them accepts an account id from the client, so a caller
-- can only ever write its own identity.

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists profiles_private_touch on public.profiles_private;
create trigger profiles_private_touch
  before update on public.profiles_private
  for each row execute function public.touch_updated_at();

drop trigger if exists user_preferences_touch on public.user_preferences;
create trigger user_preferences_touch
  before update on public.user_preferences
  for each row execute function public.touch_updated_at();

-- A profile must exist the moment the identity does. Without this, a member can
-- confirm an email and land on a screen with no row to read, and every query in
-- the app would need a "create if missing" fallback.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), '')
  )
  on conflict (id) do nothing;

  insert into public.profiles_private (profile_id)
  values (new.id)
  on conflict (profile_id) do nothing;

  insert into public.user_preferences (profile_id)
  values (new.id)
  on conflict (profile_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- The fifth step of profile setup, in one transaction.
--
-- Writing profile, private details and sports separately lets a dropped
-- connection leave a member marked as set up with no date of birth, or with
-- their old sports. Replacing the sports wholesale also makes a retry after an
-- interrupted save converge instead of duplicating rows.
create or replace function public.complete_profile_setup(
  p_display_name  text,
  p_username      text,
  p_city          text,
  p_bio           text,
  p_date_of_birth date,
  p_gender        text,
  p_play_style    text,
  p_avatar_preset text,
  p_avatar_url    text,
  p_terms_version text,
  p_sports        jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_name     text := trim(coalesce(p_display_name, ''));
  v_username text := lower(trim(coalesce(p_username, '')));
  v_city     text := trim(coalesce(p_city, ''));
  v_bio      text := trim(coalesce(p_bio, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Mirrors validateProfileIdentity so a bypassed client cannot store values the
  -- UI would refuse to draw.
  if char_length(v_name) not between 2 and 80 then
    raise exception 'invalid_display_name' using errcode = '22023';
  end if;

  if v_username !~ '^[a-z0-9._]{3,30}$' then
    raise exception 'invalid_username' using errcode = '22023';
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

  if p_sports is null
     or jsonb_typeof(p_sports) <> 'array'
     or jsonb_array_length(p_sports) = 0 then
    raise exception 'sports_required' using errcode = '22023';
  end if;

  update public.profiles
     set display_name           = v_name,
         username               = v_username,
         city                   = v_city,
         bio                    = v_bio,
         avatar_preset          = nullif(p_avatar_preset, ''),
         avatar_url             = nullif(p_avatar_url, ''),
         play_style             = p_play_style,
         profile_setup_complete = true
   where id = v_uid;

  if not found then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  -- Consent is recorded once and never rewritten by a later save.
  insert into public.profiles_private as pp
    (profile_id, date_of_birth, gender, terms_version, terms_accepted_at)
  values
    (v_uid, p_date_of_birth, p_gender, coalesce(p_terms_version, 'v1'), now())
  on conflict (profile_id) do update
     set date_of_birth     = excluded.date_of_birth,
         gender            = excluded.gender,
         terms_version     = excluded.terms_version,
         terms_accepted_at = coalesce(pp.terms_accepted_at, excluded.terms_accepted_at);

  delete from public.profile_sports where profile_id = v_uid;

  insert into public.profile_sports (profile_id, sport_key, level, position)
  select v_uid,
         s ->> 'sport_key',
         nullif(s ->> 'level', ''),
         nullif(s ->> 'position', '')
    from jsonb_array_elements(p_sports) as s;

  return;
end;
$$;

-- Called while the member types, to give a hint before they submit. The unique
-- index is still the authority: two people can pass this check at the same time.
create or replace function public.is_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1
      from public.profiles
     where lower(username) = lower(trim(p_username))
       and id <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
  );
$$;

revoke all on function public.complete_profile_setup(
  text, text, text, text, date, text, text, text, text, text, jsonb
) from public, anon;

grant execute on function public.complete_profile_setup(
  text, text, text, text, date, text, text, text, text, text, jsonb
) to authenticated;

grant execute on function public.is_username_available(text) to anon, authenticated;
