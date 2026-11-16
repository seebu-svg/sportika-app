-- Sportika monetization module: configurable streams and plans, purchases,
-- subscriptions, entitlements, a payment ledger and a billing audit trail.
--
-- Two revenue streams are active in the MVP:
--   * tournament_pass  one-time premium unlock for a single tournament
--   * organizer_pro    monthly subscription, premium tools account-wide
-- Three more are configured but disabled, so they have no plan rows, no UI and
-- no charge path until an operator turns them on:
--   * featured_listing, sponsorship, analytics
--
-- Conventions match 0001..0008: RLS is enabled but never forced, every write is a
-- `security definer` function that derives the member from auth.uid(), clients
-- hold SELECT grants only, and no client can ever name the row it writes.
--
-- Counter-intuitive but deliberate: the operator functions (verify, refund,
-- grant, revoke, expire) are granted to `service_role` ONLY. Sportika ships one
-- universal account and no admin role, so payment verification happens out of
-- band through tool/billing_admin.py or the SQL editor. A member has no path to
-- mark a purchase paid, which is exactly the "never trust the client" rule.
begin;

-- ── streams ─────────────────────────────────────────────────────────────────
create table if not exists public.monetization_streams (
  stream_key      text primary key,
  label           text not null,
  summary         text not null default '',
  mode            text not null,
  enabled         boolean not null default false,
  ui_visible      boolean not null default false,
  sort_order      int not null default 0,
  -- Platform-level knobs the client reads instead of hard-coding them, e.g.
  -- {"free_entry_cap": 16} on tournament_pass.
  settings        jsonb not null default '{}'::jsonb,
  activation_note text not null default '',
  updated_at      timestamptz not null default now(),

  constraint monetization_streams_key check (stream_key in (
    'tournament_pass', 'organizer_pro', 'featured_listing', 'sponsorship', 'analytics'
  )),
  constraint monetization_streams_mode check (mode in (
    'one_time', 'subscription', 'placement', 'contract', 'addon'
  )),
  constraint monetization_streams_label_len
    check (char_length(label) between 2 and 60),
  constraint monetization_streams_settings_object
    check (jsonb_typeof(settings) = 'object')
);

alter table public.monetization_streams enable row level security;
revoke all on public.monetization_streams from public, anon, authenticated;
grant select on public.monetization_streams to authenticated;

drop policy if exists monetization_streams_select_members
  on public.monetization_streams;
create policy monetization_streams_select_members on public.monetization_streams
  for select to authenticated
  using (true);

insert into public.monetization_streams
  (stream_key, label, summary, mode, enabled, ui_visible, sort_order, settings, activation_note)
values
  ('tournament_pass', 'Tournament pass',
   'Premium tools for one event: more entries, draw controls and rule presets.',
   'one_time', true, true, 1,
   '{"free_entry_cap": 16}'::jsonb,
   'MVP stream. Active.'),
  ('organizer_pro', 'Organizer Pro',
   'Monthly subscription: every tournament you organise keeps the premium tools.',
   'subscription', true, true, 2,
   '{}'::jsonb,
   'MVP stream. Active.'),
  ('featured_listing', 'Featured tournaments',
   'Paid discovery placement above the regular tournament list.',
   'placement', false, false, 3,
   '{}'::jsonb,
   'Planned. Disabled by configuration: add plan rows and set enabled/ui_visible.'),
  ('sponsorship', 'Sponsorships and advertising',
   'Sponsored banners, branded placements and sports partnerships.',
   'contract', false, false, 4,
   '{}'::jsonb,
   'Planned. Disabled by configuration: add plan rows and set enabled/ui_visible.'),
  ('analytics', 'Advanced analytics',
   'Premium tournament reports, performance insights and exports.',
   'addon', false, false, 5,
   '{}'::jsonb,
   'Planned. Disabled by configuration: add plan rows and set enabled/ui_visible.')
on conflict (stream_key) do nothing;

drop trigger if exists monetization_streams_touch on public.monetization_streams;
create trigger monetization_streams_touch
  before update on public.monetization_streams
  for each row execute function public.touch_updated_at();

