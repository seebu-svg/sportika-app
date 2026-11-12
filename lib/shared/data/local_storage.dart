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

  /// Bumped whenever the persisted shape changes. [migrateState] upgrades an
  /// older document in place, so an existing install keeps its scorecards.
  static const int schemaVersion = 2;

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
    return state;
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
    await _prefs.remove(schemaKey);
  }
}
