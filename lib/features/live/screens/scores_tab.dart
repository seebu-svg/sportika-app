import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';

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
    final state = context.watch<FixturesController>();
    final fixtures = (tab == 0 ? state.liveFixtures : state.completedFixtures)
        .where((f) => sport == null || state.tournamentOf(f)?.sport == sport)
        .toList();
    return Column(
      children: [
        TabHeader(
          title: 'Live',
          subtitle: 'Official matches and your private scores.',
          actions: [
            if (context.read<SessionController>().hasRole(UserRole.scorer))
              IconButton(
                tooltip: 'Scorer assignments',
                icon: const Icon(Icons.assignment_outlined),
                onPressed: () => pushRoute(context, AppRoute.scorerWorkspace),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: FilterChipRow<int>(
            label: 'Scores section',
            selected: tab,
            onChanged: (v) => setState(() => tab = v),
            choices: const [
              FilterChoice(0, 'Live Scores'),
              FilterChoice(1, 'Results'),
              FilterChoice(2, 'Personal'),
            ],
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
                  onPressed: () => pushRoute(context, AppRoute.personalGames),
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