-- ── plans ───────────────────────────────────────────────────────────────────
-- The catalogue. Prices, limits and wording live here, never in the client: the
-- app renders exactly these rows and refuses to invent a price when the table is
-- unreachable.
create table if not exists public.billing_plans (
  code                 text primary key,
  stream_key           text not null
    references public.monetization_streams (stream_key)
    on update cascade on delete restrict,
  label                text not null,
  tagline              text not null default '',
  description          text not null default '',
  price_minor          bigint not null,
  currency             text not null default 'PKR',
  billing_interval     text not null default 'one_time',
  period_days          int,
  entitlement_days     int,
  -- Human bullets for the pricing screen.
  benefits             jsonb not null default '[]'::jsonb,
  -- Machine-readable entitlement: {"entitlement": "...", "max_entries": 128, ...}
  features             jsonb not null default '{}'::jsonb,
  payment_instructions text not null default '',
  active               boolean not null default true,
  sort_order           int not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint billing_plans_price     check (price_minor >= 0),
  constraint billing_plans_currency  check (currency ~ '^[A-Z]{3}$'),
  constraint billing_plans_interval
    check (billing_interval in ('one_time', 'month', 'year')),
  constraint billing_plans_period
    check (period_days is null or period_days between 1 and 366),
  constraint billing_plans_entitlement_days
    check (entitlement_days is null or entitlement_days between 1 and 3660),
  constraint billing_plans_label_len check (char_length(label) between 2 and 60),
  constraint billing_plans_benefits_array
    check (jsonb_typeof(benefits) = 'array'),
  constraint billing_plans_features_object
    check (jsonb_typeof(features) = 'object')
);

alter table public.billing_plans enable row level security;
revoke all on public.billing_plans from public, anon, authenticated;
grant select on public.billing_plans to authenticated;

drop policy if exists billing_plans_select_members on public.billing_plans;
create policy billing_plans_select_members on public.billing_plans
  for select to authenticated
  using (true);

insert into public.billing_plans
  (code, stream_key, label, tagline, description, price_minor, currency,
   billing_interval, period_days, entitlement_days, benefits, features,
   payment_instructions, active, sort_order)
values
  ('tournament_pass_standard', 'tournament_pass', 'Tournament pass',
   'Premium tools for one event',
   'Unlock the premium tournament toolkit for a single event you organise. '
   'Entries, draws and the official results flow stay exactly as they are - '
   'the pass only raises the ceiling.',
   250000, 'PKR', 'one_time', null, null,
   '["Up to 128 confirmed entries", "Custom group draw and rule presets", "Premium badge on your tournament"]'::jsonb,
   '{"entitlement": "tournament.premium", "max_entries": 128, "group_counts": [1, 2, 3, 4], "rules_presets": true}'::jsonb,
   'Transfer the amount to the Sportika collection account and use the reference code shown on your purchase screen as the payment description. An operator verifies the transfer, usually within one working day.',
   true, 1),
  ('organizer_pro_monthly', 'organizer_pro', 'Organizer Pro',
   'Premium tools across every tournament',
   'A monthly subscription that keeps the premium toolkit on for every event you '
   'organise while it is active. Basic match creation and official scoring are '
   'free and are never affected.',
   450000, 'PKR', 'month', 30, null,
   '["Premium tools on every tournament you organise", "Up to 128 confirmed entries", "Draw controls and rule presets", "Priority organiser support"]'::jsonb,
   '{"entitlement": "organizer.premium", "max_entries": 128, "group_counts": [1, 2, 3, 4], "rules_presets": true}'::jsonb,
   'Transfer the monthly amount to the Sportika collection account and use the reference code shown on your purchase screen as the payment description. An operator verifies the transfer and your subscription starts from the verification day.',
   true, 2)
on conflict (code) do nothing;

drop trigger if exists billing_plans_touch on public.billing_plans;
create trigger billing_plans_touch
  before update on public.billing_plans
  for each row execute function public.touch_updated_at();

-- ── purchases ───────────────────────────────────────────────────────────────
-- One row per purchase attempt. `amount_minor` and `currency` are snapshots: a
-- later price change must never rewrite what a member already owed or paid.
create table if not exists public.purchases (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles (id) on delete cascade,
  plan_code       text not null references public.billing_plans (code),
  stream_key      text not null,
  amount_minor    bigint not null,
  currency        text not null,
  status          text not null default 'pending',
  target_kind     text not null default 'account',
  target_id       text,
  idempotency_key text not null,
  provider        text not null default 'manual',
  provider_ref    text not null default '',
  expires_at      timestamptz,
  paid_at         timestamptz,
  failed_at       timestamptz,
  expired_at      timestamptz,
  refunded_at     timestamptz,
  note            text not null default '',
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint purchases_status check (status in (
    'pending', 'paid', 'failed', 'expired', 'refunded'
  )),
  constraint purchases_target_kind check (target_kind in (
    'account', 'tournament', 'listing', 'campaign'
  )),
  constraint purchases_target_shape check (
    (target_kind = 'account' and target_id is null)
    or (target_kind in ('tournament', 'listing', 'campaign')
        and target_id is not null
        and char_length(target_id) between 1 and 120)
  ),
  constraint purchases_provider check (provider in ('manual', 'gateway')),
  constraint purchases_amount check (amount_minor >= 0),
  constraint purchases_currency check (currency ~ '^[A-Z]{3}$'),
  constraint purchases_idempotency_len
    check (char_length(idempotency_key) between 8 and 80),
  constraint purchases_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint purchases_unique_key unique (profile_id, idempotency_key)
);

