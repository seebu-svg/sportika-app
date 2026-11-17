import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/screens/change_email_screen.dart';
import 'package:sportika/features/auth/screens/change_password_screen.dart';

import 'package:sportika/features/discover/screens/create_tournament_screen.dart';
import 'package:sportika/features/discover/screens/games_tab.dart';
import 'package:sportika/features/discover/screens/organizer_dashboard_screen.dart';
import 'package:sportika/features/discover/screens/player_profile_screen.dart';
import 'package:sportika/features/discover/screens/tournament_detail_screen.dart';
import 'package:sportika/features/live/screens/fixture_detail_screen.dart';
import 'package:sportika/features/live/screens/match_history_screen.dart';
import 'package:sportika/features/live/screens/notification_preferences_screen.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';
import 'package:sportika/features/live/screens/results_review_screen.dart';
import 'package:sportika/features/live/screens/scorer_workspace_screen.dart';
import 'package:sportika/features/matches/screens/create_match_screen.dart';
import 'package:sportika/features/matches/screens/match_detail_screen.dart';
import 'package:sportika/features/matches/screens/matches_screen.dart';
import 'package:sportika/features/matches/scoring/match_scoring_shell.dart';
import 'package:sportika/features/monetization/screens/billing_history_screen.dart';
import 'package:sportika/features/monetization/screens/pricing_screen.dart';
import 'package:sportika/features/monetization/screens/subscription_screen.dart';
import 'package:sportika/features/monetization/screens/tournament_upgrade_screen.dart';
import 'package:sportika/features/personal_games/screens/new_personal_match_screen.dart';
import 'package:sportika/features/personal_games/screens/personal_games_screen.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';
import 'package:sportika/features/personal_games/screens/sport_scoring_screens.dart';
import 'package:sportika/features/teams/screens/create_team_screen.dart';
import 'package:sportika/features/teams/screens/team_detail_screen.dart';
import 'package:sportika/features/profile/screens/edit_profile_screen.dart';
import 'package:sportika/features/profile/screens/identity_documents_screen.dart';
import 'package:sportika/features/profile/screens/personal_information_screen.dart';
import 'package:sportika/features/profile/screens/scorer_assignments_screen.dart';
import 'package:sportika/features/profile/screens/settings_screen.dart';
import 'package:sportika/features/profile/screens/sports_preferences_screen.dart';
import 'package:sportika/features/profile/screens/team_memberships_screen.dart';
import 'package:sportika/features/profile/screens/tournament_history_screen.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';

/// Named routes for every pushed screen.
///
/// The app is Android-only and local-first, so there is no URL contract to
/// serve; the table exists to give every push a single typed entry point, to
/// keep the back stack and the notification deep links in one place, and to
/// make an argument mismatch a compile error instead of a cast failure.
abstract final class AppRoute {
  static const String notifications = '/notifications';
  static const String notificationPreferences = '/notifications/preferences';
  static const String editProfile = '/me/edit';
  static const String personalInformation = '/me/personal';
  static const String sportsPreferences = '/me/sports';
  static const String tournamentHistory = '/me/tournaments';
  static const String teamMemberships = '/me/teams';
  static const String scorerAssignments = '/me/scoring';
  static const String identityDocuments = '/me/identity';
  static const String matchHistory = '/me/history';
  static const String settings = '/me/settings';
  static const String changePassword = '/me/security/password';
  static const String changeEmail = '/me/security/email';

  static const String playerProfile = '/team/players/profile';

  static const String teamDetail = '/team/detail';
  static const String createTeam = '/team/create';

  static const String createGame = '/match/games/create';
  static const String gameDetail = '/match/games/detail';
  static const String createTournament = '/tournament/create';
  static const String tournamentDetail = '/tournament/detail';

  static const String fixtureDetail = '/match/fixture';
  static const String matches = '/match/official';
  static const String createMatch = '/match/official/create';
  static const String matchDetail = '/match/official/detail';
  static const String matchScoring = '/match/official/scoring';
  static const String organizerDashboard = '/tournament/organizer';
  static const String scorerWorkspace = '/match/scorer';
  static const String resultsReview = '/match/results';

  /// Plans, one subscription surface, the purchase ledger, and the per-tournament
  /// upgrade flow. All four live under `/me/billing` except the upgrade, which is
  /// reached from a tournament and carries its id.
  static const String pricing = '/me/billing';
  static const String subscription = '/me/billing/pro';
  static const String billingHistory = '/me/billing/history';
  static const String tournamentUpgrade = '/tournament/upgrade';

