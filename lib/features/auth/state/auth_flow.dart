import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/state/app_state.dart';

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
  accountType,
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

/// Keeps the whole pre-auth journey in one place: the current stage, the
/// in-progress sign-up draft, simulated request state, and the copy for the
/// error/session states.
///
/// Nothing here touches the network. Requests are simulated with short delays
/// so the prototype can show busy, timeout and retry behaviour honestly.
class AuthFlowController extends ChangeNotifier {
  AuthFlowController(this._app) {
    _app.addListener(_handleAccountChange);
  }

  final AppState _app;

  /// A sign-out from the profile tab puts the app back on Sign In and clears
  /// the credentials held by the flow.
  void _handleAccountChange() {
    if (_app.isSignedIn) return;
    if (_stage != AuthStage.home && _stage != AuthStage.sessionCheck) return;
    _stage = AuthStage.signIn;
    email = '';
    password = '';
    notice = null;
    notifyListeners();
  }

  AuthStage _stage = AuthStage.splash;
  bool _disposed = false;
  bool _begun = false;
  bool _resolved = false;
  Timer? _startTimer;
  Timer? _sessionTimer;
  Timer? _otpTimer;

  // ── Shared status ──────────────────────────────────────────────────────

  /// True while a simulated request is in flight.
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
  AccountIntent intent = AccountIntent.player;

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

  AuthStage get stage {
    // Signing out from the profile tab drops the session; the gate falls back
    // to Sign In without the flow having to know about that screen.
    if (!_app.isSignedIn &&
        (_stage == AuthStage.home || _stage == AuthStage.sessionCheck)) {
      return AuthStage.signIn;
    }
    return _stage;
  }

  bool get isOrganizer => intent == AccountIntent.organizer;

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

  void _resolveStart() {
    if (_disposed || _resolved) return;
    _resolved = true;
    final account = _app.currentAccount;
    if (account == null) {
      _stage = _app.onboardingSeen ? AuthStage.signIn : AuthStage.onboarding;
      notifyListeners();
      return;
    }
    _hydrate(account);
    _stage = AuthStage.sessionCheck;
    notifyListeners();
    _sessionTimer = Timer(const Duration(milliseconds: 1750), () {
      if (_disposed) return;
      _stage = account.setupComplete
          ? AuthStage.home
          : AuthStage.profileBasics;
      notifyListeners();
    });
  }

  void _hydrate(Account account) {
    fullName = account.displayName;
    email = account.email;
    city = account.city;
    handle = account.handle.isNotEmpty ? account.handle : account.username;
    bio = account.bio;
    sports
      ..clear()
      ..addAll(account.sports);
    levels
      ..clear()
      ..addAll(account.levels);
    for (final sport in sports) {
      levels.putIfAbsent(sport.key, () => defaultLevelFor(sport));
    }
    playStyle = account.playStyle;
    avatar = account.avatar;
    intent = account.has(UserRole.organizer)
        ? AccountIntent.organizer
        : AccountIntent.player;
    verificationEmail = account.email;
    acceptedTerms = true;
  }