alter table public.purchases enable row level security;
revoke all on public.purchases from public, anon, authenticated;
grant select on public.purchases to authenticated;

drop policy if exists purchases_select_self on public.purchases;
create policy purchases_select_self on public.purchases
  for select to authenticated
  using (profile_id = auth.uid());

create index if not exists purchases_profile
  on public.purchases (profile_id, created_at desc);
create index if not exists purchases_status
  on public.purchases (status, expires_at);
create index if not exists purchases_target
  on public.purchases (stream_key, target_id);

-- One paid pass per event, and at most one live attempt at a time. A retry
-- returns the open attempt instead of stacking a second one.
create unique index if not exists purchases_one_paid_pass
  on public.purchases (profile_id, target_id)
  where stream_key = 'tournament_pass' and status = 'paid';
create unique index if not exists purchases_one_pending_pass
  on public.purchases (profile_id, target_id)
  where stream_key = 'tournament_pass' and status = 'pending';

drop trigger if exists purchases_touch on public.purchases;
create trigger purchases_touch
  before update on public.purchases
  for each row execute function public.touch_updated_at();

-- ── subscriptions ───────────────────────────────────────────────────────────
-- One row per member per plan, extended in place on every verified renewal, so
-- "is this member Pro right now" is always one read. The full payment history
-- lives in purchases and payment_records.
create table if not exists public.subscriptions (
  id                   uuid primary key default gen_random_uuid(),
  profile_id           uuid not null references public.profiles (id) on delete cascade,
  plan_code            text not null references public.billing_plans (code),
  status               text not null default 'pending',
  current_period_start timestamptz,
  current_period_end   timestamptz,
  cancel_at_period_end boolean not null default false,
  last_purchase_id     uuid references public.purchases (id) on delete set null,
  started_at           timestamptz,
  ended_at             timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint subscriptions_unique_plan unique (profile_id, plan_code),
  constraint subscriptions_status check (status in (
    'pending', 'active', 'past_due', 'expired', 'cancelled', 'refunded'
  )),
  constraint subscriptions_period check (
    current_period_start is null
    or current_period_end is null
    or current_period_end > current_period_start
  )
);

alter table public.subscriptions enable row level security;
revoke all on public.subscriptions from public, anon, authenticated;
grant select on public.subscriptions to authenticated;

drop policy if exists subscriptions_select_self on public.subscriptions;
create policy subscriptions_select_self on public.subscriptions
  for select to authenticated
  using (profile_id = auth.uid());

create index if not exists subscriptions_profile
  on public.subscriptions (profile_id, status);

drop trigger if exists subscriptions_touch on public.subscriptions;
create trigger subscriptions_touch
  before update on public.subscriptions
  for each row execute function public.touch_updated_at();

-- ── entitlements ────────────────────────────────────────────────────────────
-- What the member may actually use. A pass is scoped to one tournament; Pro is
-- scoped to the account and satisfies every tournament check while it lives.
create table if not exists public.entitlements (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles (id) on delete cascade,
  feature_key     text not null,
  source          text not null,
  purchase_id     uuid references public.purchases (id) on delete cascade,
  subscription_id uuid references public.subscriptions (id) on delete cascade,
  target_kind     text not null default 'account',
  target_id       text,
  status          text not null default 'active',
  granted_at      timestamptz not null default now(),
  expires_at      timestamptz,
  revoked_at      timestamptz,
  revoke_reason   text not null default '',

  constraint entitlements_feature_len
    check (char_length(feature_key) between 3 and 60),
  constraint entitlements_source
    check (source in ('purchase', 'subscription', 'grant')),
  constraint entitlements_status
    check (status in ('active', 'expired', 'revoked')),
  constraint entitlements_target_kind
    check (target_kind in ('account', 'tournament', 'listing', 'campaign')),
  constraint entitlements_target_shape check (
    (target_kind = 'account' and target_id is null)
    or (target_kind in ('tournament', 'listing', 'campaign')
        and target_id is not null
        and char_length(target_id) between 1 and 120)
  ),
  -- Exactly one origin: a purchase, a subscription, or an operator grant.
  constraint entitlements_origin check (
    (source = 'purchase' and purchase_id is not null and subscription_id is null)
    or (source = 'subscription'
        and subscription_id is not null and purchase_id is null)
    or (source = 'grant'
        and purchase_id is null and subscription_id is null)
  ),
  constraint entitlements_expiry
    check (expires_at is null or expires_at > granted_at)
);

