import 'dart:async';
import 'dart:math';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/monetization.dart';

/// Plans, purchases, subscriptions and the entitlement answers the rest of the
/// app asks for.
///
/// Two different questions live here and they are deliberately separate:
///
/// * [canUsePremiumTournament] paints from the loaded snapshot, so a badge or a
///   locked chip draws instantly.
/// * [verifyEntitlement] asks the server every time, and is what a screen calls
///   before it lets a premium value through.
///
/// Nothing here ever infers payment success from a tap; a purchase is only paid
/// once PostgreSQL says so.
class MonetizationController extends FeatureController<MonetizationRepository> {
  MonetizationController(super.repo) {
    // A lazy provider can be created while a destination is building.
    // Defer repository notifications until that build has completed.
    unawaited(Future<void>.microtask(refresh));
  }

  final Random _random = Random();

  bool get loading => repo.loading;
  String? get error => repo.error;

  List<MonetizationStream> get streams => repo.streams;
  List<BillingPlan> get plans => repo.plans;
  List<Purchase> get purchases => repo.purchases;
  List<Subscription> get subscriptions => repo.subscriptions;
  List<Entitlement> get entitlements => repo.entitlements;
  List<PaymentRecord> get payments => repo.payments;

  /// Streams that are both activated server-side and allowed to be painted. The
  /// three future streams stay absent rather than greyed out.
  List<MonetizationStream> get visibleStreams {
    final visible = repo.streams.where((stream) => stream.isVisible).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return visible;
  }

  List<BillingPlan> plansFor(BillingStream stream) {
    final matching =
        repo.plans
            .where((plan) => plan.stream == stream && plan.active)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return matching;
  }

  BillingPlan? planFor(BillingStream stream) => plansFor(stream).firstOrNull;

  BillingPlan? planByCode(String code) =>
      repo.plans.where((plan) => plan.code == code).firstOrNull;

  List<BillingPlan> get activePlans {
    final active = repo.plans.where((plan) => plan.active).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return active;
  }

  /// The entry ceiling a member without any premium entitlement may use. It comes
  /// from the stream configuration so pricing and limits stay configurable; the
  /// fallback only exists so an empty catalogue cannot crash the form.
  int get freeEntryCap {
    final stream = repo.streams
        .where((value) => value.stream == BillingStream.tournamentPass)
        .firstOrNull;
    return stream?.settingInt('free_entry_cap') ?? 16;
  }

  Subscription? subscriptionFor(String planCode) => repo.subscriptions
      .where((subscription) => subscription.planCode == planCode)
      .firstOrNull;

  /// The live Organizer Pro subscription, if there is one.
  Subscription? get proSubscription {
    for (final subscription in repo.subscriptions) {
      final plan = planByCode(subscription.planCode);
      if (plan?.stream == BillingStream.organizerPro && subscription.isLive) {
        return subscription;
      }
    }
    return null;
  }

  bool get isPro => proSubscription != null;

  /// Instant answer for painting. Backed by the loaded snapshot only.
  bool canUsePremiumTournament(String tournamentId) {
    if (_accountWidePremium) return true;
    return repo.entitlements.any(
      (entitlement) => entitlement.covers(
        BillingFeature.tournamentPremium,
        target: tournamentId,
      ),
    );
  }

  bool get _accountWidePremium => repo.entitlements.any(
    (entitlement) => entitlement.covers(BillingFeature.organizerPremium),
  );

  /// Whether the loaded snapshot already says the account carries the premium
  /// toolkit. Painting only; accepting a premium value calls [verifyEntitlement]
  /// instead, because the snapshot is exactly as fresh as the last read.
  bool get hasPremiumAccountTools => _accountWidePremium;

  /// The pass or subscription a tournament's premium state comes from, for
  /// wording like "unlocked with your Organizer Pro subscription".
  BillingStream? premiumSourceFor(String tournamentId) {
    if (_accountWidePremium) return BillingStream.organizerPro;
    for (final entitlement in repo.entitlements) {
      if (entitlement.covers(
        BillingFeature.tournamentPremium,
        target: tournamentId,
      )) {
        return BillingStream.tournamentPass;
      }
    }
    return null;
  }

