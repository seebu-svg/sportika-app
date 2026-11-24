import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/features/discover/screens/games_tab.dart';
import 'package:sportika/features/matches/screens/matches_tab.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Hosts [MatchesTab] inside the shell.
///
/// Notifications and discovery shortcuts still request a match subsection
/// through [matchSectionRequest]; this adapter maps those legacy values onto
/// [MatchesTab] scopes and pushes the personal and pickup destinations.
class MatchesTabHost extends StatefulWidget {
  const MatchesTabHost({super.key});

  @override
  State<MatchesTabHost> createState() => _MatchesTabHostState();
}

class _MatchesTabHostState extends State<MatchesTabHost> {
  // Existing MatchesTab scope indices.
  static const int _defaultScope = 0;
  static const int _firstScope = 1;
  static const int _secondScope = 2;
  static const int _thirdScope = 3;

  // Legacy navigation request values.
  static const int _personalGamesRequest = 2;
  static const int _pickupGamesRequest = 4;

  int _scope = _defaultScope;

  // Used to force MatchesTab to apply a newly requested initial scope.
  int _scopeRevision = 0;

  // Prevents opening the same destination repeatedly while it is active.
  bool _openingDestination = false;

  @override
  void initState() {
    super.initState();

    matchSectionRequest.addListener(_handleSectionRequest);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (matchSectionRequest.value != 0) {
        _handleSectionRequest();
      }
    });
  }

  /// Converts the existing legacy section values to MatchesTab scopes.
  ///
  /// Mapping intentionally matches the original implementation:
  /// 0 -> 1
  /// 1 -> 3
  /// 3 -> 2
  /// Other values -> 0
  int _scopeForSection(int section) {
    return switch (section) {
      0 => _firstScope,
      1 => _thirdScope,
      3 => _secondScope,
      _ => _defaultScope,
    };
  }

  void _handleSectionRequest() {
    if (!mounted || _openingDestination) return;

    final section = matchSectionRequest.value;

    if (section == _personalGamesRequest) {
      _openPersonalGames();
      return;
    }

    if (section == _pickupGamesRequest) {
      _openPickupGames();
      return;
    }

    final nextScope = _scopeForSection(section);

    if (_scope == nextScope) return;

    setState(() {
      _scope = nextScope;
      _scopeRevision++;
    });
  }

  Future<void> _openPersonalGames() async {
    if (_openingDestination) return;

    _openingDestination = true;

    try {
      await pushRoute(context, AppRoute.personalGames);
    } finally {
      _openingDestination = false;
    }
  }

  Future<void> _openPickupGames() async {
    if (_openingDestination) return;

    _openingDestination = true;

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: sportikaAppBar(
              'Pickup games',
              subtitle: 'Discover games and join the action',
            ),
            body: const SafeArea(child: GamesTab()),
          ),
        ),
      );
    } finally {
      _openingDestination = false;
    }
  }

  @override
  void dispose() {
    matchSectionRequest.removeListener(_handleSectionRequest);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MatchesTab(
      // Ensures MatchesTab reinitializes when an external
      // navigation request selects a different scope.
      key: ValueKey(_scopeRevision),
      initialScope: _scope,
    );
  }
}
