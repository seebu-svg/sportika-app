import 'dart:async';

import 'package:sportika/app/env.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:sportika/features/auth/services/supabase_auth_errors.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The production implementation of [AuthenticationService].
///
/// Everything the old mock did in memory is now decided by GoTrue: passwords are
/// hashed server-side, codes are issued and expired by the server, and a session
/// only exists because the server issued it. This class owns no copy of a
/// password and no fallback identity — if the server says no, the answer is no.
///
/// Typed six-digit codes are used rather than email links, which is why
/// `AuthChallenge.id` carries the address: GoTrue identifies a pending code by
/// address plus token type, and `verifyEmail`/`resetPassword` pass it straight
/// back. Links are supported as well — `AppEnv.authCallback` sends them back to
/// the app, where supabase_flutter exchanges them for a session.
class SupabaseAuthenticationService extends AuthenticationService {
  SupabaseAuthenticationService(this._client) {
    _authState = _client.auth.onAuthStateChange.listen(_handleAuthState);
  }

  /// Codes expire in ten minutes server-side; the resend cooldown is generous
  /// because Supabase rate-limits confirmation mail per address.
  static const Duration _resendCooldown = Duration(seconds: 60);

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _authState;
  bool _disposed = false;
  bool _pendingRecovery = false;
  int _accountRevision = 0;

  @override
  bool get isConfigured => true;

  @override
  bool get pendingPasswordRecovery => _pendingRecovery;

  /// Bumped for events that may leave the cached profile stale: a confirmed
  /// email change, or a session this app did not create (recovery link).
  @override
  int get accountRevision => _accountRevision;

  @override
  AuthSession? get session {
    final current = _client.auth.currentSession;
    return current == null ? null : _fromSession(current);
  }

  /// Refreshes an expired access token on demand and returns null when nothing
  /// is stored. A revoked or unreadable session ends up here too, which is what
  /// makes `restoreSession` honest: it can only ever return what the server
  /// still accepts.
  @override
  Future<AuthSession?> restoreSession() async {
    try {
      final restored = await _client.auth.getSession();
      return restored == null ? null : _fromSession(restored);
    } on AuthException {
      await _forgetSession();
      return null;
    } catch (_) {
      // A launch path may never throw: the flow treats null as "sign in".
      return null;
    }
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final address = email.trim();
    try {
      final response = await _client.auth.signInWithPassword(
        email: address,
        password: password,
      );
      final signedIn = response.session;
      if (signedIn == null) {
        throw const AuthenticationException(
          'We could not sign you in. Please try again.',
        );
      }
      return _fromSession(signedIn);
    } on AuthException catch (error) {
      if (error.code == 'email_not_confirmed') {
        // Not a failure to the member: an unverified account gets the code
        // screen back, with a resend already waiting.
        throw EmailVerificationRequired(
          _challenge(address, AuthChallengeKind.signup),
        );
      }
      throw mapAuthError(error);
    }
  }

  @override
  Future<AuthChallenge> requestSignInCode({required String email}) async {
    final address = email.trim();
    try {
      await _client.auth.signInWithOtp(
        email: address,
        // A sign-in screen must never become a signup route, and the challenge
        // is identical for known and unknown addresses on purpose.
        shouldCreateUser: false,
        emailRedirectTo: AppEnv.authCallback,
      );
    } catch (error) {
      // Only a missing account is swallowed: the challenge must look identical
      // for known and unknown addresses. A disabled provider or an offline
      // device is a real failure and must reach the member.
      final unknownAddress =
          error is AuthException && error.code == 'user_not_found';
      if (!unknownAddress) throw mapAuthError(error);
    }
    return _challenge(address, AuthChallengeKind.signIn);
  }

  @override
  Future<AuthSession> verifySignInCode({
    required String challengeId,
    required String code,
  }) async {
    final address = challengeId.trim();
    final token = code.trim();
    try {
      return await _verifyCode(address, token, OtpType.email);
    } on AuthException catch (error) {
      final notAMagicToken =
          error.code == 'invalid_otp' ||
          error.code == 'otp_expired' ||
          error.code == 'token has expired or is invalid';
      if (!notAMagicToken) throw mapAuthError(error);
      // An account created but never confirmed receives a signup token even
      // when it asked for a sign-in code. One retry with that token type turns
      // a dead end into a completed sign-in.
      try {
        return await _verifyCode(address, token, OtpType.signup);
      } on AuthException catch (retryError) {
        throw mapAuthError(retryError);
      }
    }
  }

