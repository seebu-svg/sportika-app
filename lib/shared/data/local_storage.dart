import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin JSON blob store on top of SharedPreferences.
///
/// The prototype keeps everything on-device: the whole game state is one
/// document that is rewritten after every mutation, which is what lets a
/// personal scorecard auto-save each entry and resume where it stopped
/// (spec §2.3 and §6).
class LocalStorage {
  LocalStorage(this._prefs);

  static const String dataKey = 'sportika.state.v1';
  static const String sessionKey = 'sportika.session_account';
  static const String onboardingKey = 'sportika.onboarding_seen.v1';
  static const String schemaKey = 'sportika.schema_version';

  /// Scoring actions recorded while the server was unreachable. They are kept
  /// apart from the main document because they belong to the server, not to the
  /// demo world, and they must survive a rebuild of that document.
  static const String matchOutboxKey = 'sportika.match_outbox';

  /// Demo-only billing records (plans come from the seed, purchases and
  /// entitlements are written by the simulated operator). A live build never
  /// reads this key: its billing comes from PostgreSQL alone.
  static const String billingKey = 'sportika.billing.v1';

  /// Bumped whenever the persisted shape changes. [migrateState] upgrades an
  /// older document in place, so an existing install keeps its scorecards.
  static const int schemaVersion = 3;

  final SharedPreferences _prefs;

  /// Set when a stored document could not be decoded. The repository surfaces
  /// this once so the player knows the demo world was rebuilt.
  bool recoveredFromCorruption = false;

  static Future<LocalStorage> open() async =>
      LocalStorage(await SharedPreferences.getInstance());

  int get storedSchemaVersion => _prefs.getInt(schemaKey) ?? 1;

  Map<String, dynamic>? readState() {
    final raw = _prefs.getString(dataKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('not an object');
      final state = Map<String, dynamic>.from(decoded);
      return migrateState(state, from: storedSchemaVersion);
    } catch (_) {
      recoveredFromCorruption = true;
      return null;
    }
  }

  /// Forward-only migrations. Each step is additive so an old document can
  /// always be lifted to the current shape without losing recorded scores.
  Map<String, dynamic> migrateState(
    Map<String, dynamic> state, {
    required int from,
  }) {
    var version = from;
    if (version < 2) {
      state['preferences'] ??= <String, bool>{};
      state['notifications'] ??= <String>[];
      version = 2;
    }
    if (version < 3) {
      // Standalone official matches are a new aggregate; an older document
      // simply has none yet and the demo matches are seeded on first read.
      state['matches'] ??= <Map<String, dynamic>>[];
      version = 3;
    }
    return state;
  }

  // ── match outbox ──────────────────────────────────────────────────────────

  /// Scoring actions still waiting for the server, oldest first.
  List<Map<String, dynamic>> readMatchOutbox() {
    final raw = _prefs.getString(matchOutboxKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // A corrupt queue must never block scoring: drop it and carry on.
      return [];
    }
  }

  Future<void> writeMatchOutbox(List<Map<String, dynamic>> entries) async {
    if (entries.isEmpty) {
      await _prefs.remove(matchOutboxKey);
      return;
    }
    await _prefs.setString(matchOutboxKey, jsonEncode(entries));
  }

  /// The simulated billing ledger of a device-only build. A corrupt document is
  /// dropped rather than throwing: billing must never block the app from
  /// starting.
  Map<String, dynamic>? readBilling() {
    final raw = _prefs.getString(billingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeBilling(Map<String, dynamic> billing) async {
    await _prefs.setString(billingKey, jsonEncode(billing));
  }

  Future<void> writeState(Map<String, dynamic> state) async {
    await _prefs.setString(dataKey, jsonEncode(state));
    if (storedSchemaVersion != schemaVersion) {
      await _prefs.setInt(schemaKey, schemaVersion);
    }
  }

  String? readSessionAccountId() => _prefs.getString(sessionKey);

  /// Device-level flag: onboarding is shown once, then skipped for everyone
  /// who already saw the story.
  bool readOnboardingSeen() => _prefs.getBool(onboardingKey) ?? false;

  Future<void> writeOnboardingSeen(bool seen) =>
      _prefs.setBool(onboardingKey, seen);

  Future<void> writeSessionAccountId(String? id) async {
    if (id == null) {
      await _prefs.remove(sessionKey);
    } else {
      await _prefs.setString(sessionKey, id);
    }
  }

  Future<void> clearAll() async {
    await _prefs.remove(dataKey);
    await _prefs.remove(sessionKey);
    await _prefs.remove(onboardingKey);
    await _prefs.remove(matchOutboxKey);
    await _prefs.remove(billingKey);
    await _prefs.remove(schemaKey);
  }
}