alter table public.entitlements enable row level security;
revoke all on public.entitlements from public, anon, authenticated;
grant select on public.entitlements to authenticated;

drop policy if exists entitlements_select_self on public.entitlements;
create policy entitlements_select_self on public.entitlements
  for select to authenticated
  using (profile_id = auth.uid());

create index if not exists entitlements_profile
  on public.entitlements (profile_id, feature_key);
create index if not exists entitlements_target
  on public.entitlements (target_kind, target_id);

-- A purchase can only grant once, a subscription only carries one live row per
-- feature, and an operator grant is idempotent per subject.
create unique index if not exists entitlements_from_purchase
  on public.entitlements (purchase_id, feature_key, coalesce(target_id, ''))
  where purchase_id is not null;
create unique index if not exists entitlements_from_subscription
  on public.entitlements (subscription_id, feature_key)
  where subscription_id is not null;
create unique index if not exists entitlements_from_grant
  on public.entitlements (profile_id, feature_key, target_kind, coalesce(target_id, ''))
  where source = 'grant';

-- ── payment ledger ──────────────────────────────────────────────────────────
-- Append-only. One charge and one refund per purchase in the MVP, which is what
-- makes a repeated verification a no-op instead of a second line.
create table if not exists public.payment_records (
  id           uuid primary key default gen_random_uuid(),
  purchase_id  uuid not null references public.purchases (id) on delete cascade,
  kind         text not null,
  amount_minor bigint not null,
  currency     text not null,
  method       text not null default 'manual',
  provider_ref text not null default '',
  recorded_by  text not null default 'operator',
  note         text not null default '',
  at           timestamptz not null default now(),

  constraint payment_records_kind check (kind in ('charge', 'refund', 'adjustment')),
  constraint payment_records_method check (method in ('manual', 'gateway')),
  constraint payment_records_amount check (amount_minor >= 0),
  constraint payment_records_currency check (currency ~ '^[A-Z]{3}$')
);

alter table public.payment_records enable row level security;
revoke all on public.payment_records from public, anon, authenticated;
grant select on public.payment_records to authenticated;

-- The member sees the ledger lines of their own purchases only.
drop policy if exists payment_records_select_self on public.payment_records;
create policy payment_records_select_self on public.payment_records
  for select to authenticated
  using (
    exists (
      select 1 from public.purchases p
       where p.id = payment_records.purchase_id
         and p.profile_id = auth.uid()
    )
  );

create unique index if not exists payment_records_one_charge
  on public.payment_records (purchase_id) where kind = 'charge';
create unique index if not exists payment_records_one_refund
  on public.payment_records (purchase_id) where kind = 'refund';
create index if not exists payment_records_purchase
  on public.payment_records (purchase_id, at);

-- ── audit ───────────────────────────────────────────────────────────────────
-- Every state change lands here. `provider_event_id` is the reserved dedupe key
-- for a future gateway webhook: it is unique when present, so a replayed event
-- can never be applied twice even after Edge Functions arrive.
create table if not exists public.billing_events (
  id               uuid primary key default gen_random_uuid(),
  subject_kind     text not null,
  subject_id       uuid,
  action           text not null,
  actor            text not null default 'system',
  actor_id         uuid references public.profiles (id) on delete set null,
  detail           jsonb not null default '{}'::jsonb,
  provider_event_id text,
  at               timestamptz not null default now(),

  constraint billing_events_subject check (subject_kind in (
    'purchase', 'subscription', 'entitlement', 'plan', 'stream'
  )),
  constraint billing_events_actor check (actor in ('member', 'operator', 'system')),
  constraint billing_events_action_len check (char_length(action) between 2 and 60),
  constraint billing_events_detail_object check (jsonb_typeof(detail) = 'object')
);

-- No client grant at all: the audit trail is operator-only.
alter table public.billing_events enable row level security;
revoke all on public.billing_events from public, anon, authenticated;

create index if not exists billing_events_subject
  on public.billing_events (subject_kind, subject_id, at desc);
create unique index if not exists billing_events_provider_event
  on public.billing_events (provider_event_id)
  where provider_event_id is not null;

