import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/core/data/local_monetization_repository.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/data/unavailable_monetization_repository.dart';
import 'package:sportika/core/state/monetization_controller.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/monetization.dart';

/// The billing state machine, exercised through the real device adapter so the
/// same rules `0009_monetization.sql` enforces are the rules the client runs.
///
/// Nothing here touches the widget layer: what matters is that a purchase only
/// becomes paid through a verification action, that a retry converges instead of
/// duplicating, and that an entitlement answers for exactly the scope it was
/// granted in.
void main() {
  const organizerId = 'acc-yasir';
  const ownedTournament = 'trn-t10';
  const someoneElsesTournament = 'trn-futsal';

  late LocalStorage storage;
  late LocalSportikaRepository device;
  late LocalMonetizationRepository billing;
  late MonetizationController controller;
  var opened = false;

  Future<MonetizationController> openBilling() async {
    SharedPreferences.setMockInitialValues({
      'sportika.onboarding_seen.v1': true,
      'sportika.session_account': organizerId,
    });
    storage = await LocalStorage.open();
    device = LocalSportikaRepository(storage);
    await device.load();
    await device.signIn(organizerId);
    expect(device.tournamentById(ownedTournament)!.organizerId, organizerId);
    expect(
      device.tournamentById(someoneElsesTournament)!.organizerId,
      isNot(organizerId),
    );
    billing = LocalMonetizationRepository(device, storage);
    controller = MonetizationController(billing);
    opened = true;
    await controller.refresh();
    return controller;
  }

  tearDown(() {
    if (!opened) return;
    opened = false;
    controller.dispose();
    billing.dispose();
    device.dispose();
  });

  /// Runs the simulated operator action and re-reads, which is the only way a
  /// member's screen ever learns that a request was paid.
  Future<void> verify(Purchase purchase) async {
    await billing.simulateVerification(purchase.id);
    await billing.reload();
  }

  group('catalogue', () {
    test('activates exactly the two MVP streams', () async {
      await openBilling();
      expect(
        billing.streams
            .where((stream) => stream.enabled)
            .map((stream) => stream.stream.key),
        [BillingStream.tournamentPass.key, BillingStream.organizerPro.key],
      );
      expect(controller.visibleStreams.map((stream) => stream.stream), [
        BillingStream.tournamentPass,
        BillingStream.organizerPro,
      ]);
      // The three planned streams are configured but never rendered, and there
      // is no plan row to buy, so the charge path cannot be reached.
      for (final stream in [
        BillingStream.featuredListing,
        BillingStream.sponsorship,
        BillingStream.analytics,
      ]) {
        expect(
          billing.streams
              .firstWhere((value) => value.stream == stream)
              .isVisible,
          isFalse,
          reason: stream.key,
        );
        expect(billing.plans.where((plan) => plan.stream == stream), isEmpty);
      }
    });

    test(
      'prices and caps come from the catalogue, not from the client',
      () async {
        await openBilling();
        expect(controller.freeEntryCap, 16);
        expect(controller.premiumEntryCap, 128);
        expect(controller.premiumGroupCounts, [1, 2, 3, 4]);
        expect(controller.offersPremiumPresets, isTrue);
        expect(
          controller.planFor(BillingStream.tournamentPass)!.priceLabel,
          'PKR 2,500',
        );
        expect(
          controller.planFor(BillingStream.organizerPro)!.priceLabel,
          'PKR 4,500',
        );
      },
    );
  });

  group('startPurchase', () {
    test('creates one pending request with a 72-hour window', () async {
      await openBilling();
      final created = await billing.startPurchase(
        planCode: 'tournament_pass_standard',
        targetKind: PurchaseTargetKind.tournament,
        targetId: ownedTournament,
        idempotencyKey: 'flow-key-000001',
      );
      expect(created.status, PaymentStatus.pending);
      expect(created.amountMinor, 250000);
      expect(created.currency, 'PKR');
      expect(created.reference, startsWith('SPK-'));
      expect(
        created.expiresAt!.difference(created.createdAt).inHours,
        closeTo(72, 1),
      );
      expect(billing.purchases, hasLength(1));
      // Nothing unlocked yet - a request is not a payment.
      expect(controller.canUsePremiumTournament(ownedTournament), isFalse);
      expect(controller.entryCapFor(ownedTournament), 16);
      expect(billing.payments, isEmpty);
      expect(
        controller.purchaseForTournament(ownedTournament)!.status,
        PaymentStatus.pending,
      );
    });

    test('a repeated idempotency key returns the stored row', () async {
      await openBilling();
      final first = await billing.startPurchase(
        planCode: 'tournament_pass_standard',
        targetKind: PurchaseTargetKind.tournament,
        targetId: ownedTournament,
        idempotencyKey: 'flow-key-000002',
      );
      final retry = await billing.startPurchase(
        planCode: 'tournament_pass_standard',
        targetKind: PurchaseTargetKind.tournament,
        targetId: ownedTournament,
        idempotencyKey: 'flow-key-000002',
      );
      expect(retry.id, first.id);
      expect(billing.purchases, hasLength(1));
    });

    test(
      'a new key for the same event converges on the live attempt',
      () async {
        await openBilling();
        final first = await billing.startPurchase(
          planCode: 'tournament_pass_standard',
          targetKind: PurchaseTargetKind.tournament,
          targetId: ownedTournament,
          idempotencyKey: 'flow-key-000003',
        );
        final again = await billing.startPurchase(
          planCode: 'tournament_pass_standard',
          targetKind: PurchaseTargetKind.tournament,
          targetId: ownedTournament,
          idempotencyKey: 'flow-key-000004',
        );
        expect(again.id, first.id);
        expect(billing.purchases, hasLength(1));
      },
    );

    test('a paid event never accepts a second pass', () async {
      await openBilling();
      final purchase = await billing.startPurchase(
        planCode: 'tournament_pass_standard',
        targetKind: PurchaseTargetKind.tournament,
        targetId: ownedTournament,
        idempotencyKey: 'flow-key-000005',
      );
      await verify(purchase);
      final replay = await billing.startPurchase(
        planCode: 'tournament_pass_standard',
        targetKind: PurchaseTargetKind.tournament,
        targetId: ownedTournament,
        idempotencyKey: 'flow-key-000006',
      );
      expect(replay.id, purchase.id);
      expect(replay.status, PaymentStatus.paid);
      expect(billing.purchases, hasLength(1));
      expect(billing.payments, hasLength(1));
    });

    test(
      'refuses a pass for a tournament the caller does not organise',
      () async {
        await openBilling();
        await expectLater(
          billing.startPurchase(
            planCode: 'tournament_pass_standard',
            targetKind: PurchaseTargetKind.tournament,
            targetId: someoneElsesTournament,
            idempotencyKey: 'flow-key-000007',
          ),
          throwsA(
            isA<MonetizationException>()
                .having((error) => error.code, 'code', '42501')
                .having(
                  (error) => error.message,
                  'message',
                  'Only the organizer of this tournament can unlock it.',
                ),
          ),
        );
        expect(billing.purchases, isEmpty);
        expect(controller.openProPurchase, isNull);
      },
    );

    test(
      'refuses an unknown plan, a target-less pass and a short key',
      () async {
        await openBilling();
        await expectLater(
          billing.startPurchase(
            planCode: 'featured_listing_spot',
            idempotencyKey: 'flow-key-000008',
          ),
          throwsA(
            isA<MonetizationException>().having(
              (error) => error.message,
              'message',
              'That plan is no longer offered.',
            ),
          ),
        );
        await expectLater(
          billing.startPurchase(
            planCode: 'tournament_pass_standard',
            idempotencyKey: 'flow-key-000009',
          ),
          throwsA(
            isA<MonetizationException>().having(
              (error) => error.code,
              'code',
              '22023',
            ),
          ),
        );
        await expectLater(
          billing.startPurchase(
            planCode: 'organizer_pro_monthly',
            idempotencyKey: 'short',
          ),
          throwsA(
            isA<MonetizationException>().having(
              (error) => error.message,
              'message',
              'The purchase reference is not valid. Try again.',
            ),
          ),
        );
        expect(billing.purchases, isEmpty);
      },
    );

    test(
      'retires an attempt whose window closed before offering a new one',
      () async {
        await openBilling();
        final stale = await billing.startPurchase(
          planCode: 'tournament_pass_standard',
          targetKind: PurchaseTargetKind.tournament,
          targetId: ownedTournament,
          idempotencyKey: 'flow-key-000010',
        );
        // Rewind the stored attempt past its payment window, the way the
        // service_role sweep would have.
        await storage.writeBilling({
          'purchases': [
            {
              'id': stale.id,
              'profile_id': organizerId,
              'plan_code': 'tournament_pass_standard',
              'stream_key': 'tournament_pass',
              'amount_minor': 250000,
              'currency': 'PKR',
              'status': 'pending',
              'target_kind': 'tournament',
              'target_id': ownedTournament,
              'idempotency_key': 'flow-key-000010',
              'provider': 'manual',
              'expires_at': DateTime.now()
                  .subtract(const Duration(hours: 1))
                  .toIso8601String(),
              'created_at': DateTime.now()
                  .subtract(const Duration(hours: 73))
                  .toIso8601String(),
              'metadata': const <String, dynamic>{},
            },
          ],
          'subscriptions': const <Map<String, dynamic>>[],
          'entitlements': const <Map<String, dynamic>>[],
          'payments': const <Map<String, dynamic>>[],
        });
        await billing.reload();
        expect(billing.purchases.single.status, PaymentStatus.pending);

        final fresh = await billing.startPurchase(
          planCode: 'tournament_pass_standard',
          targetKind: PurchaseTargetKind.tournament,
          targetId: ownedTournament,
          idempotencyKey: 'flow-key-000011',
        );
        expect(billing.purchases, hasLength(1));
        expect(billing.purchases.single.id, stale.id);
        expect(fresh.id, stale.id);
        expect(fresh.status, PaymentStatus.pending);
        expect(fresh.idempotencyKey, 'flow-key-000011');
      },
    );
  });

  group('verification grants the entitlement and nothing else', () {
    test('a paid pass unlocks exactly one tournament', () async {
      await openBilling();
      final purchase = await billing.startPurchase(
        planCode: 'tournament_pass_standard',
        targetKind: PurchaseTargetKind.tournament,
        targetId: ownedTournament,
        idempotencyKey: 'flow-key-000012',
      );
      await verify(purchase);

      expect(billing.purchases.single.status, PaymentStatus.paid);
      expect(billing.payments, hasLength(1));
      expect(billing.payments.single.kind, 'charge');
      expect(billing.payments.single.amountMinor, 250000);
      expect(controller.canUsePremiumTournament(ownedTournament), isTrue);
      expect(
        controller.canUsePremiumTournament(someoneElsesTournament),
        isFalse,
      );
      expect(
        controller.premiumSourceFor(ownedTournament),
        BillingStream.tournamentPass,
      );
      expect(controller.entryCapFor(ownedTournament), 128);
      expect(controller.groupCountsFor(ownedTournament), [1, 2, 3, 4]);
      expect(controller.offersRulePresets(someoneElsesTournament), isFalse);
      expect(controller.isPro, isFalse);
      expect(controller.subscriptions, isEmpty);
      expect(billing.entitlements.single.targetId, ownedTournament);

      // Re-verifying is a no-op: one charge line, one entitlement.
      await billing.simulateVerification(purchase.id);
      expect(billing.payments, hasLength(1));
      expect(billing.entitlements, hasLength(1));
    });

    test('an Organizer Pro payment unlocks every event and starts a period', () async {
      await openBilling();
      final purchase = await billing.startPurchase(
        planCode: 'organizer_pro_monthly',
        idempotencyKey: 'flow-key-000013',
      );
      expect(controller.isPro, isFalse);
      expect(billing.purchases.single.status, PaymentStatus.pending);
      await verify(purchase);

      expect(controller.isPro, isTrue);
      expect(controller.proSubscription!.isLive, isTrue);
      expect(
        controller.subscriptionFor('organizer_pro_monthly')!.status,
        SubscriptionStatus.active,
      );
      // Account-wide: every tournament the member organises answers yes.
      expect(controller.canUsePremiumTournament(ownedTournament), isTrue);
      expect(controller.canUsePremiumTournament('trn-padel-cup'), isTrue);
      expect(
        controller.premiumSourceFor(someoneElsesTournament),
        BillingStream.organizerPro,
        reason:
            'the Pro grant is account-wide, so the paint-time answer is yes '
            'for any id; ownership is enforced by the UI and by start_purchase',
      );
      expect(controller.hasPremiumAccountTools, isTrue);
      expect(
        billing.entitlements.single.featureKey,
        BillingFeature.organizerPremium,
      );
      expect(
        billing.entitlements.single.expiresAt,
        controller.proSubscription!.currentPeriodEnd,
      );
      expect(controller.canUsePremiumTournament(ownedTournament), isTrue);
    });

    test('renewing extends the period instead of restarting it', () async {
      await openBilling();
      final first = await billing.startPurchase(
        planCode: 'organizer_pro_monthly',
        idempotencyKey: 'flow-key-000014',
      );
      await verify(first);
      final endsAt = controller.proSubscription!.currentPeriodEnd!;

      final renewal = await billing.startPurchase(
        planCode: 'organizer_pro_monthly',
        idempotencyKey: 'flow-key-000015',
      );
      await verify(renewal);
      final extended = controller.proSubscription!.currentPeriodEnd!;

      expect(extended.isAfter(endsAt), isTrue);
      expect(controller.subscriptions, hasLength(1));
      expect(controller.proSubscription!.lastPurchaseId, isNot(first.id));
      expect(controller.entitlements, hasLength(1));
    });

    test('the authoritative check decides, not the cached read', () async {
      await openBilling();
      final purchase = await billing.startPurchase(
        planCode: 'tournament_pass_standard',
        targetKind: PurchaseTargetKind.tournament,
        targetId: ownedTournament,
        idempotencyKey: 'flow-key-000016',
      );
      expect(
        await controller.verifyEntitlement(
          tournamentId: ownedTournament,
          featureKey: BillingFeature.tournamentPremium,
        ),
        isFalse,
      );
      await verify(purchase);
      expect(
        await controller.verifyEntitlement(tournamentId: ownedTournament),
        isTrue,
      );
      expect(
        await controller.verifyEntitlement(
          tournamentId: someoneElsesTournament,
        ),
        isFalse,
      );
      expect(
        await controller.verifyEntitlement(
          featureKey: BillingFeature.organizerPremium,
        ),
        isFalse,
      );
      expect(
        await controller.confirmPremiumTournament(ownedTournament),
        isTrue,
      );
    });
  });

  group('cancel at period end', () {
    test(
      'flags the live subscription and keeps tools until it closes',
      () async {
        await openBilling();
        final purchase = await billing.startPurchase(
          planCode: 'organizer_pro_monthly',
          idempotencyKey: 'flow-key-000017',
        );
        await verify(purchase);

        await billing.cancelSubscription('organizer_pro_monthly');
        await billing.reload();
        final subscription = controller.subscriptionFor(
          'organizer_pro_monthly',
        )!;
        expect(subscription.cancelAtPeriodEnd, isTrue);
        expect(subscription.status, SubscriptionStatus.active);
        expect(subscription.isLive, isTrue);
        expect(controller.canUsePremiumTournament(ownedTournament), isTrue);
      },
    );

    test('refuses when there is nothing running', () async {
      await openBilling();
      await expectLater(
        billing.cancelSubscription('organizer_pro_monthly'),
        throwsA(
          isA<MonetizationException>().having(
            (error) => error.message,
            'message',
            'There is no active subscription to cancel.',
          ),
        ),
      );
    });

    test('an expired period stops answering', () async {
      await openBilling();
      final purchase = await billing.startPurchase(
        planCode: 'organizer_pro_monthly',
        idempotencyKey: 'flow-key-000018',
      );
      await verify(purchase);
      // Rewind the paid period so the computed predicate stops matching, which
      // is how a lapsed subscription behaves with no sweep involved.
      final past = DateTime.now().subtract(const Duration(days: 30));
      final rows = billing.purchases.map((row) {
        final written = Map<String, dynamic>.of(row.metadata);
        return <String, dynamic>{
          'id': row.id,
          'profile_id': organizerId,
          'plan_code': row.planCode,
          'stream_key': row.stream.key,
          'amount_minor': row.amountMinor,
          'currency': row.currency,
          'status': row.status.key,
          'target_kind': row.targetKind.key,
          'target_id': row.targetId,
          'idempotency_key': row.idempotencyKey,
          'provider': row.provider,
          'expires_at': row.expiresAt?.toIso8601String(),
          'created_at': row.createdAt.toIso8601String(),
          'paid_at': row.paidAt?.toIso8601String(),
          'metadata': written,
        };
      }).toList();
      await storage.writeBilling({
        'purchases': rows,
        'subscriptions': [
          {
            'id': 'sub-past',
            'profile_id': organizerId,
            'plan_code': 'organizer_pro_monthly',
            'status': 'active',
            'cancel_at_period_end': false,
            'current_period_start': past
                .subtract(const Duration(days: 30))
                .toIso8601String(),
            'current_period_end': past.toIso8601String(),
            'last_purchase_id': purchase.id,
            'started_at': past
                .subtract(const Duration(days: 30))
                .toIso8601String(),
          },
        ],
        'entitlements': [
          {
            'id': 'ent-past',
            'profile_id': organizerId,
            'feature_key': BillingFeature.organizerPremium,
            'source': 'subscription',
            'subscription_id': 'sub-past',
            'target_kind': 'account',
            'target_id': null,
            'status': 'active',
            'granted_at': past
                .subtract(const Duration(days: 30))
                .toIso8601String(),
            'expires_at': past.toIso8601String(),
          },
        ],
        'payments': const <Map<String, dynamic>>[],
      });
      await billing.reload();

      expect(controller.isPro, isFalse);
      expect(controller.hasPremiumAccountTools, isFalse);
      expect(controller.canUsePremiumTournament(ownedTournament), isFalse);
      expect(
        await controller.verifyEntitlement(tournamentId: ownedTournament),
        isFalse,
      );
      expect(
        await controller.verifyEntitlement(
          featureKey: BillingFeature.organizerPremium,
        ),
        isFalse,
      );
    });
  });

  group('persistence', () {
    test('records survive a restart of the demo world', () async {
      await openBilling();
      final purchase = await billing.startPurchase(
        planCode: 'tournament_pass_standard',
        targetKind: PurchaseTargetKind.tournament,
        targetId: ownedTournament,
        idempotencyKey: 'flow-key-000019',
      );
      await verify(purchase);
      final paidId = purchase.id;
      final entitlementCount = billing.entitlements.length;

      // A fresh adapter over the same stored document - the cold-start path.
      final reopened = LocalMonetizationRepository(device, storage);
      addTearDown(reopened.dispose);
      await reopened.reload();
      expect(reopened.purchases.single.id, paidId);
      expect(reopened.purchases.single.status, PaymentStatus.paid);
      expect(reopened.entitlements, hasLength(entitlementCount));
      expect(reopened.payments.single.kind, 'charge');
      expect(
        reopened.plans.map((plan) => plan.code),
        containsAll(['tournament_pass_standard', 'organizer_pro_monthly']),
      );
    });

    test(
      'a corrupt billing document is dropped rather than blocking start-up',
      () async {
        await openBilling();
        final purchase = await billing.startPurchase(
          planCode: 'organizer_pro_monthly',
          idempotencyKey: 'flow-key-000020',
        );
        await verify(purchase);
        SharedPreferences.setMockInitialValues({
          'sportika.onboarding_seen.v1': true,
          'sportika.session_account': organizerId,
          'sportika.billing.v1': '{"purchases": not json',
        });
        final store = await LocalStorage.open();
        final state = LocalSportikaRepository(store);
        await state.load();
        await state.signIn(organizerId);
        final recovered = LocalMonetizationRepository(state, store);
        addTearDown(recovered.dispose);
        await recovered.reload();
        expect(recovered.purchases, isEmpty);
        expect(recovered.error, isNull);
        // The catalogue still renders, so the screen is not a dead end.
        expect(recovered.plans, isNotEmpty);
        state.dispose();
      },
    );

    test('signing out hides every billing row from the adapter', () async {
      await openBilling();
      final purchase = await billing.startPurchase(
        planCode: 'organizer_pro_monthly',
        idempotencyKey: 'flow-key-000021',
      );
      await verify(purchase);

      await device.signOut();
      expect(billing.snapshot.isEmpty, isTrue);
      expect(billing.purchases, isEmpty);
      expect(billing.entitlements, isEmpty);
      expect(
        await billing.hasEntitlement(
          featureKey: BillingFeature.organizerPremium,
        ),
        isFalse,
      );
    });

    test('refuses to write without an account at all', () async {
      await openBilling();
      await device.signOut();
      await expectLater(
        billing.startPurchase(
          planCode: 'organizer_pro_monthly',
          idempotencyKey: 'flow-key-000022',
        ),
        throwsA(
          isA<MonetizationException>().having(
            (error) => error.code,
            'code',
            '28000',
          ),
        ),
      );
      expect(billing.purchases, isEmpty);
    });
  });

  group('a live build with no billing wired', () {
    test('fails closed instead of falling back to demo data', () async {
      await openBilling();
      final repo = UnavailableMonetizationRepository();
      addTearDown(repo.dispose);
      final seam = repo as MonetizationRepository;
      expect(seam.snapshot.isEmpty, isTrue);
      expect(seam.plans, isEmpty);
      expect(seam.streams, isEmpty);
      expect(seam.loading, isFalse);
      expect(seam.error, 'Billing is not connected in this build.');
      await seam.reload();
      expect(seam.error, 'Billing is not connected in this build.');

      await expectLater(
        seam.startPurchase(
          planCode: 'organizer_pro_monthly',
          idempotencyKey: 'flow-key-000023',
        ),
        throwsA(isA<MonetizationException>()),
      );
      await expectLater(
        seam.cancelSubscription('organizer_pro_monthly'),
        throwsA(isA<MonetizationException>()),
      );
      await expectLater(
        seam.simulateVerification('pur-1'),
        throwsA(
          isA<MonetizationException>().having(
            (error) => error.message,
            'message',
            'Billing is not connected in this build.',
          ),
        ),
      );
      expect(
        await seam.hasEntitlement(featureKey: BillingFeature.organizerPremium),
        isFalse,
      );

      // A controller over that seam can never unlock a premium tool.
      final guarded = MonetizationController(seam);
      addTearDown(guarded.dispose);
      expect(guarded.freeEntryCap, 16);
      expect(guarded.activePlans, isEmpty);
      expect(guarded.canUsePremiumTournament(ownedTournament), isFalse);
      expect(guarded.entryCapFor(ownedTournament), 16);
      expect(guarded.groupCountsFor(ownedTournament), isEmpty);
      expect(await guarded.confirmPremiumTournament(ownedTournament), isFalse);
    });
  });
}
