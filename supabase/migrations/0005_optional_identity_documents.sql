-- Optional MVP identity submission. This table is deliberately separate from
-- public profiles, signup triggers and complete_profile_setup. No document is
-- required to create an account, finish setup or participate in Sportika.
begin;

create table if not exists public.profile_identity_documents (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  document_type text not null check (document_type in ('cnic', 'b_form')),
  document_number text check (document_number is null or document_number ~ '^[0-9]{13}$'),
  front_path text,
  back_path text,
  submitted_at timestamptz not null default now(),
  constraint identity_has_submission check (
    document_number is not null or front_path is not null or back_path is not null),
  constraint b_form_number_only check (
    document_type <> 'b_form' or (front_path is null and back_path is null)),
  constraint identity_front_owner_path check (front_path is null or
    front_path ~ ('^' || profile_id::text || '/[a-zA-Z0-9_-]+[.]png$')),
  constraint identity_back_owner_path check (back_path is null or
    back_path ~ ('^' || profile_id::text || '/[a-zA-Z0-9_-]+[.]png$'))
);

alter table public.profile_identity_documents enable row level security;
revoke all on public.profile_identity_documents from public, anon, authenticated;
grant select, insert, delete on public.profile_identity_documents to authenticated;
-- A submitted document is not a verified identity. No client-writable
-- verification flag exists, and no public view joins this table.
-- Every statement below is re-runnable: an earlier push created these objects
-- without recording the version, so this file must converge instead of failing.
drop policy if exists identity_documents_select_self on public.profile_identity_documents;
create policy identity_documents_select_self on public.profile_identity_documents
  for select to authenticated using (profile_id = (select auth.uid()));
drop policy if exists identity_documents_insert_self on public.profile_identity_documents;
create policy identity_documents_insert_self on public.profile_identity_documents
  for insert to authenticated with check (profile_id = (select auth.uid()));
drop policy if exists identity_documents_delete_self on public.profile_identity_documents;
create policy identity_documents_delete_self on public.profile_identity_documents
  for delete to authenticated using (profile_id = (select auth.uid()));

create or replace function public.validate_optional_identity_age()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare birth date;
begin
  select date_of_birth into birth from public.profiles_private
    where profile_id = new.profile_id;
  if birth is null then
    raise exception 'A date of birth is needed only when submitting identity details.' using errcode = '23514';
  end if;
  if (new.document_type = 'cnic') <> (birth <= (current_date - interval '18 years')::date) then
    raise exception 'Document type does not match the date of birth.' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_optional_identity_age() from public, anon, authenticated;
drop trigger if exists validate_optional_identity_age on public.profile_identity_documents;
create trigger validate_optional_identity_age before insert
  on public.profile_identity_documents for each row
  execute function public.validate_optional_identity_age();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('identity-documents', 'identity-documents', false, 5242880, array['image/png'])
on conflict (id) do update set public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Immutable, random PNG object names; only the authenticated owner may list,
-- download, upload or delete. Never use the public avatars bucket for IDs.
drop policy if exists identity_images_select_self on storage.objects;
create policy identity_images_select_self on storage.objects
  for select to authenticated using (
    bucket_id = 'identity-documents' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists identity_images_insert_self on storage.objects;
create policy identity_images_insert_self on storage.objects
  for insert to authenticated with check (
    bucket_id = 'identity-documents' and (storage.foldername(name))[1] = (select auth.uid())::text
    and storage.extension(name) = 'png');
drop policy if exists identity_images_delete_self on storage.objects;
create policy identity_images_delete_self on storage.objects
  for delete to authenticated using (
    bucket_id = 'identity-documents' and (storage.foldername(name))[1] = (select auth.uid())::text);

commit;