  @override
  void dispose() {
    _disposed = true;
    _app.removeListener(_handleAccountChange);
    _startTimer?.cancel();
    _sessionTimer?.cancel();
    _otpTimer?.cancel();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  void _go(AuthStage next) {
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
    switch (_stage) {
      case AuthStage.welcome:
        _go(AuthStage.onboarding);
      case AuthStage.signIn:
        _go(AuthStage.welcome);
      case AuthStage.createAccount:
        _go(AuthStage.welcome);
      case AuthStage.accountType:
        _go(AuthStage.createAccount);
      case AuthStage.verifyEmail:
        _stopOtpTimer();
        _go(AuthStage.accountType);
      case AuthStage.forgotPassword:
        _go(AuthStage.signIn);
      case AuthStage.resetPassword:
        _go(AuthStage.forgotPassword);
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
    if (index == onboardingIndex) return;
    onboardingIndex = index;
    notifyListeners();
  }

  void nextOnboarding() {
    if (onboardingIndex >= 2) {
      finishOnboarding();
      return;
    }
    setOnboardingIndex(onboardingIndex + 1);
  }

  /// Remembers the story so the next cold start goes straight to auth.
  void finishOnboarding() {
    _app.markOnboardingSeen();
    _go(AuthStage.welcome);
  }

  void openSignIn() {
    _go(AuthStage.signIn);
  }

  void openCreateAccount() {
    notice = null;
    _go(AuthStage.createAccount);
  }

  void openForgotPassword() {
    notice = null;
    _go(AuthStage.forgotPassword);
  }

  /// Leaves a persisted session behind when the user does not want to be
  /// recognised on this device.
  Future<void> cancelSession() async {
    await _app.signOut();
    email = '';
    password = '';
    _go(AuthStage.signIn);
  }

  // ── Sign in ────────────────────────────────────────────────────────────

  Future<void> submitSignIn() async {
    final value = email.trim();
    if (!AuthRules.email(value)) {
      _inline('email', 'Enter a valid email address.');
      return;
    }
    if (password.trim().length < 6) {
      _inline('password', 'Enter your password (6+ characters).');
      return;
    }
    busy = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (_disposed) return;

    final account = _app.accountByEmail(value);
    if (account == null) {
      _fail(
        'We could not find a Sportika account for $value. Check the address, or '
        'create an account in under a minute.',
        code: 'AUTH-404',
        returnTo: AuthStage.signIn,
      );
      return;
    }
    await _app.signIn(account.id);
    await _app.markOnboardingSeen();
    _hydrate(account);
    busy = false;
    _stage = account.setupComplete ? AuthStage.home : AuthStage.profileBasics;
    notifyListeners();
  }

  Future<void> demoSignIn(String accountId) async {
    final account = _app.accountById(accountId);
    if (account == null) return;
    busy = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_disposed) return;
    await _app.signIn(accountId);
    await _app.markOnboardingSeen();
    _hydrate(account);
    busy = false;
    _stage = account.setupComplete ? AuthStage.home : AuthStage.profileBasics;
    notifyListeners();
  }

  // ── Create account ─────────────────────────────────────────────────────

  void submitAccountDetails() {
    if (fullName.trim().length < 2) {
      _inline('name', 'Tell us what to call you.');
      return;
    }
    if (!AuthRules.email(email)) {
      _inline('email', 'Enter a valid email address.');
      return;
    }
    if (_app.accountByEmail(email) != null) {
      _inline('email', 'An account already uses this email. Sign in instead.');
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
    _go(AuthStage.accountType);
  }

  void selectIntent(AccountIntent value) {
    intent = value;
    notifyListeners();
  }

  void setAcceptedTerms(bool value) {
    acceptedTerms = value;
    if (value && inlineField == 'terms') {
      inlineError = null;
      inlineField = null;
    }
    notifyListeners();
  }

  void submitIntent() {
    verificationEmail = email.trim();
    _go(AuthStage.verifyEmail);
    _startOtpTimer();
  }

  // ── Verification ───────────────────────────────────────────────────────

  void _startOtpTimer() {
    _otpTimer?.cancel();
    otpSecondsLeft = 30;
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      if (otpSecondsLeft <= 1) {
        timer.cancel();
        otpSecondsLeft = 0;
      } else {
        otpSecondsLeft--;
      }
      notifyListeners();
    });
  }

  void _stopOtpTimer() {
    _otpTimer?.cancel();
    _otpTimer = null;
  }

  void resendCode() {
    if (otpSecondsLeft > 0) return;
    notice = 'A new code is on its way to $verificationEmail.';
    _startOtpTimer();
    notifyListeners();
  }

  void changeEmail() {
    _stopOtpTimer();
    _go(AuthStage.createAccount);
  }

