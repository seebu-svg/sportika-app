import 'package:sportika/shared/models/monetization.dart';

/// The device-only catalogue: what `DEMO_MODE` builds render instead of the
/// `billing_plans` table.
///
/// This is demo data, exactly like the seeded accounts and tournaments in
/// [seed.dart] — a live build reads the catalogue from PostgreSQL and never
/// touches these constants. Keeping the shape identical means the pricing
/// screen, the gating logic and the tests are the same in both worlds.
const List<MonetizationStream> demoMonetizationStreams = [
  MonetizationStream(
    stream: BillingStream.tournamentPass,
    label: 'Tournament pass',
    summary:
        'Premium tools for one event: more entries, draw controls and rule '
        'presets.',
    mode: 'one_time',
    enabled: true,
    uiVisible: true,
    sortOrder: 1,
    settings: {'free_entry_cap': 16},
    activationNote: 'MVP stream. Active.',
  ),
  MonetizationStream(
    stream: BillingStream.organizerPro,
    label: 'Organizer Pro',
    summary:
        'Monthly subscription: every tournament you organise keeps the premium '
        'tools.',
    mode: 'subscription',
    enabled: true,
    uiVisible: true,
    sortOrder: 2,
    settings: {},
    activationNote: 'MVP stream. Active.',
  ),
  MonetizationStream(
    stream: BillingStream.featuredListing,
    label: 'Featured tournaments',
    summary: 'Paid discovery placement above the regular tournament list.',
    mode: 'placement',
    enabled: false,
    uiVisible: false,
    sortOrder: 3,
    settings: {},
    activationNote: 'Planned. Disabled by configuration.',
  ),
  MonetizationStream(
    stream: BillingStream.sponsorship,
    label: 'Sponsorships and advertising',
    summary: 'Sponsored banners, branded placements and sports partnerships.',
    mode: 'contract',
    enabled: false,
    uiVisible: false,
    sortOrder: 4,
    settings: {},
    activationNote: 'Planned. Disabled by configuration.',
  ),
  MonetizationStream(
    stream: BillingStream.analytics,
    label: 'Advanced analytics',
    summary: 'Premium tournament reports, performance insights and exports.',
    mode: 'addon',
    enabled: false,
    uiVisible: false,
    sortOrder: 5,
    settings: {},
    activationNote: 'Planned. Disabled by configuration.',
  ),
];

const List<BillingPlan> demoBillingPlans = [
  BillingPlan(
    code: 'tournament_pass_standard',
    stream: BillingStream.tournamentPass,
    label: 'Tournament pass',
    tagline: 'Premium tools for one event',
    description:
        'Unlock the premium tournament toolkit for a single event you '
        'organise. Entries, draws and the official results flow stay exactly '
        'as they are - the pass only raises the ceiling.',
    priceMinor: 250000,
    currency: 'PKR',
    interval: BillingInterval.oneTime,
    periodDays: null,
    entitlementDays: null,
    benefits: [
      'Up to 128 confirmed entries',
      'Custom group draw and rule presets',
      'Premium badge on your tournament',
    ],
    features: {
      'entitlement': BillingFeature.tournamentPremium,
      'max_entries': 128,
      'group_counts': [1, 2, 3, 4],
      'rules_presets': true,
    },
    paymentInstructions:
        'Transfer the amount to the Sportika collection account and use the '
        'reference code shown on your purchase screen as the payment '
        'description. An operator verifies the transfer, usually within one '
        'working day.',
    active: true,
    sortOrder: 1,
  ),
  BillingPlan(
    code: 'organizer_pro_monthly',
    stream: BillingStream.organizerPro,
    label: 'Organizer Pro',
    tagline: 'Premium tools across every tournament',
    description:
        'A monthly subscription that keeps the premium toolkit on for every '
        'event you organise while it is active. Basic match creation and '
        'official scoring are free and are never affected.',
    priceMinor: 450000,
    currency: 'PKR',
    interval: BillingInterval.month,
    periodDays: 30,
    entitlementDays: null,
    benefits: [
      'Premium tools on every tournament you organise',
      'Up to 128 confirmed entries',
      'Draw controls and rule presets',
      'Priority organiser support',
    ],
    features: {
      'entitlement': BillingFeature.organizerPremium,
      'max_entries': 128,
      'group_counts': [1, 2, 3, 4],
      'rules_presets': true,
    },
    paymentInstructions:
        'Transfer the monthly amount to the Sportika collection account and '
        'use the reference code shown on your purchase screen as the payment '
        'description. An operator verifies the transfer and your subscription '
        'starts from the verification day.',
    active: true,
    sortOrder: 2,
  ),
];
