-- Media ownership claims for the still device-local teams and tournaments.
--
-- Squads and tournaments are created on the phone, so their ids arrive with no
-- server-side proof of ownership. Being able to set a public logo or banner is
-- also a narrow right: it can never read private data or touch another table.
-- So the creator claims an entity once and the first claim owns it forever.
--
-- What keeps that acceptable:
--   * ids are `sqd-<base36 micros>-<base36 mod 997>` (see newId in
--     lib/shared/models/models.dart), i.e. unguessable without a leaked id;
--   * a claim only succeeds for an unclaimed entity, so a claimed team keeps
--     its artwork even if its id becomes public later;
--   * a per-profile quota makes spraying the ~997-value space of one known
--     millisecond pointless;
--   * the prefix in the id must match the bucket, so a team id can never be
--     used to claim tournament artwork.
-- When squads and tournaments move to server tables, replace this path with
-- ownership derived from those rows and drop the RPC.

begin;

alter table public.media_entities
  add column if not exists claimed_at timestamptz not null default now();

create or replace function public.claim_media_entity(p_bucket text, p_entity text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  recent int;
begin
  if auth.uid() is null then
    raise exception 'Sign in before managing this artwork.' using errcode = '28000';
  end if;
  if p_bucket not in ('team-media', 'tournament-media') then
    raise exception 'Only team and tournament artwork can be claimed.'
      using errcode = '22023';
  end if;
  if p_entity !~ '^(sqd|trn)-[0-9a-z]{4,16}(-[0-9a-z]{1,4})?$'
     or (p_bucket = 'team-media') <> (p_entity like 'sqd-%') then
    raise exception 'That entity cannot own artwork in this bucket.'
      using errcode = '22023';
  end if;
  select count(*) into recent from public.media_entities e
   where e.owner_id = auth.uid() and e.claimed_at > now() - interval '24 hours';
  if recent >= 25 then
    raise exception 'Too many artwork claims in the last 24 hours.'
      using errcode = '23514';
  end if;
  insert into public.media_entities (bucket_id, entity_id, owner_id)
  values (p_bucket, p_entity, auth.uid())
  on conflict (bucket_id, entity_id) do nothing;
  return exists (
    select 1 from public.media_entities e
    where e.bucket_id = p_bucket and e.entity_id = p_entity
      and e.owner_id = auth.uid());
end;
$$;
revoke all on function public.claim_media_entity(text, text) from public, anon;
grant execute on function public.claim_media_entity(text, text) to authenticated;

-- The client only needs the boolean above, so ownership stays non-enumerable.
drop policy if exists media_entities_read on public.media_entities;
revoke select on public.media_entities from authenticated;

commit;
