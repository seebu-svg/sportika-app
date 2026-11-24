-- Sportika profile module, part 2: athlete attributes on the personal card.
--
-- The Me -> Personal information screen keeps every sensitive module (email /
-- phone verification, identity documents, medical and emergency data) behind
-- dedicated verification workflows. This file backs only the benign physical
-- attributes a member volunteers about themselves: height, weight, laterality
-- and a preferred jersey number.
--
-- They live in `profiles_private`, which RLS already scopes to the owner, so no
-- public read can reach them. The write is a security-definer function that
-- derives the subject from auth.uid() and takes no profile id, exactly like the
-- other granular profile edits in 0006. Every column is nullable and a null
-- clears the value: the screen submits the whole section at once, so "blank"
-- genuinely means "the member removed it".
--
-- Every statement is re-runnable so a re-push converges instead of failing.
begin;

-- ── columns ──────────────────────────────────────────────────────────────────
alter table public.profiles_private
  add column if not exists height_cm        smallint,
  add column if not exists weight_kg        numeric(5, 2),
  add column if not exists dominant_hand    text,
  add column if not exists dominant_foot    text,
  add column if not exists preferred_jersey smallint;

-- ── check constraints (added idempotently) ───────────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.profiles_private'::regclass
       and conname = 'profiles_private_height'
  ) then
    alter table public.profiles_private
      add constraint profiles_private_height
      check (height_cm is null or height_cm between 50 and 280);
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.profiles_private'::regclass
       and conname = 'profiles_private_weight'
  ) then
    alter table public.profiles_private
      add constraint profiles_private_weight
      check (weight_kg is null or weight_kg between 20 and 400);
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.profiles_private'::regclass
       and conname = 'profiles_private_dominant_hand'
  ) then
    alter table public.profiles_private
      add constraint profiles_private_dominant_hand
      check (dominant_hand is null
             or dominant_hand in ('left', 'right', 'ambidextrous'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.profiles_private'::regclass
       and conname = 'profiles_private_dominant_foot'
  ) then
    alter table public.profiles_private
      add constraint profiles_private_dominant_foot
      check (dominant_foot is null
             or dominant_foot in ('left', 'right', 'ambidextrous'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.profiles_private'::regclass
       and conname = 'profiles_private_jersey'
  ) then
    alter table public.profiles_private
      add constraint profiles_private_jersey
      check (preferred_jersey is null or preferred_jersey between 1 and 999);
  end if;
end;
$$;

-- ── write ────────────────────────────────────────────────────────────────────
create or replace function public.update_profile_athlete_details(
  p_height_cm        smallint,
  p_weight_kg        numeric,
  p_dominant_hand    text,
  p_dominant_foot    text,
  p_preferred_jersey smallint
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

  -- The client is not the authority; the same bounds as the column checks are
  -- raised here so a bad value reports a stable identifier instead of a raw
  -- 23514 constraint failure.
  if p_height_cm is not null and p_height_cm not between 50 and 280 then
    raise exception 'invalid_height' using errcode = '22023';
  end if;
  if p_weight_kg is not null and p_weight_kg not between 20 and 400 then
    raise exception 'invalid_weight' using errcode = '22023';
  end if;
  if p_dominant_hand is not null
     and p_dominant_hand not in ('left', 'right', 'ambidextrous') then
    raise exception 'invalid_dominant_hand' using errcode = '22023';
  end if;
  if p_dominant_foot is not null
     and p_dominant_foot not in ('left', 'right', 'ambidextrous') then
    raise exception 'invalid_dominant_foot' using errcode = '22023';
  end if;
  if p_preferred_jersey is not null
     and p_preferred_jersey not between 1 and 999 then
    raise exception 'invalid_preferred_jersey' using errcode = '22023';
  end if;

  insert into public.profiles_private
    (profile_id, height_cm, weight_kg, dominant_hand, dominant_foot,
     preferred_jersey)
  values
    (v_uid, p_height_cm, p_weight_kg, p_dominant_hand, p_dominant_foot,
     p_preferred_jersey)
  on conflict (profile_id) do update
     set height_cm        = excluded.height_cm,
         weight_kg        = excluded.weight_kg,
         dominant_hand    = excluded.dominant_hand,
         dominant_foot    = excluded.dominant_foot,
         preferred_jersey = excluded.preferred_jersey;
end;
$$;

revoke all on function public.update_profile_athlete_details(
  smallint, numeric, text, text, smallint)
  from public, anon, authenticated;
grant execute on function public.update_profile_athlete_details(
  smallint, numeric, text, text, smallint)
  to authenticated;

commit;
