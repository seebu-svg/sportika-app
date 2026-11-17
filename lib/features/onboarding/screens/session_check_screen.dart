import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// Shows the real service restoration request, without staged verification.
class SessionVerificationScreen extends StatelessWidget {
  const SessionVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    return AuthPage(
      stepLabel: 'SESSION CHECK',
      footer: TextButton(
        onPressed: flow.cancelSession,
        child: const Text('Use another account'),
      ),
      children: const [
        SizedBox(height: 48),
        AuthEyebrow('WELCOME BACK'),
        SizedBox(height: 16),
        AuthHeadline('CHECKING', accent: 'YOUR SESSION.', size: 42),
        SizedBox(height: 20),
        AuthLead('Verifying your saved session before opening your account.'),
        SizedBox(height: 32),
        Center(
          child: CircularProgressIndicator(semanticsLabel: 'Verifying session'),
        ),
      ],
    );
  }
}
