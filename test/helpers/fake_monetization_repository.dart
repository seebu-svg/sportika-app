import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/data/monetization_seed.dart';
import 'package:sportika/shared/models/monetization.dart';

/// Test-only stand-in for the billing server.
///
/// It answers through the same [BillingSnapshot] shape `0009_monetization.sql`
/// returns, so the pricing, upgrade, subscription and history screens can be
/// driven through a paid, pending, empty or failing ledger without a project and
/// without a device document. Nothing here is imported by `lib/`.
///
/// The fake never silently invents an entitlement: a purchase only becomes paid
/// when a test calls [markPaid] or flips [verifyPendingOnReload], which is what
/// makes it usable as a proof that a screen reads payment state from the
/// repository rather than from a tap.
class MonetizationFixture extends ChangeNotifier
    with MonetizationSnapshotAccess
    implements MonetizationRepository {
  MonetizationFixture({
    List<MonetizationStream>? streams,
    List<BillingPlan>? plans,
    List<Purchase>? purchases,
    List<Subscription>? subscriptions,
    List<Entitlement>? entitlements,
    List<PaymentRecord>? payments,
  }) : _streams = [...?streams, ...?_defaultStreams(streams)],
       _plans = [...?plans, ...?_defaultPlans(plans)],
       _purchases = [...?purchases],
       _subscriptions = [...?subscriptions],
       _entitlements = [...?entitlements],
       _payments = [...?payments] {
    _rebuild();
  }

  static List<MonetizationStream>? _defaultStreams(
    List<MonetizationStream>? given,
  ) => given == null ? demoMonetizationStreams : null;

  static List<BillingPlan>? _defaultPlans(List<BillingPlan>? given) =>
      given == null ? demoBillingPlans : null;

  List<MonetizationStream> _streams;
  List<BillingPlan> _plans;
  List<Purchase> _purchases;
  List<Subscription> _subscriptions;
  List<Entitlement> _entitlements;
  List<PaymentRecord> _payments;

  BillingSnapshot _snapshot = BillingSnapshot.empty;

  @override
  BillingSnapshot get snapshot => _snapshot;

  @override
  bool get loading => _loading;
  bool _loading = false;

  @override
  String? get error => _error;
  String? _error;

  /// Thrown by the next [reload]. The message is then reported through [error],
  /// exactly as the Supabase adapter reports a failed catalogue read.
  Object? loadError;

  /// Thrown by the next [startPurchase] / [cancelSubscription] / [hasEntitlement]
  /// call. A [MonetizationException] message reaches the member verbatim.
  Object? purchaseError;
  Object? cancelError;
  Object? entitlementError;

  /// A stalled read, used to assert the loading state before it resolves.
  Completer<void>? loadBarrier;

  /// Forces the answer of [hasEntitlement] regardless of the seeded rows. This
  /// is how a test separates "the snapshot says yes" from "the server says yes".
  bool? entitlementAnswer;

  /// When true, the next [reload] verifies every pending purchase, exactly as an
  /// operator's `verify_purchase` would.
  bool verifyPendingOnReload = false;

  // ── Recorded calls ──────────────────────────────────────────────────────
  int reloads = 0;
  final List<String> startCalls = <String>[];
  final List<String> entitlementCalls = <String>[];
  final List<String> cancelCalls = <String>[];
  final List<String> simulateCalls = <String>[];
  final List<String> idempotencyKeys = <String>[];

  // ── Seeding helpers ─────────────────────────────────────────────────────

  /// Puts the fixture into the "nothing bought yet" state without touching the
  /// catalogue, which is what the pricing screen still needs to render.
  void clearRecords() {
    _purchases = [];
    _subscriptions = [];
    _entitlements = [];
    _payments = [];
    _rebuild();
    notifyListeners();
  }

  /// Drops the whole catalogue, to prove a build without migration 0009 shows
  /// an error rather than a purchasable plan.
  void removeCatalogue({
    String message = 'Billing is not available in this build.',
  }) {
    _streams = [];
    _plans = [];
    _error = message;
    _rebuild();
    notifyListeners();
  }

  Purchase addPurchase({
    String? id,
    String planCode = 'tournament_pass_standard',
    BillingStream stream = BillingStream.tournamentPass,
    PaymentStatus status = PaymentStatus.pending,
    PurchaseTargetKind targetKind = PurchaseTargetKind.tournament,
    String? targetId = 't-1',
    int? amountMinor,
    String? idempotencyKey,
    DateTime? createdAt,
    DateTime? expiresAt,
    String note = '',
  }) {
    final plan = _planFor(planCode);
    final row = Purchase(
      id: id ?? 'pur-${_purchases.length + 1}',
      profileId: 'me',
      planCode: planCode,
      stream: stream,
      amountMinor: amountMinor ?? plan?.priceMinor ?? 250000,
      currency: 'PKR',
      status: status,
      targetKind: targetKind,
      targetId: targetId,
      idempotencyKey: idempotencyKey ?? 'key-${_purchases.length + 1}0000000',
      provider: 'manual',
      expiresAt: expiresAt ?? DateTime(2026, 11, 18, 9),
      createdAt: createdAt ?? DateTime(2026, 11, 15, 9),
      paidAt: status == PaymentStatus.paid ? DateTime(2026, 11, 15, 12) : null,
      expiredAt: status == PaymentStatus.expired
          ? DateTime(2026, 11, 18, 9)
          : null,
      refundedAt: status == PaymentStatus.refunded
          ? DateTime(2026, 11, 16, 9)
          : null,
      note: note,
      metadata: {
        'plan_label': plan?.label ?? planCode,
        'stream_label': stream.label,
      },
    );
    _purchases = [..._purchases, row];
    _rebuild();
    return row;
  }

  /// A paid purchase plus the ledger line and the entitlement the real RPC
  /// would have written with it.
  void addPaidWithEntitlement({
    String planCode = 'tournament_pass_standard',
    String? targetId = 't-1',
    PurchaseTargetKind targetKind = PurchaseTargetKind.tournament,
    DateTime? expiresAt,
  }) {
    final plan = _planFor(planCode)!;
    final purchase = addPurchase(
      planCode: planCode,
      stream: plan.stream,
      status: PaymentStatus.paid,
      targetKind: targetKind,
      targetId: targetId,
    );
    _payments = [
      ..._payments,
      PaymentRecord(
        id: 'pay-${purchase.id}',
        purchaseId: purchase.id,
        kind: 'charge',
        amountMinor: purchase.amountMinor,
        currency: purchase.currency,
        method: 'manual',
        at: DateTime(2026, 11, 15, 12),
        note: 'Operator verified the transfer',
      ),
    ];
    addEntitlement(
      featureKey: plan.entitlementFeature ?? BillingFeature.tournamentPremium,
      targetKind: targetKind,
      targetId: targetKind == PurchaseTargetKind.tournament ? targetId : null,
      expiresAt: expiresAt,
    );
    if (plan.stream == BillingStream.organizerPro) {
      setSubscription(planCode: plan.code, lastPurchaseId: purchase.id);
    }
    _rebuild();
    notifyListeners();
  }

  void addEntitlement({
    required String featureKey,
    PurchaseTargetKind targetKind = PurchaseTargetKind.account,
    String? targetId,
    EntitlementStatus status = EntitlementStatus.active,
    DateTime? expiresAt,
    String source = 'grant',
  }) {
    _entitlements = [
      ..._entitlements,
      Entitlement(
        id: 'ent-${_entitlements.length + 1}',
        profileId: 'me',
        featureKey: featureKey,
        source: source,
        status: status,
        targetKind: targetKind,
        targetId: targetId,
        grantedAt: DateTime(2026, 11, 15, 12),
        expiresAt: expiresAt,
        revokedAt: status == EntitlementStatus.revoked
            ? DateTime(2026, 11, 16, 12)
            : null,
        revokeReason: status == EntitlementStatus.revoked ? 'Refunded' : '',
      ),
    ];
    _rebuild();
  }

  /// Replaces the subscription rows, used to script active / cancelling /
  /// expired states directly.
  void setSubscription({
    String planCode = 'organizer_pro_monthly',
    SubscriptionStatus status = SubscriptionStatus.active,
    bool cancelAtPeriodEnd = false,
    Duration period = const Duration(days: 30),
    String? lastPurchaseId,
  }) {
    final end = DateTime.now().add(
      status == SubscriptionStatus.expired ? -period : period,
    );
    _subscriptions = [
      Subscription(
        id: 'sub-$planCode',
        profileId: 'me',
        planCode: planCode,
        status: status,
        cancelAtPeriodEnd: cancelAtPeriodEnd,
        currentPeriodStart: end.subtract(period),
        currentPeriodEnd: end,
        lastPurchaseId: lastPurchaseId,
        startedAt: end.subtract(period),
      ),
    ];
    _rebuild();
    notifyListeners();
  }

  /// The operator action the app can never perform itself.
  void markPaid(String purchaseId, {String note = 'Operator verified'}) {
    for (final purchase in [..._purchases]) {
      if (purchase.id != purchaseId) continue;
      final verified = Purchase(
        id: purchase.id,
        profileId: purchase.profileId,
        planCode: purchase.planCode,
        stream: purchase.stream,
        amountMinor: purchase.amountMinor,
        currency: purchase.currency,
        status: PaymentStatus.paid,
        targetKind: purchase.targetKind,
        targetId: purchase.targetId,
        idempotencyKey: purchase.idempotencyKey,
        provider: purchase.provider,
        expiresAt: purchase.expiresAt,
        createdAt: purchase.createdAt,
        paidAt: DateTime(2026, 11, 15, 12),
        note: note,
        metadata: purchase.metadata,
      );
      _purchases = [
        ..._purchases.where((row) => row.id != purchaseId),
        verified,
      ];
      if (!_payments.any((row) => row.purchaseId == purchaseId)) {
        _payments = [
          ..._payments,
          PaymentRecord(
            id: 'pay-$purchaseId',
            purchaseId: purchaseId,
            kind: 'charge',
            amountMinor: purchase.amountMinor,
            currency: purchase.currency,
            method: 'manual',
            at: DateTime(2026, 11, 15, 12),
            note: note,
          ),
        ];
      }
      final plan = _planFor(purchase.planCode);
      addEntitlement(
        featureKey:
            plan?.entitlementFeature ?? BillingFeature.tournamentPremium,
        targetKind: purchase.targetKind,
        targetId: purchase.targetKind == PurchaseTargetKind.tournament
            ? purchase.targetId
            : null,
        source: 'purchase',
      );
      if (plan?.stream == BillingStream.organizerPro) {
        setSubscription();
      }
    }
    _rebuild();
    notifyListeners();
  }

  // ── Repository surface ──────────────────────────────────────────────────

  @override
  Future<void> reload() async {
    reloads++;
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (loadBarrier != null) await loadBarrier!.future;
      if (loadError != null) throw loadError!;
      if (verifyPendingOnReload) {
        verifyPendingOnReload = false;
        for (final purchase in _purchases.where(
          (row) => row.status == PaymentStatus.pending,
        )) {
          markPaid(purchase.id);
        }
      }
    } catch (error) {
      _error = error is MonetizationException
          ? error.message
          : 'Plans and billing could not be loaded.';
    } finally {
      _loading = false;
      _rebuild();
      notifyListeners();
    }
  }

  @override
  Future<Purchase> startPurchase({
    required String planCode,
    PurchaseTargetKind targetKind = PurchaseTargetKind.account,
    String? targetId,
    required String idempotencyKey,
  }) async {
    startCalls.add('$planCode|${targetKind.key}|${targetId ?? '-'}');
    idempotencyKeys.add(idempotencyKey);
    if (purchaseError != null) throw purchaseError!;
    final plan = _planFor(planCode);
    if (plan == null) {
      throw const MonetizationException('That plan is no longer offered.');
    }
    if (idempotencyKey.trim().length < 8) {
      throw const MonetizationException(
        'The purchase reference is not valid. Try again.',
        code: '22023',
      );
    }
    // A repeated key is a retry, so it must land on the stored row.
    final retried = _purchases.where(
      (purchase) => purchase.idempotencyKey == idempotencyKey,
    );
    if (retried.isNotEmpty) return retried.first;
    final purchase = addPurchase(
      planCode: planCode,
      stream: plan.stream,
      targetKind: targetKind,
      targetId: targetKind == PurchaseTargetKind.tournament
          ? (targetId ?? 't-1')
          : null,
      idempotencyKey: idempotencyKey,
    );
    _rebuild();
    notifyListeners();
    return purchase;
  }

  @override
  Future<bool> hasEntitlement({
    required String featureKey,
    PurchaseTargetKind targetKind = PurchaseTargetKind.account,
    String? targetId,
  }) async {
    entitlementCalls.add('$featureKey|${targetKind.key}|${targetId ?? '-'}');
    if (entitlementError != null) throw entitlementError!;
    if (entitlementAnswer != null) return entitlementAnswer!;
    return _entitlements.any(
      (entitlement) => entitlement.covers(featureKey, target: targetId),
    );
  }

  @override
  Future<void> cancelSubscription(String planCode) async {
    cancelCalls.add(planCode);
    if (cancelError != null) throw cancelError!;
    final row = _subscriptions.where(
      (subscription) =>
          subscription.planCode == planCode &&
          subscription.status == SubscriptionStatus.active,
    );
    if (row.isEmpty) {
      throw const MonetizationException(
        'There is no active subscription to cancel.',
        code: '22023',
      );
    }
    setSubscription(
      planCode: planCode,
      cancelAtPeriodEnd: true,
      period:
          row.first.currentPeriodEnd?.difference(DateTime.now()) ??
          const Duration(days: 30),
    );
  }

  /// Release builds never reach this: the shipped seam throws. The fake keeps a
  /// recording implementation so the demo-only button can still be exercised.
  @override
  Future<void> simulateVerification(String purchaseId) async {
    simulateCalls.add(purchaseId);
    if (purchaseError != null) throw purchaseError!;
    markPaid(purchaseId, note: 'Simulated operator verification');
  }

  void _rebuild() {
    final purchases = [..._purchases]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _snapshot = BillingSnapshot(
      streams: _streams,
      plans: _plans,
      purchases: purchases,
      subscriptions: List.unmodifiable(_subscriptions),
      entitlements: List.unmodifiable(_entitlements),
      payments: [..._payments]..sort((a, b) => b.at.compareTo(a.at)),
    );
  }

  BillingPlan? _planFor(String code) =>
      _plans.where((plan) => plan.code == code).firstOrNull;
}
