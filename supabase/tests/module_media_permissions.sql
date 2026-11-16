-- Run with psql -v ON_ERROR_STOP=1 after migrations on a disposable database.
-- Plain PostgreSQL assertions; no pgTAP dependency. Rolled back at completion.
--
-- Covers the media authority added by 0010 (module_media, can_manage_media) and
-- 0011 (claim_media_entity, the one-time claim that lets a device-local team or
-- tournament creator manage its public artwork).
begin;

-- Test subjects must be existing profiles; two are required. Seed them here
-- when running on a fresh database: the signup trigger (handle_new_user) turns
-- the auth.users inserts into profile rows. On a database that already has
-- members the seed is skipped entirely and real profiles are used.
do $$begin
  if (select count(*) from public.profiles) < 2 then
    insert into auth.users
      (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
       created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
    values
      ('a4aaaaaa-0000-4000-8000-000000000001',
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'media-a@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
       now(), now(), '{"provider":"email","providers":["email"]}',
       '{"display_name":"Media Tester A"}'),
      ('a4aaaaaa-0000-4000-8000-000000000002',
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'media-b@sportika.test', '$2a$10$notarealhashnotarealhashno', now(),
       now(), now(), '{"provider":"email","providers":["email"]}',
       '{"display_name":"Media Tester B"}')
    on conflict (id) do nothing;
  end if;
end$$;

do $$begin
 if (select count(*) from public.profiles)<2 then raise exception 'Seed two profiles before running media permission tests'; end if;
end$$;

-- ── Claim: anonymous callers have no grant on the RPC at all ────────────────
set local role anon;
do $$begin
 begin
  perform public.claim_media_entity('team-media','sqd-claimtest-a4');
  raise exception 'Anonymous claim accepted';
 exception when insufficient_privilege then null; end;
end$$;
reset role;

-- ── Claim: the first claim is the owner, repeats are idempotent ─────────────
select set_config('request.jwt.claims',
  json_build_object('sub', (select id::text from public.profiles order by id limit 1),
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
do $$begin
 if public.claim_media_entity('team-media','sqd-claimtest-a4') is not true then
  raise exception 'Owner claim refused'; end if;
 if public.claim_media_entity('team-media','sqd-claimtest-a4') is not true then
  raise exception 'Repeat claim lost ownership'; end if;
 if not public.can_manage_media('team-media','sqd-claimtest-a4') then
  raise exception 'Claim did not grant media rights'; end if;
 if public.can_manage_media('team-media','sqd-unclaimed-a4') then
  raise exception 'Unclaimed entity allowed'; end if;
 begin
  perform public.claim_media_entity('match-media','sqd-claimtest-a4');
  raise exception 'Match bucket claim accepted';
 exception when sqlstate '22023' then null; end;
 begin
  perform public.claim_media_entity('team-media','trn-claimtest-a4');
  raise exception 'Tournament id claimed as a team'; 
 exception when sqlstate '22023' then null; end;
 begin
  perform public.claim_media_entity('team-media','not-an-app-id');
  raise exception 'Malformed id claimed';
 exception when sqlstate '22023' then null; end;
end$$;

-- ── Owner workflow: upload, reference, replace, delete ─────────────────────
insert into storage.objects(bucket_id,name) values('team-media','sqd-claimtest-a4/logo/test.png');
insert into public.module_media values('team-media','sqd-claimtest-a4','logo','sqd-claimtest-a4/logo/test.png');
insert into storage.objects(bucket_id,name) values('team-media','sqd-claimtest-a4/logo/replacement.png');
update public.module_media set object_path='sqd-claimtest-a4/logo/replacement.png' where entity_id='sqd-claimtest-a4';
delete from storage.objects where name='sqd-claimtest-a4/logo/test.png';

-- ── Bystander: cannot claim, upload, rewrite the reference or delete ───────
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id::text from public.profiles order by id offset 1 limit 1),
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
do $$begin
 if public.claim_media_entity('team-media','sqd-claimtest-a4') then
  raise exception 'Bystander claim accepted'; end if;
 if public.can_manage_media('team-media','sqd-claimtest-a4') then
  raise exception 'Bystander allowed'; end if;
 begin
  insert into storage.objects(bucket_id,name) values('team-media','sqd-claimtest-a4/banner/evil.png');
  raise exception 'Unauthorized upload accepted';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.media_entities(bucket_id,entity_id,owner_id) values('team-media','sqd-stolen-a4',auth.uid());
  raise exception 'Client ownership registration accepted';
 exception when insufficient_privilege then null; end;
 begin
  perform 1 from public.media_entities limit 1;
  raise exception 'Clients can still enumerate media ownership';
 exception when insufficient_privilege then null; end;
end$$;
update public.module_media set object_path='sqd-claimtest-a4/logo/evil.png' where entity_id='sqd-claimtest-a4';
delete from storage.objects where name='sqd-claimtest-a4/logo/replacement.png';

-- ── Claim quota: 25 claims in a day is the ceiling ────────────────────────
reset role;
insert into public.media_entities(bucket_id,entity_id,owner_id,claimed_at)
select 'team-media','sqd-quota'||to_char(g,'FM0000')||'-a',
  (select id from public.profiles order by id offset 1 limit 1),now()
from generate_series(1,25) g;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id::text from public.profiles order by id offset 1 limit 1),
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
do $$begin
 begin
  perform public.claim_media_entity('team-media','sqd-quotaextra-a4');
  raise exception 'Claim quota not enforced';
 exception when sqlstate '23514' then null; end;
end$$;

-- ── Anonymous readers still see the public reference and the object ────────
reset role;
set local role anon;
do $$begin
 if (select object_path from public.module_media where entity_id='sqd-claimtest-a4') <> 'sqd-claimtest-a4/logo/replacement.png' then
  raise exception 'Public reference or unauthorized update failed'; end if;
 if not exists(select 1 from storage.objects where name='sqd-claimtest-a4/logo/replacement.png') then
  raise exception 'Public read or unauthorized deletion failed'; end if;
end$$;

-- ── Owner cleanup ─────────────────────────────────────────────────────────
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id::text from public.profiles order by id limit 1),
                    'role', 'authenticated', 'aud', 'authenticated')::text, true);
set local role authenticated;
delete from public.module_media where entity_id='sqd-claimtest-a4';
delete from storage.objects where name='sqd-claimtest-a4/logo/replacement.png';
do $$begin
 if exists(select 1 from public.module_media where entity_id='sqd-claimtest-a4') then
  raise exception 'Owner deletion failed'; end if;
end$$;

reset role;
rollback;