  static const String personalGames = '/personal';
  static const String newPersonalMatch = '/personal/new';
  static const String scorecard = '/personal/scorecard';
  static const String personalPerformance = '/personal/performance';
  static const String personalGameDetail = '/personal/game';
  static const String personalMatchCentre = '/personal/centre';
  static const String personalTimeline = '/personal/timeline';
  static const String personalStats = '/personal/stats';
  static const String personalEdit = '/personal/edit';
  static const String personalSetup = '/personal/setup';
  static const String personalSportDetail = '/personal/sport';
  static const String personalSettings = '/personal/settings';
}

/// Arguments for the personal screens that are keyed by one private match.
@immutable
class PersonalMatchArgs {
  const PersonalMatchArgs(this.id);

  final String id;
}

/// Arguments for [AppRoute.personalEdit]. The whole match is handed over so the
/// editor can prefill without reaching back into the store.
@immutable
class PersonalEditArgs {
  const PersonalEditArgs(this.match);

  final PersonalMatch match;
}

/// Arguments for [AppRoute.personalSetup].
@immutable
class PersonalSetupArgs {
  const PersonalSetupArgs(
    this.id, {
    this.startAfterSave = false,
    this.playersOnly = false,
  });

  final String id;
  final bool startAfterSave;
  final bool playersOnly;
}

/// Arguments for [AppRoute.personalSportDetail].
@immutable
class PersonalSportDetailArgs {
  const PersonalSportDetailArgs(this.id, this.index);

  final String id;
  final int index;
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

/// Arguments for [AppRoute.createMatch].
/// When navigating from a tournament fixture both ids are set so the new match
/// is linked. For a standalone friendly both are null.
@immutable
class CreateMatchArgs {
  const CreateMatchArgs({this.tournamentId, this.fixtureId});

  final String? tournamentId;
  final String? fixtureId;
}

/// Arguments for the standalone match screens.
@immutable
class MatchArgs {
  const MatchArgs(this.id);

  final String id;
}

/// Arguments for [AppRoute.playerProfile].
@immutable
class PlayerProfileArgs {
  const PlayerProfileArgs(this.accountId);

  final String accountId;
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

/// Arguments for [AppRoute.tournamentUpgrade]. The pass unlocks exactly one
/// tournament, so the id is required rather than inferred from whatever page
/// pushed the route.
@immutable
class TournamentUpgradeArgs {
  const TournamentUpgradeArgs(this.tournamentId);