-- ── internal helpers ────────────────────────────────────────────────────────
create or replace function public.log_billing_event(
  p_subject_kind    text,
  p_subject_id      uuid,
  p_action          text,
  p_actor           text,
  p_actor_id        uuid,
  p_detail          jsonb default '{}'::jsonb,
  p_provider_event_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.billing_events
    (subject_kind, subject_id, action, actor, actor_id, detail, provider_event_id)
  values
    (p_subject_kind, p_subject_id, p_action, p_actor, p_actor_id,
     coalesce(p_detail, '{}'::jsonb), p_provider_event_id)
  on conflict (provider_event_id) do nothing;
end;
$$;

revoke all on function public.log_billing_event(
  text, uuid, text, text, uuid, jsonb, text
) from public, anon, authenticated;

-- The single predicate every read shares: an entitlement counts only while it is
-- active and unexpired. Expiry is therefore computed at read time, not awaited
-- from a scheduler.
create or replace function public.entitlement_is_live(
  p_status     text,
  p_expires_at timestamptz
)
returns boolean
language sql
immutable
as $$
  select p_status = 'active' and (p_expires_at is null or p_expires_at > now());
$$;

revoke all on function public.entitlement_is_live(text, timestamptz)
  from public, anon, authenticated;

-- ── member reads ────────────────────────────────────────────────────────────
-- The one authoritative entitlement answer the client may rely on. It never
-- takes a profile id: the subject is always auth.uid().
create or replace function public.has_entitlement(
  p_feature_key text,
  p_target_kind text default 'account',
  p_target_id   text default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.entitlements e
     where e.profile_id = auth.uid()
       and e.feature_key = trim(coalesce(p_feature_key, ''))
       and e.status = 'active'
       and (e.expires_at is null or e.expires_at > now())
       and (
         e.target_kind = 'account'
         or (
           e.target_kind = coalesce(lower(trim(p_target_kind)), 'account')
           and e.target_id is not distinct from
               nullif(trim(coalesce(p_target_id, '')), '')
         )
       )
  );
$$;

revoke all on function public.has_entitlement(text, text, text)
  from public, anon, authenticated;
grant execute on function public.has_entitlement(text, text, text)
  to authenticated;

-- ── purchases ───────────────────────────────────────────────────────────────
create or replace function public.start_purchase(
  p_plan_code       text,
  p_target_kind     text default 'account',
  p_target_id       text default null,
  p_idempotency_key text default null
)
returns public.purchases
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_key    text := trim(coalesce(p_idempotency_key, ''));
  v_kind   text := lower(trim(coalesce(p_target_kind, 'account')));
  v_target text := nullif(trim(coalesce(p_target_id, '')), '');
  v_plan   public.billing_plans;
  v_stream public.monetization_streams;
  v_row    public.purchases;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_key) not between 8 and 80 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;

  select * into v_plan
    from public.billing_plans
   where code = trim(coalesce(p_plan_code, ''));
  if not found then
    raise exception 'unknown_plan' using errcode = 'P0002';
  end if;

  select * into v_stream
    from public.monetization_streams
   where stream_key = v_plan.stream_key;
  if not found or not v_stream.enabled or not v_plan.active then
    raise exception 'plan_not_available' using errcode = '22023';
  end if;

  -- A repeated key is a retry, not a second attempt.
  select * into v_row
    from public.purchases
   where profile_id = v_uid and idempotency_key = v_key;
  if found then
    return v_row;
  end if;

  if v_plan.stream_key = 'tournament_pass' then
    if v_kind <> 'tournament' or v_target is null then
      raise exception 'invalid_target' using errcode = '22023';
    end if;

    -- The pass belongs to the organiser of that event. First claim wins, exactly
    -- like claim_tournament_organizer: paying for someone else's tournament is a
    -- refusal, never a takeover.
    insert into public.match_organizer_claims (tournament_id, organizer_id)
    values (v_target, v_uid)
    on conflict (tournament_id) do nothing;

    if not exists (
      select 1 from public.match_organizer_claims
       where tournament_id = v_target and organizer_id = v_uid
    ) then
      raise exception 'not_tournament_organizer' using errcode = '42501';
    end if;

    -- Already premium: hand back the paid row instead of charging again.
    select * into v_row
      from public.purchases
     where profile_id = v_uid
       and stream_key = 'tournament_pass'
       and target_id = v_target
       and status = 'paid';
    if found then
      return v_row;
    end if;

    -- Retire an attempt whose window closed, so the pending index frees up.
    update public.purchases
       set status = 'expired', expired_at = now()
     where profile_id = v_uid
       and stream_key = 'tournament_pass'
       and target_id = v_target
       and status = 'pending'
       and expires_at is not null
       and expires_at <= now();

    select * into v_row
      from public.purchases
     where profile_id = v_uid
       and stream_key = 'tournament_pass'
       and target_id = v_target
       and status = 'pending'
     order by created_at desc
     limit 1;
    if found then
      return v_row;
    end if;
  else
    -- One open attempt per plan is enough; a re-tap converges on it.
    select * into v_row
      from public.purchases
     where profile_id = v_uid
       and plan_code = v_plan.code
       and status = 'pending'
     order by created_at desc
     limit 1;
    if found then
      return v_row;
    end if;
  end if;

  insert into public.purchases
    (profile_id, plan_code, stream_key, amount_minor, currency, status,
     target_kind, target_id, idempotency_key, provider, expires_at, metadata)
  values
    (v_uid, v_plan.code, v_plan.stream_key, v_plan.price_minor, v_plan.currency,
     'pending', v_kind, v_target, v_key, 'manual',
     now() + interval '72 hours',
     jsonb_build_object('plan_label', v_plan.label,
                        'stream_label', v_stream.label))
  returning * into v_row;

  perform public.log_billing_event(
    'purchase', v_row.id, 'purchase_started', 'member', v_uid,
    jsonb_build_object('plan_code', v_plan.code, 'target_id', v_target)
  );
  return v_row;
