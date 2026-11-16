begin;
-- Device-local entities cannot establish server authority. Only a trusted
-- backend/import may register their owners; never grant clients INSERT here.
-- Written so a re-run converges instead of aborting half-applied objects.
create table if not exists public.media_entities (
  bucket_id text not null check (bucket_id in ('team-media','tournament-media')),
  entity_id text not null check (entity_id ~ '^[a-zA-Z0-9_-]{1,120}$'),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  primary key (bucket_id, entity_id)
);
alter table public.media_entities enable row level security;
revoke all on public.media_entities from public, anon, authenticated;
grant select on public.media_entities to authenticated;
drop policy if exists media_entities_read on public.media_entities;
create policy media_entities_read on public.media_entities for select to authenticated using (true);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
select b,b,true,5242880,array['image/jpeg','image/png','image/webp']
from unnest(array['team-media','tournament-media','match-media']) b
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,
 allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.can_manage_media(p_bucket text,p_entity text)
returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and (
 exists(select 1 from public.media_entities e where e.bucket_id=p_bucket
   and e.entity_id=p_entity and e.owner_id=auth.uid())
 or (p_bucket='match-media' and exists(select 1 from public.matches m
   where m.id::text=p_entity and m.organizer_id=auth.uid() and m.visibility='public'))
 );
$$;
revoke all on function public.can_manage_media(text,text) from public;
grant execute on function public.can_manage_media(text,text) to authenticated;

drop policy if exists module_media_read on storage.objects;
create policy module_media_read on storage.objects for select
using (bucket_id in ('team-media','tournament-media','match-media'));
drop policy if exists module_media_insert on storage.objects;
create policy module_media_insert on storage.objects for insert to authenticated
with check (bucket_id in ('team-media','tournament-media','match-media')
 and public.can_manage_media(bucket_id,(storage.foldername(name))[1])
 and name ~ '^[a-zA-Z0-9_-]+/(logo|banner)/[a-zA-Z0-9_-]+[.](png|jpg|webp)$');
-- Immutable objects: replacement uploads a new path, then commits its reference.
drop policy if exists module_media_delete on storage.objects;
create policy module_media_delete on storage.objects for delete to authenticated
using (bucket_id in ('team-media','tournament-media','match-media')
 and public.can_manage_media(bucket_id,(storage.foldername(name))[1]));

create table if not exists public.module_media (
 bucket_id text not null check (bucket_id in ('team-media','tournament-media','match-media')),
 entity_id text not null,
 slot text not null check (slot in ('logo','banner')),
 object_path text not null,
 primary key(bucket_id,entity_id,slot),
 check (object_path like entity_id || '/' || slot || '/%'
   and object_path ~ '^[a-zA-Z0-9_-]+/(logo|banner)/[a-zA-Z0-9_-]+[.](png|jpg|webp)$')
);
alter table public.module_media enable row level security;
revoke all on public.module_media from public,anon,authenticated;
grant select on public.module_media to anon,authenticated;
grant insert,update,delete on public.module_media to authenticated;
drop policy if exists module_media_public on public.module_media;
create policy module_media_public on public.module_media for select using(true);
drop policy if exists module_media_write on public.module_media;
create policy module_media_write on public.module_media for insert to authenticated
with check(public.can_manage_media(bucket_id,entity_id) and exists(
 select 1 from storage.objects o where o.bucket_id=module_media.bucket_id and o.name=object_path));
drop policy if exists module_media_replace on public.module_media;
create policy module_media_replace on public.module_media for update to authenticated
using(public.can_manage_media(bucket_id,entity_id))
with check(public.can_manage_media(bucket_id,entity_id) and exists(
 select 1 from storage.objects o where o.bucket_id=module_media.bucket_id and o.name=object_path));
drop policy if exists module_media_remove on public.module_media;
create policy module_media_remove on public.module_media for delete to authenticated
using(public.can_manage_media(bucket_id,entity_id));
-- Preserve the existing URL contract while recording the portable object path.
alter table public.profiles add column if not exists avatar_path text;
alter table public.profiles drop constraint if exists avatar_path_owner;
alter table public.profiles add constraint avatar_path_owner check (
 avatar_path is null or avatar_path ~ ('^' || id::text || '/[a-zA-Z0-9_-]+[.](png|jpg|webp)$'));
grant update(avatar_path) on public.profiles to authenticated;
-- Return bounded, aged candidates; object bytes are deleted via Storage API.
-- A one-day grace period excludes interrupted uploads still being committed.
create or replace function public.module_media_orphans()
returns table(bucket_id text,name text)
language sql stable security definer set search_path = '' as $$
 select o.bucket_id,o.name from storage.objects o
 where o.bucket_id in ('team-media','tournament-media','match-media')
 and o.created_at < now()-interval '1 day'
 and not exists(select 1 from public.module_media m
   where m.bucket_id=o.bucket_id and m.object_path=o.name)
 order by o.created_at limit 500;
$$;
revoke all on function public.module_media_orphans() from public,anon,authenticated;
grant execute on function public.module_media_orphans() to service_role;
commit;
