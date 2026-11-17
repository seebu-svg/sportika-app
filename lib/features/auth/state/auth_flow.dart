import 'package:sportika/app/env.dart';
import 'package:sportika/core/data/identity_document_store.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/profile_setup.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:sportika/features/auth/services/authentication_service.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';

/// Every screen and supporting state in the pre-authentication flow.
///
/// [home] is the hand-off point: the root gate only shows the signed-in shell
/// once the flow reaches it, which is how a returning authenticated session
/// bypasses onboarding and authentication.
enum AuthStage {
  splash,
  onboarding,
  welcome,
  signIn,
  createAccount,
  verifyEmail,
  forgotPassword,
  resetPassword,
  profileBasics,
  selectSports,
  sportsLevels,
  profilePhoto,
  setupComplete,
  sessionCheck,
  authError,
  terms,
  home,
}

/// What the six-digit screen is currently proving. The same screen serves
/// signup confirmation, passwordless sign-in and password recovery, and each
/// one is verified by the server as a different token type.
enum AuthCodePurpose { signup, signIn, recovery }

/// Coordinates authentication, verified sessions and the profile draft.
/// Authentication succeeds only after the injected service confirms it.
class AuthFlowController extends ChangeNotifier {
  AuthFlowController(
    this._app, {
    AuthenticationService? service,
    bool ownsService = false,
    this.identityStore,
    bool? emailVerificationEnabled,
  }) : _service = service ?? UnavailableAuthenticationService(),
       _ownsService = service == null || ownsService,
       _emailVerificationEnabled =
           emailVerificationEnabled ?? AppEnv.emailVerificationEnabled {
    _app.addListener(_handleAccountChange);
    _service.addListener(_handleServiceChange);
  }

  final SessionController _app;
  final IdentityDocumentStore? identityStore;
  final identityDocuments = IdentityDocumentDraft();
  int identityDraftRevision = 0;
  String? _identityNotice;
  final bool _emailVerificationEnabled;

  /// Whether a new account has to confirm its address with a six-digit code.
  ///
  /// False today: signup takes the secure session the service returns and the
  /// verify screen is never opened. Screens read this to hide the entries that
  /// would lead there, so the flag and the reachable UI cannot drift apart.
  bool get emailVerificationEnabled => _emailVerificationEnabled;

  /// Labels for the create-account rail. Without a verify screen the journey
  /// is two steps, and the rail must not promise a third.
  List<String> get signupStepLabels => _emailVerificationEnabled
      ? const ['Account', 'Verify', 'Profile']
      : const ['Account', 'Profile'];

  String? takeIdentityNotice() {
    final message = _identityNotice;
    _identityNotice = null;
    return message;
  }

  IdentityDocumentKind? get identityKind =>
      dateOfBirth == null ? null : identityKindFor(dateOfBirth!);

  void updateBirthDate(String value) {
    final previous = identityKind;
    birthDateText = value;
    if (previous != identityKind) {
      identityDocuments.clear();
      identityDraftRevision++;
    }
  }

  void skipIdentityDocuments() {
    identityDocuments.clear();
    identityDraftRevision++;
    clearInline();
  }

  final AuthenticationService _service;
  final bool _ownsService;
  AuthSession? _verifiedSession;
  AuthChallenge? _verification;
  AuthChallenge? _recovery;
  Timer? _expiryTimer;
  DateTime? _resendAt;
  int _operation = 0;

  /// The stage the code screen returns to when the member goes back.
  AuthStage? _otpReturn;

  /// True when the reset screen was opened by an emailed recovery link rather
  /// than by typing an address on the forgot-password screen. In that case the
  /// server already issued a session and no code is required.
  bool _recoveryFromLink = false;

  /// The service revision whose profile has already been folded into the draft.
  int _seenRevision = 0;

  bool get serviceConfigured => _service.isConfigured;
  bool get authenticated =>
      _verifiedSession != null &&
      !_verifiedSession!.isExpired &&
      _service.session?.accountId == _verifiedSession!.accountId &&
      _app.currentAccount?.id == _verifiedSession!.accountId;
  bool get canAccessApp =>
      authenticated &&
      (_app.currentAccount?.setupComplete ?? false) &&
      _stage == AuthStage.home;

  /// What the six-digit screen is proving right now.
  AuthCodePurpose get codePurpose {
    if (_stage == AuthStage.resetPassword) return AuthCodePurpose.recovery;
    return _verification?.kind == AuthChallengeKind.signIn
        ? AuthCodePurpose.signIn
        : AuthCodePurpose.signup;
  }

  /// True when the reset screen came from an emailed link, where the code is
  /// already proved and only a new password is missing.
  bool get recoveryFromLink => _recoveryFromLink;

  void _handleAccountChange() {
    if (!_resolved && _begun && _app.ready && _startTimer?.isActive != true) {
      unawaited(_resolveStart());
    }
    if (_verifiedSession == null) return;
    if (_app.currentAccount?.id != _verifiedSession!.accountId) {
      _invalidate('Your session has ended. Please sign in again.');
    }
  }

