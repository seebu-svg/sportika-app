import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 14 · Setup complete / welcome to Sportika. A short confirmation card, then
/// the hand-off into the signed-in shell.
class SetupCompleteScreen extends StatelessWidget {
  const SetupCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final sports = flow.selectedSports;
    final levels = sports
        .map(
          (sport) =>
              '${sport.label} · ${(flow.levels[sport.key] ?? defaultLevelFor(sport)).label}',
        )
        .join('\n');
    final sport = flow.isOrganizer ? Sport.futsal : Sport.badminton;

    return AuthPage(
      sport: sport,
      photoAlignment: const Alignment(0, -.15),
      stepLabel: '04 / 04',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'ENTER SPORTIKA',
            icon: Icons.sports_handball_outlined,
            onPressed: flow.enterApp,
          ),
          const SizedBox(height: 8),
          AuthLink(
            'Review preferences',
            align: TextAlign.center,
            tone: SportikaColors.textMuted,
            onTap: flow.reviewPreferences,
          ),
          const SizedBox(height: 4),
          const AuthMicro(
            'Everything in this prototype lives on this device. No account is '
            'created on a server.',
          ),
        ],
      ),
      children: [
        const SizedBox(height: 24),
        const AuthEyebrow('SETUP COMPLETE', tone: SportikaColors.gold),
        const SizedBox(height: 14),
        AuthHeadline(
          "YOU'RE IN,",
          accent: '${flow.firstName.toUpperCase()}.',
          size: 46,
        ),
        const SizedBox(height: 16),
        AuthLead(
          flow.isOrganizer
              ? 'Your organizer tools are ready. Publish a tournament when you '
                    'are, and release results only when they are final.'
              : 'Your profile is ready. Start a private scorecard or find a '
                    'tournament your city is playing this week.',
          maxWidth: 330,
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: SportikaColors.surface.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: SportikaColors.gold.withValues(alpha: .28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'YOUR ATHLETE CARD',
                    style: authDisplay(
                      10,
                      color: SportikaColors.gold,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const Spacer(),
                  const BrandMark(size: 22),
                ],
              ),
              const SizedBox(height: 12),
              const AuthRule(),
              const SizedBox(height: 8),
              AuthSummaryRow(
                'Name',
                flow.fullName.isEmpty ? 'Sportika athlete' : flow.fullName,
              ),
              AuthSummaryRow(
                'Handle',
                flow.handle.isEmpty ? '@athlete' : '@${flow.handle}',
                tone: SportikaColors.mint,
              ),
              AuthSummaryRow('Role', flow.intent.label),
              AuthSummaryRow(
                'Sports',
                sports.isEmpty
                    ? 'Add a sport later'
                    : sports.map((s) => s.label).join(' · '),
              ),
              AuthSummaryRow('Level', levels.isEmpty ? 'Not set' : levels),
              AuthSummaryRow('City', flow.city.isEmpty ? 'Karachi' : flow.city),
              AuthSummaryRow('Play style', flow.playStyle.label),
              if (flow.bio.isNotEmpty) AuthSummaryRow('Bio', flow.bio),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const AuthNotice(
          'Returning to Sportika will skip onboarding and sign you straight in. '
          'Your session is remembered on this device.',
          icon: Icons.bolt_outlined,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
