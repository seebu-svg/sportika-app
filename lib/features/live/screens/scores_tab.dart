import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/features/personal_games/screens/personal_games_screen.dart';
import 'package:sportika/features/live/screens/scorer_workspace_screen.dart';

class ScoresTab extends StatefulWidget {
  const ScoresTab({super.key});
  @override
  State<ScoresTab> createState() => _ScoresTabState();
}

class _ScoresTabState extends State<ScoresTab> {
  int tab = 0;
  Sport? sport;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<LocalSportikaRepository>();
    final fixtures = (tab == 0 ? state.liveFixtures : state.completedFixtures)
        .where((f) => sport == null || state.tournamentOf(f)?.sport == sport)
        .toList();
    return Column(
      children: [
        TabHeader(
          title: 'Live',
          subtitle: 'Official matches and your private scores.',
          actions: [
            if (state.hasRole(UserRole.scorer))
              IconButton(
                tooltip: 'Scorer assignments',
                icon: const Icon(Icons.assignment_outlined),
                onPressed: () =>
                    pushScreen(context, const ScorerWorkspaceScreen()),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Live Scores')),
              ButtonSegment(value: 1, label: Text('Results')),
              ButtonSegment(value: 2, label: Text('Personal')),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),
        ),
        if (tab != 2)
          SportFilterBar(
            selected: sport,
            onChanged: (v) => setState(() => sport = v),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (tab == 2) ...[
                const InfoBanner(
                  icon: Icons.lock_outline,
                  text: 'Personal games and spectator scorecards are private. They never affect official tournament results.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () =>
                      pushScreen(context, const PersonalGamesScreen()),
                  icon: const Icon(Icons.sports_score),
                  label: const Text('My personal games'),
                ),
              ] else ...[
                for (final f in fixtures)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: officialFixtureTile(context, f),
                  ),
                if (fixtures.isEmpty)
                  const EmptyState(
                    title: 'No matches here yet',
                    icon: Icons.sports_score,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
