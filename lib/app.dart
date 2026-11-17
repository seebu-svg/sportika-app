import 'package:sportika/core/data/identity_document_store.dart';
import 'package:flutter/material.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/providers.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/onboarding/screens/auth_error_screen.dart';
import 'package:sportika/features/auth/screens/create_account_screen.dart';
import 'package:sportika/features/auth/screens/forgot_password_screen.dart';
import 'package:sportika/features/onboarding/screens/onboarding_screen.dart';
import 'package:sportika/features/auth/screens/profile_basics_screen.dart';
import 'package:sportika/features/auth/screens/profile_photo_screen.dart';
import 'package:sportika/features/auth/screens/reset_password_screen.dart';
import 'package:sportika/features/auth/screens/select_sports_screen.dart';
import 'package:sportika/features/onboarding/screens/session_check_screen.dart';
import 'package:sportika/features/auth/screens/setup_complete_screen.dart';
import 'package:sportika/features/auth/screens/sign_in_screen.dart';
import 'package:sportika/features/onboarding/screens/splash_screen.dart';
import 'package:sportika/features/auth/screens/sports_levels_screen.dart';
import 'package:sportika/features/onboarding/screens/terms_screen.dart';
import 'package:sportika/features/auth/screens/verify_email_screen.dart';
import 'package:sportika/features/onboarding/screens/welcome_screen.dart';
import 'package:sportika/features/home/screens/home_shell.dart';

class SportikaApp extends StatelessWidget {
  const SportikaApp({
    super.key,
    this.authenticationService,
    this.accountRepository,
    this.profileModuleRepository,
    this.matchRepository,
    this.tournamentRepository,
    this.fixtureRepository,
    this.gameRepository,
    this.teamRepository,
    this.notificationRepository,
    this.monetizationRepository,
    this.identityStore,
    this.emailVerificationEnabled,
  });

  /// Supplied by the composition root in `main.dart`, or by a test harness.
  ///
  /// When it is missing the app fails closed instead of falling back to the demo
  /// adapter: a release build that forgot to wire authentication must break
  /// visibly, never quietly verify credentials against the device.
  final AuthenticationService? authenticationService;

  /// Identity and profile when they come from the server. Null keeps both on the
  /// device store, which is what demo builds and every test use.
  final AccountRepository? accountRepository;

  /// The Me module when it reads and writes PostgreSQL. Null keeps it on the
  /// device adapter, which is what demo builds and every test use.
  final ProfileModuleRepository? profileModuleRepository;

  /// The match module when it reads and writes PostgreSQL. Null keeps official
  /// matches in the device document, which is what demo builds and every test
  /// use.
  final MatchRepository? matchRepository;

  /// The four discovery modules when they read and write PostgreSQL. Null
  /// keeps them in the device document, which is what demo builds and every
  /// test use.
  final TournamentRepository? tournamentRepository;
  final FixtureRepository? fixtureRepository;
  final GameRepository? gameRepository;
  final TeamRepository? teamRepository;

  /// The in-app inbox when it is read from PostgreSQL. Null keeps it in the
  /// device document, which is what demo builds and every test use.
  final NotificationRepository? notificationRepository;

  /// Billing when it reads and writes PostgreSQL. Null keeps it on the device
  /// adapter in a demo build, and on the fail-closed adapter everywhere else:
  /// no build ever fabricates a paid purchase.
  final MonetizationRepository? monetizationRepository;
  final IdentityDocumentStore? identityStore;

  /// Overrides the compile-time email-verification flag. Only tests pass it,
  /// so a binary always reflects the defines it was built with.
  final bool? emailVerificationEnabled;

  @override
  Widget build(BuildContext context) {
    return buildAppProviders(
      repository: context.read<LocalSportikaRepository>(),
      accountRepository: accountRepository,
      profileModuleRepository: profileModuleRepository,
      matchRepository: matchRepository,
      tournamentRepository: tournamentRepository,
      fixtureRepository: fixtureRepository,
      gameRepository: gameRepository,
      teamRepository: teamRepository,
      notificationRepository: notificationRepository,
      monetizationRepository: monetizationRepository,
      child: ChangeNotifierProvider<AuthFlowController>(
        create: (context) => AuthFlowController(
          context.read<SessionController>(),
          ownsService: authenticationService == null,
          identityStore: identityStore,
          emailVerificationEnabled: emailVerificationEnabled,
          service: authenticationService ?? UnavailableAuthenticationService(),
        )..begin(),
        child: MaterialApp(
          title: 'Sportika',
          debugShowCheckedModeBanner: false,
          theme: buildSportikaTheme(),
          onGenerateRoute: onGenerateRoute,
          home: const RootGate(),
        ),
      ),
    );
  }
}

/// Decides between the pre-auth journey and the five-tab shell.
///
/// A persisted session resolves through session verification and lands on
/// [AuthStage.home], so returning users never see onboarding or authentication
/// again. Everything else is a single stage of [AuthFlowController], swapped
/// with a short editorial cross-fade.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AuthFlowController>().revalidateSession();
    }
  }

  bool _noticeShown = false;

  /// A rebuilt (corrupt or migrated) document is announced exactly once, the
  /// first time the shell is on screen, so the player knows why their saved
  /// scorecards are gone instead of silently seeing demo data.
  void _maybeShowStorageNotice(SessionController session) {
    if (_noticeShown) return;
    _noticeShown = true;
    final notice = session.takeStorageNotice();
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(notice)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionController>();
    final flow = context.watch<AuthFlowController>();

    if (!state.ready) return const SplashScreen();
    _maybeShowStorageNotice(state);

    final stage = flow.stage;
    if (flow.canAccessApp) {
      final identityNotice = flow.takeIdentityNotice();
      if (identityNotice != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(identityNotice),
              duration: const Duration(seconds: 8),
            ),
          );
        });
      }
    }
    if (!flow.canAccessApp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !context.read<AuthFlowController>().canAccessApp) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }
    final screen = switch (stage) {
      AuthStage.splash => const SplashScreen(),
      AuthStage.onboarding => const OnboardingScreen(),
      AuthStage.welcome => const WelcomeScreen(),
      AuthStage.signIn => const SignInScreen(),
      AuthStage.createAccount => const CreateAccountScreen(),
      AuthStage.verifyEmail => const VerifyEmailScreen(),
      AuthStage.forgotPassword => const ForgotPasswordScreen(),
      AuthStage.resetPassword => const ResetPasswordScreen(),
      AuthStage.profileBasics => const ProfileBasicsScreen(),
      AuthStage.selectSports => const SelectSportsScreen(),
      AuthStage.sportsLevels => const SportsLevelsScreen(),
      AuthStage.profilePhoto => const ProfilePhotoScreen(),
      AuthStage.setupComplete => const SetupCompleteScreen(),
      AuthStage.sessionCheck => const SessionVerificationScreen(),
      AuthStage.authError => const AuthErrorScreen(),
      AuthStage.terms => const TermsScreen(),
      AuthStage.home => const HomeShell(),
    };

    final canGoBack = switch (stage) {
      AuthStage.splash ||
      AuthStage.onboarding ||
      AuthStage.home ||
      AuthStage.sessionCheck => false,
      _ => true,
    };
    return PopScope(
      canPop: !canGoBack && !flow.busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && canGoBack && !flow.busy) flow.back();
      },
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context) || !flow.authenticated
            ? Duration.zero
            : const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .025),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: ValueKey(stage), child: screen),
      ),
    );
  }
}
