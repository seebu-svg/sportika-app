import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Empty state that speaks to what this account can actually do next: a brand
/// new player is pointed at onboarding, a player at the tournament list, and an
/// organizer at their dashboard.
class RoleAwareEmpty extends StatelessWidget {
  const RoleAwareEmpty({
    super.key,
    required this.title,
    required this.newcomerBody,
    required this.playerBody,
    required this.organizerBody,
    this.icon = Icons.event_available,
    this.action,
  });

  final String title;
  final String newcomerBody;
  final String playerBody;
  final String organizerBody;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final me = session.currentAccount;
    final body = switch (me) {
      null => newcomerBody,
      Account(roles: final roles) when roles.contains(UserRole.organizer) =>
        organizerBody,
      Account(sports: final sports) when sports.isEmpty => newcomerBody,
      _ => playerBody,
    };
    return EmptyState(title: title, body: body, icon: icon, action: action);
  }
}
