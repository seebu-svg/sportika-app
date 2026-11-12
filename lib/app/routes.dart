import 'package:flutter/material.dart';

import 'package:sportika/features/discover/screens/create_tournament_screen.dart';
import 'package:sportika/features/discover/screens/games_tab.dart';
import 'package:sportika/features/discover/screens/organizer_dashboard_screen.dart';
import 'package:sportika/features/discover/screens/tournament_detail_screen.dart';
import 'package:sportika/features/live/screens/fixture_detail_screen.dart';
import 'package:sportika/features/live/screens/match_history_screen.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';
import 'package:sportika/features/live/screens/results_review_screen.dart';
import 'package:sportika/features/live/screens/scorer_workspace_screen.dart';
import 'package:sportika/features/personal_games/screens/new_personal_match_screen.dart';
import 'package:sportika/features/personal_games/screens/personal_games_screen.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';
import 'package:sportika/features/teams/screens/create_team_screen.dart';
import 'package:sportika/features/teams/screens/team_detail_screen.dart';
import 'package:sportika/features/profile/screens/edit_profile_screen.dart';
import 'package:sportika/features/profile/screens/settings_screen.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/theme/theme.dart';

/// Named routes for every pushed screen.
///
/// The app is Android-only and local-first, so there is no URL contract to
/// serve; the table exists to give every push a single typed entry point, to
/// keep the back stack and the notification deep links in one place, and to
/// make an argument mismatch a compile error instead of a cast failure.
abstract final class AppRoute {
  static const String notifications = '/notifications';
  static const String editProfile = '/me/edit';
  static const String matchHistory = '/me/history';
  static const String settings = '/me/settings';

  static const String teamDetail = '/team/detail';
  static const String createTeam = '/team/create';

  static const String createGame = '/discover/games/create';
  static const String gameDetail = '/discover/games/detail';
  static const String createTournament = '/discover/tournaments/create';
  static const String tournamentDetail = '/discover/tournaments/detail';

  static const String fixtureDetail = '/live/fixture';
  static const String organizerDashboard = '/live/organizer';
  static const String scorerWorkspace = '/live/scorer';
  static const String resultsReview = '/live/results';

  static const String personalGames = '/personal';
  static const String newPersonalMatch = '/personal/new';
  static const String scorecard = '/personal/scorecard';
}

/// Arguments for [AppRoute.tournamentDetail].
@immutable
class TournamentDetailArgs {
  const TournamentDetailArgs(this.id);

  final String id;
}

/// Arguments for [AppRoute.fixtureDetail].
@immutable
class FixtureDetailArgs {
  const FixtureDetailArgs(this.fixtureId);

  final String fixtureId;
}

/// Arguments for [AppRoute.teamDetail].
@immutable
class TeamDetailArgs {
  const TeamDetailArgs(this.squadId);

  final String squadId;
}

/// Arguments for [AppRoute.gameDetail].
@immutable
class GameDetailArgs {
  const GameDetailArgs(this.game);

  final CommunityGame game;
}

/// Arguments for [AppRoute.scorecard]. [mode] decides which engine drives the
/// card: a private scorecard or an official fixture.
@immutable
class ScorecardArgs {
  const ScorecardArgs(this.id, this.mode);

  final String id;
  final ScorecardMode mode;
}

/// Arguments for [AppRoute.resultsReview].
@immutable
class ResultsReviewArgs {
  const ResultsReviewArgs({this.tournamentId, this.highlightId});

  final String? tournamentId;
  final String? highlightId;
}

/// Builds the screen for a route. Kept as a named map so an unknown name can
/// fall back instead of crashing on a production build.
Widget Function(Object? args) _builderFor(String name) {
  switch (name) {
    case AppRoute.notifications:
      return (_) => const NotificationsScreen();
    case AppRoute.editProfile:
      return (_) => const EditProfileScreen();
    case AppRoute.matchHistory:
      return (_) => const MatchHistoryScreen();
    case AppRoute.settings:
      return (_) => const SettingsScreen();
    case AppRoute.teamDetail:
      return (args) =>
          TeamDetailScreen(squadId: (args as TeamDetailArgs).squadId);
    case AppRoute.createTeam:
      return (_) => const CreateTeamScreen();
    case AppRoute.createGame:
      return (_) => const CreateGameScreen();
    case AppRoute.gameDetail:
      return (args) => GameDetailScreen(game: (args as GameDetailArgs).game);
    case AppRoute.createTournament:
      return (_) => const CreateTournamentScreen();
    case AppRoute.tournamentDetail:
      return (args) =>
          TournamentDetailScreen(id: (args as TournamentDetailArgs).id);
    case AppRoute.fixtureDetail:
      return (args) =>
          FixtureDetailScreen(fixtureId: (args as FixtureDetailArgs).fixtureId);
    case AppRoute.organizerDashboard:
      return (_) => const OrganizerDashboardScreen();
    case AppRoute.scorerWorkspace:
      return (_) => const ScorerWorkspaceScreen();
    case AppRoute.resultsReview:
      return (args) {
        final review = args as ResultsReviewArgs?;
        return ResultsReviewScreen(
          tournamentId: review?.tournamentId,
          highlightId: review?.highlightId,
        );
      };
    case AppRoute.personalGames:
      return (_) => const PersonalGamesScreen();
    case AppRoute.newPersonalMatch:
      return (_) => const NewPersonalMatchScreen();
    case AppRoute.scorecard:
      return (args) {
        final card = args as ScorecardArgs;
        return ScorecardScreen(id: card.id, mode: card.mode);
      };
    default:
      return (_) => const _UnknownRouteScreen();
  }
}

/// Resolves a [RouteSettings] name to a page route.
Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final builder = _builderFor(settings.name ?? '');
  return MaterialPageRoute<dynamic>(
    settings: settings,
    builder: (_) => builder(settings.arguments),
  );
}

/// The single push entry point. Callers name the route and hand it typed
/// arguments; nothing outside this file builds a [MaterialPageRoute].
Future<T?> pushRoute<T>(BuildContext context, String name, {Object? args}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name, arguments: args),
      builder: (_) => _builderFor(name)(args),
    ),
  );
}

class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not available')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This screen is no longer part of the build.',
              style: TextStyle(color: SportikaColors.textDim),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}
