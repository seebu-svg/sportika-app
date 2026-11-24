import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';

/// Where a notification opens.
///
/// The server sends ids and a tab hint, never a path. This resolver turns
/// those ids into a route the app knows and checks that the member may open
/// it: a notification about a match they were removed from, or about a squad
/// they never joined, must not walk them into that screen.
///
/// A null result means the thing the notification talked about is gone or is
/// not theirs to see. The caller explains that instead of opening something
/// else.
NotificationTarget? resolveNotificationTarget(
  BuildContext context,
  AppNotification notification,
) {
  final type = notification.entityType;
  final id = notification.entityId;

  if (type == null || id == null || id.isEmpty) {
    // The device store's older rows carry only a route key.
    return notificationTargets[notification.route];
  }

  switch (type) {
    case 'match':
      return _matchTarget(context, notification, id);
    case 'result':
      return _resultTarget(context, notification, id);
    case 'fixture':
      return _fixtureTarget(context, notification, id);
    case 'tournament':
      return _tournamentTarget(context, id);
    case 'team':
      return _teamTarget(context, id);
    case 'dispute':
      return _disputeTarget(context, notification);
    case 'account':
      return const NotificationTarget.tab(HomeTabIndex.me);
    default:
      return notificationTargets[notification.route];
  }
}

/// Opens the destination of [notification] and says whether it landed.
///
/// A notification whose destination cannot be vouched for falls back to the
/// section it belongs to rather than to an error screen, so a stale message
/// never dead-ends the member.
Future<NotificationOpenResult> openNotification(
  BuildContext context,
  AppNotification notification,
) async {
  final target = resolveNotificationTarget(context, notification);
  if (target == null) return NotificationOpenResult.unavailable;
  if (target.route != null) {
    await pushRoute(context, target.route!, args: target.args);
    return NotificationOpenResult.opened;
  }
  openHomeTab(context, target.tab ?? 0);
  return NotificationOpenResult.opened;
}

/// What happened when a notification was tapped.
enum NotificationOpenResult {
  /// The destination opened.
  opened,

  /// The thing the notification talked about no longer exists, or is not
  /// this member's to open.
  unavailable,
}

/// The match itself, when the member may see it.
///
/// A scoring assignment opens the scorer workspace instead: the scorer is not
/// there to read the fixture sheet but to score it.
NotificationTarget? _matchTarget(
  BuildContext context,
  AppNotification notification,
  String matchId,
) {
  final matches = context.read<MatchRepository>();
  final match = matches.matchById(matchId);
  if (match == null) {
    // The list may simply not be loaded yet. Only a loaded list that does
    // not hold the match proves that it is gone.
    return matches.discoverableMatches.isEmpty
        ? const NotificationTarget.tab(HomeTabIndex.matches)
        : null;
  }

  final visible = matches.discoverableMatches.any((m) => m.id == matchId);
  if (!visible) return null;

  if (notification.kind == NotificationKind.scorerAssignment &&
      matches.myScoringMatches.any((m) => m.id == matchId)) {
    return const NotificationTarget.route(AppRoute.scorerWorkspace);
  }

  return NotificationTarget.route(
    AppRoute.matchDetail,
    args: MatchArgs(matchId),
  );
}

/// A published result: the match sheet first, then the fixture it belongs to.
NotificationTarget? _resultTarget(
  BuildContext context,
  AppNotification notification,
  String id,
) {
  final matchTarget = _matchTarget(context, notification, id);
  if (matchTarget?.route == AppRoute.matchDetail) return matchTarget;

  final fixtureTarget = _fixtureTarget(context, notification, id);
  if (fixtureTarget?.route == AppRoute.fixtureDetail) return fixtureTarget;

  return const NotificationTarget.tab(HomeTabIndex.matches);
}

/// A tournament fixture, or the scoring duty that goes with it.
NotificationTarget? _fixtureTarget(
  BuildContext context,
  AppNotification notification,
  String fixtureId,
) {
  final fixtures = context.read<FixtureRepository>();
  final fixture = fixtures.fixtureById(fixtureId);
  if (fixture != null) {
    final tournaments = context.read<TournamentRepository>();
    final tournament = tournaments.tournamentById(fixture.tournamentId);
    if (tournament == null) {
      return const NotificationTarget.tab(HomeTabIndex.tournaments);
    }
    return NotificationTarget.route(
      AppRoute.fixtureDetail,
      args: FixtureDetailArgs(fixtureId),
    );
  }

  if (notification.kind == NotificationKind.scorerAssignment) {
    return const NotificationTarget.route(AppRoute.scorerWorkspace);
  }

  // The fixture lives on the server and this build keeps tournament fixtures
  // on the device, so the sheet is not reachable from here. The tournament
  // section is where the member finds it.
  return const NotificationTarget.tab(HomeTabIndex.tournaments);
}

/// The tournament the notification is about.
NotificationTarget? _tournamentTarget(BuildContext context, String id) {
  final tournaments = context.read<TournamentRepository>();
  final tournament = tournaments.tournamentById(id);
  if (tournament == null) {
    return tournaments.tournaments.isEmpty
        ? const NotificationTarget.tab(HomeTabIndex.tournaments)
        : null;
  }
  return NotificationTarget.route(
    AppRoute.tournamentDetail,
    args: TournamentDetailArgs(id),
  );
}

/// The squad, but only for a member of that squad.
NotificationTarget? _teamTarget(BuildContext context, String id) {
  final teams = context.read<TeamRepository>();
  final squad = teams.squadById(id);
  if (squad == null) {
    return teams.squads.isEmpty
        ? const NotificationTarget.tab(HomeTabIndex.teams)
        : null;
  }
  final me = teams.currentAccountId;
  final onRoster = squad.ownerId == me || squad.memberAccountIds.contains(me);
  if (!onRoster) return null;
  return NotificationTarget.route(
    AppRoute.teamDetail,
    args: TeamDetailArgs(id),
  );
}

/// A dispute, which always belongs to a match.
NotificationTarget? _disputeTarget(
  BuildContext context,
  AppNotification notification,
) {
  final matchId = notification.payload['matchId'] as String?;
  if (matchId != null && matchId.isNotEmpty) {
    final target = _matchTarget(context, notification, matchId);
    if (target?.route == AppRoute.matchDetail) return target;
  }
  return const NotificationTarget.tab(HomeTabIndex.matches);
}
