import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 16 · Authentication error / retry. Says what failed, what it means, and
/// offers both a retry and a clean exit.
class AuthErrorScreen extends StatelessWidget {
  const AuthErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();

    return AuthPage(
      sport: Sport.futsal,
      photoAlignment: const Alignment(0, -.2),
      stepLabel: 'AUTH ERROR',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'TRY AGAIN',
            onPressed: flow.retry,
            icon: Icons.refresh,
          ),
          const SizedBox(height: 10),
          AuthAction(
            label: 'USE A DIFFERENT ACCOUNT',
            ghost: true,
            icon: Icons.switch_account_outlined,
            onPressed: flow.useAnotherAccount,
          ),
          const SizedBox(height: 6),
          AuthLink(
            'Create an account instead',
            align: TextAlign.center,
            tone: SportikaColors.textMuted,
            onTap: flow.openCreateAccount,
          ),
        ],
      ),
      children: [
        const SizedBox(height: 26),
        Container(
          height: 62,
          width: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SportikaColors.danger.withValues(alpha: .12),
            border: Border.all(
              color: SportikaColors.danger.withValues(alpha: .5),
            ),
          ),
          child: const Icon(
            Icons.priority_high_rounded,
            color: SportikaColors.danger,
            size: 28,
          ),
        ),
        const SizedBox(height: 22),
        const AuthEyebrow('AUTHENTICATION FAILED', tone: SportikaColors.danger),
        const SizedBox(height: 14),
        const AuthHeadline(
          "THAT DIDN'T",
          accent: 'GO THROUGH.',
          size: 44,
          accentTone: SportikaColors.danger,
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SportikaColors.surface.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: SportikaColors.danger.withValues(alpha: .25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'WHAT HAPPENED',
                    style: authDisplay(
                      10,
                      color: SportikaColors.textDim,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const Spacer(),
                  if (flow.errorCode != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: SportikaColors.danger.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: SportikaColors.danger.withValues(alpha: .3),
                        ),
                      ),
                      child: Text(
                        flow.errorCode!,
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: SportikaColors.danger,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                flow.errorMessage ??
                    'The request could not be completed. Check your connection '
                        'and try again.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: SportikaColors.textBody,
                ),
              ),
              const SizedBox(height: 13),
              const Divider(color: SportikaColors.borderSubtle, height: 1),
              const SizedBox(height: 12),
              const _CheckLine('Your account and scorecards are safe.'),
              const _CheckLine('Nothing was charged, published or deleted.'),
              const _CheckLine(
                'Demo accounts sign in instantly if time is short.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const AuthMicro(
          'If this keeps happening, sign in with a demo account from the Sign In '
          'screen to keep exploring the prototype.',
          icon: Icons.support_agent,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, size: 13, color: SportikaColors.mint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                height: 1.4,
                color: SportikaColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
