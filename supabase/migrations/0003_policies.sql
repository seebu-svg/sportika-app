-- Sportika authentication schema, part 3: row level security and column grants.
--
-- RLS is enabled but *not* forced. Supabase's default privileges hand anon and
-- authenticated the run of the public schema, so every table below starts with an
-- explicit revoke and then re-grants exactly what the client needs.
--
-- Forcing RLS is deliberately avoided: handle_new_user and
-- complete_profile_setup are `security definer` and run as the table owner. With
-- FORCE, their inserts would be judged against policies that reference
-- auth.uid() — which is null inside the GoTrue signup request — and account
-- creation would fail. Clients connect as `authenticated`, never as the owner,
-- so ordinary requests are still fully policy-checked.

alter table public.profiles         enable row level security;
alter table public.profiles_private enable row level security;
alter table public.profile_sports   enable row level security;
alter table public.user_preferences enable row level security;
alter table public.sports           enable row level security;

-- ── profiles ────────────────────────────────────────────────────────────────
-- Readable by members (that is the product: a member card is public), writable
-- only on the owner's own row, and only on the columns below.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, bio, city, avatar_preset, avatar_url, play_style)
  on public.profiles to authenticated;

drop policy if exists profiles_select_members on public.profiles;
create policy profiles_select_members on public.profiles
  for select to authenticated
  using (true);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- `username` and `profile_setup_complete` are absent from the column grant, so a
-- client can neither rename itself around the unique index nor declare its own
-- onboarding finished. Only complete_profile_setup changes them.

-- ── profiles_private ────────────────────────────────────────────────────────
revoke all on public.profiles_private from anon, authenticated;
grant select, insert, update on public.profiles_private to authenticated;

drop policy if exists profiles_private_select_self on public.profiles_private;
create policy profiles_private_select_self on public.profiles_private
  for select to authenticated
  using (profile_id = auth.uid());

drop policy if exists profiles_private_insert_self on public.profiles_private;
create policy profiles_private_insert_self on public.profiles_private
  for insert to authenticated
  with check (profile_id = auth.uid());

drop policy if exists profiles_private_update_self on public.profiles_private;
create policy profiles_private_update_self on public.profiles_private
  for update to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- ── profile_sports ──────────────────────────────────────────────────────────
revoke all on public.profile_sports from anon, authenticated;
grant select, insert, update, delete on public.profile_sports to authenticated;

drop policy if exists profile_sports_select_members on public.profile_sports;
create policy profile_sports_select_members on public.profile_sports
  for select to authenticated
  using (true);

drop policy if exists profile_sports_insert_self on public.profile_sports;
create policy profile_sports_insert_self on public.profile_sports
  for insert to authenticated
  with check (profile_id = auth.uid());

drop policy if exists profile_sports_update_self on public.profile_sports;
create policy profile_sports_update_self on public.profile_sports
  for update to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

drop policy if exists profile_sports_delete_self on public.profile_sports;
create policy profile_sports_delete_self on public.profile_sports
  for delete to authenticated
  using (profile_id = auth.uid());

-- ── user_preferences ────────────────────────────────────────────────────────
revoke all on public.user_preferences from anon, authenticated;
grant select, insert, update on public.user_preferences to authenticated;

drop policy if exists user_preferences_select_self on public.user_preferences;
create policy user_preferences_select_self on public.user_preferences
  for select to authenticated
  using (profile_id = auth.uid());

drop policy if exists user_preferences_insert_self on public.user_preferences;
create policy user_preferences_insert_self on public.user_preferences
  for insert to authenticated
  with check (profile_id = auth.uid());

drop policy if exists user_preferences_update_self on public.user_preferences;
create policy user_preferences_update_self on public.user_preferences
  for update to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- ── sports ──────────────────────────────────────────────────────────────────
-- Reference data: readable everywhere, writable by nobody through the API.
revoke all on public.sports from anon, authenticated;
grant select on public.sports to anon, authenticated;

drop policy if exists sports_select_all on public.sports;
create policy sports_select_all on public.sports
  for select to anon, authenticated
  using (true);
