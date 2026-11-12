import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// A milestone with the evidence that unlocked it. `progress` is only used for
/// locked rows, so the athlete can see how far the next one is.
@immutable
class Achievement {
  const Achievement({
    required this.title,
    required this.description,
    required this.icon,
    required this.tone,
    required this.unlocked,
    this.progress,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color tone;
  final bool unlocked;
  final double? progress;
}

/// Data-derived achievements. Nothing here is stored: every row is recomputed
/// from the same records the rest of the app shows, so the list cannot drift
/// away from the profile.
List<Achievement> achievementsFrom({
  required List<Fixture> official,
  required int wins,
  required int squadsLed,
  required int tournamentsEntered,
  required int personalCards,
  required Set<Sport> sports,
}) {
  const gold = SportikaColors.gold;
  return [
    Achievement(
      title: 'First whistle',
      description: 'Play an official match',
      icon: Icons.sports,
      tone: SportikaColors.mint,
      unlocked: official.isNotEmpty,
      progress: official.isEmpty ? 0 : 1,
    ),
    Achievement(
      title: 'Off the mark',
      description: 'Win your first official match',
      icon: Icons.emoji_events_outlined,
      tone: gold,
      unlocked: wins >= 1,
      progress: wins >= 1 ? 1 : 0,
    ),
    Achievement(
      title: 'Hat-trick',
      description: 'Win three official matches',
      icon: Icons.military_tech_outlined,
      tone: gold,
      unlocked: wins >= 3,
      progress: (wins / 3).clamp(0.0, 1.0),
    ),
    Achievement(
      title: 'Squad builder',
      description: 'Lead a team or pair',
      icon: Icons.groups_2_outlined,
      tone: SportikaColors.blueBright,
      unlocked: squadsLed >= 1,
      progress: squadsLed >= 1 ? 1 : 0,
    ),
    Achievement(
      title: 'On the entry list',
      description: 'Enter a tournament',
      icon: Icons.how_to_reg_outlined,
      tone: SportikaColors.blueBright,
      unlocked: tournamentsEntered >= 1,
      progress: tournamentsEntered >= 1 ? 1 : 0,
    ),
    Achievement(
      title: 'Keep your own score',
      description: 'Log three private scorecards',
      icon: Icons.scoreboard_outlined,
      tone: SportikaColors.mint,
      unlocked: personalCards >= 3,
      progress: (personalCards / 3).clamp(0.0, 1.0),
    ),
    Achievement(
      title: 'Multi-sport',
      description: 'Play three different sports',
      icon: Icons.all_inclusive,
      tone: SportikaColors.padel,
      unlocked: sports.length >= 3,
      progress: (sports.length / 3).clamp(0.0, 1.0),
    ),
    Achievement(
      title: 'Season regular',
      description: 'Play five official matches',
      icon: Icons.calendar_month_outlined,
      tone: SportikaColors.mint,
      unlocked: official.length >= 5,
      progress: (official.length / 5).clamp(0.0, 1.0),
    ),
  ];
}

class AchievementsSection extends StatelessWidget {
  const AchievementsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<ProfileController>().currentAccount;
    if (me == null) return const SizedBox.shrink();

    final official = context.watch<ProfileController>().officialMatchesPlayed();
    final entryIds = context
        .watch<TournamentsController>()
        .entries
        .where((e) => e.memberAccountIds.contains(me.id))
        .map((e) => e.id)
        .toSet();
    final wins = official
        .where(
          (f) =>
              f.result?.winnerIndex ==
              (entryIds.contains(f.home.entryId) ? 0 : 1),
        )
        .length;
    final squadsLed = context.watch<TeamsController>().mySquads.length;
    final personalCards = context
        .watch<PersonalGamesController>()
        .myPersonal
        .length;
    final sports = official
        .map((f) => context.read<FixturesController>().tournamentOf(f)?.sport)
        .whereType<Sport>()
        .toSet();

    final achievements = achievementsFrom(
      official: official,
      wins: wins,
      squadsLed: squadsLed,
      tournamentsEntered: entryIds.length,
      personalCards: personalCards,
      sports: sports,
    );
    final unlocked = achievements.where((a) => a.unlocked).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Achievements',
          action: '$unlocked of ${achievements.length}',
        ),
        for (final achievement in achievements)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AchievementRow(achievement: achievement),
          ),
      ],
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    return Semantics(
      label:
          '${a.title}, ${a.unlocked ? 'unlocked' : 'locked'}. ${a.description}',
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        fillColor: a.unlocked ? null : SportikaColors.surfaceSunken,
        child: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: a.unlocked
                    ? a.tone.withValues(alpha: .16)
                    : SportikaColors.surfaceAlt,
                borderRadius: BorderRadius.circular(SportikaRadius.sm),
                border: Border.all(
                  color: a.unlocked
                      ? a.tone.withValues(alpha: .4)
                      : SportikaColors.borderSubtle,
                ),
              ),
              child: Icon(
                a.icon,
                size: 19,
                color: a.unlocked ? a.tone : SportikaColors.textDim,
              ),
            ),
            const SizedBox(width: SportikaSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    a.title,
                    style: SportikaType.bodyStrong.copyWith(
                      color: a.unlocked
                          ? SportikaColors.text
                          : SportikaColors.textMuted,
                    ),
                  ),
                  Text(a.description, style: SportikaType.caption),
                  if (!a.unlocked && a.progress != null) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(SportikaRadius.pill),
                      child: LinearProgressIndicator(
                        value: a.progress,
                        minHeight: 4,
                        color: SportikaColors.borderStrong,
                        backgroundColor: SportikaColors.borderSubtle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (a.unlocked) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, size: 18, color: a.tone),
            ],
          ],
        ),
      ),
    );
  }
}

/// Per-sport appearances and win rate, computed from the same official fixtures
/// the history list shows.
class SportStatisticsSection extends StatelessWidget {
  const SportStatisticsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<ProfileController>().currentAccount;
    if (me == null) return const SizedBox.shrink();
    final official = context.watch<ProfileController>().officialMatchesPlayed();
    final entries = context.watch<TournamentsController>().entries;
    final entryIds = entries
        .where((e) => e.memberAccountIds.contains(me.id))
        .map((e) => e.id)
        .toSet();
    final fixtures = context.watch<FixturesController>();

    final rows = <Sport, ({int played, int won})>{};
    for (final fixture in official) {
      final sport = fixtures.tournamentOf(fixture)?.sport;
      if (sport == null) continue;
      final current = rows[sport] ?? (played: 0, won: 0);
      final mySide = entryIds.contains(fixture.home.entryId) ? 0 : 1;
      final won = fixture.result?.winnerIndex == mySide;
      rows[sport] = (
        played: current.played + 1,
        won: current.won + (won ? 1 : 0),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Sport statistics'),
        if (rows.isEmpty)
          const EmptyState(
            title: 'No official appearances yet',
            body: 'Your win rate per sport appears once you play a fixture.',
            icon: Icons.insights_outlined,
          )
        else
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Column(
              children: [
                for (final entry in rows.entries)
                  StatBar(
                    label:
                        '${entry.key.label} · ${entry.value.played} played, '
                        '${entry.value.won} won',
                    value: entry.value.won,
                    total: entry.value.played,
                    trailing: entry.value.played == 0
                        ? '—'
                        : '${(entry.value.won / entry.value.played * 100).round()}%',
                    tone: sportColor(entry.key),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
