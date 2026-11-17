import 'dart:async';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:sportika/shared/models/onboarding.dart';

/// Test-only service fixture. Never imported by lib/. This exercises the
/// frontend contract and does not claim to verify a deployed backend or SDK.
class AuthServiceFixture extends AuthenticationService {
  AuthServiceFixture(this.repository, {String? restoredAccountId}) {
    passwords = {
      for (final a in repository.accounts) a.email.toLowerCase(): validPassword,
    };
    if (restoredAccountId != null) establish(restoredAccountId);
  }
  static const validPassword = 'Sportika9!';
  final LocalSportikaRepository repository;
  late final Map<String, String> passwords;
  AuthSession? _session;
  @override
  AuthSession? get session => _session;
  AuthenticationException? nextError;
  Completer<void>? signInBarrier;
  Completer<void>? restoreBarrier;
  bool failSignOut = false;
  int signInCalls = 0;
  int resendCalls = 0;
  Duration cooldown = const Duration(seconds: 30);
  int registerCalls = 0;
  int registerWithoutVerificationCalls = 0;
  int signInCodeCalls = 0;
  int passwordChanges = 0;
  int emailChanges = 0;
  int signOutEverywhereCalls = 0;
  bool recoveryPending = false;

  /// The address an email change is waiting to be confirmed by both inboxes.
  /// The stored account keeps the old address until then, exactly like the
  /// server does with "Secure email change" enabled.
  String? pendingEmailChange;
  int _revision = 0;
  AccountIntent? registeredIntent;
  ({String name, String email, String password, AccountIntent intent})?
  _registration;
  String? _resetEmail;
  String? _signInEmail;
  int _challenge = 0;

  void _checkError() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  AuthSession establish(
    String accountId, {
    Duration lifetime = const Duration(hours: 1),
  }) {
    _session = AuthSession(
      accountId: accountId,
      expiresAt: DateTime.now().add(lifetime),
    );
    notifyListeners();
    return _session!;
  }

  void revoke() {
    _session = null;
    notifyListeners();
  }

  /// Simulates an emailed recovery link being exchanged while the app is open.
  /// GoTrue hands the SDK a short-lived session for the recovered account and
  /// fires `passwordRecovery`, so the fixture does the same instead of only
  /// flipping a flag.
  void beginRecovery(String accountId) {
    establish(accountId);
    recoveryPending = true;
    notifyListeners();
  }

  @override
  bool get pendingPasswordRecovery => recoveryPending;

  /// Bumped whenever the SDK would fire `signedIn` or `userUpdated`, so the
  /// flow's profile refresh runs in tests the same way it does on device.
  @override
  int get accountRevision => _revision;

  @override
  Future<AuthSession?> restoreSession() async {
    await restoreBarrier?.future;
    _checkError();
    return _session;
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    await signInBarrier?.future;
    _checkError();
    final account = repository.accountByEmail(email);
    if (account == null || passwords[email.toLowerCase()] != password) {
      throw const AuthenticationException('Email or password is incorrect.');
    }
    return establish(account.id);
  }

  @override
  Future<AuthChallenge> requestSignInCode({required String email}) async {
    signInCodeCalls++;
    _checkError();
    _signInEmail = email;
    return AuthChallenge(
      id: 'signin-${++_challenge}',
      email: email,
      kind: AuthChallengeKind.signIn,
      resendAfter: cooldown,
    );
  }

  @override
  Future<AuthSession> verifySignInCode({
    required String challengeId,
    required String code,
  }) async {
    _checkError();
    final account = repository.accountByEmail(_signInEmail ?? '');
    if (code != '123456' ||
        challengeId != 'signin-$_challenge' ||
        account == null) {
      throw const AuthenticationException(
        'The code is invalid or expired.',
        field: 'otp',
      );
    }
    return establish(account.id);
  }

  @override
  Future<AuthChallenge> register({
    required String name,
    required String email,
    required String password,
    required AccountIntent intent,
    required bool acceptedTerms,
  }) async {
    registerCalls++;
    _checkError();
    if (!acceptedTerms) {
      throw const AuthenticationException('Accept the terms.');
    }
    if (repository.accountByEmail(email) != null) {
      throw const AuthenticationException(
        'This email cannot be registered.',
        field: 'email',
      );
    }
    _registration = (
      name: name,
      email: email,
      password: password,
      intent: intent,
    );
    registeredIntent = intent;
    return AuthChallenge(
      id: 'verify-${++_challenge}',
      email: email,
      resendAfter: cooldown,
    );
  }

  @override
  Future<AuthSession> verifyEmail({
    required String challengeId,
    required String code,
  }) async {
    _checkError();
    if (code != '123456' ||
        _registration == null ||
        challengeId != 'verify-$_challenge') {
      throw const AuthenticationException(
        'The code is invalid or expired.',
        field: 'otp',
      );
    }
    final draft = _registration!;
    final account = await repository.createAccount(
      displayName: draft.name,
      email: draft.email,
      city: 'Karachi',
      intent: draft.intent,
    );
    passwords[draft.email.toLowerCase()] = draft.password;
    _registration = null;
    return establish(account.id);
  }

