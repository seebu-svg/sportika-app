import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:sportika/shared/models/onboarding.dart';

/// Device-only prototype authentication. Never use this adapter for real identity.
/// Seed accounts use Sportika9!; verification is 123456, recovery is 654321.
/// Passwords are held in memory only and reset when the app restarts. Email
/// changes apply immediately on the device: there is no mail to confirm them.
class MockAuthenticationService extends AuthenticationService {
  MockAuthenticationService(this.repository) {
    passwords = {
      for (final account in repository.accounts) account.id: 'Sportika9!',
    };
  }
  final LocalSportikaRepository repository;
  late final Map<String, String> passwords;
  AuthSession? _session;
  @override
  AuthSession? get session => _session;
  ({String name, String email, String password, AccountIntent intent})?
  _registration;
  String? _resetEmail;
  String? _signInEmail;
  int _challenge = 0;
  final cooldown = const Duration(seconds: 30);

  AuthSession establish(String accountId) {
    _session = AuthSession(
      accountId: accountId,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    notifyListeners();
    return _session!;
  }

  void revoke() {
    _session = null;
    notifyListeners();
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final account = repository.currentAccount;
    return account == null ? null : establish(account.id);
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final account = repository.accountByEmail(email);
    if (account == null || passwords[account.id] != password) {
      throw const AuthenticationException('Email or password is incorrect.');
    }
    return establish(account.id);
  }

  @override
  Future<AuthChallenge> requestSignInCode({required String email}) async {
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
    final account = repository.accountByEmail(_signInEmail ?? '');
    if (code != '123456' ||
        challengeId != 'signin-$_challenge' ||
        account == null) {
      throw const AuthenticationException(
        'The code is invalid or expired.',
        field: 'otp',
      );
    }
    _signInEmail = null;
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
    return AuthChallenge(
      id: 'verify-${++_challenge}',
      email: email,
      resendAfter: cooldown,
    );
  }

  /// Demo signup without the code screen: the device account is created now
  /// instead of on a later [verifyEmail].
  @override
  Future<AuthSession> registerWithoutVerification({
    required String name,
    required String email,
    required String password,
    required AccountIntent intent,
    required bool acceptedTerms,
  }) async {
    if (!acceptedTerms) {
      throw const AuthenticationException('Accept the terms.');
    }
    if (repository.accountByEmail(email) != null) {
      throw const AuthenticationException(
        'This email cannot be registered.',
        field: 'email',
      );
    }
    final account = await repository.createAccount(
      displayName: name,
      email: email,
      city: 'Karachi',
      intent: intent,
    );
    passwords[account.id] = password;
    return establish(account.id);
  }

  @override
  Future<AuthSession> verifyEmail({
    required String challengeId,
    required String code,
  }) async {
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
    passwords[account.id] = draft.password;
    _registration = null;
    return establish(account.id);
  }

  @override
  Future<AuthChallenge> resendVerification({
    required String challengeId,
  }) async {
    return AuthChallenge(
      id: 'verify-${++_challenge}',
      email: _registration!.email,
      resendAfter: cooldown,
    );
  }

  @override
  Future<AuthChallenge> requestPasswordReset({required String email}) async {
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
    if (code != '654321' ||
        challengeId != 'reset-$_challenge' ||
        repository.accountByEmail(_resetEmail ?? '') == null) {
      throw const AuthenticationException(
        'The code is invalid or expired.',
        field: 'otp',
      );
    }
    passwords[repository.accountByEmail(_resetEmail!)!.id] = password;
    _resetEmail = null;
    revoke();
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String password,
  }) async {
    final account = repository.currentAccount;
    if (account == null) {
      throw const AuthenticationException(
        'Your session has ended. Please sign in again.',
      );
    }
    if (passwords[account.id] != currentPassword) {
      throw const AuthenticationException(
        'Your current password is incorrect.',
        field: 'currentPassword',
      );
    }
    passwords[account.id] = password;
  }

  @override
  Future<void> changeEmail({
    required String currentPassword,
    required String email,
  }) async {
    final account = repository.currentAccount;
    if (account == null) {
      throw const AuthenticationException(
        'Your session has ended. Please sign in again.',
      );
    }
    if (passwords[account.id] != currentPassword) {
      throw const AuthenticationException(
        'Your current password is incorrect.',
        field: 'currentPassword',
      );
    }
    final next = email.trim();
    final existing = repository.accountByEmail(next);
    if (existing != null && existing.id != account.id) {
      throw const AuthenticationException(
        'That email address is already in use.',
        field: 'email',
      );
    }
    await repository.updateProfile(email: next);
  }

  @override
  Future<void> completePasswordRecovery({required String password}) async {
    throw const AuthenticationException(
      'Recovery links are not available in the demo build.',
    );
  }

  @override
  bool get pendingPasswordRecovery => false;

  @override
  int get accountRevision => 0;

  @override
  Future<void> signOutEverywhere() => signOut();

  @override
  Future<void> signOut() async {
    revoke();
  }
}
