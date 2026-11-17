import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the GoTrue session out of `SharedPreferences`.
///
/// The refresh token is a credential: whatever can read the app's preference
/// file — a backup, a rooted device, a debug build left installed — can mint
/// new access tokens with it. `flutter_secure_storage` puts the payload behind
/// the Android keystore instead.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String sessionKey = 'sportika.auth.session.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {
    // Reads are lazy, so there is nothing to warm up. Kept for the interface.
  }

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: sessionKey);

  @override
  Future<String?> accessToken() => _storage.read(key: sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: sessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: sessionKey);
    } on Exception {
      // A revoked or unreadable keystore entry must not block sign-out: the
      // in-memory session is already gone, and the next launch simply starts
      // signed out.
    }
  }
}

/// Holds the PKCE code verifier while an emailed link is being exchanged.
///
/// Phase 1 verifies typed codes, so this is rarely populated, but Supabase
/// writes the verifier before every `resetPasswordForEmail` call and a write
/// failure would abort the request.
class SecureGotrueStorage extends GotrueAsyncStorage {
  SecureGotrueStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem({required String key}) => _storage.read(key: key);

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> removeItem({required String key}) => _storage.delete(key: key);
}