  /// The entry ceiling a premium tournament may use, straight from the plan row.
  /// The fallback only covers a catalogue that is loaded but silent on limits.
  int get premiumEntryCap {
    final plan =
        planFor(BillingStream.organizerPro) ??
        planFor(BillingStream.tournamentPass);
    return plan?.maxEntries ?? 128;
  }

  /// The entry ceiling for one tournament: the premium plan's cap when it is
  /// unlocked, otherwise the configured free cap.
  int entryCapFor(String tournamentId) =>
      canUsePremiumTournament(tournamentId) ? premiumEntryCap : freeEntryCap;

  /// Group counts a premium organizer may pick. Empty keeps the engine default.
  List<int> get premiumGroupCounts {
    final plan =
        planFor(BillingStream.organizerPro) ??
        planFor(BillingStream.tournamentPass);
    return plan?.groupCounts ?? const <int>[];
  }

  /// Whether the plan offers the extra rule presets at all - the entitlement
  /// still has to be confirmed before the UI shows them.
  bool get offersPremiumPresets {
    final plan =
        planFor(BillingStream.organizerPro) ??
        planFor(BillingStream.tournamentPass);
    return plan?.offersRulePresets ?? false;
  }

  /// Group counts a premium organizer may pick for one tournament. Empty keeps
  /// the engine default.
  List<int> groupCountsFor(String tournamentId) {
    if (!canUsePremiumTournament(tournamentId)) return const <int>[];
    return premiumGroupCounts;
  }

  bool offersRulePresets(String tournamentId) =>
      canUsePremiumTournament(tournamentId) && offersPremiumPresets;

  /// The live pass for a tournament, or the open attempt waiting on verification.
  Purchase? purchaseForTournament(String tournamentId) {
    for (final purchase in repo.purchases) {
      if (purchase.stream == BillingStream.tournamentPass &&
          purchase.targetId == tournamentId &&
          (purchase.status == PaymentStatus.pending ||
              purchase.status == PaymentStatus.paid)) {
        return purchase;
      }
    }
    return null;
  }

  /// The open Pro attempt, so the subscription screen can show "awaiting
  /// verification" instead of offering a second purchase.
  Purchase? get openProPurchase {
    for (final purchase in repo.purchases) {
      if (purchase.stream == BillingStream.organizerPro &&
          purchase.status == PaymentStatus.pending) {
        return purchase;
      }
    }
    return null;
  }

  List<PaymentRecord> paymentsFor(String purchaseId) => repo.payments
      .where((payment) => payment.purchaseId == purchaseId)
      .toList(growable: false);

  /// The authoritative check. Call this before accepting a premium value; it is
  /// the only path that asks PostgreSQL rather than the cached snapshot.
  Future<bool> verifyEntitlement({
    String? tournamentId,
    String featureKey = BillingFeature.tournamentPremium,
  }) async {
    try {
      return await repo.hasEntitlement(
        featureKey: featureKey,
        targetKind: tournamentId == null
            ? PurchaseTargetKind.account
            : PurchaseTargetKind.tournament,
        targetId: tournamentId,
      );
    } on MonetizationException {
      return false;
    }
  }

  /// Whether the member may use the premium toolkit for [tournamentId] right
  /// now: the snapshot for painting, the server for the decision.
  Future<bool> confirmPremiumTournament(String tournamentId) async {
    if (canUsePremiumTournament(tournamentId)) return true;
    return verifyEntitlement(tournamentId: tournamentId);
  }

  Future<Purchase> startPurchase({
    required String planCode,
    PurchaseTargetKind targetKind = PurchaseTargetKind.account,
    String? targetId,
    String? idempotencyKey,
  }) async {
    final purchase = await repo.startPurchase(
      planCode: planCode,
      targetKind: targetKind,
      targetId: targetId,
      idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
    );
    await refresh();
    return purchase;
  }

  Future<void> cancelSubscription(String planCode) async {
    await repo.cancelSubscription(planCode);
    await refresh();
  }

  /// Demo builds only; the release seam throws.
  Future<void> simulateVerification(String purchaseId) async {
    await repo.simulateVerification(purchaseId);
    await refresh();
  }

  Future<void> refresh() => repo.reload();

  /// A fresh key per attempt. The server also converges by target, so a retry
  /// with a new key still lands on the open attempt instead of a second one.
  String newIdempotencyKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${_random.nextInt(0x7fffffff).toRadixString(16)}';
}
