import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 06 · Account type. Two photographic choices, each carrying the promise of
/// that role; the copy makes it clear the choice is not permanent.
class AccountTypeScreen extends StatelessWidget {
  const AccountTypeScreen({super.key});

  static Sport _sportFor(AccountIntent intent) => switch (intent) {
    AccountIntent.player => Sport.cricket,
    AccountIntent.organizer => Sport.futsal,
  };

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();

    return AuthPage(
      sport: Sport.futsal,
      photoAlignment: const Alignment(0, -.25),
      showBack: true,
      onBack: flow.back,
      stepLabel: 'ACCOUNT TYPE',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(label: 'CONTINUE', onPressed: flow.submitIntent),
          const SizedBox(height: 10),
          const AuthMicro(
            'Organizer tools publish official results. Player scorecards stay '
            'private to you.',
          ),
        ],
      ),
      children: [
        const SizedBox(height: 8),
        const AuthStepRail(current: 1, labels: ['Account', 'Type', 'Verify']),
        const SizedBox(height: 26),
        const AuthEyebrow('ACCOUNT TYPE'),
        const SizedBox(height: 14),
        const AuthHeadline('HOW WILL', accent: 'YOU PLAY?', size: 44),
        const SizedBox(height: 16),
        const AuthLead(
          'This sets up your first tools. A single Sportika account can carry '
          'both roles at once.',
        ),
        const SizedBox(height: 24),
        for (final intent in AccountIntent.values) ...[
          AuthSelectCard(
            selected: flow.intent == intent,
            onTap: () => flow.selectIntent(intent),
            tone: intent == AccountIntent.player
                ? SportikaColors.mint
                : SportikaColors.blueBright,
            padding: const EdgeInsets.all(13),
            semanticLabel: intent.label,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SizedBox(
                    height: 72,
                    width: 64,
                    child: AuthPhoto(
                      sport: _sportFor(intent),
                      alignment: Alignment.center,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        intent.label.toUpperCase(),
                        style: authDisplay(22, height: 1.05, letterSpacing: .2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        intent.tagline,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        intent.proof.toUpperCase(),
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: intent == AccountIntent.player
                              ? SportikaColors.mint
                              : SportikaColors.blueBright,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Selector(
                  selected: flow.intent == intent,
                  tone: intent == AccountIntent.player
                      ? SportikaColors.mint
                      : SportikaColors.blueBright,
                ),
              ],
            ),
          ),
          if (intent != AccountIntent.organizer) const SizedBox(height: 12),
        ],
        const SizedBox(height: 18),
        const AuthNotice(
          'Players can organize. Organizers can play. Add a second role any '
          'time from your profile.',
          tone: SportikaColors.blueBright,
          icon: Icons.swap_horiz,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Selector extends StatelessWidget {
  const _Selector({required this.selected, required this.tone});

  final bool selected;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 26,
      width: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? tone : Colors.transparent,
        border: Border.all(
          color: selected ? tone : SportikaColors.borderStrong,
          width: 1.4,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 15, color: SportikaColors.deepest)
          : null,
    );
  }
}