  void _handleServiceChange() {
    // A recovery link has to be handled before the session guard below: the
    // member may not have been signed in at all when they tapped it.
    if (_service.pendingPasswordRecovery && !_recoveryFromLink) {
      _openRecoveryFromLink();
      return;
    }
    if (_verifiedSession != null) {
      final revision = _service.accountRevision;
      if (revision != _seenRevision) {
        _seenRevision = revision;
        unawaited(_refreshProfile(_verifiedSession!.accountId));
      }
    }
    if (_verifiedSession == null) return;
    final session = _service.session;
    if (session == null ||
        session.isExpired ||
        session.accountId != _verifiedSession!.accountId) {
      _invalidate('Your session has expired. Please sign in again.');
    } else {
      _verifiedSession = session;
      _scheduleExpiry(session);
    }
  }

  /// Opens the reset screen for a link the SDK has already exchanged. The
  /// recovery session lives in the service; the app shell and the device
  /// identity are cleared so a protected screen cannot stay on top.
  void _openRecoveryFromLink() {
    if (_disposed) return;
    _operation++;
    _recoveryFromLink = true;
    _recovery = null;
    _verifiedSession = null;
    _expiryTimer?.cancel();
    _stopOtpTimer();
    password = '';
    otp = '';
    notice = 'Choose a new password for your account.';
    busy = false;
    _stage = AuthStage.resetPassword;
    notifyListeners();
    unawaited(_clearLocalSession());
  }

  /// Re-reads a profile the server says has changed (most often a confirmed
  /// email address) without disturbing the current screen.
  Future<void> _refreshProfile(String accountId) async {
    try {
      await _app.hydrateAccount(accountId);
    } catch (_) {
      // A stale row is better than an error dialog on a background refresh.
      return;
    }
    if (_disposed) return;
    final account = _app.accountById(accountId);
    if (account == null) return;
    _hydrate(account);
    notifyListeners();
  }

  void _scheduleExpiry(AuthSession session) {
    _expiryTimer?.cancel();
    _expiryTimer = Timer(session.expiresAt.difference(DateTime.now()), () {
      _invalidate('Your session has expired. Please sign in again.');
    });
  }

  void _invalidate(String message) {
    if (_disposed) return;
    _operation++;
    _verifiedSession = null;
    _expiryTimer?.cancel();
    _clearDraft();
    notice = message;
    busy = false;
    _stage = AuthStage.signIn;
    notifyListeners();
    // SDK invalidation must hide protected UI even if disk cleanup fails.
    unawaited(_clearLocalSession());
  }

  Future<void> _clearLocalSession() async {
    try {
      await _app.signOut();
    } catch (_) {
      if (!_disposed) {
        notice =
            'Signed out here. Device storage could not be cleared. '
            'A saved identity will still require session verification.';
        notifyListeners();
      }
    }
  }

  void _clearDraft() {
    email = '';
    password = '';
    fullName = '';
    handle = '';
    city = 'Karachi';
    bio = '';
    birthDateText = '';
    identityDocuments.clear();
    _identityNotice = null;
    gender = null;
    playingPositions.clear();
    playingPreferencesSkipped = false;
    sports.clear();
    levels.clear();
    playStyle = PlayStyle.weekly;
    avatar = 'midnight';
    acceptedTerms = false;
    otp = '';
    verificationEmail = '';
    resetEmail = '';
    _verification = null;
    _recovery = null;
    _resendAt = null;
    _termsReturn = null;
    _errorReturn = null;
    _returnToReview = false;
    _otpReturn = null;
    _recoveryFromLink = false;
    inlineError = null;
    inlineField = null;
    errorMessage = null;
    errorCode = null;
    _stopOtpTimer();
  }

  bool _active(int operation) => !_disposed && operation == _operation;

