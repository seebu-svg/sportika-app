import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';

/// Tab requested by a notification deep link. [HomeShell] listens to this and
/// switches tab in place, so a notification never stacks a second shell.
final ValueNotifier<int> homeTabRequest = ValueNotifier<int>(0);

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

/// One table for every notification route key. Tabs are Home 0, Discover 1,
/// Live 2, Team 3, Me 4. Keeping the mapping here means a new notification
/// kind is a one-line change instead of a second switch statement.
const Map<String, NotificationTarget> notificationTargets = {
  'matchCenter': NotificationTarget.tab(2),
  'tournaments': NotificationTarget.tab(1),
  'games': NotificationTarget.tab(1),
  'teams': NotificationTarget.tab(3),
  'profile': NotificationTarget.tab(4),
  'organizer': NotificationTarget.route(AppRoute.organizerDashboard),
  'scorer': NotificationTarget.route(AppRoute.scorerWorkspace),
};

Future<void> openNotificationRoute(BuildContext context, String? route) async {
  final target = notificationTargets[route] ?? const NotificationTarget.tab(0);
  if (target.route != null) {
    await pushRoute(context, target.route!, args: target.args);
    return;
  }
  openHomeTab(context, target.tab ?? 0);
}
