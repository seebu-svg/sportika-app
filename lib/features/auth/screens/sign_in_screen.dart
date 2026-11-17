import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/env.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// Email and password sign-in through the configured authentication service.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final TextEditingController _email;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    final flow = context.read<AuthFlowController>();
    _email = TextEditingController(text: flow.email);
    _password = TextEditingController(text: flow.password);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit(AuthFlowController flow) {
    FocusScope.of(context).unfocus();
    flow.email = _email.text;
    flow.password = _password.text;
    flow.submitSignIn();
  }

  /// Passwordless path: the same address, sent a six-digit code instead of
  /// being asked for the password.
  void _sendCode(AuthFlowController flow) {
    FocusScope.of(context).unfocus();
    flow.email = _email.text;
    flow.beginPasswordlessSignIn();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    return AuthPage(
      sport: Sport.futsal,
      photoAlignment: const Alignment(0, -.25),
      showBack: true,
      onBack: flow.back,
      stepLabel: 'SIGN IN',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AppEnv.demoMode)
            const AuthNotice(
              'Local frontend demo · Sign in with seebu@sportika.pk and Sportika9!, or create an account. No server is connected.',
            ),
          AuthAction(
            label: 'SIGN IN',
            busy: flow.busy,
            onPressed: () => _submit(flow),
            icon: Icons.arrow_forward,
          ),
          // The code entry lives on the verify screen, which is hidden while
          // email verification is off: offering the link would open nothing.
          if (flow.serviceConfigured && flow.emailVerificationEnabled) ...[
            const SizedBox(height: 4),
            AuthLink(
              'Email me a sign-in code',
              align: TextAlign.center,
              icon: Icons.mail_outline,
              onTap: () => _sendCode(flow),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              const Text(
                'New to Sportika?',
                style: TextStyle(fontSize: 11.5, color: SportikaColors.textDim),
              ),
              AuthLink('Create an account', onTap: flow.openCreateAccount),
            ],
          ),
        ],
      ),
      children: [
        const SizedBox(height: 18),
        const AuthEyebrow('WELCOME BACK'),
        const SizedBox(height: 14),
        const AuthHeadline('PICK UP', accent: 'WHERE YOU\nLEFT OFF.', size: 42),
        if (flow.notice != null) ...[
          const SizedBox(height: 18),
          AuthNotice(flow.notice!),
        ],
        const SizedBox(height: 20),
        AuthField(
          label: 'Email address',
          controller: _email,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          errorText: flow.inlineField == 'email' ? flow.inlineError : null,
          onChanged: (value) {
            flow.email = value;
            if (flow.inlineField == 'email') flow.clearInline();
          },
        ),
        const SizedBox(height: 18),
        AuthField(
          label: 'Password',
          controller: _password,
          hint: 'Your password',
          obscure: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          errorText: flow.inlineField == 'password' ? flow.inlineError : null,
          onChanged: (value) {
            flow.password = value;
            if (flow.inlineField == 'password') flow.clearInline();
          },
          onSubmitted: (_) => _submit(flow),
          labelAction: AuthLink(
            'FORGOT?',
            tone: SportikaColors.textMuted,
            onTap: () => flow.openForgotPassword(),
          ),
        ),
        if (!flow.serviceConfigured) ...[
          const SizedBox(height: 22),
          const AuthNotice(
            'Sign-in is temporarily unavailable. Please try again later.',
            tone: SportikaColors.gold,
            icon: Icons.cloud_off_outlined,
          ),
        ],
        const SizedBox(height: 6),
      ],
    );
  }
}
