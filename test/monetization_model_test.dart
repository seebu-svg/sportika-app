import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/shared/models/monetization.dart';

/// The pure model layer. Everything the billing screens print is decoded here
/// from a PostgREST row, so these tests are what keeps a JSONB shape change
/// from silently turning a price into `PKR 0`.
void main() {
  group('formatMoney', () {
    test('groups thousands on whole amounts', () {
      expect(formatMoney(250000, 'PKR'), 'PKR 2,500');
      expect(formatMoney(450000, 'PKR'), 'PKR 4,500');
      expect(formatMoney(1000000, 'PKR'), 'PKR 10,000');
      expect(formatMoney(123456700, 'PKR'), 'PKR 1,234,567');
    });

    test('keeps a fraction only when the minor units are not zero', () {
      expect(formatMoney(0, 'PKR'), 'PKR 0');
      expect(formatMoney(100, 'PKR'), 'PKR 1');
      expect(formatMoney(99, 'PKR'), 'PKR 0.99');
      expect(formatMoney(150, 'PKR'), 'PKR 1.50');
      expect(formatMoney(123456789, 'PKR'), 'PKR 1,234,567.89');
    });

    test('puts the sign in front of the amount, not the currency', () {
      expect(formatMoney(-250000, 'PKR'), 'PKR -2,500');
    });

    test('honours whatever currency the row carries', () {
      expect(formatMoney(150000, 'USD'), 'USD 1,500');
    });
  });

  group('status parsing', () {
    test('covers exactly the five required payment states', () {
      expect(PaymentStatus.values.map((s) => s.key), [
        'pending',
        'paid',
        'failed',
        'expired',
        'refunded',
      ]);
    });

    test('treats only pending as open', () {
      expect(PaymentStatus.pending.isOpen, isTrue);
      expect(PaymentStatus.pending.isTerminal, isFalse);
      for (final status in PaymentStatus.values.where(
        (value) => value != PaymentStatus.pending,
      )) {
        expect(status.isTerminal, isTrue, reason: status.key);
      }
    });

    test('defaults an unknown server value to pending, never to paid', () {
      // Fail-closed: a status this build does not know must not unlock tools.
      expect(PaymentStatus.fromKey('gateway_settled'), PaymentStatus.pending);
      expect(PaymentStatus.fromKey(null), PaymentStatus.pending);
      expect(PaymentStatus.fromKey('refunded'), PaymentStatus.refunded);
    });

    test('round-trips the subscription and entitlement vocabularies', () {
      expect(SubscriptionStatus.values.map((s) => s.key), [
        'pending',
        'active',
        'past_due',
        'expired',
        'cancelled',
        'refunded',
      ]);
      expect(SubscriptionStatus.fromKey('past_due').label, 'Payment due');
      expect(SubscriptionStatus.fromKey('nope').label, 'Not started');
      expect(EntitlementStatus.fromKey('revoked'), EntitlementStatus.revoked);
      expect(EntitlementStatus.fromKey('bogus'), EntitlementStatus.active);
      expect(BillingInterval.fromKey('month').label, 'monthly');
      expect(BillingInterval.fromKey(null), BillingInterval.oneTime);
      expect(
        PurchaseTargetKind.fromKey('campaign'),
        PurchaseTargetKind.campaign,
      );
      expect(PurchaseTargetKind.fromKey(''), PurchaseTargetKind.account);
    });

    test('an unknown stream key parses to null instead of guessing', () {
      expect(BillingStream.tryParse('lobby_booster'), isNull);
      expect(BillingStream.tryParse(null), isNull);
      expect(
        BillingStream.tryParse('organizer_pro'),
        BillingStream.organizerPro,
      );
    });
  });

  group('MonetizationStream.fromRow', () {
    test('only an enabled and visible stream is painted', () {
      MonetizationStream row({required bool enabled, required bool visible}) =>
          MonetizationStream.fromRow({
            'stream_key': 'sponsorship',
            'label': 'Sponsorships and advertising',
            'summary': 'Sponsored banners.',
            'mode': 'contract',
            'enabled': enabled,
            'ui_visible': visible,
            'sort_order': 4,
            'settings': {'free_entry_cap': 16},
            'activation_note': 'Planned.',
          });

      expect(row(enabled: true, visible: true).isVisible, isTrue);
      expect(row(enabled: true, visible: false).isVisible, isFalse);
      expect(row(enabled: false, visible: true).isVisible, isFalse);
    });

    test('reads a numeric setting from a string, a num or an int', () {
      final stream = MonetizationStream.fromRow({
        'stream_key': 'tournament_pass',
        'settings': {'free_entry_cap': '16', 'wide': 8.0, 'exact': 12},
      });
      expect(stream.settingInt('free_entry_cap'), 16);
      expect(stream.settingInt('wide'), 8);
      expect(stream.settingInt('exact'), 12);
      expect(stream.settingInt('missing'), isNull);
    });

    test('falls back to the raw key when the label is blank', () {
      final stream = MonetizationStream.fromRow({
        'stream_key': 'analytics',
        'label': '   ',
      });
      expect(stream.stream, BillingStream.analytics);
      expect(stream.label, 'analytics');
      expect(stream.summary, '');
      expect(stream.enabled, isFalse);
    });
  });

  group('BillingPlan.fromRow', () {
    Map<String, dynamic> planRow([Map<String, dynamic>? override]) => {
      'code': 'tournament_pass_standard',
      'stream_key': 'tournament_pass',
      'label': 'Tournament pass',
      'tagline': 'Premium tools for one event',
      'description': 'One event.',
      'price_minor': 250000,
      'currency': 'PKR',
      'billing_interval': 'one_time',
      'period_days': null,
      'entitlement_days': null,
      'benefits': [
        'Up to 128 confirmed entries',
        '',
        null,
        'Premium badge on your tournament',
      ],
      'features': {
        'entitlement': 'tournament.premium',
        'max_entries': 128,
        'group_counts': [1, 2, 3, 4],
        'rules_presets': true,
      },
      'payment_instructions': 'Transfer and quote the reference.',
      'active': true,
      'sort_order': 1,
      ...?override,
    };

    test('decodes price, interval and the machine-readable features', () {
      final plan = BillingPlan.fromRow(planRow());
      expect(plan.code, 'tournament_pass_standard');
      expect(plan.stream, BillingStream.tournamentPass);
      expect(plan.priceLabel, 'PKR 2,500');
      expect(plan.priceSuffix, '');
      expect(plan.entitlementFeature, BillingFeature.tournamentPremium);
      expect(plan.maxEntries, 128);
      expect(plan.groupCounts, [1, 2, 3, 4]);
      expect(plan.offersRulePresets, isTrue);
      // Blank and null bullets are dropped, not rendered as empty rows.
      expect(plan.benefits, [
        'Up to 128 confirmed entries',
        'Premium badge on your tournament',
      ]);
    });

    test('a monthly plan carries its interval and period', () {
      final plan = BillingPlan.fromRow(
        planRow({
          'code': 'organizer_pro_monthly',
          'stream_key': 'organizer_pro',
          'billing_interval': 'month',
          'period_days': 30,
          'price_minor': 450000,
        }),
      );
      expect(plan.stream, BillingStream.organizerPro);
      expect(plan.interval, BillingInterval.month);
      expect(plan.periodDays, 30);
      expect(plan.priceSuffix, '/ monthly');
      expect(plan.priceLabel, 'PKR 4,500');
    });

    test(
      'treats a missing active flag as active and an explicit false as off',
      () {
        final row = planRow()..remove('active');
        expect(BillingPlan.fromRow(row).active, isTrue);
        expect(BillingPlan.fromRow(planRow({'active': false})).active, isFalse);
      },
    );

    test('ignores malformed group counts instead of offering them', () {
      final plan = BillingPlan.fromRow(
        planRow({
          'features': {
            'group_counts': [0, -1, 2, '3', 'x', null],
          },
        }),
      );
      expect(plan.groupCounts, [2, 3]);
      expect(plan.maxEntries, isNull);
      expect(plan.entitlementFeature, isNull);
      expect(plan.offersRulePresets, isFalse);
    });

    test('a non-list benefits value decodes to no bullets', () {
      expect(
        BillingPlan.fromRow(planRow({'benefits': 'nope'})).benefits,
        isEmpty,
      );
    });
  });

  group('Purchase.fromRow', () {
    Map<String, dynamic> purchaseRow([Map<String, dynamic>? override]) => {
      'id': 'f1a2b3c4-0506-4708-890a-bbccddeeff00',
      'profile_id': 'acc-yasir',
      'plan_code': 'tournament_pass_standard',
      'stream_key': 'tournament_pass',
      'amount_minor': 250000,
      'currency': 'PKR',
      'status': 'paid',
      'target_kind': 'tournament',
      'target_id': 'trn-t10',
      'idempotency_key': '1731-9f2c',
      'provider': 'manual',
      'expires_at': '2026-11-18T09:00:00.000Z',
      'created_at': '2026-11-15T09:00:00.000Z',
      'paid_at': '2026-11-15T12:30:00.000Z',
      'failed_at': null,
      'expired_at': null,
      'refunded_at': null,
      'note': 'Transfer matched',
      'metadata': {'plan_label': 'Tournament pass'},
      ...?override,
    };

    test('decodes the snapshot columns the ledger prints', () {
      final purchase = Purchase.fromRow(purchaseRow());
      expect(purchase.profileId, 'acc-yasir');
      expect(purchase.stream, BillingStream.tournamentPass);
      expect(purchase.status, PaymentStatus.paid);
      expect(purchase.targetKind, PurchaseTargetKind.tournament);
      expect(purchase.targetId, 'trn-t10');
      expect(purchase.amountLabel, 'PKR 2,500');
      expect(purchase.provider, 'manual');
      expect(purchase.planLabel, 'Tournament pass');
      expect(purchase.paidAt, isNotNull);
      expect(purchase.expiredAt, isNull);
      expect(purchase.createdAt.year, 2026);
    });

    test('reference is the short upper-cased head of the id', () {
      final purchase = Purchase.fromRow(purchaseRow());
      expect(purchase.reference, 'SPK-F1A2B3C4');
      expect(purchase.reference.length, 12);
      // A short or malformed id still yields a printable handle.
      expect(Purchase.fromRow(purchaseRow({'id': 'abc'})).reference, 'SPK-ABC');
      expect(Purchase.fromRow(purchaseRow({'id': null})).reference, 'SPK-');
    });

    test('a null target stays null so account purchases read as account', () {
      final purchase = Purchase.fromRow(
        purchaseRow({'target_kind': null, 'target_id': null}),
      );
      expect(purchase.targetKind, PurchaseTargetKind.account);
      expect(purchase.targetId, isNull);
      expect(purchase.metadata, isNotEmpty);
    });

    test('defaults a missing amount to zero rather than crashing', () {
      final purchase = Purchase.fromRow(
        purchaseRow({'amount_minor': null, 'currency': null}),
      );
      expect(purchase.amountMinor, 0);
      expect(purchase.amountLabel, 'PKR 0');
    });
  });

  group('Entitlement', () {
    Entitlement build({
      String featureKey = BillingFeature.tournamentPremium,
      PurchaseTargetKind targetKind = PurchaseTargetKind.tournament,
      String? targetId = 'trn-t10',
      EntitlementStatus status = EntitlementStatus.active,
      DateTime? expiresAt,
    }) => Entitlement(
      id: 'ent-1',
      profileId: 'acc-yasir',
      featureKey: featureKey,
      source: 'purchase',
      status: status,
      targetKind: targetKind,
      targetId: targetId,
      grantedAt: DateTime(2026, 11, 15),
      expiresAt: expiresAt,
    );

    test('an account-wide grant answers for every target', () {
      final pro = build(
        featureKey: BillingFeature.organizerPremium,
        targetKind: PurchaseTargetKind.account,
        targetId: null,
      );
      expect(pro.covers(BillingFeature.organizerPremium), isTrue);
      expect(
        pro.covers(BillingFeature.organizerPremium, target: 'trn-t10'),
        isTrue,
      );
      expect(pro.covers(BillingFeature.tournamentPremium), isFalse);
    });

    test('a pass answers only for its own tournament', () {
      final pass = build();
      expect(
        pass.covers(BillingFeature.tournamentPremium, target: 'trn-t10'),
        isTrue,
      );
      expect(
        pass.covers(BillingFeature.tournamentPremium, target: 'trn-padel-cup'),
        isFalse,
      );
      expect(pass.covers(BillingFeature.tournamentPremium), isFalse);
    });

    test('expiry and revocation end the grant', () {
      expect(
        build(expiresAt: DateTime.now().subtract(const Duration(days: 1)))
            .isLive,
        isFalse,
      );
      expect(
        build(expiresAt: DateTime.now().add(const Duration(days: 1))).isLive,
        isTrue,
      );
      expect(build(status: EntitlementStatus.revoked).isLive, isFalse);
      expect(
        build(status: EntitlementStatus.expired)
            .covers(BillingFeature.tournamentPremium, target: 'trn-t10'),
        isFalse,
      );
    });
  });

  group('Subscription.isLive', () {
    Subscription build({
      SubscriptionStatus status = SubscriptionStatus.active,
      DateTime? currentPeriodEnd,
    }) => Subscription(
      id: 'sub-1',
      profileId: 'acc-yasir',
      planCode: 'organizer_pro_monthly',
      status: status,
      cancelAtPeriodEnd: false,
      currentPeriodEnd: currentPeriodEnd,
    );

    test('only an active period that has not run out counts', () {
      expect(build().isLive, isTrue);
      expect(build(currentPeriodEnd: null).isLive, isTrue);
      expect(
        build(currentPeriodEnd: DateTime.now().add(const Duration(days: 3)))
            .isLive,
        isTrue,
      );
      expect(
        build(
          currentPeriodEnd: DateTime.now().subtract(const Duration(seconds: 1)),
        ).isLive,
        isFalse,
      );
      expect(build(status: SubscriptionStatus.cancelled).isLive, isFalse);
      expect(build(status: SubscriptionStatus.pastDue).isLive, isFalse);
    });
  });

  group('PaymentRecord and BillingSnapshot', () {
    test('decodes a ledger line and knows a refund', () {
      final charge = PaymentRecord.fromRow({
        'id': 'pay-1',
        'purchase_id': 'pur-1',
        'kind': 'charge',
        'amount_minor': 250000,
        'currency': 'PKR',
        'method': 'manual',
        'at': '2026-11-15T12:30:00.000Z',
        'note': 'Operator verified',
      });
      expect(charge.isRefund, isFalse);
      expect(charge.amountLabel, 'PKR 2,500');
      expect(charge.purchaseId, 'pur-1');
      final refund = PaymentRecord.fromRow({
        'id': 'pay-2',
        'purchase_id': 'pur-1',
        'kind': 'refund',
        'amount_minor': -250000,
      });
      expect(refund.isRefund, isTrue);
      expect(refund.amountLabel, 'PKR -2,500');
    });

    test('an empty snapshot is empty and the default lists are inert', () {
      expect(BillingSnapshot.empty.isEmpty, isTrue);
      expect(BillingSnapshot.empty.purchases, isEmpty);
      expect(const BillingSnapshot(plans: []).isEmpty, isTrue);
      expect(
        BillingSnapshot(
          purchases: [
            Purchase(
              id: 'x',
              profileId: 'p',
              planCode: 'c',
              stream: BillingStream.tournamentPass,
              amountMinor: 0,
              currency: 'PKR',
              status: PaymentStatus.pending,
              targetKind: PurchaseTargetKind.account,
              targetId: null,
              idempotencyKey: 'k',
              provider: 'manual',
              expiresAt: null,
              createdAt: DateTime(2026, 11, 15),
            ),
          ],
        ).isEmpty,
        isFalse,
      );
    });
  });

  test('entitlement feature keys match the strings the RPC stores', () {
    expect(BillingFeature.tournamentPremium, 'tournament.premium');
    expect(BillingFeature.organizerPremium, 'organizer.premium');
  });
}
