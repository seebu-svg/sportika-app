import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/personal_games/screens/new_personal_match_screen.dart';

/// Profile-linked history: private scorecards (resume any unfinished card) and
/// the official matches the account took part in.
class MatchHistoryScreen extends StatelessWidget {
  const MatchHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final personal = state.myPersonal;
    final inProgress = personal.where(
      (m) => m.events.isNotEmpty || m.sideNames.isNotEmpty,
    );
    final official = state.officialMatchesPlayed();
    final completed = state.myPersonal
        .where((m) => m.status.name == 'completed')
        .length;

    return Scaffold(
      appBar: sportikaAppBar(
        'Match history',
        subtitle: 'Private cards and official appearances',
        actions: [
          IconButton(
            tooltip: 'New scorecard',
            icon: const Icon(Icons.add),
            onPressed: () =>
                pushScreen(context, const NewPersonalMatchScreen()),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${personal.length}',
                  label: 'Scorecards',
                  tone: SportikaColors.blueBright,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '$completed',
                  label: 'Completed',
                  tone: SportikaColors.mint,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '${official.length}',
                  label: 'Official',
                  tone: SportikaColors.gold,
                ),
              ),
            ],
          ),
          SectionTitle(
            'Personal scorecards',
            action: 'New',
            onAction: () => pushScreen(context, const NewPersonalMatchScreen()),
          ),
          if (inProgress.isEmpty)
            const EmptyState(
              title: 'No scorecards yet',
              body: 'Keep your own card for any match, then resume it later from here.',
              icon: Icons.scoreboard_outlined,
            )
          else
            for (final match in inProgress)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: personalScorecardTile(context, match),
              ),
          SectionTitle('Official matches'),
          if (official.isEmpty)
            const EmptyState(
              title: 'No official appearances',
              body:
                  'Enter a tournament and completed fixtures will appear here with '
                  'their published result.',
              icon: Icons.emoji_events_outlined,
            )
          else
            for (final fixture in official)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: officialFixtureTile(context, fixture),
              ),
          const SizedBox(height: 10),
          const InfoBanner(
            icon: Icons.shield_outlined,
            text:
                'Personal scorecards never appear in the Match Center or affect '
                'official results - only organizers publish those.',
          ),
        ],
      ),
    );
  }
}
