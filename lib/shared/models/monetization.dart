import 'package:flutter/foundation.dart';

/// The five revenue streams the monetization module is designed around.
///
/// Two are active in the MVP ([tournamentPass], [organizerPro]); the other three
/// are configured in `public.monetization_streams` with `enabled = false` and
/// have no plans, no UI and no charge path until an operator activates them.
enum BillingStream {
  tournamentPass('tournament_pass', 'Tournament pass'),
  organizerPro('organizer_pro', 'Organizer Pro'),
  featuredListing('featured_listing', 'Featured tournaments'),
  sponsorship('sponsorship', 'Sponsorships and advertising'),
  analytics('analytics', 'Advanced analytics');

  const BillingStream(this.key, this.label);

  final String key;
  final String label;

  /// Null for a key this build does not know, so a stream added server-side can
  /// never crash a release client.
  static BillingStream? tryParse(String? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// Entitlement feature keys. The server stores these strings on every grant.
abstract final class BillingFeature {
  /// One tournament, granted by a verified tournament pass.
  static const String tournamentPremium = 'tournament.premium';

  /// Every tournament the member organises, granted by Organizer Pro.
  static const String organizerPremium = 'organizer.premium';
}

enum BillingInterval {
  oneTime('one_time', 'one-time'),
  month('month', 'monthly'),
  year('year', 'yearly');

  const BillingInterval(this.key, this.label);

  final String key;
  final String label;

  static BillingInterval fromKey(String? key) => values.firstWhere(
    (value) => value.key == key,
    orElse: () => BillingInterval.oneTime,
  );
}

/// The five payment states required of every purchase.
enum PaymentStatus {
  pending('pending', 'Awaiting verification'),
  paid('paid', 'Paid'),
  failed('failed', 'Failed'),
  expired('expired', 'Expired'),
  refunded('refunded', 'Refunded');

  const PaymentStatus(this.key, this.label);

  final String key;
  final String label;

  bool get isOpen => this == PaymentStatus.pending;
  bool get isTerminal => this != PaymentStatus.pending;

  static PaymentStatus fromKey(String? key) => values.firstWhere(
    (value) => value.key == key,
    orElse: () => PaymentStatus.pending,
  );
}

enum SubscriptionStatus {
  pending('pending', 'Not started'),
  active('active', 'Active'),
  pastDue('past_due', 'Payment due'),
  expired('expired', 'Expired'),
  cancelled('cancelled', 'Cancelled'),
  refunded('refunded', 'Refunded');

  const SubscriptionStatus(this.key, this.label);

  final String key;
  final String label;

  static SubscriptionStatus fromKey(String? key) => values.firstWhere(
    (value) => value.key == key,
    orElse: () => SubscriptionStatus.pending,
  );
}

enum EntitlementStatus {
  active('active', 'Active'),
  expired('expired', 'Expired'),
  revoked('revoked', 'Revoked');

  const EntitlementStatus(this.key, this.label);

  final String key;
  final String label;

  static EntitlementStatus fromKey(String? key) => values.firstWhere(
    (value) => value.key == key,
    orElse: () => EntitlementStatus.active,
  );
}

/// What a purchase is scoped to. Only [account] and [tournament] are used by the
/// MVP streams; [listing] and [campaign] exist so the placement streams need no
/// migration when they activate.
enum PurchaseTargetKind {
  account('account'),
  tournament('tournament'),
  listing('listing'),
  campaign('campaign');

  const PurchaseTargetKind(this.key);

  final String key;

  static PurchaseTargetKind fromKey(String? key) => values.firstWhere(
    (value) => value.key == key,
    orElse: () => PurchaseTargetKind.account,
  );
}

/// One configured revenue stream.
@immutable
class MonetizationStream {
  const MonetizationStream({
    required this.stream,
    required this.label,
    required this.summary,
    required this.mode,
    required this.enabled,
    required this.uiVisible,
    required this.sortOrder,
    required this.settings,
    required this.activationNote,
  });

  final BillingStream stream;
  final String label;
  final String summary;
  final String mode;
  final bool enabled;
  final bool uiVisible;
  final int sortOrder;

  /// Platform knobs the client must not hard-code, e.g. `free_entry_cap`.
  final Map<String, dynamic> settings;
  final String activationNote;

  /// A stream is only ever painted when it is both activated and allowed to show.
  bool get isVisible => enabled && uiVisible;

  int? settingInt(String key) {
    final value = settings[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static MonetizationStream fromRow(Map<String, dynamic> row) {
    final key = row['stream_key'] as String?;
    return MonetizationStream(
      stream: BillingStream.tryParse(key) ?? BillingStream.tournamentPass,
      label: _asString(row['label'], fallback: key ?? ''),
      summary: _asString(row['summary']),
      mode: _asString(row['mode'], fallback: 'one_time'),
      enabled: row['enabled'] == true,
      uiVisible: row['ui_visible'] == true,
      sortOrder: _asInt(row['sort_order']) ?? 0,
      settings: _asMap(row['settings']),
      activationNote: _asString(row['activation_note']),
    );
  }
}

/// One purchasable plan. Every number the pricing screen prints comes from here,
/// which is what keeps prices configurable instead of hard-coded.
@immutable
class BillingPlan {
  const BillingPlan({
    required this.code,
    required this.stream,
    required this.label,
    required this.tagline,
    required this.description,
    required this.priceMinor,
    required this.currency,
    required this.interval,
    required this.periodDays,
    required this.entitlementDays,
    required this.benefits,
    required this.features,
    required this.paymentInstructions,
    required this.active,
    required this.sortOrder,
  });

  final String code;
  final BillingStream stream;
  final String label;
  final String tagline;
  final String description;
  final int priceMinor;
  final String currency;
  final BillingInterval interval;
  final int? periodDays;
  final int? entitlementDays;
  final List<String> benefits;

  /// Machine-readable entitlement description, e.g.
  /// `{"entitlement": "tournament.premium", "max_entries": 128}`.
  final Map<String, dynamic> features;
  final String paymentInstructions;
  final bool active;
  final int sortOrder;

  String get priceLabel => formatMoney(priceMinor, currency);

  String get priceSuffix =>
      interval == BillingInterval.oneTime ? '' : '/ ${interval.label}';

  String? get entitlementFeature {
    final value = features['entitlement'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  int? get maxEntries => _asInt(features['max_entries']);

  /// Group counts a premium organizer may choose from. Empty means "keep the
  /// engine default", which is what every free tournament does today.
  List<int> get groupCounts {
    final value = features['group_counts'];
    if (value is! List) return const <int>[];
    return value
        .map((entry) => entry is num ? entry.toInt() : int.tryParse('$entry'))
        .whereType<int>()
        .where((count) => count > 0)
        .toList(growable: false);
  }

  bool get offersRulePresets => features['rules_presets'] == true;

  static BillingPlan fromRow(Map<String, dynamic> row) => BillingPlan(
    code: _asString(row['code']),
    stream:
        BillingStream.tryParse(row['stream_key'] as String?) ??
        BillingStream.tournamentPass,
    label: _asString(row['label']),
    tagline: _asString(row['tagline']),
    description: _asString(row['description']),
    priceMinor: _asInt(row['price_minor']) ?? 0,
    currency: _asString(row['currency'], fallback: 'PKR'),
    interval: BillingInterval.fromKey(row['billing_interval'] as String?),
    periodDays: _asInt(row['period_days']),
    entitlementDays: _asInt(row['entitlement_days']),
    benefits: _asStringList(row['benefits']),
    features: _asMap(row['features']),
    paymentInstructions: _asString(row['payment_instructions']),
    active: row['active'] != false,
    sortOrder: _asInt(row['sort_order']) ?? 0,
  );
}

/// One purchase attempt. The member sees [reference] on the payment screen and
/// types it back to the operator, who verifies the transfer out of band.
@immutable
class Purchase {
  const Purchase({
    required this.id,
    required this.profileId,
    required this.planCode,
    required this.stream,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.targetKind,
    required this.targetId,
    required this.idempotencyKey,
    required this.provider,
    required this.expiresAt,
    required this.createdAt,
    this.paidAt,
    this.failedAt,
    this.expiredAt,
    this.refundedAt,
    this.note = '',
    this.metadata = const {},
  });

  final String id;
  final String profileId;
  final String planCode;
  final BillingStream stream;
  final int amountMinor;
  final String currency;
  final PaymentStatus status;
  final PurchaseTargetKind targetKind;
  final String? targetId;
  final String idempotencyKey;
  final String provider;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? failedAt;
  final DateTime? expiredAt;
  final DateTime? refundedAt;
  final String note;
  final Map<String, dynamic> metadata;

  String get amountLabel => formatMoney(amountMinor, currency);

  /// Short, human-typable handle for the transfer description.
  String get reference {
    final compact = id.replaceAll('-', '').toUpperCase();
    final trimmed = compact.length > 8 ? compact.substring(0, 8) : compact;
    return 'SPK-$trimmed';
  }

  String? get planLabel {
    final value = metadata['plan_label'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static Purchase fromRow(Map<String, dynamic> row) => Purchase(
    id: _asString(row['id']),
    profileId: _asString(row['profile_id']),
    planCode: _asString(row['plan_code']),
    stream:
        BillingStream.tryParse(row['stream_key'] as String?) ??
        BillingStream.tournamentPass,
    amountMinor: _asInt(row['amount_minor']) ?? 0,
    currency: _asString(row['currency'], fallback: 'PKR'),
    status: PaymentStatus.fromKey(row['status'] as String?),
    targetKind: PurchaseTargetKind.fromKey(row['target_kind'] as String?),
    targetId: _asNullableString(row['target_id']),
    idempotencyKey: _asString(row['idempotency_key']),
    provider: _asString(row['provider'], fallback: 'manual'),
    expiresAt: _asDate(row['expires_at']),
    createdAt: _asDate(row['created_at']) ?? DateTime.now(),
    paidAt: _asDate(row['paid_at']),
    failedAt: _asDate(row['failed_at']),
    expiredAt: _asDate(row['expired_at']),
    refundedAt: _asDate(row['refunded_at']),
    note: _asString(row['note']),
    metadata: _asMap(row['metadata']),
  );
}

/// One subscription row per member per plan, extended in place on renewal.
@immutable
class Subscription {
  const Subscription({
    required this.id,
    required this.profileId,
    required this.planCode,
    required this.status,
    required this.cancelAtPeriodEnd,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.lastPurchaseId,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String profileId;
  final String planCode;
  final SubscriptionStatus status;
  final bool cancelAtPeriodEnd;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final String? lastPurchaseId;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// A subscription only counts while it is active and its period has not run
  /// out; the server computes the same predicate on the entitlement itself.
  bool get isLive {
    if (status != SubscriptionStatus.active) return false;
    final end = currentPeriodEnd;
    return end == null || end.isAfter(DateTime.now());
  }

  static Subscription fromRow(Map<String, dynamic> row) => Subscription(
    id: _asString(row['id']),
    profileId: _asString(row['profile_id']),
    planCode: _asString(row['plan_code']),
    status: SubscriptionStatus.fromKey(row['status'] as String?),
    cancelAtPeriodEnd: row['cancel_at_period_end'] == true,
    currentPeriodStart: _asDate(row['current_period_start']),
    currentPeriodEnd: _asDate(row['current_period_end']),
    lastPurchaseId: _asNullableString(row['last_purchase_id']),
    startedAt: _asDate(row['started_at']),
    endedAt: _asDate(row['ended_at']),
  );
}

/// What the member may actually use. [targetId] scopes a tournament pass; an
/// account-scoped entitlement satisfies every target.
@immutable
class Entitlement {
  const Entitlement({
    required this.id,
    required this.profileId,
    required this.featureKey,
    required this.source,
    required this.status,
    required this.targetKind,
    required this.grantedAt,
    this.targetId,
    this.purchaseId,
    this.subscriptionId,
    this.expiresAt,
    this.revokedAt,
    this.revokeReason = '',
  });

  final String id;
  final String profileId;
  final String featureKey;
  final String source;
  final EntitlementStatus status;
  final PurchaseTargetKind targetKind;
  final DateTime grantedAt;
  final String? targetId;
  final String? purchaseId;
  final String? subscriptionId;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final String revokeReason;

  bool get isLive {
    if (status != EntitlementStatus.active) return false;
    final end = expiresAt;
    return end == null || end.isAfter(DateTime.now());
  }

  /// Whether this entitlement answers a question about [featureKey] and [target].
  bool covers(String feature, {String? target}) {
    if (!isLive || featureKey != feature) return false;
    if (targetKind == PurchaseTargetKind.account) return true;
    return targetKind == PurchaseTargetKind.tournament &&
        target != null &&
        targetId == target;
  }

  static Entitlement fromRow(Map<String, dynamic> row) => Entitlement(
    id: _asString(row['id']),
    profileId: _asString(row['profile_id']),
    featureKey: _asString(row['feature_key']),
    source: _asString(row['source'], fallback: 'grant'),
    status: EntitlementStatus.fromKey(row['status'] as String?),
    targetKind: PurchaseTargetKind.fromKey(row['target_kind'] as String?),
    grantedAt: _asDate(row['granted_at']) ?? DateTime.now(),
    targetId: _asNullableString(row['target_id']),
    purchaseId: _asNullableString(row['purchase_id']),
    subscriptionId: _asNullableString(row['subscription_id']),
    expiresAt: _asDate(row['expires_at']),
    revokedAt: _asDate(row['revoked_at']),
    revokeReason: _asString(row['revoke_reason']),
  );
}

/// One ledger line. Charges and refunds are append-only and never edited.
@immutable
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.purchaseId,
    required this.kind,
    required this.amountMinor,
    required this.currency,
    required this.method,
    required this.at,
    this.providerRef = '',
    this.note = '',
  });

  final String id;
  final String purchaseId;
  final String kind;
  final int amountMinor;
  final String currency;
  final String method;
  final DateTime at;
  final String providerRef;
  final String note;

  bool get isRefund => kind == 'refund';

  String get amountLabel => formatMoney(amountMinor, currency);

  static PaymentRecord fromRow(Map<String, dynamic> row) => PaymentRecord(
    id: _asString(row['id']),
    purchaseId: _asString(row['purchase_id']),
    kind: _asString(row['kind'], fallback: 'charge'),
    amountMinor: _asInt(row['amount_minor']) ?? 0,
    currency: _asString(row['currency'], fallback: 'PKR'),
    method: _asString(row['method'], fallback: 'manual'),
    at: _asDate(row['at']) ?? DateTime.now(),
    providerRef: _asString(row['provider_ref']),
    note: _asString(row['note']),
  );
}

/// Everything the billing screens need, read as one unit.
@immutable
class BillingSnapshot {
  const BillingSnapshot({
    this.streams = const [],
    this.plans = const [],
    this.purchases = const [],
    this.subscriptions = const [],
    this.entitlements = const [],
    this.payments = const [],
  });

  final List<MonetizationStream> streams;
  final List<BillingPlan> plans;
  final List<Purchase> purchases;
  final List<Subscription> subscriptions;
  final List<Entitlement> entitlements;
  final List<PaymentRecord> payments;

  static const BillingSnapshot empty = BillingSnapshot();

  bool get isEmpty =>
      streams.isEmpty &&
      plans.isEmpty &&
      purchases.isEmpty &&
      subscriptions.isEmpty &&
      entitlements.isEmpty &&
      payments.isEmpty;
}

/// The client-side twin of `ProfileModuleException`: a message the UI can show
/// and the SQLSTATE code behind it.
class MonetizationException implements Exception {
  const MonetizationException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Formats minor units for display: `250000` PKR becomes `PKR 2,500`.
///
/// Hand-rolled rather than pulled from `intl`, which the app does not depend on;
/// it is pure and unit-tested.
String formatMoney(int minorUnits, String currency) {
  final negative = minorUnits < 0;
  final absolute = minorUnits.abs();
  final whole = (absolute ~/ 100).toString();
  final minor = absolute % 100;
  final buffer = StringBuffer(currency)
    ..write(' ')
    ..write(negative ? '-' : '')
    ..write(_groupThousands(whole));
  if (minor != 0) {
    buffer
      ..write('.')
      ..write(minor.toString().padLeft(2, '0'));
  }
  return buffer.toString();
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _asNullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _asDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  final parsed = DateTime.tryParse(value.toString());
  return parsed?.toLocal();
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .where((entry) => entry != null)
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}
