import 'package:flutter/material.dart';
import 'package:sportika/features/matches/screens/matches_tab.dart';

/// Pushed entry for deep links and scorer shortcuts; the feed owns its header.
class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Align(alignment: Alignment.centerLeft, child: BackButton()),
          Expanded(child: MatchesTab()),
        ],
      ),
    ),
  );
}
