import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/monetization.dart';

/// A live build that forgot to inject the server repository.
///
/// It publishes an empty catalogue and refuses every purchase, so a build can
/// never fabricate an entitlement by falling back to demo data.
class UnavailableMonetizationRepository extends ChangeNotifier
    with MonetizationSnapshotAccess
    implements MonetizationRepository {
  UnavailableMonetizationRepository();

  @override
  BillingSnapshot get snapshot => BillingSnapshot.empty;

  @override
  bool get loading => false;

  @override
  String? get error => 'Billing is not connected in this build.';

  @override
  Future<void> reload() async => notifyListeners();

  @override
  Future<Purchase> startPurchase({
    required String planCode,
    PurchaseTargetKind targetKind = PurchaseTargetKind.account,
    String? targetId,
    required String idempotencyKey,
  }) async => throw const MonetizationException(
    'Billing is not connected in this build.',
    code: 'billing_unavailable',
  );

  @override
  Future<bool> hasEntitlement({
    required String featureKey,
    PurchaseTargetKind targetKind = PurchaseTargetKind.account,
    String? targetId,
  }) async => false;

  @override
  Future<void> cancelSubscription(String planCode) async =>
      throw const MonetizationException(
        'Billing is not connected in this build.',
        code: 'billing_unavailable',
      );

  @override
  Future<void> simulateVerification(String purchaseId) async =>
      throw const MonetizationException(
        'Billing is not connected in this build.',
        code: 'billing_unavailable',
      );
}
