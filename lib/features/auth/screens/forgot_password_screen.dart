import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 08 · Forgot password. One field, one honest promise about enumeration, and
/// a clear way back.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(
      text: context.read<AuthFlowController>().email,
    );
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();

    return AuthPage(
      sport: Sport.badminton,
      photoAlignment: const Alignment(0, -.2),
      showBack: true,
      onBack: flow.back,
      stepLabel: 'RECOVERY',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'SEND RESET CODE',
            busy: flow.busy,
            onPressed: flow.submitForgotPassword,
            icon: Icons.outgoing_mail,
          ),
          const SizedBox(height: 8),
          AuthLink(
            'Back to sign in',
            align: TextAlign.center,
            icon: Icons.arrow_back,
            onTap: flow.openSignIn,
          ),
        ],
      ),
      children: [
        const SizedBox(height: 30),
        const AuthEyebrow('ACCOUNT RECOVERY'),
        const SizedBox(height: 14),
        const AuthHeadline("LET'S GET", accent: 'YOU BACK IN.', size: 44),
        const SizedBox(height: 16),
        const AuthLead(
          'Enter the email on your Sportika account and we will send a reset '
          'code. Your scorecards are untouched.',
        ),
        const SizedBox(height: 26),
        AuthField(
          label: 'Email address',
          controller: _email,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          errorText: flow.inlineField == 'email' ? flow.inlineError : null,
          onChanged: (value) {
            flow.email = value;
            if (flow.inlineField == 'email') flow.clearInline();
          },
          onSubmitted: (_) => flow.submitForgotPassword(),
        ),
        const SizedBox(height: 22),
        const AuthNotice(
          'For privacy, we show the same confirmation whether or not an account '
          'exists for the address.',
          tone: SportikaColors.blueBright,
          icon: Icons.shield_outlined,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