  /// Signup with no code screen: the account exists as soon as the form is
  /// submitted, exactly as a project with *Confirm email* off behaves.
  @override
  Future<AuthSession> registerWithoutVerification({
    required String name,
    required String email,
    required String password,
    required AccountIntent intent,
    required bool acceptedTerms,
  }) async {
    // Counted apart from [registerCalls]: the no-code path must never look like
    // the code path when a test asserts which one ran.
    registerWithoutVerificationCalls++;
    _checkError();
    if (!acceptedTerms) {
      throw const AuthenticationException('Accept the terms.');
    }
    if (repository.accountByEmail(email) != null) {
      throw const AuthenticationException(
        'This email cannot be registered.',
        field: 'email',
      );
    }
    registeredIntent = intent;
    final account = await repository.createAccount(
      displayName: name,
      email: email,
      city: 'Karachi',
      intent: intent,
    );
    passwords[email.toLowerCase()] = password;
    return establish(account.id);
  }

  @override
  Future<AuthChallenge> resendVerification({
    required String challengeId,
  }) async {
    _checkError();
    resendCalls++;
    return AuthChallenge(
      id: 'verify-${++_challenge}',
      email: _registration!.email,
      resendAfter: cooldown,
    );
  }

  @override
  Future<AuthChallenge> requestPasswordReset({required String email}) async {
    _checkError();
    _resetEmail = email;
    return AuthChallenge(
      id: 'reset-${++_challenge}',
      email: email,
      resendAfter: cooldown,
    );
  }

  @override
  Future<AuthChallenge> resendPasswordReset({
    required String challengeId,
  }) async {
    _checkError();
    resendCalls++;
    return AuthChallenge(
      id: 'reset-${++_challenge}',
      email: _resetEmail!,
      resendAfter: cooldown,
    );
  }

  @override
  Future<void> resetPassword({
    required String challengeId,
    required String code,
    required String password,
  }) async {
    _checkError();
    if (code != '654321' ||
        challengeId != 'reset-$_challenge' ||
        !passwords.containsKey(_resetEmail!.toLowerCase())) {
      throw const AuthenticationException(
        'The code is invalid or expired.',
        field: 'otp',
      );
    }
    passwords[_resetEmail!.toLowerCase()] = password;
    _resetEmail = null;
    revoke();
  }

  @override
  Future<void> signOut() async {
    // The SDK fires `signedOut`, which is what clears the pending recovery.
    recoveryPending = false;
    revoke();
    if (failSignOut) {
      throw const AuthenticationException('Remote revocation unavailable.');
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String password,
  }) async {
    _checkError();
    final id = _session?.accountId;
    final account = repository.accountById(id);
    if (account == null) {
      throw const AuthenticationException(
        'Your session has ended. Please sign in again.',
      );
    }
    if (passwords[account.email.toLowerCase()] != currentPassword) {
      throw const AuthenticationException(
        'Your current password is incorrect.',
        field: 'currentPassword',
      );
    }
    passwords[account.email.toLowerCase()] = password;
    passwordChanges++;
    // Reauthenticating to authorise the write is a real sign-in, and the
    // follow-up updateUser is a real userUpdated. Both bump the revision, and
    // the flow must survive them without leaving Settings.
    _revision += 2;
    notifyListeners();
  }

  @override
  Future<void> changeEmail({
    required String currentPassword,
    required String email,
  }) async {
    _checkError();
    final account = repository.accountById(_session?.accountId);
    if (account == null) {
      throw const AuthenticationException(
        'Your session has ended. Please sign in again.',
      );
    }
    if (passwords[account.email.toLowerCase()] != currentPassword) {
      throw const AuthenticationException(
        'Your current password is incorrect.',
        field: 'currentPassword',
      );
    }
    final next = email.trim();
    if (repository.accountByEmail(next) != null) {
      throw const AuthenticationException(
        'That email address is already in use.',
        field: 'email',
      );
    }
    // Nothing moves locally: the server mails both inboxes and only applies
    // the address after both confirmations, so the profile keeps the old one.
    pendingEmailChange = next;
    emailChanges++;
    _revision += 2;
    notifyListeners();
  }

  @override
  Future<void> completePasswordRecovery({required String password}) async {
    _checkError();
    final account = repository.accountById(_session?.accountId);
    if (account == null) {
      throw const AuthenticationException(
        'Your session has ended. Please sign in again.',
      );
    }
    passwords[account.email.toLowerCase()] = password;
    recoveryPending = false;
    revoke();
  }

  @override
  Future<void> signOutEverywhere() async {
    signOutEverywhereCalls++;
    await signOut();
  }
}
