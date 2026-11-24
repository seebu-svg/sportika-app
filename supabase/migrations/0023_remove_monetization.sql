-- Sportika MVP is free: the monetization module is removed.
--
-- Migration 0009 created billing streams, plans, purchases, subscriptions,
-- entitlements, payment records, a billing audit trail and the RPCs that drove
-- them. None of that exists any more: no pricing catalogue, no upgrade flow, no
-- payment records, no entitlement checks anywhere in the app.
--
-- Nothing else depended on these objects. Organizer and scorer authority live in
-- match_organizer_claims, tournaments.organizer_id and matches.organizer_id /
-- scorer_id, and scoring, result publication and disputes were never gated on an
-- entitlement, so those permissions are untouched.
--
-- Every statement is convergent: a fresh database that never ran 0009 simply
-- drops nothing.
--
-- History note: 0009_monetization.sql was deleted from this directory. A linked
-- project that already recorded it still lists the version, so drop that ledger
-- row once before the next `supabase db push`:
--   supabase migration repair --status reverted 0009
begin;

-- ── RPCs ────────────────────────────────────────────────────────────────────
-- Operator-only functions (service_role grants disappear with the functions).
drop function if exists public.verify_purchase(uuid, text, text);
drop function if exists public.refund_purchase(uuid, text);
drop function if exists public.grant_entitlement(
  uuid, text, text, text, timestamptz, text
);
drop function if exists public.revoke_entitlement(uuid, text);
drop function if exists public.expire_stale_purchases();

-- Member-facing functions.
drop function if exists public.start_purchase(text, text, text, text);
drop function if exists public.cancel_subscription(text);
drop function if exists public.has_entitlement(text, text, text);

-- Internal helpers.
drop function if exists public.entitlement_is_live(text, timestamptz);
drop function if exists public.log_billing_event(
  text, uuid, text, text, uuid, jsonb, text
);

-- ── Tables ──────────────────────────────────────────────────────────────────
-- Ordered child-first. Policies, indexes and triggers on these tables go with
-- them; public.touch_updated_at() predates 0009 and stays.
drop table if exists public.billing_events;
drop table if exists public.payment_records;
drop table if exists public.entitlements;
drop table if exists public.subscriptions;
drop table if exists public.purchases;
drop table if exists public.billing_plans;
drop table if exists public.monetization_streams;

commit;