end;
$$;

revoke all on function public.start_purchase(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.start_purchase(text, text, text, text)
  to authenticated;

create or replace function public.cancel_subscription(p_plan_code text)
returns public.subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.subscriptions;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  update public.subscriptions
     set cancel_at_period_end = true
   where profile_id = v_uid
     and plan_code = trim(coalesce(p_plan_code, ''))
     and status = 'active'
  returning * into v_row;

  if not found then
    raise exception 'no_active_subscription' using errcode = '22023';
  end if;

  perform public.log_billing_event(
    'subscription', v_row.id, 'subscription_cancel_scheduled', 'member', v_uid,
    jsonb_build_object('plan_code', v_row.plan_code,
                       'current_period_end', v_row.current_period_end)
  );
  return v_row;
end;
$$;

revoke all on function public.cancel_subscription(text)
  from public, anon, authenticated;
grant execute on function public.cancel_subscription(text) to authenticated;

-- ── operator writes (service_role only) ─────────────────────────────────────
-- Manual verification for the MVP. There is no self-service path: a member
-- cannot execute any of the functions below, so a forged client response can
-- never produce a paid purchase or an entitlement.
create or replace function public.verify_purchase(
  p_purchase_id uuid,
  p_decision    text,
  p_note        text default ''
)
returns public.purchases
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor    uuid := auth.uid();
  v_decision text := lower(trim(coalesce(p_decision, '')));
  v_note     text := trim(coalesce(p_note, ''));
  v_row      public.purchases;
  v_plan     public.billing_plans;
  v_sub      public.subscriptions;
  v_feature  text;
begin
  if v_decision not in ('paid', 'failed') then
    raise exception 'invalid_decision' using errcode = '22023';
  end if;

  select * into v_row
    from public.purchases
   where id = p_purchase_id
   for update;
  if not found then
    raise exception 'purchase_not_found' using errcode = 'P0002';
  end if;

  -- Terminal states are returned untouched: a retried verification never
  -- charges twice and never grants a second entitlement.
  if v_row.status = 'paid' then
    if v_decision = 'failed' then
      raise exception 'purchase_already_paid' using errcode = '22023';
    end if;
    return v_row;
  end if;
  if v_row.status = 'refunded' then
    raise exception 'purchase_already_refunded' using errcode = '22023';
  end if;

  if v_decision = 'failed' then
    update public.purchases
       set status = 'failed',
           failed_at = now(),
           note = coalesce(nullif(v_note, ''), note)
     where id = v_row.id
    returning * into v_row;

    perform public.log_billing_event(
      'purchase', v_row.id, 'purchase_failed', 'operator', v_actor,
      jsonb_build_object('note', v_note)
    );
    return v_row;
  end if;

  update public.purchases
     set status = 'paid',
         paid_at = now(),
         note = coalesce(nullif(v_note, ''), note)
   where id = v_row.id
  returning * into v_row;

  insert into public.payment_records
    (purchase_id, kind, amount_minor, currency, method, provider_ref,
     recorded_by, note)
  values
    (v_row.id, 'charge', v_row.amount_minor, v_row.currency, v_row.provider,
     v_row.provider_ref, coalesce(nullif(v_note, ''), 'operator'), v_note)
  on conflict do nothing;

  select * into v_plan
    from public.billing_plans
   where code = v_row.plan_code;

  v_feature := coalesce(
    nullif(v_plan.features ->> 'entitlement', ''),
    v_row.stream_key || '.premium'
  );

  if v_row.stream_key = 'organizer_pro' then
    -- Start from the end of the current period when one is running, so an early
    -- renewal extends rather than restarts the subscription.
    insert into public.subscriptions
      (profile_id, plan_code, status, current_period_start, current_period_end,
       last_purchase_id, started_at)
    values
      (v_row.profile_id, v_row.plan_code, 'active', now(),
       now() + make_interval(days => coalesce(v_plan.period_days, 30)),
       v_row.id, now())
    on conflict (profile_id, plan_code) do update
       set status               = 'active',
           cancel_at_period_end = false,
           current_period_start = greatest(
             public.subscriptions.current_period_end, now()
           ),
           current_period_end   = greatest(
             public.subscriptions.current_period_end, now()
           ) + make_interval(days => coalesce(v_plan.period_days, 30)),
           last_purchase_id     = excluded.last_purchase_id,
           started_at           = coalesce(public.subscriptions.started_at, now()),
           ended_at             = null
    returning * into v_sub;

    insert into public.entitlements
      (profile_id, feature_key, source, subscription_id, target_kind, status,
       expires_at)
    values
      (v_row.profile_id, v_feature, 'subscription', v_sub.id, 'account',
       'active', v_sub.current_period_end)
    on conflict (subscription_id, feature_key) where subscription_id is not null
    do update
       set status        = 'active',
           expires_at    = excluded.expires_at,
           revoked_at    = null,
           revoke_reason = '';

    perform public.log_billing_event(
      'subscription', v_sub.id, 'subscription_activated', 'operator', v_actor,
      jsonb_build_object('plan_code', v_row.plan_code,
                         'purchase_id', v_row.id,
                         'current_period_end', v_sub.current_period_end)
    );
  else
    insert into public.entitlements
      (profile_id, feature_key, source, purchase_id, target_kind, target_id,
       status, expires_at)
    values
      (v_row.profile_id, v_feature, 'purchase', v_row.id,
       'tournament', v_row.target_id, 'active',
       case
         when v_plan.entitlement_days is null then null
         else now() + make_interval(days => v_plan.entitlement_days)
       end);

    perform public.log_billing_event(
      'entitlement', v_row.id, 'entitlement_granted', 'operator', v_actor,
      jsonb_build_object('plan_code', v_row.plan_code,
                         'feature_key', v_feature,
                         'target_id', v_row.target_id)
    );
  end if;

  perform public.log_billing_event(
    'purchase', v_row.id, 'purchase_paid', 'operator', v_actor,
    jsonb_build_object('amount_minor', v_row.amount_minor,
                       'currency', v_row.currency,
                       'note', v_note)
  );

  return v_row;
end;
$$;

create or replace function public.refund_purchase(
  p_purchase_id uuid,
  p_note        text default ''
)
returns public.purchases
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_note  text := coalesce(nullif(trim(coalesce(p_note, '')), ''), 'refunded');
  v_row   public.purchases;
  v_sub   public.subscriptions;
begin
  select * into v_row
    from public.purchases
   where id = p_purchase_id
   for update;
  if not found then
    raise exception 'purchase_not_found' using errcode = 'P0002';
  end if;

  if v_row.status = 'refunded' then
    return v_row;
  end if;
  if v_row.status <> 'paid' then
    raise exception 'purchase_not_paid' using errcode = '22023';
  end if;

  update public.purchases
     set status = 'refunded',
         refunded_at = now(),
         note = v_note
   where id = v_row.id
  returning * into v_row;

  insert into public.payment_records
    (purchase_id, kind, amount_minor, currency, method, provider_ref,
     recorded_by, note)
  values
    (v_row.id, 'refund', v_row.amount_minor, v_row.currency, v_row.provider,
     v_row.provider_ref, 'operator', v_note)
  on conflict do nothing;

  update public.entitlements
     set status = 'revoked',
         revoked_at = now(),
         revoke_reason = v_note
   where purchase_id = v_row.id
     and status <> 'revoked';

  if v_row.stream_key = 'organizer_pro' then
    select * into v_sub
      from public.subscriptions
     where profile_id = v_row.profile_id
       and plan_code = v_row.plan_code;

    if found then
      update public.subscriptions
         set status = 'refunded',
             ended_at = now(),
             cancel_at_period_end = false
       where id = v_sub.id;

      update public.entitlements
         set status = 'revoked',
             revoked_at = now(),
             revoke_reason = v_note
       where subscription_id = v_sub.id
         and status <> 'revoked';
    end if;
  end if;

  perform public.log_billing_event(
    'purchase', v_row.id, 'purchase_refunded', 'operator', v_actor,
    jsonb_build_object('amount_minor', v_row.amount_minor,
                       'currency', v_row.currency,
                       'note', v_note)
  );
  return v_row;
end;
$$;

-- Comps, partnerships and anything a future sponsorship deal hands out. The
-- grant index makes a repeat converge instead of stacking.
create or replace function public.grant_entitlement(
  p_profile_id  uuid,
  p_feature_key text,
  p_target_kind text default 'account',
  p_target_id   text default null,
  p_expires_at  timestamptz default null,
  p_note        text default ''
)
returns public.entitlements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor   uuid := auth.uid();
  v_kind    text := lower(trim(coalesce(p_target_kind, 'account')));
  v_target  text := nullif(trim(coalesce(p_target_id, '')), '');
  v_feature text := trim(coalesce(p_feature_key, ''));
  v_row     public.entitlements;
begin
  if p_profile_id is null then
    raise exception 'invalid_profile' using errcode = '22023';
  end if;

  insert into public.entitlements as e
    (profile_id, feature_key, source, target_kind, target_id, status, expires_at)
  values
    (p_profile_id, v_feature, 'grant', v_kind, v_target, 'active', p_expires_at)
  on conflict (profile_id, feature_key, target_kind, coalesce(target_id, ''))
    where source = 'grant'
  do update
     set status        = 'active',
         expires_at    = excluded.expires_at,
         revoked_at    = null,
         revoke_reason = ''
  returning * into v_row;

  perform public.log_billing_event(
    'entitlement', v_row.id, 'entitlement_granted', 'operator', v_actor,
    jsonb_build_object('feature_key', v_feature,
                       'target_kind', v_kind,
                       'target_id', v_target,
                       'note', trim(coalesce(p_note, '')))
  );
  return v_row;
end;
$$;

create or replace function public.revoke_entitlement(
  p_entitlement_id uuid,
  p_reason         text default ''
)
returns public.entitlements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor  uuid := auth.uid();
  v_reason text := coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'revoked');
  v_row    public.entitlements;
