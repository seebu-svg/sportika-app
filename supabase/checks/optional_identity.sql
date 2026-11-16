-- Run with psql -v ON_ERROR_STOP=1 -f supabase/checks/optional_identity.sql
-- against a disposable local Supabase DB after migrations. Always rolls back.
begin;
create function pg_temp.assert_true(value boolean, message text)
returns void language plpgsql as $$ begin
  if value is distinct from true then raise exception 'Assertion failed: %', message; end if;
end $$;

insert into auth.users(id, raw_user_meta_data) values
 ('31111111-1111-1111-1111-111111111111', '{"display_name":"Adult test"}'),
 ('32222222-2222-2222-2222-222222222222', '{"display_name":"Minor test"}');
update public.profiles_private set date_of_birth = (current_date - interval '18 years')::date
 where profile_id = '31111111-1111-1111-1111-111111111111';
update public.profiles_private set date_of_birth = (current_date - interval '12 years')::date
 where profile_id = '32222222-2222-2222-2222-222222222222';

select pg_temp.assert_true((select not public from storage.buckets where id = 'identity-documents'), 'identity bucket is private');
select pg_temp.assert_true((select public from storage.buckets where id = 'avatars'), 'avatar branding remains public');

set local role authenticated;
set local request.jwt.claims = '{"sub":"31111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- Core RPC succeeds with absolutely no identity row, images or number.
select public.complete_profile_setup(
 p_display_name => 'Adult test', p_username => 'adult_identity_test',
 p_city => 'Karachi', p_bio => '', p_date_of_birth => (current_date - interval '18 years')::date,
 p_gender => null, p_avatar_url => null, p_terms_version => 'v1', p_avatar_preset => 'midnight', p_play_style => 'social',
 p_sports => '[{"sport_key":"cricket"}]'::jsonb);
select pg_temp.assert_true((select profile_setup_complete from public.profiles
 where id = '31111111-1111-1111-1111-111111111111'), 'completion works without identity');
select pg_temp.assert_true((select count(*) = 0 from public.profile_identity_documents), 'completion creates no identity data');

insert into storage.objects(bucket_id,name) values
 ('identity-documents','31111111-1111-1111-1111-111111111111/front-test.png');
insert into public.profile_identity_documents(profile_id,document_type,front_path) values
 ('31111111-1111-1111-1111-111111111111','cnic','31111111-1111-1111-1111-111111111111/front-test.png');
select pg_temp.assert_true((select document_number is null from public.profile_identity_documents), 'images do not require a number or other side');

do $$ begin
  begin
    insert into storage.objects(bucket_id,name) values
     ('identity-documents','32222222-2222-2222-2222-222222222222/stolen.png');
    raise exception 'Cross-owner upload unexpectedly allowed';
  exception when insufficient_privilege then null; end;
end $$;

set local request.jwt.claims = '{"sub":"32222222-2222-2222-2222-222222222222","role":"authenticated"}';
select pg_temp.assert_true((select count(*) = 0 from public.profile_identity_documents), 'another member cannot read identity numbers or paths');
select pg_temp.assert_true((select count(*) = 0 from storage.objects where bucket_id = 'identity-documents'), 'another member cannot list or download images');
with removed as (delete from public.profile_identity_documents where profile_id = '31111111-1111-1111-1111-111111111111' returning 1)
 select pg_temp.assert_true((select count(*) = 0 from removed), 'another member cannot delete identity data');
with removed as (delete from storage.objects where bucket_id = 'identity-documents' returning 1)
 select pg_temp.assert_true((select count(*) = 0 from removed), 'another member cannot delete identity images');

do $$ begin
  begin
    insert into public.profile_identity_documents(profile_id,document_type,document_number) values
     ('32222222-2222-2222-2222-222222222222','b_form','123');
    raise exception 'Invalid number unexpectedly allowed';
  exception when check_violation then null; end;
  begin
    insert into public.profile_identity_documents(profile_id,document_type,document_number) values
     ('32222222-2222-2222-2222-222222222222','cnic','1234512345671');
    raise exception 'CNIC for minor unexpectedly allowed';
  exception when check_violation then null; end;
  begin
    insert into public.profile_identity_documents(profile_id,document_type,front_path) values
     ('32222222-2222-2222-2222-222222222222','b_form','31111111-1111-1111-1111-111111111111/front-test.png');
    raise exception 'Cross-owner path unexpectedly allowed';
  exception when check_violation then null; end;
end $$;
insert into public.profile_identity_documents(profile_id,document_type,document_number) values
 ('32222222-2222-2222-2222-222222222222','b_form','1234512345671');
select pg_temp.assert_true((select count(*) = 1 from public.profile_identity_documents), 'minor can submit an optional B-Form');

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
do $$ begin
  begin
    perform * from public.profile_identity_documents;
    raise exception 'Anonymous identity read unexpectedly allowed';
  exception when insufficient_privilege then null; end;
end $$;
select pg_temp.assert_true((select count(*) = 0 from storage.objects where bucket_id = 'identity-documents'), 'anonymous visitors cannot read identity images');
rollback;
