-- Cricket result authority (migration 0026) verified end to end.
--
-- Nothing below trusts a client-computed number. Every entry is written by
-- record_match_event, folded by _cricket_fold_detail, refused by
-- _cricket_event_refusal and paid out by submit_match_result, against the real
-- functions and the real row locks.
--
-- The literal sequences are mirrored by test/cricket_authority_test.dart, which
-- folds the same events through CricketEngine, so a drift between the SQL fold
-- and the Dart fold fails in both places rather than silently in one.
--
-- The headline case is C2: two sides that name DIFFERENT XIs (so their wicket
-- caps differ) and a chase won on balls remaining. The engine's "won by N
-- wickets" margin reads the FIRST innings' cap, which is only right when both
-- caps match; here they do not, so the fold must report the chasing side's own
-- cap. That asymmetry is what the old fixtures hid.
--
-- _ct_user(n) is one of eleven signed-in members; member 1 creates and scores
-- every cricket match below, so it is always the organizer and always allowed.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(43);

-- ── members, logins, match lookup ───────────────────────────────────────────
create or replace function public._ct_user(p_n int)
returns uuid
language sql
immutable
as $$ select ('b0000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid $$;

create or replace function public._ct_login(p_n int)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',  public._ct_user(p_n)::text,
      'role', 'authenticated',
      'aud',  'authenticated')::text,
    true);
end;
$$;

create or replace function public._ct_match(p_title text)
returns uuid
language sql
stable
as $$ select id from public.matches where title = p_title $$;

-- The fold is revoked from every client role (that is the point); this security
-- definer wrapper lets the suite read it the way the server does.
create or replace function public._ct_fold(p_title text)
returns jsonb
language sql
security definer
set search_path = public
as $$ select public._cricket_fold_detail(public._ct_match(p_title)) $$;

-- Stable, unique client ids for the writes the suite performs.
create sequence if not exists public._ct_seq;
grant usage, select on sequence public._ct_seq to authenticated;

create or replace function public._ct_next()
returns text
language sql
as $$ select 'ct-' || nextval('public._ct_seq')::text $$;

-- ── event helpers (only ever used for the SUCCESSFUL writes) ────────────────
-- Refusal cases call record_match_event directly inside throws_ok so the raised
-- error is caught by the shim rather than aborting the transaction.
create or replace function public._ct_toss(p_title text, p_side int, p_decision text)
returns void
language plpgsql
as $$
begin
  perform public.record_match_event(
    public._ct_match(p_title), public._ct_next(), 'toss', p_side,
    jsonb_build_object('decision', p_decision));
end;
$$;

create or replace function public._ct_lineup(p_title text, p_side int, p_n int)
returns void
language plpgsql
as $$
declare
  v_players jsonb;
begin
  select jsonb_agg(public._ct_user(g)) into v_players
    from generate_series(1, p_n) g;
  perform public.record_match_event(
    public._ct_match(p_title), public._ct_next(), 'lineup', p_side,
    jsonb_build_object('players', v_players));
end;
$$;

create or replace function public._ct_istart(p_title text, p_side int)
returns void
language plpgsql
as $$
begin
  perform public.record_match_event(
    public._ct_match(p_title), public._ct_next(), 'innings_start', p_side,
    '{}'::jsonb);
end;
$$;

create or replace function public._ct_ball(
  p_title text, p_side int, p_runs int,
  p_wicket boolean default false, p_dismissal text default null
)
returns void
language plpgsql
as $$
declare
  v_data jsonb := jsonb_build_object('runs', p_runs);
begin
  if p_wicket then
    v_data := v_data
      || jsonb_build_object('wicket', true)
      || jsonb_build_object('dismissal', coalesce(p_dismissal, 'Bowled'));
  end if;
  perform public.record_match_event(
    public._ct_match(p_title), public._ct_next(), 'ball', p_side, v_data);
end;
$$;

create or replace function public._ct_mend(p_title text)
returns void
language plpgsql
as $$
begin
  perform public.record_match_event(
    public._ct_match(p_title), public._ct_next(), 'match_end', null,
    jsonb_build_object('reason', 'Abandoned'));
