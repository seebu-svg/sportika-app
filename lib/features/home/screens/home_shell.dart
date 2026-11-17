import 'package:flutter/material.dart';
import 'package:sportika/shared/widgets/global_app_header.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/features/home/screens/home_tab.dart';
import 'package:sportika/features/discover/screens/tournament_tab.dart';
import 'package:sportika/features/live/screens/scores_tab.dart';
import 'package:sportika/features/teams/screens/teams_tab.dart';
import 'package:sportika/features/profile/screens/profile_tab.dart';

/// Root shell: Home, Tournament, Match, Team and Me, with an in-place index, so a
/// notification deep link switches tab instead of pushing a second shell.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 4);
    homeTabRequest.value = _index;
    homeTabRequest.addListener(_handleTabRequest);
  }

  @override
  void dispose() {
    homeTabRequest.removeListener(_handleTabRequest);
    super.dispose();
  }

  void _handleTabRequest() {
    final next = homeTabRequest.value.clamp(0, 4);
    if (next == _index || !mounted) return;
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          GlobalAppHeader(
            section: const [
              'Home',
              'Tournament',
              'Match',
              'Team',
              'Me',
            ][_index],
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                HomeTab(),
                TournamentTab(),
                ScoresTab(),
                TeamsTab(),
                ProfileTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SportikaColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => homeTabRequest.value = i,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Tournament',
            ),
            NavigationDestination(
              icon: Icon(Icons.sensors_outlined),
              selectedIcon: Icon(Icons.sensors_rounded),
              label: 'Match',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups_rounded),
              label: 'Team',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Me',
            ),
          ],
        ),
      ),
    );
  }
}
