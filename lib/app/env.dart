import 'package:flutter/foundation.dart';

/// Compile-time configuration for a Sportika build.
///
/// Nothing here is read from a file, so no credential is ever committed:
///
/// ```bash
/// flutter run \
///   --dart-define=SUPABASE_URL=https://<project>.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// ```
///
/// [demoMode] is the only switch that enables the device-only demo world —
/// seeded accounts, mock authentication and the printed OTP codes. It is off
/// unless the build explicitly asks for it, so a release binary cannot ship
/// demo credentials by accident.
@immutable
class AppEnv {
  const AppEnv._();

  /// Which authentication implementation this build should use.
  ///
  /// [unavailable] fails closed: the sign-in screen explains that the service
  /// is not connected instead of quietly authenticating against the device.
  static AuthBackend get authBackend {
    if (demoMode) return AuthBackend.demo;
    return hasSupabase ? AuthBackend.supabase : AuthBackend.unavailable;
  }

  /// True only for internal builds that should keep the seeded demo world.
  static const bool demoMode = bool.fromEnvironment('DEMO_MODE');

  /// Whether a new account has to prove its address with a six-digit code
  /// before it can be used.
  ///
  /// **Currently off**, matching a project that runs with *Confirm email*
  /// off: registration returns a session in the same call, the verify screen
  /// is never opened and passwordless sign-in is not offered. Build with
  /// `--dart-define=EMAIL_VERIFICATION=true` — or flip the default here — to
  /// put the code screen back; nothing else has to change with it.
  static const bool emailVerificationEnabled = bool.fromEnvironment(
    'EMAIL_VERIFICATION',
    defaultValue: false,
  );

  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase now issues publishable keys; the legacy anon key is accepted as a
  /// fallback so an existing project keeps working unchanged. Only the
  /// publishable key is ever compiled in; the service-role key never ships.
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseUrl => _supabaseUrl.trim();

  static String get supabaseKey {
    final key = _publishableKey.isNotEmpty ? _publishableKey : _anonKey;
    return key.trim();
  }

  /// Both values present. A half-configured build must not attempt to connect.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Storage bucket that holds profile pictures.
  static const String avatarBucket = 'avatars';

  /// Revision written with every profile save so consent stays auditable.
  static const String termsVersion = 'v1-2026-11';

  /// Where Supabase sends the browser back after an email link (signup
  /// confirmation, magic link, recovery, email change).
  ///
  /// This string must match the redirect allowlist in the Supabase dashboard
  /// verbatim and the intent-filter in AndroidManifest.xml. A mismatch is
  /// silent: the link opens a browser instead of the app.
  ///
  /// Typed six-digit codes never depend on this, which is why they stay the
  /// primary path — mail scanners and desktop clients mangle links.
  static const String authCallback = 'pk.sportika.mobile://auth-callback';

  /// Accepts only links aimed at [authCallback], so unrelated deep links are
  /// never exchanged for a session by supabase_flutter.
  static bool isAuthCallback(Uri uri) {
    final target = Uri.parse(authCallback);
    return uri.scheme.toLowerCase() == target.scheme.toLowerCase() &&
        uri.host.toLowerCase() == target.host.toLowerCase();
  }
}

/// The three states a build can be in, decided by [AppEnv.authBackend].
enum AuthBackend {
  /// Real Supabase Auth against PostgreSQL.
  supabase,

  /// Device-only seeded accounts with mock verification codes.
  demo,

  /// No backend configured: authentication fails closed.
  unavailable,
}