end;
$$;

-- submit in the four shapes the suite needs, always as the current member.
create or replace function public._ct_submit(
  p_title text, p_headline text, p_scores text, p_values text, p_winner int
)
returns void
language sql
as $$
  select public.submit_match_result(
    p_match_id => public._ct_match(p_title),
    p_headline => p_headline,
    p_detail   => 'derived by the server',
    p_side_scores  => p_scores::jsonb,
    p_side_values  => p_values::jsonb,
    p_winner_index => p_winner);
$$;

-- ── members ─────────────────────────────────────────────────────────────────
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
select
  public._ct_user(i),
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'cricket' || i || '@sportika.test', '$2a$10$notarealhashnotarealhashno',
  now(), now(), now(), '{"provider":"email","providers":["email"]}',
  jsonb_build_object('display_name', 'Cricketer ' || i)
from generate_series(1, 11) i;

-- ── the fold and the refusal are server internals ───────────────────────────
select ok(
  not has_function_privilege(
    'authenticated', 'public._cricket_fold_detail(uuid)', 'EXECUTE')
  and not has_function_privilege(
    'authenticated',
    'public._cricket_event_refusal(jsonb, text, int, jsonb)', 'EXECUTE')
  and not has_function_privilege(
    'authenticated', 'public._cricket_derived_scores(uuid)', 'EXECUTE'),
  'the cricket fold, refusal and score builder cannot be called by a member');

select ok(
  has_function_privilege(
    'authenticated', 'public.record_match_event(uuid, text, text, int, jsonb)',
    'EXECUTE')
  and has_function_privilege(
    'authenticated',
    'public.submit_match_result(uuid, text, text, jsonb, jsonb, int)',
    'EXECUTE'),
  'the two doors the app calls stay open to signed-in members');

-- ════════════════════════════════════════════════════════════════════════════
--  C1 · chase lost: Coast bats first, Dale falls short, decided by runs.
--       Equal (default) caps, so the runs margin needs no fix; this fixture
--       proves the happy path, auto-completion and submit derivation.
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
select public._ct_login(1);

select public.create_match(
  'cricket', 'T10 · 1 over',
  '{"oversPerInnings":1,"wicketsPerInnings":10,"innings":2}'::jsonb,
  'C1 run win', 'Green', '2026-04-01 14:00+05', 'public',
  'Coast', 'Dale', 11, 'team', null);
select public.create_match(
  'cricket', 'T10 · 1 over',
  '{"oversPerInnings":1,"wicketsPerInnings":10,"innings":2}'::jsonb,
  'C2 wicket win', 'Blue', '2026-04-01 15:00+05', 'public',
  'Coast', 'Dale', 11, 'team', null);
select public.create_match(
  'cricket', 'T10 · 1 over',
  '{"oversPerInnings":1,"wicketsPerInnings":10,"innings":2}'::jsonb,
  'C3 refusals', 'Red', '2026-04-01 16:00+05', 'public',
  'Coast', 'Dale', 11, 'team', null);
select public.create_match(
  'cricket', 'T10 · 1 over',
  '{"oversPerInnings":1,"wicketsPerInnings":10,"innings":2}'::jsonb,
  'C4 abandon', 'Black', '2026-04-01 17:00+05', 'public',
  'Coast', 'Dale', 11, 'team', null);

select public.start_match(public._ct_match('C1 run win'));

select is(
  public._ct_fold('C1 run win')->'state'->>'innings',
  '0',
  'an empty cricket log folds to no innings yet');

select public._ct_toss('C1 run win', 0, 'bat');
select public._ct_istart('C1 run win', 0);
-- Coast: three runs off the over, all out never reached, the over closes it.
select public._ct_ball('C1 run win', 0, 1);
select public._ct_ball('C1 run win', 0, 1);
select public._ct_ball('C1 run win', 0, 1);
select public._ct_ball('C1 run win', 0, 0);
select public._ct_ball('C1 run win', 0, 0);
select public._ct_ball('C1 run win', 0, 0);

select is(
  public._ct_fold('C1 run win')->>'isComplete',
  'false',
  'one innings closed does not complete a two-innings match');