  @override
  Future<AuthChallenge> register({
    required String name,
    required String email,
    required String password,
    required AccountIntent intent,
    required bool acceptedTerms,
  }) async {
    final address = email.trim();
    if (!acceptedTerms) {
      throw const AuthenticationException('Accept the terms to continue.');
    }

    try {
      await _client.auth.signUp(
        email: address,
        password: password,
        data: {'display_name': name.trim()},
      );
      // `intent` is deliberately unused: Sportika has one universal account and
      // the database has no column to record a player/organizer split.
      return _challenge(address, AuthChallengeKind.signup);
    } on AuthException catch (error) {
      if (error.code == 'user_already_exists' || error.code == 'email_exists') {
        // Do not confirm that the address is registered. The member continues to
        // the code screen exactly as a new signup would, and can change the
        // address there.
        return _challenge(address, AuthChallengeKind.signup);
      }
      throw mapAuthError(error);
    }
  }

  /// Registers and returns a session in one call, for the builds that run
  /// without email confirmation.
  ///
  /// `signUp` hands back the session it just created whenever the project has
  /// *Confirm email* off. A project that still confirms addresses returns no
  /// session, and that is reported as [EmailVerificationRequired] instead of
  /// being papered over with a session nobody issued.
  @override
  Future<AuthSession> registerWithoutVerification({
    required String name,
    required String email,
    required String password,
    required AccountIntent intent,
    required bool acceptedTerms,
  }) async {
    final address = email.trim();
    if (!acceptedTerms) {
      throw const AuthenticationException('Accept the terms to continue.');
    }

    try {
      final response = await _client.auth.signUp(
        email: address,
        password: password,
        data: {'display_name': name.trim()},
      );
      final signedUp = response.session;
      if (signedUp != null) return _fromSession(signedUp);
    } on AuthException catch (error) {
      final alreadyRegistered =
          error.code == 'user_already_exists' || error.code == 'email_exists';
      // A registered address is answered by the sign-in below: the same
      // password completes it and a different one fails like any wrong
      // password. Neither answer tells the caller whether the address exists.
      if (!alreadyRegistered) throw mapAuthError(error);
    }

    try {
      final response = await _client.auth.signInWithPassword(
        email: address,
        password: password,
      );
      final signedIn = response.session;
      if (signedIn == null) {
        throw const AuthenticationException(
          'We could not finish creating your account. Please try again.',
        );
      }
      return _fromSession(signedIn);
    } on AuthException catch (error) {
      if (error.code == 'email_not_confirmed') {
        throw EmailVerificationRequired(
          _challenge(address, AuthChallengeKind.signup),
        );
      }
      throw mapAuthError(error);
    }
  }

  @override
  Future<AuthSession> verifyEmail({
    required String challengeId,
    required String code,
  }) async {
    final address = challengeId.trim();
    try {
      // If Supabase is configured to confirm accounts on signup, we already hold
      // a session for this address — a stronger proof than the code, so there is
      // nothing left to verify.
      final existing = _client.auth.currentSession;
      if (existing != null &&
          existing.user.email?.toLowerCase() == address.toLowerCase()) {
        return _fromSession(existing);
      }

      final response = await _client.auth.verifyOTP(
        type: OtpType.signup,
        email: address,
        token: code.trim(),
      );
      final verified = response.session;
      if (verified == null) {
        throw const AuthenticationException(
          'That code could not be confirmed. Try again.',
          field: 'otp',
        );
      }
      return _fromSession(verified);
    } on AuthException catch (error) {
      throw mapAuthError(error);
    }
  }

  @override
  Future<AuthChallenge> resendVerification({
    required String challengeId,
  }) async {
    final address = challengeId.trim();
    try {
      await _client.auth.resend(email: address, type: OtpType.signup);
      return _challenge(address, AuthChallengeKind.signup);
    } on AuthException catch (error) {
      throw mapAuthError(error);
    }
  }

  @override
  Future<AuthChallenge> requestPasswordReset({required String email}) async {
    final address = email.trim();
    await _sendRecoveryCode(address);
    return _challenge(address, AuthChallengeKind.recovery);
  }

  @override
  Future<AuthChallenge> resendPasswordReset({
    required String challengeId,
  }) async {
    final address = challengeId.trim();
    await _sendRecoveryCode(address);
    return _challenge(address, AuthChallengeKind.recovery);
  }

