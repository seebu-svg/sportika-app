import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/providers.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/screens/account_type_screen.dart';
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
  const SportikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return buildAppProviders(
      repository: context.read<LocalSportikaRepository>(),
      child: MaterialApp(
        title: 'Sportika',
        debugShowCheckedModeBanner: false,
        theme: buildSportikaTheme(),
        home: ChangeNotifierProvider<AuthFlowController>(
          create: (context) =>
              AuthFlowController(context.read<SessionController>())..begin(),
          child: const RootGate(),
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
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionController>();
    final flow = context.watch<AuthFlowController>();

    if (!state.ready) return const SplashScreen();

    final stage = flow.stage;
    final screen = switch (stage) {
      AuthStage.splash => const SplashScreen(),
      AuthStage.onboarding => const OnboardingScreen(),
      AuthStage.welcome => const WelcomeScreen(),
      AuthStage.signIn => const SignInScreen(),
      AuthStage.createAccount => const CreateAccountScreen(),
      AuthStage.accountType => const AccountTypeScreen(),
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
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
    );
  }
}