select public._ct_istart('C1 run win', 1);
-- Dale: only a single run in reply, so they lose by runs.
select public._ct_ball('C1 run win', 1, 1);
select public._ct_ball('C1 run win', 1, 0);
select public._ct_ball('C1 run win', 1, 0);
select public._ct_ball('C1 run win', 1, 0);
select public._ct_ball('C1 run win', 1, 0);
select public._ct_ball('C1 run win', 1, 0);

select is(
  public._ct_fold('C1 run win')->>'winnerSide',
  '0',
  'the side that scored more wins');

select is(
  public._ct_fold('C1 run win')->>'resultLabel',
  'Coast won by 2 runs',
  'a defence is decided by the run margin');

select is(
  public._ct_fold('C1 run win')->'scoreValues',
  '[3, 1]'::jsonb,
  'the per-side run totals are what submit compares against');

select is(
  public._ct_fold('C1 run win')->'scoreDisplay',
  '["3/0", "1/0"]'::jsonb,
  'each side shows its own runs/wickets');

select is(
  public._ct_fold('C1 run win')->'state'->>'innings',
  '2',
  'both innings are on the book');

select ok(
  exists (select 1 from public.match_lifecycle_log
           where match_id = public._ct_match('C1 run win')
             and action = 'cricket_auto_complete'),
  'the last ball auto-completes the match and logs it');

select throws_ok(
  format('select public._ct_submit(%L,%L,%L,%L,%s)',
         'C1 run win', 'irrelevant', '["0","0"]', '[9,9]', 0),
  '22023', 'score_payload_mismatch',
  'run totals the fold disagrees with are refused');

select throws_ok(
  format('select public._ct_submit(%L,%L,%L,%L,%s)',
         'C1 run win', 'irrelevant', '["3/0","1/0"]', '[3,1]', 1),
  '22023', 'score_payload_mismatch',
  'a winner the fold disagrees with is refused');

select lives_ok(
  format('select public._ct_submit(%L,%L,%L,%L,%s)',
         'C1 run win', 'whatever the caller typed', '["bogus","bogus"]',
         '[3,1]', 0),
  'a submission whose totals and winner match the fold is accepted');

select is(
  (select headline from public.match_results
    where match_id = public._ct_match('C1 run win')),
  'Coast won by 2 runs',
  'the headline is written from the fold, not the caller');

select is(
  (select side_scores from public.match_results
    where match_id = public._ct_match('C1 run win')),
  '["3/0", "1/0"]'::jsonb,
  'the stored score strings are the fold''s, never the caller''s');

select is(
  (select side_values from public.match_results
    where match_id = public._ct_match('C1 run win')),
  '[3, 1]'::jsonb,
  'the numeric totals are stored beside the display strings');

select throws_ok(
  format('select public._ct_submit(%L,%L,%L,%L,%s)',
         'C1 run win', 'again', '["3/0","1/0"]', '[3,1]', 0),
  '22023', 'invalid_match_transition',
  'a second submission is refused by the status, not overwritten');

-- ════════════════════════════════════════════════════════════════════════════
--  C2 · the wicket-margin regression. Coast names a full XI (cap 10), Dale
--       names only five (cap 4). Dale chases a low total down and wins with
--       one wicket in hand. The margin MUST come from Dale's own cap.
-- ════════════════════════════════════════════════════════════════════════════
select public.start_match(public._ct_match('C2 wicket win'));

select public._ct_lineup('C2 wicket win', 0, 11);
select public._ct_lineup('C2 wicket win', 1, 5);
select public._ct_toss('C2 wicket win', 0, 'bat');

select is(
  public._ct_fold('C2 wicket win')->'state'->'battingSize',
  '[11, 5]'::jsonb,
  'the two named XIs seed different squad sizes');

select public._ct_istart('C2 wicket win', 0);
-- Coast: two runs, clean sheet, the over is bowled out.
select public._ct_ball('C2 wicket win', 0, 0);
select public._ct_ball('C2 wicket win', 0, 0);
select public._ct_ball('C2 wicket win', 0, 0);
select public._ct_ball('C2 wicket win', 0, 0);
select public._ct_ball('C2 wicket win', 0, 1);
select public._ct_ball('C2 wicket win', 0, 1);

