import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/discover/screens/create_tournament_screen.dart';
import 'package:sportika/features/discover/screens/games_tab.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';
import 'package:sportika/features/discover/screens/players_tab.dart';
import 'package:sportika/features/discover/screens/tournaments_tab.dart';

/// Discover: games, tournaments and players in one place, with a single
/// create entry point for the things this account is allowed to start.
class DiscoverTab extends StatefulWidget {
  const DiscoverTab({super.key});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LocalSportikaRepository>();
    return Column(
      children: [
        TabHeader(
          title: 'Discover',
          subtitle: 'Find games, tournaments and sports activities near you.',
          actions: [
            IconButton(
              tooltip: 'Create',
              onPressed: () => _showCreateSheet(state),
              icon: const Icon(Icons.add_circle_outline),
            ),
            const NotificationBell(),
            const SizedBox(width: 10),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            segments: const [
              ButtonSegment(value: 0, label: Text('Games')),
              ButtonSegment(value: 1, label: Text('Tournaments')),
              ButtonSegment(value: 2, label: Text('Players')),
            ],
            selected: {_segment},
            onSelectionChanged: (v) => setState(() => _segment = v.first),
          ),
        ),
        Expanded(
          child: switch (_segment) {
            0 => const GamesTab(),
            1 => const TournamentsTab(),
            _ => const PlayersTab(),
          },
        ),
      ],
    );
  }

  Future<void> _showCreateSheet(LocalSportikaRepository state) async {
    final me = state.currentAccount;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => AppSheet(
        title: 'Start something',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetOption(
              icon: Icons.sports,
              title: 'Pickup match',
              subtitle: 'Open a game for the community to join',
              tone: SportikaColors.blueBright,
              onTap: () {
                Navigator.pop(sheetContext);
                pushScreen(context, const CreateGameScreen());
              },
            ),
            if (state.canOrganize)
              SheetOption(
                icon: Icons.emoji_events_outlined,
                title: 'Tournament',
                subtitle:
                    'Run an event with entries, draw and official results',
                tone: SportikaColors.mint,
                onTap: () {
                  Navigator.pop(sheetContext);
                  pushScreen(context, const CreateTournamentScreen());
                },
              ),
            if (me != null)
              SheetOption(
                icon: Icons.group_add_outlined,
                title: 'Team',
                subtitle: 'Build a squad and register it for events',
                tone: SportikaColors.gold,
                onTap: () {
                  Navigator.pop(sheetContext);
                  openHomeTab(context, 3);
                },
              ),
          ],
        ),
      ),
    );
  }
}
