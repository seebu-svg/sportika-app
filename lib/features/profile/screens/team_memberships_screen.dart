import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

// ============================================================
// TEAM MEMBERSHIPS SCREEN
// ============================================================

class TeamMembershipsScreen extends StatefulWidget {
  const TeamMembershipsScreen({super.key});

  @override
  State<TeamMembershipsScreen> createState() => _TeamMembershipsScreenState();
}

class _TeamMembershipsScreenState extends State<TeamMembershipsScreen> {
  final Set<String> _busyInvites = {};
  final Map<String, String> _inviteErrors = {};

  Future<void> _refresh() async {
    final profile = context.read<ProfileRepository>();
    final teams = context.read<TeamRepository>();

    try {
      await profile.reload();
      await teams.reload();
    } catch (_) {
      if (!mounted) return;
      showSnack(context, 'Unable to refresh team memberships.', error: true);
    }
  }

  Future<void> _respondToInvite(Squad squad, {required bool accept}) async {
    if (_busyInvites.contains(squad.id)) return;

    if (!accept) {
      final confirmed = await _confirmDecline(squad);
      if (!confirmed || !mounted) return;
    }

    setState(() {
      _busyInvites.add(squad.id);
      _inviteErrors.remove(squad.id);
    });

    try {
      context.read<TeamsController>().respondToInvite(squad.id, accept: accept);

      if (!mounted) return;

      showSnack(
        context,
        accept ? 'You joined ${squad.name}.' : 'Invitation declined.',
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _inviteErrors[squad.id] =
            'Could not ${accept ? "accept" : "decline"} this invitation. '
            'Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busyInvites.remove(squad.id);
        });
      }
    }
  }

  Future<bool> _confirmDecline(Squad squad) async {
    final theme = context.sportika;

    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Decline invitation?'),
            content: Text(
              'You will decline the invitation to join ${squad.name}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  'Keep invitation',
                  style: SportikaType.action.copyWith(color: theme.textBody),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  'Decline',
                  style: SportikaType.action.copyWith(
                    color: SportikaColors.danger,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

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

    final captaincies = squads
        .where((squad) => squad.captainId == me.id)
        .length;

    return ScreenScaffold(
      title: 'Team memberships',
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TeamHeadquartersHero(
            squads: squads.length,
            captaincies: captaincies,
            invitations: invites.length,
          ),

          const SizedBox(height: SportikaSpacing.lg),

          // --------------------------------------------------
          // PENDING INVITATIONS
          // --------------------------------------------------
          if (invites.isNotEmpty) ...[
            _SectionHeading(
              title: 'Pending Invitations',
              subtitle: 'Teams waiting for your response',
              count: invites.length,
            ),

            const SizedBox(height: SportikaSpacing.md),

            for (final squad in invites)
              Padding(
                key: ValueKey('invite-${squad.id}'),
                padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                child: _InvitationCard(
                  squad: squad,
                  busy: _busyInvites.contains(squad.id),
                  error: _inviteErrors[squad.id],
                  onAccept: () => _respondToInvite(squad, accept: true),
                  onDecline: () => _respondToInvite(squad, accept: false),
                ),
              ),

            const SizedBox(height: SportikaSpacing.lg),
          ],

          // --------------------------------------------------
          // MY SQUADS
          // --------------------------------------------------
          _SectionHeading(
            title: 'Your Squads',
            subtitle: 'Teams you represent',
            count: squads.length,
          ),

          const SizedBox(height: SportikaSpacing.md),

          if (squads.isEmpty)
            _NoSquadsState(
              hasInvitations: invites.isNotEmpty,
              onCreate: () => pushRoute(context, AppRoute.createTeam),
            )
          else
            for (final squad in squads)
              Padding(
                key: ValueKey('squad-${squad.id}'),
                padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                child: _MembershipSquadCard(
                  squad: squad,
                  isCaptain: squad.captainId == me.id,
                  onTap: () => pushRoute(
                    context,
                    AppRoute.teamDetail,
                    args: TeamDetailArgs(squad.id),
                  ),
                ),
              ),

          const SizedBox(height: SportikaSpacing.md),

          // --------------------------------------------------
          // CREATE TEAM ACTION
          // --------------------------------------------------
          if (squads.isNotEmpty)
            _CreateTeamAction(
              onTap: () => pushRoute(context, AppRoute.createTeam),
            ),

          const SizedBox(height: SportikaSpacing.lg),

          const InfoBanner(
            icon: Icons.info_outline,
            text:
                'Every Sportika member can create teams, invite players '
                'and organize events. Captaincy belongs to a squad, '
                'not a separate account type.',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TEAM HEADQUARTERS HERO
// ============================================================

class _TeamHeadquartersHero extends StatelessWidget {
  const _TeamHeadquartersHero({
    required this.squads,
    required this.captaincies,
    required this.invitations,
  });

  final int squads;
  final int captaincies;
  final int invitations;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        gradient: SportikaGradients.sportCoin(theme.live),
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: theme.live,
                size: SportikaIconSize.md,
              ),
              const SizedBox(width: SportikaSpacing.xs),
              Text(
                'MY SPORTIKA / TEAMS',
                style: SportikaType.micro.copyWith(color: theme.live),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          const Text('YOUR TEAM\nHEADQUARTERS', style: SportikaType.title),

          const SizedBox(height: SportikaSpacing.sm),

          Text(
            'Your squads, leadership and invitations in one place.',
            style: SportikaType.body.copyWith(color: theme.textBody),
          ),

          const SizedBox(height: SportikaSpacing.lg),

          Row(
            children: [
              Expanded(
                child: _HeadquartersMetric(
                  value: squads,
                  label: 'SQUADS',
                  icon: Icons.groups_2_outlined,
                  tone: theme.live,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: _HeadquartersMetric(
                  value: captaincies,
                  label: 'CAPTAIN',
                  icon: Icons.workspace_premium_outlined,
                  tone: SportikaColors.gold,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: _HeadquartersMetric(
                  value: invitations,
                  label: 'INVITES',
                  icon: Icons.mail_outline_rounded,
                  tone: SportikaColors.mint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeadquartersMetric extends StatelessWidget {
  const _HeadquartersMetric({
    required this.value,
    required this.label,
    required this.icon,
    required this.tone,
  });

  final int value;
  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: SportikaSpacing.md,
        horizontal: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(icon, size: SportikaIconSize.md, color: tone),
          const SizedBox(height: SportikaSpacing.xs),
          Text('$value', style: SportikaType.scoreSmall),
          const SizedBox(height: SportikaSpacing.xxs),
          Text(
            label,
            style: SportikaType.micro,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SECTION HEADING
// ============================================================

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final String title;
  final String subtitle;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SportikaType.titleMedium),
              const SizedBox(height: SportikaSpacing.xxs),
              Text(
                subtitle,
                style: SportikaType.caption.copyWith(color: theme.textMuted),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SportikaSpacing.sm,
            vertical: SportikaSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceSunken,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
          ),
          child: Text(
            '$count',
            style: SportikaType.caption.copyWith(color: theme.live),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// INVITATION CARD
// ============================================================

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.squad,
    required this.busy,
    required this.error,
    required this.onAccept,
    required this.onDecline,
  });

  final Squad squad;
  final bool busy;
  final String? error;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final tone = sportColor(squad.sport);

    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(
        alpha: SportikaOpacity.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MembershipSportCrest(sport: squad.sport, tone: tone),

              const SizedBox(width: SportikaSpacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      squad.name,
                      style: SportikaType.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: SportikaSpacing.xxs),
                    Text(
                      '${squad.sport.label} · ${squad.size} '
                      '${squad.size == 1 ? "member" : "members"}',
                      style: SportikaType.caption,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: SportikaSpacing.xs),

              const StatusPill('Pending', color: SportikaColors.gold),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          Text(
            'This squad has invited you to join their roster.',
            style: SportikaType.caption.copyWith(color: theme.textBody),
          ),

          if (error != null) ...[
            const SizedBox(height: SportikaSpacing.sm),
            InlineBanner(text: error!, tone: SportikaColors.danger),
          ],

          const SizedBox(height: SportikaSpacing.md),

          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Decline',
                  expand: true,
                  tone: theme.textMuted,
                  onPressed: busy ? null : onDecline,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: PrimaryButton(
                  label: busy ? 'Processing' : 'Accept Invite',
                  small: true,
                  tone: SportikaColors.mint,
                  busy: busy,
                  onPressed: busy ? null : onAccept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MEMBERSHIP SQUAD CARD
// ============================================================

class _MembershipSquadCard extends StatelessWidget {
  const _MembershipSquadCard({
    required this.squad,
    required this.isCaptain,
    required this.onTap,
  });

  final Squad squad;
  final bool isCaptain;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(squad.sport);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(SportikaSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                _MembershipSportCrest(sport: squad.sport, tone: tone),

                const SizedBox(width: SportikaSpacing.md),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        squad.name,
                        style: SportikaType.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: SportikaSpacing.xxs),
                      Text(
                        '${squad.sport.label} · ${squad.type.label} · '
                        '${squad.size} '
                        '${squad.size == 1 ? "member" : "members"}',
                        style: SportikaType.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const Icon(
                  Icons.chevron_right_rounded,
                  size: SportikaIconSize.md,
                ),
              ],
            ),

            const SizedBox(height: SportikaSpacing.md),

            Row(
              children: [
                StatusPill(
                  isCaptain ? 'Captain' : 'Member',
                  color: isCaptain
                      ? SportikaColors.gold
                      : SportikaColors.blueBright,
                ),
                const Spacer(),
                Text(
                  'View Squad',
                  style: SportikaType.action.copyWith(color: tone),
                ),
                const SizedBox(width: SportikaSpacing.xs),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: SportikaIconSize.sm,
                  color: tone,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SPORT CREST
// ============================================================

class _MembershipSportCrest extends StatelessWidget {
  const _MembershipSportCrest({required this.sport, required this.tone});

  final Sport sport;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: SportikaSpacing.xxxl + SportikaSpacing.md,
      height: SportikaSpacing.xxxl + SportikaSpacing.md,
      decoration: BoxDecoration(
        gradient: SportikaGradients.sportCoin(tone),
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(
          color: tone.withValues(alpha: SportikaOpacity.medium),
        ),
      ),
      child: Center(
        child: SportGlyph(sport: sport, color: tone, size: SportikaIconSize.lg),
      ),
    );
  }
}

// ============================================================
// EMPTY STATE
// ============================================================

class _NoSquadsState extends StatelessWidget {
  const _NoSquadsState({required this.hasInvitations, required this.onCreate});

  final bool hasInvitations;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: hasInvitations
          ? 'Your first squad is waiting'
          : 'Build your team legacy',
      body: hasInvitations
          ? 'Accept an invitation above to join your first squad, '
                'or create a team of your own.'
          : 'Create a squad, invite athletes and start playing '
                'together on Sportika.',
      icon: Icons.groups_2_outlined,
      action: GhostButton(
        label: 'Create a Team',
        icon: Icons.group_add_outlined,
        onPressed: onCreate,
      ),
    );
  }
}

// ============================================================
// CREATE TEAM ACTION
// ============================================================

class _CreateTeamAction extends StatelessWidget {
  const _CreateTeamAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(SportikaSpacing.sm),
            decoration: BoxDecoration(
              color: theme.surfaceSunken,
              borderRadius: BorderRadius.circular(SportikaRadius.control),
            ),
            child: Icon(
              Icons.add_circle_outline_rounded,
              color: theme.live,
              size: SportikaIconSize.lg,
            ),
          ),
          const SizedBox(width: SportikaSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create a New Team', style: SportikaType.bodyStrong),
                SizedBox(height: SportikaSpacing.xxs),
                Text(
                  'Build your squad and invite athletes',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            color: theme.textMuted,
            size: SportikaIconSize.md,
          ),
        ],
      ),
    );
  }
}