  final String tournamentId;
}

/// Builds the screen for a route. Kept as a named map so an unknown name can
/// fall back instead of crashing on a production build.
Widget Function(Object? args) _builderFor(String name) {
  switch (name) {
    case AppRoute.notifications:
      return (_) => const NotificationsScreen();
    case AppRoute.notificationPreferences:
      return (_) => const NotificationPreferencesScreen();
    case AppRoute.editProfile:
      return (_) => const EditProfileScreen();
    case AppRoute.personalInformation:
      return (_) => const PersonalInformationScreen();
    case AppRoute.sportsPreferences:
      return (_) => const SportsPreferencesScreen();
    case AppRoute.tournamentHistory:
      return (_) => const TournamentHistoryScreen();
    case AppRoute.teamMemberships:
      return (_) => const TeamMembershipsScreen();
    case AppRoute.scorerAssignments:
      return (_) => const ScorerAssignmentsScreen();
    case AppRoute.identityDocuments:
      return (_) => const IdentityDocumentsScreen();
    case AppRoute.matchHistory:
      return (_) => const MatchHistoryScreen();
    case AppRoute.settings:
      return (_) => const SettingsScreen();
    case AppRoute.changePassword:
      return (_) => const ChangePasswordScreen();
    case AppRoute.changeEmail:
      return (_) => const ChangeEmailScreen();
    case '/discover/players/profile': // Keep existing deep links working.
    case AppRoute.playerProfile:
      return (args) =>
          PlayerProfileScreen(accountId: (args as PlayerProfileArgs).accountId);
    case AppRoute.teamDetail:
      return (args) =>
          TeamDetailScreen(squadId: (args as TeamDetailArgs).squadId);
    case AppRoute.createTeam:
      return (_) => const CreateTeamScreen();
    case '/discover/games/create': // Keep existing deep links working.
    case AppRoute.createGame:
      return (_) => const CreateGameScreen();
    case '/discover/games/detail': // Keep existing deep links working.
    case AppRoute.gameDetail:
      return (args) => GameDetailScreen(game: (args as GameDetailArgs).game);
    case '/discover/tournaments/create': // Keep existing deep links working.
    case AppRoute.createTournament:
      return (_) => const CreateTournamentScreen();
    case '/discover/tournaments/detail': // Keep existing deep links working.
    case AppRoute.tournamentDetail:
      return (args) =>
          TournamentDetailScreen(id: (args as TournamentDetailArgs).id);
    case '/live/fixture': // Keep existing deep links working.
    case AppRoute.fixtureDetail:
      return (args) =>
          FixtureDetailScreen(fixtureId: (args as FixtureDetailArgs).fixtureId);
    case '/live/organizer': // Keep existing deep links working.
    case AppRoute.organizerDashboard:
      return (_) => const OrganizerDashboardScreen();
    case '/live/scorer': // Keep existing deep links working.
    case AppRoute.scorerWorkspace:
      return (_) => const ScorerWorkspaceScreen();
    case AppRoute.matches:
      return (_) => const MatchesScreen();
    case AppRoute.createMatch:
      return (args) {
        final a = args as CreateMatchArgs?;
        return CreateMatchScreen(
          tournamentId: a?.tournamentId,
          fixtureId: a?.fixtureId,
        );
      };
    case AppRoute.matchDetail:
      return (args) => MatchDetailScreen(matchId: (args as MatchArgs).id);
    case AppRoute.matchScoring:
      return (args) => MatchScoringScreen(matchId: (args as MatchArgs).id);
    case '/live/results': // Keep existing deep links working.
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
    case AppRoute.personalPerformance:
      return (_) => const PersonalPerformanceScreen();
    case AppRoute.personalGameDetail:
      return (args) =>
          PersonalGameDetailsScreen(id: (args as PersonalMatchArgs).id);
    case AppRoute.personalMatchCentre:
      return (args) =>
          SportMatchCentreScreen(id: (args as PersonalMatchArgs).id);
    case AppRoute.personalTimeline:
      return (args) =>
          PersonalTimelineScreen(id: (args as PersonalMatchArgs).id);
    case AppRoute.personalSettings:
      return (args) =>
          PersonalScoringSettingsScreen(id: (args as PersonalMatchArgs).id);
    case AppRoute.personalStats:
      return (args) => PersonalStatsScreen(id: (args as PersonalMatchArgs).id);
    case AppRoute.personalEdit:
      return (args) =>
          EditPersonalGameScreen(match: (args as PersonalEditArgs).match);
    case AppRoute.personalSetup:
      return (args) {
        final setup = args as PersonalSetupArgs;
        return SportMatchSetupScreen(
          id: setup.id,
          startAfterSave: setup.startAfterSave,
          playersOnly: setup.playersOnly,
        );
      };
    case AppRoute.personalSportDetail:
      return (args) {
        final detail = args as PersonalSportDetailArgs;
        return SportDetailScreen(id: detail.id, index: detail.index);
      };
    case AppRoute.scorecard:
      return (args) {
        final card = args as ScorecardArgs;
        return ScorecardScreen(id: card.id, mode: card.mode);
      };
    case AppRoute.pricing:
      return (_) => const PricingScreen();
    case AppRoute.subscription:
      return (_) => const SubscriptionScreen();
    case AppRoute.billingHistory:
      return (_) => const BillingHistoryScreen();
    case AppRoute.tournamentUpgrade:
      return (args) => TournamentUpgradeScreen(
        tournamentId: (args as TournamentUpgradeArgs).tournamentId,
      );
    default:
      return (_) => const _UnknownRouteScreen();
  }
}

/// Resolves a [RouteSettings] name to a page route.
Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final builder = _builderFor(settings.name ?? '');
  return MaterialPageRoute<dynamic>(
    settings: settings,
    builder: (_) =>
        _AuthenticatedPage(builder: () => builder(settings.arguments)),
  );
}

/// The single push entry point. Callers name the route and hand it typed
/// arguments; nothing outside this file builds a [MaterialPageRoute].
Future<T?> pushRoute<T>(BuildContext context, String name, {Object? args}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name, arguments: args),
      builder: (_) =>
          _AuthenticatedPage(builder: () => _builderFor(name)(args)),
    ),
  );
}

/// Like [pushRoute] but replaces the current page, so a wizard cannot be
/// reached again with the back button after it has handed over.
Future<T?> pushReplacementRoute<T>(
  BuildContext context,
  String name, {
  Object? args,
}) {
  return Navigator.of(context).pushReplacement<T, dynamic>(
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name, arguments: args),
      builder: (_) =>
          _AuthenticatedPage(builder: () => _builderFor(name)(args)),
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

/// Protect both named and typed pushes, including pages already on the stack.
class _AuthenticatedPage extends StatelessWidget {
  const _AuthenticatedPage({required this.builder});
  final Widget Function() builder;

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    if (flow.canAccessApp) return builder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    return const Scaffold(backgroundColor: SportikaColors.background);
  }
}