  @override
  Future<void> resetPassword({
    required String challengeId,
    required String code,
    required String password,
  }) async {
    final address = challengeId.trim();
    try {
      final response = await _client.auth.verifyOTP(
        type: OtpType.recovery,
        email: address,
        token: code.trim(),
      );
      if (response.session == null) {
        throw const AuthenticationException(
          'That code is invalid or has expired.',
          field: 'otp',
        );
      }
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      throw mapAuthError(error);
    } finally {
      // A recovery session is a means to change the password, not a way to be
      // signed in. Revoke it whatever the outcome, so the member must prove the
      // new password works.
      _pendingRecovery = false;
      await _forgetSession();
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String password,
  }) async {
    await _reauthenticate(currentPassword);
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      throw mapAuthError(error);
    }
  }

  @override
  Future<void> changeEmail({
    required String currentPassword,
    required String email,
  }) async {
    await _reauthenticate(currentPassword);
    try {
      await _client.auth.updateUser(
        UserAttributes(email: email.trim()),
        emailRedirectTo: AppEnv.authCallback,
      );
    } on AuthException catch (error) {
      throw mapAuthError(error);
    }
    // Nothing local changes: the address is applied only after the member
    // confirms the mail sent to it (and, with secure email change, the mail
    // sent to the current address as well).
  }

  @override
  Future<void> completePasswordRecovery({required String password}) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      throw mapAuthError(error);
    } finally {
      _pendingRecovery = false;
      await _forgetSession();
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Revocation failed (offline, or the token was already gone). The SDK has
      // dropped the in-memory session and the flow hides protected UI anyway.
    }
    _pendingRecovery = false;
    await _forgetSession();
  }

  /// Settings → "Sign out of all devices".
  @override
  Future<void> signOutEverywhere() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.global);
    } catch (_) {
      // Fall through to the local clear: this device must end up signed out.
    }
    _pendingRecovery = false;
    await _forgetSession();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_authState.cancel());
    super.dispose();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Recovery mail is requested identically for every address. Only a rate limit
  /// is surfaced, because the member needs to know to stop retrying; anything
  /// else is indistinguishable from success on purpose.
  Future<void> _sendRecoveryCode(String address) async {
    try {
      await _client.auth.resetPasswordForEmail(
        address,
        redirectTo: AppEnv.authCallback,
      );
    } on AuthException catch (error) {
      final limited =
          error.statusCode == '429' ||
          (error.code?.contains('rate_limit') ?? false);
      if (limited) throw mapAuthError(error);
    }
  }

  /// Clears both the in-memory session and the keystore entry. Best effort by
  /// design: sign-out must never fail because storage misbehaved.
  Future<void> _forgetSession() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Nothing further to do; the caller hides protected UI regardless.
    }
  }

  AuthSession _fromSession(Session session) {
    final seconds = session.expiresAt;
    return AuthSession(
      accountId: session.user.id,
      // `expiresAt` is decoded from the token; if it cannot be read the session
      // is treated as short-lived so the flow revalidates rather than trusting
      // an unreadable token.
      expiresAt: seconds == null
          ? DateTime.now().add(const Duration(minutes: 30))
          : DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
    );
  }

  /// Proves the current password before a security change.
  ///
  /// Proving it also refreshes the token, which is what makes the following
  /// `updateUser` acceptable to the server even on a long-lived session. The
  /// refresh belongs to the same account, so the flow's session guard holds.
  Future<void> _reauthenticate(String currentPassword) async {
    final address = _client.auth.currentUser?.email;
    if (address == null) throw mapAuthError(AuthSessionMissingException());
    try {
      final response = await _client.auth.signInWithPassword(
        email: address,
        password: currentPassword,
      );
      if (response.session == null) {
        throw const AuthenticationException(
          'Your current password is incorrect.',
          field: 'currentPassword',
        );
      }
    } on AuthException catch (error) {
      if (error.code == 'invalid_credentials') {
        throw const AuthenticationException(
          'Your current password is incorrect.',
          field: 'currentPassword',
        );
      }
      throw mapAuthError(error);
    }
  }

  Future<AuthSession> _verifyCode(
    String address,
    String token,
    OtpType type,
  ) async {
    final response = await _client.auth.verifyOTP(
      type: type,
      email: address,
      token: token,
    );
    final verified = response.session;
    if (verified == null) {
      throw const AuthenticationException(
        'That code is invalid or has expired.',
        field: 'otp',
      );
    }
    return _fromSession(verified);
  }

  AuthChallenge _challenge(String email, AuthChallengeKind kind) =>
      AuthChallenge(
        id: email,
        email: email,
        kind: kind,
        resendAfter: _resendCooldown,
      );

  void _handleAuthState(AuthState state) {
    if (_disposed) return;
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        // A recovery link was exchanged. The session is short-lived and exists
        // only so the password can be replaced.
        _pendingRecovery = true;
        _accountRevision++;
      case AuthChangeEvent.userUpdated:
        // The server confirmed something about the account — most often an
        // email change — that the cached profile does not show yet.
        _accountRevision++;
      case AuthChangeEvent.signedIn:
        _pendingRecovery = false;
        _accountRevision++;
      case AuthChangeEvent.signedOut:
        _pendingRecovery = false;
      default:
        break;
    }
    // The controller re-reads [session] on every notification, so a refresh that
    // lands on a new expiry, or a sign-out pushed from another device, is picked
    // up without polling.
    notifyListeners();
  }
}
