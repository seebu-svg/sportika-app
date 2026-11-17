import 'package:flutter/foundation.dart';

import 'package:sportika/shared/models/onboarding.dart';

/// Verified identity only. Tokens and credentials belong to the SDK adapter,
/// never SharedPreferences or the UI. Account IDs must match SessionRepository.
@immutable
class AuthSession {
  const AuthSession({required this.accountId, required this.expiresAt});
  final String accountId;
  final DateTime expiresAt;
  bool get isExpired => !expiresAt.isAfter(DateTime.now());
}

/// Which emailed code a challenge refers to. A real adapter needs this because
/// the same six-digit screen serves signup confirmation, password recovery and
/// passwordless sign-in, and the server verifies them as different token types.
enum AuthChallengeKind { signup, recovery, signIn }

/// Opaque server challenge; the service decides expiry and resend throttling.
@immutable
class AuthChallenge {
  const AuthChallenge({
    required this.id,
    required this.email,
    this.kind = AuthChallengeKind.signup,
    this.resendAfter = const Duration(seconds: 30),
  });
  final String id;
  final String email;
  final AuthChallengeKind kind;
  final Duration resendAfter;
}

/// A safe, user-facing error supplied by an authentication adapter.
class AuthenticationException implements Exception {
  const AuthenticationException(this.message, {this.field});
  final String message;
  final String? field;
}

/// The service can require verification when an existing unverified user
/// signs in. The challenge must be issued by the server, never synthesized.
class EmailVerificationRequired extends AuthenticationException {
  const EmailVerificationRequired(this.challenge)
    : super('Verify your email to continue.');
  final AuthChallenge challenge;
}

/// Frontend integration seam, not an HTTP/API contract. A real SDK adapter must
/// restore/refresh securely, validate passwords/codes on the server, synchronize
/// account data through the existing repository, and notify on expiry/revocation.
/// No local account lookup or arbitrary code can establish a verified session.
abstract class AuthenticationService extends ChangeNotifier {
  AuthSession? get session;
  bool get isConfigured => true;
  Future<AuthSession?> restoreSession();
  Future<AuthSession> signIn({required String email, required String password});

  /// Sends a sign-in code (and, when the template carries it, a magic link) to
  /// an address that may or may not have an account.
  ///
  /// Deliberately incapable of creating an account: the sign-in screen must
  /// never become a signup route, and the challenge is returned even when the
  /// address is unknown so the screen cannot be used to discover members.
  Future<AuthChallenge> requestSignInCode({required String email});

  /// Exchanges a passwordless sign-in code for a session.
  Future<AuthSession> verifySignInCode({
    required String challengeId,
    required String code,
  });
  Future<AuthChallenge> register({
    required String name,
    required String email,
    required String password,
    required AccountIntent intent,
    required bool acceptedTerms,
  });

  /// Registers and returns a session in one call, with no emailed code in
  /// between.
  ///
  /// Only used while the build has email verification switched off. An adapter
  /// must never synthesize a session here: if the server still insists on a
  /// confirmation, throw [EmailVerificationRequired] exactly as [signIn] does.
  Future<AuthSession> registerWithoutVerification({
    required String name,
    required String email,
    required String password,
    required AccountIntent intent,
    required bool acceptedTerms,
  });
  Future<AuthSession> verifyEmail({
    required String challengeId,
    required String code,
  });
  Future<AuthChallenge> resendVerification({required String challengeId});
  Future<AuthChallenge> requestPasswordReset({required String email});
  Future<AuthChallenge> resendPasswordReset({required String challengeId});
  Future<void> resetPassword({
    required String challengeId,
    required String code,
    required String password,
  });

  /// Changes the password of the signed-in member after the current one has
  /// been proved. The session survives, so the member is not signed out.
  Future<void> changePassword({
    required String currentPassword,
    required String password,
  });

  /// Starts an address change for the signed-in member, after proving the
  /// current password.
  ///
  /// With secure email change enabled the server mails both the old and the
  /// new address and the account keeps its current address until both are
  /// confirmed, so this call changes nothing locally.
  Future<void> changeEmail({
    required String currentPassword,
    required String email,
  });

  /// Sets a new password on the short-lived session an emailed recovery link
  /// produced. The session is revoked afterwards: recovery is a way to change
  /// the password, not a way to stay signed in.
  Future<void> completePasswordRecovery({required String password});

  /// Revokes every session for the account, not only this device.
  Future<void> signOutEverywhere();

  /// True once a recovery link has been exchanged and the member still has to
  /// choose a new password. The flow watches this to open the reset screen.
  bool get pendingPasswordRecovery;

  /// Bumped when the server confirms something the cached profile may not
  /// show yet — a confirmed email change, or a session this app did not create.
  /// The flow re-hydrates when it changes, and never polls.
  int get accountRevision;

  /// Must clear SDK credentials even if remote token revocation fails.
  Future<void> signOut();
}

/// No backend is configured in this checkout. Fail closed, without inventing
/// credentials, issuing codes, persisting tokens, or reporting false success.
class UnavailableAuthenticationService extends AuthenticationService {
  @override
  AuthSession? get session => null;
  @override
  bool get isConfigured => false;
  Never _unavailable() => throw const AuthenticationException(
    'Authentication is not connected yet. Please try again once the service is available.',
  );
  @override
  Future<AuthSession?> restoreSession() async => null;
  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async => _unavailable();
  @override
  Future<AuthChallenge> register({
    required String name,
    required String email,
    required String password,
    required AccountIntent intent,
    required bool acceptedTerms,
  }) async => _unavailable();
  @override
  Future<AuthSession> registerWithoutVerification({
    required String name,
    required String email,
    required String password,
    required AccountIntent intent,
    required bool acceptedTerms,
  }) async => _unavailable();
  @override
  Future<AuthSession> verifyEmail({
    required String challengeId,
    required String code,
  }) async => _unavailable();
  @override
  Future<AuthChallenge> resendVerification({
    required String challengeId,
  }) async => _unavailable();
  @override
  Future<AuthChallenge> requestPasswordReset({required String email}) async =>
      _unavailable();
  @override
  Future<AuthChallenge> resendPasswordReset({
    required String challengeId,
  }) async => _unavailable();
  @override
  Future<void> resetPassword({
    required String challengeId,
    required String code,
    required String password,
  }) async => _unavailable();
  @override
  Future<AuthChallenge> requestSignInCode({required String email}) async =>
      _unavailable();
  @override
  Future<AuthSession> verifySignInCode({
    required String challengeId,
    required String code,
  }) async => _unavailable();
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String password,
  }) async => _unavailable();
  @override
  Future<void> changeEmail({
    required String currentPassword,
    required String email,
  }) async => _unavailable();
  @override
  Future<void> completePasswordRecovery({required String password}) async =>
      _unavailable();
  @override
  bool get pendingPasswordRecovery => false;
  @override
  int get accountRevision => 0;
  @override
  Future<void> signOutEverywhere() async {}
  @override
  Future<void> signOut() async {}
}
