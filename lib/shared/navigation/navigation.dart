import 'package:flutter/material.dart';

import 'package:sportika/features/discover/screens/organizer_dashboard_screen.dart';
import 'package:sportika/features/live/screens/scorer_workspace_screen.dart';

/// Tab requested by a notification deep link. [HomeShell] listens to this and
/// switches tab in place, so a notification never stacks a second shell.
final ValueNotifier<int> homeTabRequest = ValueNotifier<int>(0);

Future<T?> pushScreen<T>(BuildContext context, Widget child) {
  return Navigator.of(context)
      .push<T>(MaterialPageRoute<T>(builder: (_) => child));
}

void openHomeTab(BuildContext context, int index) {
  homeTabRequest.value = index;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Resolves a notification route key to the screen it should open. Tabs are
/// Home 0, Discover 1, Live 2, Team 3, Me 4.
Future<void> openNotificationRoute(BuildContext context, String? route) async {
  switch (route) {
    case 'matchCenter':
      openHomeTab(context, 2);
    case 'tournaments':
    case 'games':
      openHomeTab(context, 1);
    case 'teams':
      openHomeTab(context, 3);
    case 'profile':
      openHomeTab(context, 4);
    case 'organizer':
      await pushScreen(context, const OrganizerDashboardScreen());
    case 'scorer':
      await pushScreen(context, const ScorerWorkspaceScreen());
    default:
      openHomeTab(context, 0);
  }
}
