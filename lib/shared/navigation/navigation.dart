import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';

/// Shell tab indexes. [HomeShell] renders its destinations in this order, so a
/// tab request and the navigation bar can never drift apart.
abstract final class HomeTabIndex {
  static const int home = 0;
  static const int tournaments = 1;
  static const int matches = 2;
  static const int teams = 3;
  static const int me = 4;
}

/// Tab requested by a notification deep link. [HomeShell] listens to this and
/// switches tab in place, so a notification never stacks a second shell.
final ValueNotifier<int> homeTabRequest = ValueNotifier<int>(HomeTabIndex.home);

/// Match subsection requested by discovery shortcuts and notifications.
final ValueNotifier<int> matchSectionRequest = ValueNotifier<int>(0);

void openMatchTab(BuildContext context, {int section = 0}) {
  matchSectionRequest.value = section;
  openHomeTab(context, HomeTabIndex.matches);
}

void openMatchGames(BuildContext context) => openMatchTab(context, section: 4);

void openHomeTab(BuildContext context, int index) {
  homeTabRequest.value = index;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Where a notification should land: either a tab index, or a pushed route.
@immutable
class NotificationTarget {
  const NotificationTarget.tab(this.tab) : route = null, args = null;

  const NotificationTarget.route(this.route, {this.args}) : tab = null;

  final int? tab;
  final String? route;
  final Object? args;
}

/// One table for every notification route key. Keeping the mapping here means
/// a new notification kind is a one-line change instead of a second switch
/// statement.
const Map<String, NotificationTarget> notificationTargets = {
  'matchCenter': NotificationTarget.tab(HomeTabIndex.matches),
  'tournaments': NotificationTarget.tab(HomeTabIndex.tournaments),
  'games': NotificationTarget.tab(HomeTabIndex.matches),
  'teams': NotificationTarget.tab(HomeTabIndex.teams),
  'profile': NotificationTarget.tab(HomeTabIndex.me),
  'organizer': NotificationTarget.route(AppRoute.organizerDashboard),
  'scorer': NotificationTarget.route(AppRoute.scorerWorkspace),
};

Future<void> openNotificationRoute(BuildContext context, String? route) async {
  final target =
      notificationTargets[route] ??
      const NotificationTarget.tab(HomeTabIndex.home);
  if (target.route != null) {
    await pushRoute(context, target.route!, args: target.args);
    return;
  }
  if (route == 'matchCenter') {
    openMatchTab(context);
    return;
  }
  if (route == 'games') {
    openMatchGames(context);
    return;
  }
  openHomeTab(context, target.tab ?? HomeTabIndex.home);
}
