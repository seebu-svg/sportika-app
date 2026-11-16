-- Sportika authentication schema, part 1: tables.
--
-- Identity lives in `auth.users` (GoTrue). Everything Sportika knows about a
-- member hangs off that id, so `profile.id` *is* `auth.users.id` and the app can
-- keep using a String account id with no mapping layer.
--
-- There is deliberately no role, account type or intent column: Sportika has one
-- universal account, and permission is expressed per object by ownership
-- (created_by) and assignment (scorer_id) in the modules that own those tables.

-- Reference data. Four sports is the whole product surface for now; the client
-- keys (`Sport` enum) must match these strings exactly.
create table if not exists public.sports (
  key        text primary key,
  label      text not null,
  sort_order int  not null default 0
);

insert into public.sports (key, label, sort_order) values
  ('cricket',   'Cricket',   1),
  ('padel',     'Padel',     2),
  ('futsal',    'Futsal',    3),
  ('badminton', 'Badminton', 4)
on conflict (key) do nothing;

-- Public side of a member card: what other members are allowed to see.
create table if not exists public.profiles (
  id                     uuid primary key references auth.users (id) on delete cascade,
  username               text,
  display_name           text not null default '',
  bio                    text not null default '',
  city                   text not null default '',
  avatar_preset          text,
  avatar_url             text,
  play_style             text not null default 'social',
  profile_setup_complete boolean not null default false,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),

  -- The signup trigger creates a row before the member has typed anything, so
  -- an empty name is legal at rest; complete_profile_setup enforces 2..80.
  constraint profiles_display_name_len
    check (char_length(display_name) between 0 and 80),
  constraint profiles_bio_len
    check (char_length(bio) <= 120),
  constraint profiles_city_len
    check (char_length(city) <= 80),
  constraint profiles_username_charset
    check (username is null or username ~ '^[a-z0-9._]{3,30}$'),
  constraint profiles_play_style
    check (play_style in ('social', 'weekly', 'competitive'))
);

-- Case-insensitive uniqueness without depending on the citext extension.
create unique index if not exists profiles_username_unique
  on public.profiles (lower(username))
  where username is not null;

-- Private side: never selected by anyone but the owner.
create table if not exists public.profiles_private (
  profile_id        uuid primary key references public.profiles (id) on delete cascade,
  date_of_birth     date,
  gender            text,
  terms_version     text,
  terms_accepted_at timestamptz,
  updated_at        timestamptz not null default now(),

  -- Values mirror ProfileGender in lib/shared/models/profile_setup.dart.
  constraint profiles_private_gender
    check (gender is null or gender in ('woman', 'man', 'non_binary', 'prefer_not_to_say')),
  constraint profiles_private_dob
    check (date_of_birth is null
           or (date_of_birth >= date '1900-01-01' and date_of_birth <= current_date))
);

-- One row per preferred sport. `level` and `position` stay nullable because the
-- fifth setup step is skippable: a member can pick sports and decline to rank
-- them, and that "declined" state has to survive a round trip.
create table if not exists public.profile_sports (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  sport_key  text not null references public.sports (key),
  level      text,
  position   text,
  primary key (profile_id, sport_key),
  constraint profile_sports_level
    check (level is null or level in ('beginner', 'intermediate', 'advanced', 'pro')),
  constraint profile_sports_position_len
    check (position is null or char_length(position) <= 40)
);

-- Mirrors PreferencesController: three switches, all on by default.
create table if not exists public.user_preferences (
  profile_id     uuid primary key references public.profiles (id) on delete cascade,
  reminders      boolean not null default true,
  invites        boolean not null default true,
  public_profile boolean not null default true,
  updated_at     timestamptz not null default now()
);
