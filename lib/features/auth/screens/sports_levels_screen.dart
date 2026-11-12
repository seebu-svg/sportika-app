import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';
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
          const AuthMicro('One more step: your profile photo.'),
        ],
      ),
      children: [
        const SizedBox(height: 8),
        const AuthStepRail(
          current: 2,
          labels: ['Basics', 'Sports', 'Levels', 'Photo'],
        ),
        const SizedBox(height: 26),
        const AuthEyebrow('PLAYING LEVEL'),
        const SizedBox(height: 14),
        const AuthHeadline('HOW DO YOU', accent: 'PLAY IT?', size: 42),
        const SizedBox(height: 14),
        const AuthLead(
          'Levels shape the games and tournaments we suggest. Be honest — you '
          'can move up whenever you like.',
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
            _SportLevelCard(sport: sport, flow: flow),
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
          'Private scorecards work at any level. Official entries follow each '
          'tournament’s own rules.',
          icon: Icons.insights_outlined,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SportLevelCard extends StatelessWidget {
  const _SportLevelCard({required this.sport, required this.flow});

  final Sport sport;
  final AuthFlowController flow;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);
    final level = flow.levels[sport.key] ?? defaultLevelFor(sport);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: SportikaColors.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SportikaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 30,
                width: 30,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: tone.withValues(alpha: .35)),
                ),
                child: Icon(sportGlyph(sport), size: 16, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sport.label.toUpperCase(),
                      style: authDisplay(17, height: 1.05, letterSpacing: .2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      level.blurb,
                      style: const TextStyle(
                        fontSize: 10,
                        color: SportikaColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                level.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: tone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final option in PlayingLevel.values)
                AuthChoicePill(
                  label: option.label,
                  dense: true,
                  tone: tone,
                  selected: level == option,
                  onTap: () => flow.setLevel(sport, option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
