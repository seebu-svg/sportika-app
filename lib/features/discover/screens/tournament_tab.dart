import 'package:flutter/material.dart';
import 'package:sportika/features/discover/screens/tournaments_tab.dart';

/// Sportika Tournament Hub.
///
/// The root shell provides the shared app header, bottom navigation,
/// and global theme.
///
/// Tournament discovery UI, including the cinematic sports hero,
/// featured competitions, sport filters, live tournaments,
/// and registration sections, belongs in TournamentsTab.
///
/// No duplicate Scaffold, AppBar, or navigation is created here.
class TournamentTab extends StatelessWidget {
  const TournamentTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const TournamentsTab();
  }
}