  Future<void> verifyCode(String code) async {
    if (!AuthRules.otp(code)) {
      _inline('otp', 'Enter the six-digit code from the email.');
      return;
    }
    busy = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (_disposed) return;

    if (code == '000000') {
      _fail(
        'That verification code has expired. Request a new one and try again.',
        code: 'AUTH-410',
        returnTo: AuthStage.verifyEmail,
      );
      return;
    }

    await _app.createAccount(
      displayName: fullName,
      email: email,
      city: city,
      intent: intent,
    );
    _stopOtpTimer();
    otp = '';
    busy = false;
    _hydrate(_app.currentAccount!);
    _hydrateDraftOnly();
    _stage = AuthStage.profileBasics;
    notifyListeners();
  }

  /// Keeps the typed name and city while the new account has no sports yet.
  void _hydrateDraftOnly() {
    sports.clear();
    levels.clear();
    playStyle = PlayStyle.weekly;
    avatar = 'midnight';
    bio = '';
    handle = '';
    acceptedTerms = true;
  }

  // ── Password recovery ──────────────────────────────────────────────────

  Future<void> submitForgotPassword() async {
    if (!AuthRules.email(email)) {
      _inline('email', 'Enter the email on your account.');
      return;
    }
    busy = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (_disposed) return;
    resetEmail = email.trim();
    busy = false;
    notice =
        'If an account exists for ${email.trim()}, a reset code is on its way.';
    _go(AuthStage.resetPassword);
  }

  void submitResetPassword(String next, String confirm) {
    if (!AuthRules.password(next)) {
      _inline('password', 'Use at least 8 characters.');
      return;
    }
    if (next != confirm) {
      _inline('confirm', 'Both passwords must match.');
      return;
    }
    password = '';
    email = resetEmail.isNotEmpty ? resetEmail : email;
    notice = 'Password updated. Sign in with your new password.';
    _go(AuthStage.signIn);
  }

  // ── Profile setup ──────────────────────────────────────────────────────

  void saveBasics({
    required String name,
    required String handleValue,
    required String cityValue,
    required String bioValue,
  }) {
    if (name.trim().length < 2) {
      _inline('name', 'Enter the name other players will see.');
      return;
    }
    final cleanHandle = handleValue.trim().replaceAll('@', '').toLowerCase();
    if (cleanHandle.length < 3 ||
        !RegExp(r'^[a-z0-9._]+$').hasMatch(cleanHandle)) {
      _inline('handle', 'Use 3+ letters, numbers, dots or underscores.');
      return;
    }
    if (cityValue.trim().isEmpty) {
      _inline('city', 'Add the city you play in.');
      return;
    }
    fullName = name.trim();
    handle = cleanHandle;
    city = cityValue.trim();
    bio = bioValue.trim();
    _go(AuthStage.selectSports);
  }

  void toggleSport(Sport sport) {
    if (sports.contains(sport)) {
      sports.remove(sport);
      levels.remove(sport.key);
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
    _go(AuthStage.sportsLevels);
  }

  void selectAllSports() {
    if (sports.length == Sport.values.length) {
      sports.clear();
      levels.clear();
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

  void submitLevels() => _go(AuthStage.profilePhoto);

  void selectAvatar(String id) {
    avatar = id;
    notifyListeners();
  }

  Future<void> finishSetup() async {
    busy = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (_disposed) return;
    await _app.completeProfileSetup(
      displayName: fullName,
      handle: handle,
      bio: bio,
      city: city,
      sports: sports,
      levels: levels,
      playStyle: playStyle,
      avatar: avatar,
    );
    busy = false;
    _go(AuthStage.setupComplete);
  }

  void enterApp() => _go(AuthStage.home);

  void reviewPreferences() => _go(AuthStage.selectSports);

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

  /// Lets the Sign In screen surface a deliberate timeout for the prototype
  /// without a backend.
  void failSession(String message) {
    _fail(message, code: 'NET-408', returnTo: AuthStage.signIn);
  }

  void retry() {
    final target = _errorReturn ?? AuthStage.signIn;
    errorMessage = null;
    errorCode = null;
    if (target == AuthStage.verifyEmail) {
      otp = '';
      _startOtpTimer();
    }
    _go(target);
  }

  void useAnotherAccount() {
    email = '';
    password = '';
    errorMessage = null;
    errorCode = null;
    _go(AuthStage.signIn);
  }
}