  Future<void> _request(Future<void> Function(int) action) async {
    if (busy || _disposed) return;
    final operation = ++_operation;
    busy = true;
    inlineError = null;
    inlineField = null;
    notice = null;
    notifyListeners();
    try {
      await action(operation).timeout(const Duration(seconds: 25));
    } on EmailVerificationRequired catch (error) {
      if (!_active(operation)) return;
      if (!_emailVerificationEnabled) {
        // The build has no code screen to offer, so say what happened instead
        // of opening a screen the flow has hidden.
        _inline(
          'email',
          'This account still needs an email confirmation. Please try again '
              'later.',
        );
        return;
      }
      _verification = error.challenge;
      verificationEmail = error.challenge.email;
      // The code screen was reached from sign-in, so back() returns there.
      _otpReturn = AuthStage.signIn;
      password = '';
      otp = '';
      _stage = AuthStage.verifyEmail;
      _startOtpTimer(error.challenge.resendAfter);
    } on AuthenticationException catch (error) {
      if (_active(operation)) _inline(error.field ?? 'request', error.message);
    } on TimeoutException {
      if (_active(operation)) {
        _inline(
          'request',
          'The request timed out. Check your connection and try again.',
        );
      }
    } catch (_) {
      if (_active(operation)) {
        _inline(
          'request',
          'We could not complete that request. Please try again.',
        );
      }
    } finally {
      if (_active(operation)) {
        // Invalidate late completions, including timed-out SDK calls.
        _operation++;
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _acceptSession(AuthSession session, int operation) async {
    if (!_active(operation)) return;
    if (session.isExpired || _service.session?.accountId != session.accountId) {
      throw const AuthenticationException(
        'Your session could not be verified. Please sign in again.',
      );
    }
    // The profile has to be in the directory before the synchronous lookup
    // below: a server-backed store fetches it here, the local one already has it.
    await _app.hydrateAccount(session.accountId);
    if (!_active(operation)) return;
    final account = _app.accountById(session.accountId);
    if (account == null) {
      throw const AuthenticationException(
        'Your account profile could not be loaded. Please try again.',
      );
    }
    await _app.signIn(session.accountId);
    if (!_active(operation)) return;
    if (_service.session?.accountId != session.accountId || session.isExpired) {
      await _clearLocalSession();
      throw const AuthenticationException(
        'Your session has ended. Please sign in again.',
      );
    }
    _verifiedSession = session;
    _scheduleExpiry(session);
    _hydrate(account);
    _seenRevision = _service.accountRevision;
    password = '';
    otp = '';
    _stopOtpTimer();
    _stage = account.setupComplete ? AuthStage.home : AuthStage.profileBasics;
  }

  AuthStage _stage = AuthStage.splash;
  bool _disposed = false;
  bool _signingOut = false;
  bool _begun = false;
  bool _resolved = false;
  Timer? _startTimer;
  Timer? _otpTimer;

  // ── Shared status ──────────────────────────────────────────────────────

  /// True while an authentication or persistence request is in flight.
  bool busy = false;

  /// Inline field validation, shown next to the offending input.
  String? inlineError;
  String? inlineField;

  /// Positive confirmation carried between stages (e.g. password reset).
  String? notice;

  /// Reason and reference shown by the authentication error state.
  String? errorMessage;
  String? errorCode;
  AuthStage? _errorReturn;

  // ── Draft ──────────────────────────────────────────────────────────────

  String email = '';
  String password = '';

  String fullName = '';
  String handle = '';
  String city = 'Karachi';
  String bio = '';
  String birthDateText = '';
  DateTime? get dateOfBirth => parseProfileDate(birthDateText);
  ProfileGender? gender;
  final Map<String, String> playingPositions = {};
  bool playingPreferencesSkipped = false;

  final Set<Sport> sports = {};
  final Map<String, PlayingLevel> levels = {};
  PlayStyle playStyle = PlayStyle.weekly;
  String avatar = 'midnight';
  bool acceptedTerms = false;

  int onboardingIndex = 0;
  int otpSecondsLeft = 0;
  String otp = '';
  String verificationEmail = '';
  String resetEmail = '';

  AuthStage? _termsReturn;

  /// True while a setup step was opened from the review screen, so completing
  /// or leaving that step returns to the review instead of walking the rest of
  /// the setup again.
  bool _returnToReview = false;

  AuthStage get stage => _stage;

  List<Sport> get selectedSports =>
      Sport.values.where(sports.contains).toList();

  String get firstName {
    final name = fullName.trim();
    if (name.isEmpty) return 'PLAYER';
    return name.split(RegExp(r'\s+')).first;
  }

  String get maskedEmail {
    final value = verificationEmail.isEmpty ? email : verificationEmail;
    final at = value.indexOf('@');
    if (at < 2) return value;
    final head = value.substring(0, at);
    final tail = value.substring(at);
    return '${head.substring(0, 2)}${'•' * (head.length - 2)}$tail';
  }

  bool get canContinueSports => sports.isNotEmpty;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Resolves where the app should land after the splash. A persisted session
  /// goes through session verification and skips everything else.
  void begin() {
    if (_begun) return;
    _begun = true;
    _startTimer = Timer(const Duration(milliseconds: 1750), _resolveStart);
  }

  void continueFromSplash() {
    _startTimer?.cancel();
    _resolveStart();
  }

  Future<void> _resolveStart() async {
    if (_disposed || _resolved || !_app.ready) return;
    _resolved = true;
    final hadSavedIdentity = _app.currentAccount != null;
    _stage = AuthStage.sessionCheck;
    await _request((operation) async {
      final session = await _service.restoreSession();
      if (!_active(operation)) return;
      if (session != null && !session.isExpired) {
        await _acceptSession(session, operation);
      } else {
        await _clearLocalSession();
        if (!_active(operation)) return;
        _stage = _app.onboardingSeen ? AuthStage.signIn : AuthStage.onboarding;
        if (hadSavedIdentity) {
          notice =
              'Your saved session could not be verified. Please sign in again.';
        }
      }
    });
    if (!_disposed && _stage == AuthStage.sessionCheck) {
      _fail(
        inlineError ?? 'Unable to verify your session.',
        code: 'SESSION',
        returnTo: AuthStage.splash,
      );
    }
  }

  Future<void> revalidateSession() async {
    if (_verifiedSession != null && !authenticated) {
      _invalidate('Your session has expired. Please sign in again.');
      return;
    }
    if (!authenticated || busy) return;
    await _request((operation) async {
      final session = await _service.restoreSession();
      if (!_active(operation)) return;
      if (session == null || session.isExpired) {
        _invalidate('Your session has expired. Please sign in again.');
        return;
      }
      if (_app.currentAccount?.setupComplete == false &&
          session.accountId == _verifiedSession?.accountId) {
        _verifiedSession = session;
        _scheduleExpiry(session);
      } else {
        await _acceptSession(session, operation);
      }
    });
    if (!_disposed && inlineError != null) {
      _invalidate('Your session could not be verified. Please sign in again.');
    }
  }

  void _hydrate(Account account) {
    fullName = account.displayName;
    email = account.email;
    city = account.city;
    handle = account.handle.isNotEmpty ? account.handle : account.username;
    bio = account.bio;
    birthDateText = profileDateLabel(account.dateOfBirth);
    gender = account.gender;
    playingPositions
      ..clear()
      ..addAll(account.playingPositions);
    playingPreferencesSkipped = account.playingPreferencesSkipped;
    sports
      ..clear()
      ..addAll(account.sports);
    levels
      ..clear()
      ..addAll(account.levels);
    for (final sport in sports) {
      if (!playingPreferencesSkipped) {
        levels.putIfAbsent(sport.key, () => defaultLevelFor(sport));
      }
    }
    playStyle = account.playStyle;
    avatar = account.avatar;
    verificationEmail = account.email;
    acceptedTerms = true;
  }

  @override
  void dispose() {
    identityDocuments.clear();
    _disposed = true;
    _app.removeListener(_handleAccountChange);
    _startTimer?.cancel();
    _expiryTimer?.cancel();
    _operation++;
    _service.removeListener(_handleServiceChange);
    if (_ownsService) _service.dispose();
    _otpTimer?.cancel();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  void _go(AuthStage next) {
    if (_disposed || busy) return;
    _operation++;
    if (next != AuthStage.verifyEmail && next != AuthStage.resetPassword) {
      _stopOtpTimer();
    }
    if (next == AuthStage.setupComplete) _returnToReview = false;
    _stage = next;
    inlineError = null;
    inlineField = null;
    busy = false;
    notifyListeners();
  }

  void clearInline() {
    if (inlineError == null && inlineField == null) return;
    inlineError = null;
    inlineField = null;
    notifyListeners();
  }

  void _inline(String field, String message) {
    inlineField = field;
    inlineError = message;
    busy = false;
    notifyListeners();
  }

  void back() {
    if (busy) return;
    // A step opened from the review screen goes back to the review, not to the
    // previous step of the walkthrough.
    if (_returnToReview &&
        const [
          AuthStage.profileBasics,
          AuthStage.profilePhoto,
          AuthStage.selectSports,
          AuthStage.sportsLevels,
        ].contains(_stage)) {
      _go(AuthStage.setupComplete);
      return;
    }
    switch (_stage) {
      case AuthStage.welcome:
        _go(AuthStage.onboarding);
      case AuthStage.signIn:
        _go(AuthStage.welcome);
      case AuthStage.createAccount:
        _go(AuthStage.welcome);
      case AuthStage.verifyEmail:
        _verification = null;
        otp = '';
        _stopOtpTimer();
        _go(_otpReturn ?? AuthStage.createAccount);
      case AuthStage.forgotPassword:
        _go(AuthStage.signIn);
      case AuthStage.resetPassword:
        if (_recoveryFromLink) {
          // Leaving a link-opened recovery must also drop the session the
          // server issued for it; otherwise it lingers until it expires.
          _recoveryFromLink = false;
          _recovery = null;
          unawaited(_service.signOut());
          _go(AuthStage.signIn);
        } else {
          _go(AuthStage.forgotPassword);
        }
      case AuthStage.profileBasics:
        unawaited(signOut());
      case AuthStage.selectSports:
        _go(AuthStage.profilePhoto);
      case AuthStage.sportsLevels:
        _go(AuthStage.selectSports);
      case AuthStage.profilePhoto:
        _go(AuthStage.profileBasics);
      case AuthStage.setupComplete:
        _go(AuthStage.sportsLevels);
      case AuthStage.authError:
        retry();
      case AuthStage.terms:
        _go(_termsReturn ?? AuthStage.createAccount);
      default:
        notifyListeners();
    }
  }

  // ── Onboarding & welcome ───────────────────────────────────────────────

  void setOnboardingIndex(int index) {
    final next = index.clamp(0, 3);
    if (next == onboardingIndex) return;
    onboardingIndex = next;
    notifyListeners();
  }

  void nextOnboarding() {
    if (onboardingIndex >= 3) {
      finishOnboarding();
      return;
    }
    setOnboardingIndex(onboardingIndex + 1);
  }

  /// Remembers the story so the next cold start goes straight to auth.
  Future<void> finishOnboarding() => _request((operation) async {
    await _app.markOnboardingSeen();
    if (_active(operation)) _stage = AuthStage.welcome;
  });

  void openSignIn() {
    if (busy) return;
    password = '';
    otp = '';
    // The reset screen offers this link next to the system back button, so it
    // has to drop a link-opened recovery exactly the same way: the short-lived
    // session the server issued for it should not outlive the screen.
    if (_recoveryFromLink) {
      _recoveryFromLink = false;
      _recovery = null;
      unawaited(_service.signOut());
    }
    _go(AuthStage.signIn);
  }

  void openCreateAccount() {
    if (busy) return;
    password = '';
    notice = null;
    _go(AuthStage.createAccount);
  }

  void openForgotPassword() {
    notice = null;
    _go(AuthStage.forgotPassword);
  }

  Future<void> cancelSession() => signOut();

  Future<void> signOut() => _endSession(everywhere: false);

  /// Settings → "Sign out of all devices".
  Future<void> signOutEverywhere() => _endSession(everywhere: true);

  Future<void> _endSession({required bool everywhere}) async {
    if (_disposed || _signingOut) return;
    _signingOut = true;
    ++_operation;
    _verifiedSession = null;
    _expiryTimer?.cancel();
    _startTimer?.cancel();
    _clearDraft();
    busy = true;
    _stage = AuthStage.signIn;
    notice = null;
    notifyListeners();
    try {
      if (everywhere) {
        await _service.signOutEverywhere().timeout(const Duration(seconds: 10));
      } else {
        await _service.signOut().timeout(const Duration(seconds: 10));
      }
    } catch (_) {
      notice = everywhere
          ? 'Signed out here. Other devices could not be reached.'
          : 'Signed out of this app. Remote session revocation could not be confirmed.';
    }
    await _clearLocalSession();
    _signingOut = false;
    if (_disposed) return;
    busy = false;
    notice ??= everywhere
        ? 'You have been signed out on every device.'
        : 'You have been signed out.';
    notifyListeners();
  }

  // ── Sign in ────────────────────────────────────────────────────────────

  Future<void> submitSignIn() async {
    if (busy || _stage != AuthStage.signIn) return;
    final value = email.trim();
    if (!AuthRules.email(value)) {
      _inline('email', 'Enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      _inline('password', 'Enter your password.');
      return;
    }
    await _request((operation) async {
      final session = await _service.signIn(email: value, password: password);
      if (!_active(operation)) return;
      await _acceptSession(session, operation);
    });
  }

  /// Sends a sign-in code instead of asking for the password.
  Future<void> beginPasswordlessSignIn() async {
    // The code screen is hidden while verification is off, so the sign-in
    // screen hides its link for the same reason: this has nowhere to go.
    if (!_emailVerificationEnabled) return;
    if (busy || _stage != AuthStage.signIn) return;
    final value = email.trim();
    if (!AuthRules.email(value)) {
      _inline('email', 'Enter a valid email address.');
      return;
    }
    await _request((operation) async {
      final challenge = await _service.requestSignInCode(email: value);
      if (!_active(operation)) return;
      _verification = challenge;
      verificationEmail = challenge.email;
      _otpReturn = AuthStage.signIn;
      password = '';
      otp = '';
      notice = 'If that address has a Sportika account, a sign-in code is on its way.';
      _stage = AuthStage.verifyEmail;
      _startOtpTimer(challenge.resendAfter);
    });
  }

  // ── Create account ─────────────────────────────────────────────────────

  Future<void> submitAccountDetails() async {
    if (busy || _stage != AuthStage.createAccount) return;
    if (fullName.trim().length < 2) {
      _inline('name', 'Tell us what to call you.');
      return;
    }
    if (!AuthRules.email(email)) {
      _inline('email', 'Enter a valid email address.');
      return;
    }
    if (!AuthRules.password(password)) {
      _inline('password', 'Use at least 8 characters.');
      return;
    }
    if (!acceptedTerms) {
      _inline('terms', 'Accept the terms to continue.');
      return;
    }
    await _registerAccount();
  }

  void setAcceptedTerms(bool value) {
    acceptedTerms = value;
    if (value && inlineField == 'terms') {
      inlineError = null;
      inlineField = null;
    }
    notifyListeners();
  }

  Future<void> _registerAccount() async {
    if (busy || _stage != AuthStage.createAccount) return;
    if (!AuthRules.password(password) ||
        !acceptedTerms ||
        !AuthRules.email(email)) {
      _go(AuthStage.createAccount);
      _inline(
        'request',
        'Review your account details and password before continuing.',
      );
      return;
    }
    await _request((operation) async {
      if (!_emailVerificationEnabled) {
        // No code screen: the registration has to hand back a session in the
        // same call, or the member is stranded on a form with no next step.
        final session = await _service.registerWithoutVerification(
          name: fullName.trim(),
          email: email.trim(),
          password: password,
          intent: AccountIntent.player,
          acceptedTerms: acceptedTerms,
        );
        if (!_active(operation)) return;
        await _acceptSession(session, operation);
        return;
      }
      final challenge = await _service.register(
        name: fullName.trim(),
        email: email.trim(),
        password: password,
        intent: AccountIntent.player,
        acceptedTerms: acceptedTerms,
      );
      if (!_active(operation)) return;
      _verification = challenge;
      verificationEmail = challenge.email;
      _otpReturn = AuthStage.createAccount;
      password = '';
      otp = '';
      _stage = AuthStage.verifyEmail;
      _startOtpTimer(challenge.resendAfter);
    });
  }

  // ── Verification ───────────────────────────────────────────────────────

  void _startOtpTimer(Duration cooldown) {
    _otpTimer?.cancel();
    _resendAt = DateTime.now().add(cooldown);
    void update() {
      otpSecondsLeft =
          ((_resendAt!.difference(DateTime.now()).inMilliseconds) / 1000)
              .ceil()
              .clamp(0, 86400);
    }

    update();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      update();
      if (otpSecondsLeft == 0) timer.cancel();
      notifyListeners();
    });
  }

  void _stopOtpTimer() {
    _otpTimer?.cancel();
    _otpTimer = null;
    otpSecondsLeft = 0;
  }

  Future<void> resendCode() async {
    if (busy || (_resendAt?.isAfter(DateTime.now()) ?? false)) return;
    final recovery = _stage == AuthStage.resetPassword;
    if (!recovery && _stage != AuthStage.verifyEmail) return;
    final challenge = recovery ? _recovery : _verification;
    if (challenge == null) return;
    await _request((operation) async {
      final AuthChallenge next;
      if (recovery) {
        next = await _service.resendPasswordReset(challengeId: challenge.id);
      } else if (challenge.kind == AuthChallengeKind.signIn) {
        // GoTrue has no resend for a sign-in code: the request itself is the
        // resend, and it stays neutral about whether the address exists.
        next = await _service.requestSignInCode(email: challenge.email);
      } else {
        next = await _service.resendVerification(challengeId: challenge.id);
      }
      if (!_active(operation)) return;
      if (recovery) {
        _recovery = next;
      } else {
        _verification = next;
      }
      otp = '';
      notice = recovery
          ? 'If an account exists for this address, a new reset code has been sent.'
          : challenge.kind == AuthChallengeKind.signIn
          ? 'If that address has a Sportika account, a new code has been sent.'
          : 'A new verification code has been sent.';
      _startOtpTimer(next.resendAfter);
    });
  }

  /// Leaves the code screen for a different address.
  void changeVerificationEmail() {
    if (busy) return;
    // An unverified sign-in sends the member back to sign in, not to the
    // account form.
    final returnTo = _otpReturn ?? AuthStage.createAccount;
    _verification = null;
    _otpReturn = null;
    otp = '';
    _go(returnTo);
  }

  Future<void> verifyCode(String code) async {
    if (busy || _stage != AuthStage.verifyEmail) return;
    if (!AuthRules.otp(code)) {
      _inline('otp', 'Enter the six-digit code from the email.');
      return;
    }
    final challenge = _verification;
    if (challenge == null) {
      _inline('otp', 'Request a new verification code.');
      return;
    }
    await _request((operation) async {
      final session = challenge.kind == AuthChallengeKind.signIn
          ? await _service.verifySignInCode(
              challengeId: challenge.id,
              code: code,
            )
          : await _service.verifyEmail(challengeId: challenge.id, code: code);
      if (!_active(operation)) return;
      await _acceptSession(session, operation);
      if (_active(operation)) _verification = null;
    });
  }

  // ── Password recovery ──────────────────────────────────────────────────

  Future<void> submitForgotPassword() async {
    if (busy || _stage != AuthStage.forgotPassword) return;
    if (!AuthRules.email(email)) {
      _inline('email', 'Enter the email on your account.');
      return;
    }
    await _request((operation) async {
      final challenge = await _service.requestPasswordReset(
        email: email.trim(),
      );
      if (!_active(operation)) return;
      _recovery = challenge;
      resetEmail = email.trim();
      otp = '';
      password = '';
      notice =
          'If an account exists for this address, a reset code has been sent.';
      _stage = AuthStage.resetPassword;
      _startOtpTimer(challenge.resendAfter);
    });
  }

  Future<void> submitResetPassword(String next, String confirm) async {
    if (busy || _stage != AuthStage.resetPassword) return;
    // A link already proved the address, so only a typed-code recovery needs
    // the six digits.
    if (!_recoveryFromLink && (!AuthRules.otp(otp) || _recovery == null)) {
      _inline('otp', 'Enter the six-digit reset code from your email.');
      return;
    }
    if (!AuthRules.password(next)) {
      _inline('password', 'Use at least 8 characters.');
      return;
    }
    if (next != confirm) {
      _inline('confirm', 'Both passwords must match.');
      return;
    }
    await _request((operation) async {
      if (_recoveryFromLink) {
        await _service.completePasswordRecovery(password: next);
      } else {
        await _service.resetPassword(
          challengeId: _recovery!.id,
          code: otp,
          password: next,
        );
      }
      if (!_active(operation)) return;
      _recovery = null;
      _recoveryFromLink = false;
      password = '';
      otp = '';
      if (resetEmail.isNotEmpty) email = resetEmail;
      _stopOtpTimer();
      notice = 'Password updated. Sign in with your new password.';
      _stage = AuthStage.signIn;
    });
  }

  // ── Account security (signed in) ──────────────────────────────────────

  /// Changes the password from Settings. Screens own their busy state; this
  /// throws [AuthenticationException] carrying the field to mark inline.
  Future<void> submitPasswordChange({
    required String currentPassword,
    required String next,
    required String confirm,
  }) async {
    if (currentPassword.isEmpty) {
      throw const AuthenticationException(
        'Enter your current password.',
        field: 'currentPassword',
      );
    }
    if (!AuthRules.password(next)) {
      throw const AuthenticationException(
        'Use at least 8 characters.',
        field: 'password',
      );
    }
    if (next != confirm) {
      throw const AuthenticationException(
        'Both passwords must match.',
        field: 'confirm',
      );
    }
    if (next == currentPassword) {
      throw const AuthenticationException(
        'Choose a password you have not used before.',
        field: 'password',
      );
    }
    await _service.changePassword(
      currentPassword: currentPassword,
      password: next,
    );
  }

  /// Starts an address change from Settings. Nothing changes until the member
  /// confirms the mail the server sends.
  Future<void> submitEmailChange({
    required String email,
    required String currentPassword,
  }) async {
    final value = email.trim();
    if (!AuthRules.email(value)) {
      throw const AuthenticationException(
        'Enter a valid email address.',
        field: 'email',
      );
    }
    final current = _app.currentAccount?.email ?? '';
    if (value.toLowerCase() == current.toLowerCase()) {
      throw const AuthenticationException(
        'That is already your email address.',
        field: 'email',
      );
    }
    if (currentPassword.isEmpty) {
      throw const AuthenticationException(
        'Enter your current password.',
        field: 'currentPassword',
      );
    }
    await _service.changeEmail(currentPassword: currentPassword, email: value);
  }

  // ── Profile setup ──────────────────────────────────────────────────────

  void saveBasics({
    required String name,
    required String handleValue,
    required String cityValue,
    required String bioValue,
    DateTime? dateOfBirthValue,
  }) {
    if (!authenticated || busy) return;
    final birth = dateOfBirthValue ?? dateOfBirth;
    final error = validateProfileIdentity(
      name: name,
      handle: handleValue,
      city: cityValue,
      bio: bioValue,
      dateOfBirth: birth,
    );
    if (error != null) {
      _inline(error.field, error.message);
      return;
    }
    final documentError = validateIdentityNumber(identityDocuments.number);
    if (documentError != null) {
      _inline('documentNumber', documentError);
      return;
    }
    final username = normalizeProfileHandle(handleValue);
    if (_app.accounts.any(
      (account) =>
          account.id != _app.currentAccount?.id &&
          account.username.toLowerCase() == username,
    )) {
      _inline(
        'handle',
        'That username is already used on this device. Choose another.',
      );
      return;
    }
    fullName = name.trim();
    handle = username;
    city = cityValue.trim();
    bio = bioValue.trim();
    birthDateText = profileDateLabel(birth);
    _go(_returnToReview ? AuthStage.setupComplete : AuthStage.profilePhoto);
  }

  void continueFromPhoto() {
    if (!authenticated) return;
    _go(_returnToReview ? AuthStage.setupComplete : AuthStage.selectSports);
  }

  void editSetupStep(AuthStage step) {
    if (!authenticated || busy) return;
    if (const [
      AuthStage.profileBasics,
      AuthStage.profilePhoto,
      AuthStage.selectSports,
      AuthStage.sportsLevels,
    ].contains(step)) {
      _returnToReview = true;
      _go(step);
    }
  }

  void toggleSport(Sport sport) {
    if (sports.contains(sport)) {
      sports.remove(sport);
      levels.remove(sport.key);
      playingPositions.remove(sport.key);
    } else {
      sports.add(sport);
      levels.putIfAbsent(sport.key, () => defaultLevelFor(sport));
    }
    notifyListeners();
  }

  void submitSports() {
    if (sports.isEmpty) {
      _inline('sports', 'Pick at least one sport to continue.');
      return;
    }
    _go(_returnToReview ? AuthStage.setupComplete : AuthStage.sportsLevels);
  }

  void selectAllSports() {
    if (sports.length == Sport.values.length) {
      sports.clear();
      levels.clear();
      playingPositions.clear();
    } else {
      for (final sport in Sport.values) {
        sports.add(sport);
        levels.putIfAbsent(sport.key, () => defaultLevelFor(sport));
      }
    }
    inlineError = null;
    inlineField = null;
    notifyListeners();
  }

  void setLevel(Sport sport, PlayingLevel level) {
    levels[sport.key] = level;
    notifyListeners();
  }

  void setPlayStyle(PlayStyle style) {
    playStyle = style;
    notifyListeners();
  }

  void setPosition(Sport sport, String? position) {
    if (position == null) {
      playingPositions.remove(sport.key);
    } else if (playingPositionsFor(sport).contains(position)) {
      playingPositions[sport.key] = position;
    }
    notifyListeners();
  }

  void submitLevels() {
    if (sports.isEmpty) {
      _inline('sports', 'Choose at least one sport.');
      return;
    }
    playingPreferencesSkipped = false;
    for (final sport in sports) {
      levels.putIfAbsent(sport.key, () => defaultLevelFor(sport));
    }
    _go(AuthStage.setupComplete);
  }

  void skipPlayingPreferences() {
    playingPreferencesSkipped = true;
    levels.clear();
    playingPositions.clear();
    _go(AuthStage.setupComplete);
  }

  void selectAvatar(String id) {
    avatar = id;
    notifyListeners();
  }

  Future<void> finishSetup() async {
    if (busy || !authenticated || _stage != AuthStage.setupComplete) return;
    final error = validateProfileIdentity(
      name: fullName,
      handle: handle,
      city: city,
      bio: bio,
      dateOfBirth: dateOfBirth,
    );
    if (error != null) {
      _inline(error.field, error.message);
      return;
    }
    if (sports.isEmpty) {
      _inline('sports', 'Choose at least one sport before finishing.');
      return;
    }
    if (_app.accounts.any(
      (a) =>
          a.id != _app.currentAccount?.id &&
          a.username.toLowerCase() == normalizeProfileHandle(handle),
    )) {
      _inline(
        'handle',
        'That username is already used on this device. Choose another.',
      );
      return;
    }
    final documentError = validateIdentityNumber(identityDocuments.number);
    if (documentError != null) {
      _inline('documentNumber', documentError);
      return;
    }
    final owner = _app.currentAccount!.id;
    final identity = IdentitySubmission(
      kind: identityKind!,
      number: normalizeIdentityNumber(identityDocuments.number).isEmpty
          ? null
          : normalizeIdentityNumber(identityDocuments.number),
      front: identityKind == IdentityDocumentKind.cnic
          ? identityDocuments.front
          : null,
      back: identityKind == IdentityDocumentKind.cnic
          ? identityDocuments.back
          : null,
    );
    await _request((operation) async {
      await _app.completeProfileSetup(
        displayName: fullName,
        handle: handle,
        bio: bio,
        city: city,
        sports: Set.of(sports),
        levels: Map.of(levels),
        playStyle: playStyle,
        avatar: avatar,
        dateOfBirth: dateOfBirth,
        gender: gender,
        playingPositions: Map.of(playingPositions),
        playingPreferencesSkipped: playingPreferencesSkipped,
      );
      if (!_active(operation)) return;
      if (!authenticated || !(_app.currentAccount?.setupComplete ?? false)) {
        throw const AuthenticationException(
          'Your profile could not be saved. Please try again.',
        );
      }
      identityDocuments.clear();
      _stage = AuthStage.home;
    });
    // Core completion has already unlocked Home. Optional uploads run outside
    // the core request's busy state and timeout and can never relock onboarding.
    if (!canAccessApp || _app.currentAccount?.id != owner || identity.isEmpty) {
      return;
    }
    String message;
    try {
      final store = identityStore;
      if (store == null) throw StateError('Private storage unavailable');
      await store
          .save(accountId: owner, submission: identity)
          .timeout(const Duration(seconds: 15));
      message =
          'Profile ready. Your optional identity details were saved privately.';
    } catch (_) {
      message = 'Your profile is ready. We could not confirm that optional identity details were saved. Identity verification is not required.';
    }
    if (!_disposed && authenticated && _app.currentAccount?.id == owner) {
      _identityNotice = message;
      notifyListeners();
    }
  }

  void enterApp() {
    unawaited(finishSetup());
  }

  void reviewPreferences() {
    if (authenticated) _go(AuthStage.selectSports);
  }

  // ── Terms ──────────────────────────────────────────────────────────────

  void openTerms(AuthStage returnTo) {
    _termsReturn = returnTo;
    _go(AuthStage.terms);
  }

  void closeTerms() {
    _go(_termsReturn ?? AuthStage.createAccount);
  }

  void acceptTerms() {
    acceptedTerms = true;
    _go(_termsReturn ?? AuthStage.createAccount);
  }

  // ── Failure & retry ────────────────────────────────────────────────────

  void _fail(
    String message, {
    required String code,
    required AuthStage returnTo,
  }) {
    busy = false;
    errorMessage = message;
    errorCode = code;
    _errorReturn = returnTo;
    _stage = AuthStage.authError;
    notifyListeners();
  }

  void retry() {
    final target = _errorReturn ?? AuthStage.signIn;
    errorMessage = null;
    errorCode = null;
    if (target == AuthStage.splash) {
      _resolved = false;
      unawaited(_resolveStart());
      return;
    }
    _go(target);
  }

  void useAnotherAccount() {
    unawaited(signOut());
    email = '';
    password = '';
    errorMessage = null;
    errorCode = null;
    _go(AuthStage.signIn);
  }
}
