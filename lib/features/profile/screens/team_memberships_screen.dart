import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Me → Team memberships.
///
/// The squads the member plays for, plus invitations still waiting on an
/// answer. Captaincy is a squad relationship, not an account type.
class TeamMembershipsScreen extends StatelessWidget {
  const TeamMembershipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();
    final me = context.watch<ProfileRepository>().currentAccount;
    if (me == null) {
      return const ScreenScaffold(
        title: 'Team memberships',
        child: ErrorState(
          title: 'Signed out',
          message: 'Sign in again to see your teams.',
        ),
      );
    }

    final squads = teams.squads
        .where((squad) => squad.memberAccountIds.contains(me.id))
        .toList();
    final invites = teams.squads
        .where((squad) => squad.invitedAccountIds.contains(me.id))
        .toList();

    return ScreenScaffold(
      title: 'Team memberships',
      onRefresh: () async {
        final profile = context.read<ProfileRepository>();
        final teams = context.read<TeamRepository>();
        await profile.reload();
        await teams.reload();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            eyebrow: 'Me',
            title: 'Team memberships',
            subtitle:
                'The squads you play for and the invitations waiting on you.',
          ),
          if (invites.isNotEmpty) ...[
            const SectionTitle('Invitations'),
            for (final squad in invites)
              Padding(
                padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                child: _InvitationCard(
                  squad: squad,
                  onAccept: () => teams.respondToInvite(squad.id, accept: true),
                  onDecline: () =>
                      teams.respondToInvite(squad.id, accept: false),
                ),
              ),
          ],
          const SectionTitle('Your squads'),
          if (squads.isEmpty)
            EmptyState(
              title: 'No teams yet',
              body:
                  'Create a squad, or accept an invitation, and your team '
                  'matches will start here.',
              icon: Icons.groups_outlined,
              action: GhostButton(
                label: 'Create a team',
                icon: Icons.group_add_outlined,
                onPressed: () => pushRoute(context, AppRoute.createTeam),
              ),
            ),
          for (final squad in squads)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: SurfaceCard(
                onTap: () => pushRoute(
                  context,
                  AppRoute.teamDetail,
                  args: TeamDetailArgs(squad.id),
                ),
                child: Row(
                  children: [
                    Container(
                      height: 38,
                      width: 38,
                      decoration: BoxDecoration(
                        color: sportColor(squad.sport).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: sportColor(squad.sport)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(
                        sportGlyph(squad.sport),
                        size: 18,
                        color: sportColor(squad.sport),
                      ),
                    ),
                    const SizedBox(width: SportikaSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            squad.name,
                            style: SportikaType.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${squad.sport.label} · ${squad.type.label} · '
                            '${squad.size} '
                            '${squad.size == 1 ? 'player' : 'players'}',
                            style: SportikaType.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          StatusPill(
                            squad.captainId == me.id ? 'Captain' : 'Member',
                            color: squad.captainId == me.id
                                ? SportikaColors.gold
                                : SportikaColors.blueBright,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: SportikaColors.textDim,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: SportikaSpacing.sm),
          const InfoBanner(
            icon: Icons.info_outline,
            text:
                'Every member can create a team, invite players and organize '
                'events. There are no separate team accounts.',
          ),
        ],
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.squad,
    required this.onAccept,
    required this.onDecline,
  });

  final Squad squad;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  squad.name,
                  style: SportikaType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SportTag(squad.sport, compact: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${squad.size} ${squad.size == 1 ? 'player' : 'players'} · '
            'invited you to join',
            style: SportikaType.caption,
          ),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Decline',
                  expand: true,
                  tone: SportikaColors.textMuted,
                  onPressed: onDecline,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: PrimaryButton(
                  label: 'Accept',
                  small: true,
                  tone: SportikaColors.mint,
                  onPressed: onAccept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
