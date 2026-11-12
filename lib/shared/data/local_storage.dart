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

  final SharedPreferences _prefs;

  static Future<LocalStorage> open() async =>
      LocalStorage(await SharedPreferences.getInstance());

  Map<String, dynamic>? readState() {
    final raw = _prefs.getString(dataKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeState(Map<String, dynamic> state) =>
      _prefs.setString(dataKey, jsonEncode(state));

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

  Future<void> clear() async {
    await _prefs.remove(dataKey);
    await _prefs.remove(sessionKey);
    await _prefs.remove(onboardingKey);
  }
}