select public._ct_istart('C2 wicket win', 1);
-- Dale: three wickets fall (never all out under a cap of four), then the
-- winning runs come on the fourth ball.
select public._ct_ball('C2 wicket win', 1, 0, true, 'Bowled');
select public._ct_ball('C2 wicket win', 1, 0, true, 'Caught');
select public._ct_ball('C2 wicket win', 1, 0, true, 'LBW');
select public._ct_ball('C2 wicket win', 1, 3);

select is(
  public._ct_fold('C2 wicket win')->>'winnerSide',
  '1',
  'the chasing side that passes the target wins');

select is(
  public._ct_fold('C2 wicket win')->>'resultLabel',
  'Dale won by 1 wickets',
  'the margin is the chasing side''s own cap minus its wickets (4 - 3 = 1)');

select isnt(
  public._ct_fold('C2 wicket win')->>'resultLabel',
  'Dale won by 7 wickets',
  'the margin is NOT the first innings'' cap minus the chase wickets (10 - 3)');

select is(
  public._ct_fold('C2 wicket win')->'scoreValues',
  '[2, 3]'::jsonb,
  'Dale passed the target by a single run');

select is(
  public._ct_fold('C2 wicket win')->'scoreDisplay',
  '["2/0", "3/3"]'::jsonb,
  'Dale finished with three wickets down');

select lives_ok(
  format('select public._ct_submit(%L,%L,%L,%L,%s)',
         'C2 wicket win', 'Dale won by 7 wickets', '["2/0","3/3"]',
         '[2,3]', 1),
  'the (buggy) client margin is accepted for parity because totals and winner match');

select is(
  (select headline from public.match_results
    where match_id = public._ct_match('C2 wicket win')),
  'Dale won by 1 wickets',
  'the official record keeps the corrected margin, overwriting the caller''s');

-- ════════════════════════════════════════════════════════════════════════════
--  C3 · the refusal helper: every crafted entry is rejected with the exact
--       reason, and none of them reaches the log.
-- ════════════════════════════════════════════════════════════════════════════
select public.start_match(public._ct_match('C3 refusals'));

select throws_ok(
  format('select public.record_match_event(p_match_id => %L, p_client_event_id => %L,'
         || ' p_kind => %L, p_side => %s, p_data => %L::jsonb)',
         public._ct_match('C3 refusals'), 'ct-r1', 'innings_end', 'null', '{}'),
  '22023', 'no_innings_open',
  'the innings-end gap the client validator never closed is refused here');

select throws_ok(
  format('select public.record_match_event(p_match_id => %L, p_client_event_id => %L,'
         || ' p_kind => %L, p_side => %s, p_data => %L::jsonb)',
         public._ct_match('C3 refusals'), 'ct-r2', 'innings_start', 0, '{}'),
  '22023', 'toss_required',
  'no innings can open before the toss');

select public._ct_toss('C3 refusals', 0, 'bat');

select throws_ok(
  format('select public.record_match_event(p_match_id => %L, p_client_event_id => %L,'
         || ' p_kind => %L, p_side => %s, p_data => %L::jsonb)',
         public._ct_match('C3 refusals'), 'ct-r3', 'toss', 1,
         '{"decision":"bat"}'),
  '22023', 'toss_already_recorded',
  'a second toss is refused');

select throws_ok(
  format('select public.record_match_event(p_match_id => %L, p_client_event_id => %L,'
         || ' p_kind => %L, p_side => %s, p_data => %L::jsonb)',
         public._ct_match('C3 refusals'), 'ct-r4', 'innings_start', 1, '{}'),
  '22023', 'side_not_due_to_bat',
  'the side not scheduled to bat cannot open the innings');

select public._ct_istart('C3 refusals', 0);

