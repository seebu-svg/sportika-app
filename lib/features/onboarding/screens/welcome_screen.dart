import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 03 · Welcome / Get started. The fork between a new account and an existing
/// one, with the brand promise stated once and no competing noise.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();

    return AuthPage(
      sport: Sport.badminton,
      photoAlignment: const Alignment(0, -.25),
      stepLabel: 'WELCOME',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'CREATE ACCOUNT',
            onPressed: flow.openCreateAccount,
            tone: SportikaColors.blue,
          ),
          const SizedBox(height: 10),
          AuthAction(
            label: 'SIGN IN',
            onPressed: flow.openSignIn,
            ghost: true,
            icon: Icons.login,
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'By continuing you agree to our ',
                style: TextStyle(fontSize: 10.5, color: SportikaColors.textDim),
              ),
              AuthLink(
                'terms & privacy',
                onTap: () => flow.openTerms(AuthStage.welcome),
                tone: SportikaColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 2),
          const AuthMicro(
            'Private scorecards and official results are separate records.',
            icon: Icons.shield_outlined,
          ),
        ],
      ),
      children: const [
        SizedBox(height: 34),
        AuthEyebrow('WELCOME TO SPORTIKA'),
        SizedBox(height: 16),
        AuthHeadline('THE GAME', accent: 'CONNECTS US.', size: 48),
        SizedBox(height: 16),
        AuthLead(
          'Discover games, find your people and bring a tournament to life. '
          'One account for Cricket, Padel, Futsal and Badminton.',
          maxWidth: 330,
        ),
        SizedBox(height: 26),
        AuthRule(label: 'THIS SEASON'),
        SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Metric(value: '04', label: 'SPORTS'),
            ),
            _MetricDivider(),
            Expanded(
              child: _Metric(value: '01', label: 'COMMUNITY'),
            ),
            _MetricDivider(),
            Expanded(
              child: _Metric(value: '01', label: 'CITY'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: authDisplay(30, height: 1, letterSpacing: -.5)),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 7.5,
            fontWeight: SportikaFontWeight.extraBold,
            letterSpacing: 1.3,
            color: SportikaColors.textDim,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 34, width: 1, color: SportikaColors.border);
}
