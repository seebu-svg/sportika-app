import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/features/discover/screens/games_tab.dart';
import 'package:sportika/features/matches/screens/matches_tab.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Match landing page. Legacy section requests still reach their destination.
class ScoresTab extends StatefulWidget {
  const ScoresTab({super.key});
  @override
  State<ScoresTab> createState() => _ScoresTabState();
}

class _ScoresTabState extends State<ScoresTab> {
  int _scope = 0;

  @override
  void initState() {
    super.initState();
    matchSectionRequest.addListener(_handleSectionRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && matchSectionRequest.value != 0) _handleSectionRequest();
    });
  }

  void _handleSectionRequest() {
    final section = matchSectionRequest.value;
    if (section == 2) {
      pushRoute(context, AppRoute.personalGames);
    } else if (section == 4) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: sportikaAppBar('Pickup games'),
            body: const SafeArea(child: GamesTab()),
          ),
        ),
      );
    } else {
      setState(
        () => _scope = switch (section) {
          0 => 1,
          1 => 3,
          3 => 2,
          _ => 0,
        },
      );
    }
  }

  @override
  void dispose() {
    matchSectionRequest.removeListener(_handleSectionRequest);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MatchesTab(initialScope: _scope);
}
