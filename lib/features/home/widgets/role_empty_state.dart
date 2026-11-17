import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

enum _AccountPreferences { loading, unavailable, unselected, selected }

/// Context supplied by the parent, with an optional sport-preference variant.
/// Sport preferences do not establish account age, experience or role.
class AccountEmptyState extends StatelessWidget {
  const AccountEmptyState({
    super.key,
    required this.title,
    required this.newcomerBody,
    required this.playerBody,
    this.icon = Icons.event_available,
    this.action,
  });

  final String title;

  /// Legacy parameter name: copy for an available account without selected
  /// sports. This must not imply that the account is new or needs onboarding.
  final String newcomerBody;

  /// Legacy parameter name: contextual copy when sports are selected, also
  /// used when preferences are unavailable. Selection does not imply a role.
  final String playerBody;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Select a scalar snapshot rather than the mutable Account/sports objects.
    // Unrelated repository notifications no longer rebuild this placeholder.
    final preferences = context.select<SessionController, _AccountPreferences>((
      session,
    ) {
      if (!session.ready) return _AccountPreferences.loading;
      final account = session.currentAccount;
      if (account == null) return _AccountPreferences.unavailable;
      return account.sports.isEmpty
          ? _AccountPreferences.unselected
          : _AccountPreferences.selected;
    });

    if (preferences == _AccountPreferences.loading) {
      return const LoadingSkeleton(rows: 1, label: 'Loading account details');
    }

    final body = switch (preferences) {
      _AccountPreferences.unselected => newcomerBody,
      _AccountPreferences.selected => playerBody,
      // Readiness only describes the repository. A missing profile is not
      // evidence of empty preferences, a new account, or an active profile load.
      _AccountPreferences.unavailable || _AccountPreferences.loading =>
        'Account details are not available yet.\n\n$playerBody',
    };
    return EmptyState(title: title, body: body, icon: icon, action: action);
  }
}