select throws_ok(
  format('select public.record_match_event(p_match_id => %L, p_client_event_id => %L,'
         || ' p_kind => %L, p_side => %s, p_data => %L::jsonb)',
         public._ct_match('C3 refusals'), 'ct-r5', 'lineup', 0,
         jsonb_build_object('players',
           (select jsonb_agg(public._ct_user(g)) from generate_series(1, 11) g))::text),
  '22023', 'lineup_after_first_ball',
  'a lineup cannot be filed after the innings has begun');

select throws_ok(
  format('select public.record_match_event(p_match_id => %L, p_client_event_id => %L,'
         || ' p_kind => %L, p_side => %s, p_data => %L::jsonb)',
         public._ct_match('C3 refusals'), 'ct-r6', 'ball', 1, '{"runs":1}'),
  '22023', 'wrong_batting_side',
  'a ball cannot be credited to a side that is not batting');

select throws_ok(
  format('select public.record_match_event(p_match_id => %L, p_client_event_id => %L,'
         || ' p_kind => %L, p_side => %s, p_data => %L::jsonb)',
         public._ct_match('C3 refusals'), 'ct-r7', 'ball', 0, '{"runs":7}'),
  '22023', 'invalid_runs',
  'seven runs off one legal delivery is refused');

select throws_ok(
  format('select public.record_match_event(p_match_id => %L, p_client_event_id => %L,'
         || ' p_kind => %L, p_side => %s, p_data => %L::jsonb)',
         public._ct_match('C3 refusals'), 'ct-r8', 'ball', 0,
         '{"runs":1,"wicket":true,"dismissal":"Dance"}'),
  '22023', 'invalid_dismissal',
  'an invented mode of dismissal is refused');

select throws_ok(
  format('select public._ct_submit(%L,%L,%L,%L,%s)',
         'C3 refusals', 'early', '["0/0","0/0"]', '[0,0]', -1),
  '22023', 'match_not_complete',
  'an unfinished cricket log cannot be published');

select is(
  (select count(*)::int from public.match_events
    where match_id = public._ct_match('C3 refusals') and not voided),
  2,
  'only the accepted toss and innings-start are in the log; every refusal left no row');

-- ════════════════════════════════════════════════════════════════════════════
--  C4 · an abandonment completes the match, freezes the log, and undoing the
--       abandonment reopens it.
-- ════════════════════════════════════════════════════════════════════════════
select public.start_match(public._ct_match('C4 abandon'));
select public._ct_toss('C4 abandon', 0, 'bat');
select public._ct_istart('C4 abandon', 0);
select public._ct_ball('C4 abandon', 0, 1);
select public._ct_mend('C4 abandon');

select is(
  public._ct_fold('C4 abandon')->>'isComplete',
  'true',
  'an explicit match_end finishes the match');

select is(
  public._ct_fold('C4 abandon')->>'winnerSide',
  '-1',
  'an abandonment after one innings has no winner');

select ok(
  exists (select 1 from public.match_lifecycle_log
           where match_id = public._ct_match('C4 abandon')
             and action = 'cricket_auto_complete'),
  'the completion is logged');

select throws_ok(
  format('select public.record_match_event(p_match_id => %L, p_client_event_id => %L,'
         || ' p_kind => %L, p_side => %s, p_data => %L::jsonb)',
         public._ct_match('C4 abandon'), 'ct-r9', 'ball', 0, '{"runs":1}'),
  '22023', 'match_complete',
  'nothing more can be recorded once the match is complete');

select lives_ok(
  format('select public.void_match_event(p_match_id => %L, p_event_id => %L)',
         public._ct_match('C4 abandon'),
         (select id from public.match_events
           where match_id = public._ct_match('C4 abandon')
             and kind = 'match_end' and not voided)),
  'undoing the abandonment is allowed');

select is(
  public._ct_fold('C4 abandon')->>'isComplete',
  'false',
  'with the abandonment withdrawn the innings is open again');

select ok(
  (select completed_at is null from public.matches
    where title = 'C4 abandon'),
  'the reopened match clears its completion stamp');

select ok(
  exists (select 1 from public.match_lifecycle_log
           where match_id = public._ct_match('C4 abandon')
             and action = 'match_reopened'),
  'the reopening is logged');

select finish();

commit;
