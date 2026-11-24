import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/profile/widgets/profile_sport_preferences.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 12 · Sports preferences & playing level. One card per chosen sport, plus a
/// single question about how often the account expects to play.
class SportsLevelsScreen extends StatelessWidget {
  const SportsLevelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final sports = flow.selectedSports;

    return AuthPage(
      showBack: true,
      onBack: flow.back,
      sport: Sport.cricket,
      photoAlignment: const Alignment(0, -.5),
      stepLabel: 'PROFILE SETUP',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'CONTINUE',
            onPressed: sports.isEmpty ? null : flow.submitLevels,
          ),
          const SizedBox(height: 8),
          AuthLink(
            'Skip playing preferences',
            onTap: flow.skipPlayingPreferences,
          ),
          const SizedBox(height: 8),
          const AuthMicro('Next: review your profile before finishing.'),
        ],
      ),
      children: [
        const SizedBox(height: 8),
        const AuthStepRail(
          current: 3,
          labels: ['Basics', 'Photo', 'Sports', 'Play', 'Review'],
        ),
        const SizedBox(height: 26),
        const AuthEyebrow('PLAYING LEVEL'),
        const SizedBox(height: 14),
        const AuthHeadline('HOW DO YOU', accent: 'PLAY IT?', size: 42),
        const SizedBox(height: 14),
        const AuthLead(
          'Set your level and preferred position for each sport, or skip this step '
          'if you are here to organize. You can update it later.',
        ),
        const SizedBox(height: 20),
        if (sports.isEmpty)
          const AuthNotice(
            'No sports selected yet. Go back one step and pick at least one.',
            tone: SportikaColors.gold,
            icon: Icons.warning_amber_rounded,
          )
        else
          for (final sport in sports) ...[
            ProfileSportPreferences(
              sport: sport,
              level: flow.levels[sport.key] ?? defaultLevelFor(sport),
              position: flow.playingPositions[sport.key],
              onLevelChanged: (level) => flow.setLevel(sport, level),
              onPositionChanged: (position) =>
                  flow.setPosition(sport, position),
            ),
            if (sport != sports.last) const SizedBox(height: 12),
          ],
        const SizedBox(height: 24),
        const AuthEyebrow('PLAY STYLE', rule: false),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final style in PlayStyle.values)
              AuthChoicePill(
                label: style.label,
                selected: flow.playStyle == style,
                onTap: () => flow.setPlayStyle(style),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          flow.playStyle.blurb,
          style: const TextStyle(
            fontSize: 11,
            height: 1.4,
            color: SportikaColors.textMuted,
          ),
        ),
        const SizedBox(height: 18),
        const AuthMicro(
          'Your preferences help personalize your experience. '
          'You can update them anytime from your profile.',
          icon: Icons.insights_outlined,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