begin
  update public.entitlements
     set status = 'revoked',
         revoked_at = now(),
         revoke_reason = v_reason
   where id = p_entitlement_id
  returning * into v_row;

  if not found then
    raise exception 'entitlement_not_found' using errcode = 'P0002';
  end if;

  perform public.log_billing_event(
    'entitlement', v_row.id, 'entitlement_revoked', 'operator', v_actor,
    jsonb_build_object('reason', v_reason)
  );
  return v_row;
end;
$$;

-- Housekeeping only: reads already treat a lapsed row as expired, so a member is
-- never granted extra time by a sweep running late.
create or replace function public.expire_stale_purchases()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  with expired as (
    update public.purchases
       set status = 'expired',
           expired_at = now()
     where status = 'pending'
       and expires_at is not null
       and expires_at <= now()
    returning id, profile_id
  ), logged as (
    insert into public.billing_events
      (subject_kind, subject_id, action, actor, actor_id, detail)
    select 'purchase', id, 'purchase_expired', 'system', profile_id,
           jsonb_build_object('reason', 'expiry')
      from expired
  )
  select count(*) into v_count from expired;

  update public.subscriptions
     set status = 'expired',
         ended_at = now()
   where status = 'active'
     and current_period_end is not null
     and current_period_end <= now();

  update public.entitlements
     set status = 'expired'
   where status = 'active'
     and expires_at is not null
     and expires_at <= now();

  return v_count;
end;
$$;

revoke all on function public.verify_purchase(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.verify_purchase(uuid, text, text) to service_role;

revoke all on function public.refund_purchase(uuid, text)
  from public, anon, authenticated;
grant execute on function public.refund_purchase(uuid, text) to service_role;

revoke all on function public.grant_entitlement(uuid, text, text, text, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.grant_entitlement(uuid, text, text, text, timestamptz, text)
  to service_role;

revoke all on function public.revoke_entitlement(uuid, text)
  from public, anon, authenticated;
grant execute on function public.revoke_entitlement(uuid, text) to service_role;

revoke all on function public.expire_stale_purchases()
  from public, anon, authenticated;
grant execute on function public.expire_stale_purchases() to service_role;

commit;
