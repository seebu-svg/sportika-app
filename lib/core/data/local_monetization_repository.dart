import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/data/monetization_seed.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/monetization.dart';

/// Billing for a device-only build.
///
/// The catalogue is the demo seed; purchases, subscriptions, entitlements and
/// ledger lines live in their own [LocalStorage] document rather than in the
/// tournament document, because in a live build they belong to the server. The
/// state machine mirrors `0009_monetization.sql` exactly — pending, paid,
/// failed, expired, refunded, one charge and one refund per purchase — so the
/// screens and their tests behave the same in both worlds.
class LocalMonetizationRepository extends ChangeNotifier
    with MonetizationSnapshotAccess
    implements MonetizationRepository {
  LocalMonetizationRepository(this._device, this._storage) {
    _device.addListener(_relay);
    _read();
  }

  final LocalSportikaRepository _device;
  final LocalStorage _storage;

  BillingSnapshot _snapshot = BillingSnapshot.empty;
  String? _error;

  List<Map<String, dynamic>> _purchases = const [];
  List<Map<String, dynamic>> _subscriptions = const [];
  List<Map<String, dynamic>> _entitlements = const [];
  List<Map<String, dynamic>> _payments = const [];

  @override
  BillingSnapshot get snapshot => _snapshot;

  /// Reading the device document is synchronous, so a demo build never has a
  /// load in flight; the screens still get a truthful answer for "empty versus
  /// not loaded yet".
  @override
  bool get loading => false;

  @override
  String? get error => _error;

  void _relay() {
    // A different account signs in: the visible billing rows change with it.
    _read();
    notifyListeners();
  }

  @override
  void dispose() {
    _device.removeListener(_relay);
    super.dispose();
  }

  // ── Read ────────────────────────────────────────────────────────────────

  @override
  Future<void> reload() async {
    _read();
    notifyListeners();
  }

  void _read() {
    final document = _storage.readBilling() ?? const <String, dynamic>{};
    _purchases = _rows(document['purchases']);
    _subscriptions = _rows(document['subscriptions']);
    _entitlements = _rows(document['entitlements']);
    _payments = _rows(document['payments']);
    _error = null;
    _rebuildSnapshot();
  }

  void _rebuildSnapshot() {
    final uid = _device.currentAccount?.id;
    _snapshot = BillingSnapshot(
      streams: demoMonetizationStreams,
      plans: demoBillingPlans.where((plan) => plan.active).toList(),
      purchases:
          uid == null
                ? const []
                : _owned(_purchases, uid).map(Purchase.fromRow).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      subscriptions: uid == null
          ? const []
          : _owned(_subscriptions, uid).map(Subscription.fromRow).toList(),
      entitlements: uid == null
          ? const []
          : _owned(_entitlements, uid).map(Entitlement.fromRow).toList(),
      payments:
          uid == null
                ? const []
                : _paymentsOwned(uid).map(PaymentRecord.fromRow).toList()
            ..sort((a, b) => b.at.compareTo(a.at)),
    );
  }

  // ── Writes ──────────────────────────────────────────────────────────────

  @override
  Future<Purchase> startPurchase({
    required String planCode,
    PurchaseTargetKind targetKind = PurchaseTargetKind.account,
    String? targetId,
    required String idempotencyKey,
  }) async {
    final uid = _requireAccount();
    final key = idempotencyKey.trim();
    if (key.length < 8 || key.length > 80) {
      throw const MonetizationException(
        'The purchase reference is not valid. Try again.',
        code: '22023',
      );
    }

    final plan = _planFor(planCode);
    if (plan == null) {
      throw const MonetizationException('That plan is no longer offered.');
    }
    final stream = _streamFor(plan.stream);
    if (stream == null || !stream.enabled || !plan.active) {
      throw const MonetizationException(
        'That plan is not available right now.',
        code: '22023',
      );
    }

    // A repeated key is a retry, not a second attempt.
    final retried = _firstWhere(
      _purchases,
      (row) => row['profile_id'] == uid && row['idempotency_key'] == key,
    );
    if (retried != null) return Purchase.fromRow(retried);

    final target = targetId?.trim();
    if (plan.stream == BillingStream.tournamentPass) {
      if (targetKind != PurchaseTargetKind.tournament ||
          target == null ||
          target.isEmpty) {
        throw const MonetizationException(
          'Choose the tournament this pass should unlock.',
          code: '22023',
        );
      }
      // The pass is the organizer's; paying for someone else's event is refused.
      final tournament = _device.tournamentById(target);
      if (tournament == null || tournament.organizerId != uid) {
        throw const MonetizationException(
          'Only the organizer of this tournament can unlock it.',
          code: '42501',
        );
      }

      final paid = _firstWhere(
        _purchases,
        (row) =>
            row['profile_id'] == uid &&
            row['stream_key'] == BillingStream.tournamentPass.key &&
            row['target_id'] == target &&
            row['status'] == PaymentStatus.paid.key,
      );
      if (paid != null) return Purchase.fromRow(paid);

      // Retire attempts whose window closed, then converge on a live one.
      var changed = false;
      final now = DateTime.now();
      for (final row in _purchases) {
        if (row['profile_id'] == uid &&
            row['stream_key'] == BillingStream.tournamentPass.key &&
            row['target_id'] == target &&
            row['status'] == PaymentStatus.pending.key &&
            _date(row['expires_at'])?.isBefore(now) == true) {
          row['status'] = PaymentStatus.expired.key;
          row['expired_at'] = now.toIso8601String();
          changed = true;
        }
      }

      final pending = _firstWhere(
        _purchases,
        (row) =>
            row['profile_id'] == uid &&
            row['stream_key'] == BillingStream.tournamentPass.key &&
            row['target_id'] == target &&
            row['status'] == PaymentStatus.pending.key,
      );
      if (pending != null) {
        if (changed) await _persist();
        return Purchase.fromRow(pending);
      }
    } else {
      final pending = _firstWhere(
        _purchases,
        (row) =>
            row['profile_id'] == uid &&
            row['plan_code'] == plan.code &&
            row['status'] == PaymentStatus.pending.key,
      );
      if (pending != null) return Purchase.fromRow(pending);
    }

    final createdAt = DateTime.now();
    final row = <String, dynamic>{
      'id': newId('pur'),
      'profile_id': uid,
      'plan_code': plan.code,
      'stream_key': plan.stream.key,
      'amount_minor': plan.priceMinor,
      'currency': plan.currency,
      'status': PaymentStatus.pending.key,
      'target_kind': targetKind.key,
      'target_id': target,
      'idempotency_key': key,
      'provider': 'manual',
      'expires_at': createdAt.add(const Duration(hours: 72)).toIso8601String(),
      'paid_at': null,
      'failed_at': null,
      'expired_at': null,
      'refunded_at': null,
      'note': '',
      'metadata': {'plan_label': plan.label, 'stream_label': stream.label},
      'created_at': createdAt.toIso8601String(),
    };
    _purchases = [..._purchases, row];
    await _persist();
    return Purchase.fromRow(row);
  }

  @override
  Future<bool> hasEntitlement({
    required String featureKey,
    PurchaseTargetKind targetKind = PurchaseTargetKind.account,
    String? targetId,
  }) async {
    final uid = _device.currentAccount?.id;
    if (uid == null) return false;
    return _owned(_entitlements, uid)
        .map(Entitlement.fromRow)
        .any((entitlement) => entitlement.covers(featureKey, target: targetId));
  }

  @override
  Future<void> cancelSubscription(String planCode) async {
    final uid = _requireAccount();
    final row = _firstWhere(
      _subscriptions,
      (entry) =>
          entry['profile_id'] == uid &&
          entry['plan_code'] == planCode &&
          entry['status'] == SubscriptionStatus.active.key,
    );
    if (row == null) {
      throw const MonetizationException(
        'There is no active subscription to cancel.',
        code: '22023',
      );
    }
    row['cancel_at_period_end'] = true;
    await _persist();
  }

  /// Demo only: stands in for the operator who verifies a bank transfer.
  ///
  /// A release build has no equivalent, on purpose. This applies the same rules
  /// as `verify_purchase`: one charge line, one entitlement, and a renewal that
  /// extends rather than restarts a running period.
  @override
  Future<void> simulateVerification(String purchaseId) async {
    final uid = _requireAccount();
    final row = _firstWhere(
      _purchases,
      (entry) => entry['id'] == purchaseId && entry['profile_id'] == uid,
    );
    if (row == null) {
      throw const MonetizationException('That purchase could not be found.');
    }
    if (row['status'] == PaymentStatus.paid.key) return;
    if (row['status'] == PaymentStatus.refunded.key) {
      throw const MonetizationException('That purchase has been refunded.');
    }

    final plan = _planFor(row['plan_code'] as String? ?? '');
    final now = DateTime.now();
    row['status'] = PaymentStatus.paid.key;
    row['paid_at'] = now.toIso8601String();

    if (!_payments.any(
      (entry) =>
          entry['purchase_id'] == purchaseId && entry['kind'] == 'charge',
    )) {
      _payments = [
        ..._payments,
        <String, dynamic>{
          'id': newId('pay'),
          'purchase_id': purchaseId,
          'kind': 'charge',
          'amount_minor': row['amount_minor'],
          'currency': row['currency'],
          'method': 'manual',
          'provider_ref': '',
          'note': 'Simulated operator verification',
          'at': now.toIso8601String(),
        },
      ];
    }

    final feature =
        plan?.entitlementFeature ??
        '${row['stream_key'] ?? BillingStream.tournamentPass.key}.premium';

    if (row['stream_key'] == BillingStream.organizerPro.key) {
      final existing = _firstWhere(
        _subscriptions,
        (entry) =>
            entry['profile_id'] == uid &&
            entry['plan_code'] == row['plan_code'],
      );
      final currentEnd = _date(existing?['current_period_end']);
      final periodStart = currentEnd != null && currentEnd.isAfter(now)
          ? currentEnd
          : now;
      final periodEnd = periodStart.add(Duration(days: plan?.periodDays ?? 30));
      final subscription = <String, dynamic>{
        'id': existing?['id'] ?? newId('sub'),
        'profile_id': uid,
        'plan_code': row['plan_code'],
        'status': SubscriptionStatus.active.key,
        'current_period_start': periodStart.toIso8601String(),
        'current_period_end': periodEnd.toIso8601String(),
        'cancel_at_period_end': false,
        'last_purchase_id': purchaseId,
        'started_at': existing?['started_at'] ?? now.toIso8601String(),
        'ended_at': null,
      };
      _subscriptions = [
        ..._subscriptions.where((entry) => entry['id'] != subscription['id']),
        subscription,
      ];

      final entitlement = _firstWhere(
        _entitlements,
        (entry) => entry['subscription_id'] == subscription['id'],
      );
      final granted = <String, dynamic>{
        'id': entitlement?['id'] ?? newId('ent'),
        'profile_id': uid,
        'feature_key': feature,
        'source': 'subscription',
        'purchase_id': null,
        'subscription_id': subscription['id'],
        'target_kind': PurchaseTargetKind.account.key,
        'target_id': null,
        'status': EntitlementStatus.active.key,
        'granted_at': entitlement?['granted_at'] ?? now.toIso8601String(),
        'expires_at': periodEnd.toIso8601String(),
        'revoked_at': null,
        'revoke_reason': '',
      };
      _entitlements = [
        ..._entitlements.where((entry) => entry['id'] != granted['id']),
        granted,
      ];
    } else {
      _entitlements = [
        ..._entitlements,
        <String, dynamic>{
          'id': newId('ent'),
          'profile_id': uid,
          'feature_key': feature,
          'source': 'purchase',
          'purchase_id': purchaseId,
          'subscription_id': null,
          'target_kind': PurchaseTargetKind.tournament.key,
          'target_id': row['target_id'],
          'status': EntitlementStatus.active.key,
          'granted_at': now.toIso8601String(),
          'expires_at': null,
          'revoked_at': null,
          'revoke_reason': '',
        },
      ];
    }

    await _persist();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _requireAccount() {
    final account = _device.currentAccount;
    if (account == null) {
      throw const MonetizationException(
        'Sign in again to manage your plans.',
        code: '28000',
      );
    }
    return account.id;
  }

  BillingPlan? _planFor(String? code) {
    for (final plan in demoBillingPlans) {
      if (plan.code == code) return plan;
    }
    return null;
  }

  MonetizationStream? _streamFor(BillingStream stream) {
    for (final value in demoMonetizationStreams) {
      if (value.stream == stream) return value;
    }
    return null;
  }

  Future<void> _persist() async {
    await _storage.writeBilling({
      'purchases': _purchases,
      'subscriptions': _subscriptions,
      'entitlements': _entitlements,
      'payments': _payments,
    });
    _rebuildSnapshot();
    notifyListeners();
  }

  static List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: true);
  }

  static List<Map<String, dynamic>> _owned(
    List<Map<String, dynamic>> rows,
    String profileId,
  ) => rows
      .where((row) => row['profile_id'] == profileId)
      .toList(growable: false);

  List<Map<String, dynamic>> _paymentsOwned(String profileId) {
    final ids = _owned(
      _purchases,
      profileId,
    ).map((row) => row['id']).whereType<String>().toSet();
    return _payments
        .where((row) => ids.contains(row['purchase_id']))
        .toList(growable: false);
  }

  static Map<String, dynamic>? _firstWhere(
    List<Map<String, dynamic>> rows,
    bool Function(Map<String, dynamic> row) test,
  ) {
    for (final row in rows) {
      if (test(row)) return row;
    }
    return null;
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
