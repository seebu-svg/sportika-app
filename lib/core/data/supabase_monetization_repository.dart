import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/monetization.dart';

/// Billing against PostgreSQL.
///
/// Reads use PostgREST on tables whose RLS policies already scope every row to
/// `auth.uid()`, so no method takes a profile id. Writes are the security-definer
/// RPCs from `0009_monetization.sql`; the two operator functions (verify and
/// refund) have no EXECUTE grant for a member, which is what makes a forged
/// client response harmless.
///
/// Every successful write reloads instead of patching the snapshot, because a
/// verification changes a purchase, a ledger line and an entitlement at once.
class SupabaseMonetizationRepository extends ChangeNotifier
    with MonetizationSnapshotAccess
    implements MonetizationRepository {
  SupabaseMonetizationRepository({
    required SupabaseClient client,
    // A named parameter cannot be a private initializing formal, so the field is
    // assigned from the matching parameter below.
    // ignore: prefer_initializing_formals
  }) : _client = client;

  final SupabaseClient _client;

  BillingSnapshot _snapshot = BillingSnapshot.empty;
  bool _loading = false;
  String? _error;

  static const String _streamColumns =
      'stream_key, label, summary, mode, enabled, ui_visible, sort_order, '
      'settings, activation_note';
  static const String _planColumns =
      'code, stream_key, label, tagline, description, price_minor, currency, '
      'billing_interval, period_days, entitlement_days, benefits, features, '
      'payment_instructions, active, sort_order';
  static const String _purchaseColumns =
      'id, profile_id, plan_code, stream_key, amount_minor, currency, status, '
      'target_kind, target_id, idempotency_key, provider, expires_at, paid_at, '
      'failed_at, expired_at, refunded_at, note, metadata, created_at';
  static const String _subscriptionColumns =
      'id, profile_id, plan_code, status, current_period_start, '
      'current_period_end, cancel_at_period_end, last_purchase_id, started_at, '
      'ended_at';
  static const String _entitlementColumns =
      'id, profile_id, feature_key, source, purchase_id, subscription_id, '
      'target_kind, target_id, status, granted_at, expires_at, revoked_at, '
      'revoke_reason';
  static const String _paymentColumns =
      'id, purchase_id, kind, amount_minor, currency, method, provider_ref, '
      'note, at';

  @override
  BillingSnapshot get snapshot => _snapshot;

  @override
  bool get loading => _loading;

  @override
  String? get error => _error;

  @override
  Future<void> reload() async {
    if (_client.auth.currentUser == null) {
      _snapshot = BillingSnapshot.empty;
      _error = 'Sign in again to see your plans and billing.';
      _loading = false;
      notifyListeners();
      return;
    }
    if (_loading) return;

    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait<List<dynamic>>([
        _client
            .from('monetization_streams')
            .select(_streamColumns)
            .order('sort_order'),
        _client.from('billing_plans').select(_planColumns).order('sort_order'),
        _client
            .from('purchases')
            .select(_purchaseColumns)
            .order('created_at', ascending: false),
        _client.from('subscriptions').select(_subscriptionColumns),
        _client
            .from('entitlements')
            .select(_entitlementColumns)
            .order('granted_at', ascending: false),
        _client
            .from('payment_records')
            .select(_paymentColumns)
            .order('at', ascending: false),
      ]);

      _snapshot = BillingSnapshot(
        streams: _rows(results[0]).map(MonetizationStream.fromRow).toList(),
        plans: _rows(results[1]).map(BillingPlan.fromRow).toList(),
        purchases: _rows(results[2]).map(Purchase.fromRow).toList(),
        subscriptions: _rows(results[3]).map(Subscription.fromRow).toList(),
        entitlements: _rows(results[4]).map(Entitlement.fromRow).toList(),
        payments: _rows(results[5]).map(PaymentRecord.fromRow).toList(),
      );
    } catch (error) {
      _error = _mapError(
        error,
        fallback: 'Plans and billing could not be loaded.',
      ).message;
    } finally {
      _loading = false;
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
    _requireSession();
    try {
      final row = await _client.rpc(
        'start_purchase',
        params: {
          'p_plan_code': planCode,
          'p_target_kind': targetKind.key,
          'p_target_id': targetId,
          'p_idempotency_key': idempotencyKey,
        },
      );
      if (row is! Map) {
        throw const MonetizationException(
          'The purchase could not be started. Try again in a moment.',
        );
      }
      await reload();
      return Purchase.fromRow(Map<String, dynamic>.from(row));
    } on MonetizationException {
      rethrow;
    } catch (error) {
      throw _mapError(error, fallback: 'The purchase could not be started.');
    }
  }

  @override
  Future<bool> hasEntitlement({
    required String featureKey,
    PurchaseTargetKind targetKind = PurchaseTargetKind.account,
    String? targetId,
  }) async {
    _requireSession();
    try {
      final value = await _client.rpc(
        'has_entitlement',
        params: {
          'p_feature_key': featureKey,
          'p_target_kind': targetKind.key,
          'p_target_id': targetId,
        },
      );
      return value == true;
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Your premium status could not be confirmed.',
      );
    }
  }

  @override
  Future<void> cancelSubscription(String planCode) async {
    _requireSession();
    try {
      await _client.rpc(
        'cancel_subscription',
        params: {'p_plan_code': planCode},
      );
      await reload();
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'The subscription could not be cancelled.',
      );
    }
  }

  /// Against a real backend there is nothing to simulate: `verify_purchase` has
  /// no EXECUTE grant for a member, so only the interface's refusal is correct
  /// here, and it is stated explicitly so nobody adds a shortcut later.
  @override
  Future<void> simulateVerification(String purchaseId) async =>
      throw const MonetizationException(
        'Payments are confirmed by an operator, not in the app.',
        code: '42501',
      );

  void _requireSession() {
    if (_client.auth.currentUser == null) {
      throw const MonetizationException(
        'Sign in again to manage your plans.',
        code: '28000',
      );
    }
  }

  static List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  MonetizationException _mapError(Object error, {required String fallback}) {
    if (error is MonetizationException) return error;
    if (error is PostgrestException) {
      if (error.code == '28000') {
        return const MonetizationException(
          'Sign in again to manage your plans.',
          code: '28000',
        );
      }
      if (error.code == '42501') {
        return const MonetizationException(
          'Only the organizer of this tournament can unlock it.',
          code: '42501',
        );
      }
      if (error.code == '23505') {
        return const MonetizationException(
          'That purchase already exists. Pull to refresh to see it.',
          code: '23505',
        );
      }
      return MonetizationException(
        _messageFor(error.message, fallback: fallback),
        code: error.code,
      );
    }
    return MonetizationException(fallback);
  }

  /// The RPCs raise stable snake_case identifiers; the member sees a sentence.
  static String _messageFor(String raw, {required String fallback}) {
    final message = raw.toLowerCase();
    if (message.contains('plan_not_available')) {
      return 'That plan is not available right now.';
    }
    if (message.contains('unknown_plan')) {
      return 'That plan is no longer offered.';
    }
    if (message.contains('invalid_target')) {
      return 'Choose the tournament this pass should unlock.';
    }
    if (message.contains('not_tournament_organizer') ||
        message.contains('tournament_already_claimed')) {
      return 'Only the organizer of this tournament can unlock it.';
    }
    if (message.contains('purchase_already_paid')) {
      return 'That purchase is already marked paid.';
    }
    if (message.contains('purchase_already_refunded')) {
      return 'That purchase has been refunded.';
    }
    if (message.contains('purchase_not_paid')) {
      return 'Only a paid purchase can be refunded.';
    }
    if (message.contains('no_active_subscription')) {
      return 'There is no active subscription to cancel.';
    }
    if (message.contains('invalid_idempotency_key') ||
        message.contains('purchase_not_found') ||
        message.contains('invalid_decision') ||
        message.contains('invalid_entitlement')) {
      return fallback;
    }
    return fallback;
  }
}
