import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

Future<void> showInvitePlayersSheet(BuildContext context, String squadId) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
    ),
    builder: (_) => _InvitePlayersSheet(squadId: squadId),
  );
}

enum _RecruitFilter {
  all('All athletes'),
  sport('Same sport'),
  city('My city');

  const _RecruitFilter(this.label);

  final String label;
}

class _InvitePlayersSheet extends StatefulWidget {
  const _InvitePlayersSheet({required this.squadId});

  final String squadId;

  @override
  State<_InvitePlayersSheet> createState() => _InvitePlayersSheetState();
}

class _InvitePlayersSheetState extends State<_InvitePlayersSheet> {
  final _search = TextEditingController();

  final Set<String> _busyAccounts = <String>{};

  Timer? _debounce;

  String _query = '';

  _RecruitFilter _filter = _RecruitFilter.all;

  bool _pendingExpanded = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});

    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;

      setState(() {
        _query = value.trim();
      });
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();

    setState(() {
      _query = '';
    });
  }

  Future<void> _invite(Account player) async {
    if (_busyAccounts.contains(player.id)) return;

    setState(() {
      _busyAccounts.add(player.id);
    });

    try {
      await Future<void>.sync(
        () => context.read<TeamsController>().invite(widget.squadId, player.id),
      );

      if (!mounted) return;

      showSnack(context, 'Invitation sent to ${player.displayName}');
    } catch (_) {
      if (!mounted) return;

      showSnack(
        context,
        'Could not invite ${player.displayName}. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyAccounts.remove(player.id);
        });
      }
    }
  }

  Future<void> _confirmCancel(Account player) async {
    if (_busyAccounts.contains(player.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel invitation?'),
        content: Text(
          'Remove the pending invitation for '
          '${player.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep invitation'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel invite'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _busyAccounts.add(player.id);
    });

    try {
      await Future<void>.sync(
        () => context.read<TeamsController>().cancelInvite(
          widget.squadId,
          player.id,
        ),
      );

      if (!mounted) return;

      showSnack(context, 'Invitation cancelled for ${player.displayName}');
    } catch (_) {
      if (!mounted) return;

      showSnack(
        context,
        'Could not cancel the invitation. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyAccounts.remove(player.id);
        });
      }
    }
  }

  void _openProfile(Account player) {
    pushRoute(
      context,
      AppRoute.playerProfile,
      args: PlayerProfileArgs(player.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();
    final profile = context.watch<ProfileController>();

    final squad = teams.squadById(widget.squadId);

    final allCandidates = squad == null
        ? <Account>[]
        : teams.inviteCandidates(widget.squadId, _query);

    final myCity = profile.currentAccount?.city.trim().toLowerCase() ?? '';

    final candidates = allCandidates.where((player) {
      switch (_filter) {
        case _RecruitFilter.all:
          return true;

        case _RecruitFilter.sport:
          if (squad == null) return false;

          return profile.sportsPlayedBy(player.id).contains(squad.sport);

        case _RecruitFilter.city:
          return myCity.isNotEmpty &&
              player.city.trim().toLowerCase() == myCity;
      }
    }).toList();

    final accountsById = {
      for (final account in teams.accounts) account.id: account,
    };

    final invited = (squad?.invitedAccountIds ?? [])
        .map((id) => accountsById[id])
        .whereType<Account>()
        .toList();

    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    final availableHeight = screenHeight - keyboardHeight;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: SizedBox(
        height: availableHeight * .90,
        child: Column(
          children: [
            // ---------------------------------------------------
            // DRAG HANDLE
            // ---------------------------------------------------
            const SizedBox(height: SportikaSpacing.sm),

            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: SportikaColors.border,
                  borderRadius: BorderRadius.circular(SportikaRadius.pill),
                ),
              ),
            ),

            // ---------------------------------------------------
            // FIXED HEADER
            // ---------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SportikaSpacing.md,
                SportikaSpacing.md,
                SportikaSpacing.md,
                SportikaSpacing.sm,
              ),
              child: _RecruitmentHeader(
                onClose: () => Navigator.of(context).pop(),
              ),
            ),

            // ---------------------------------------------------
            // SQUAD IDENTITY
            // ---------------------------------------------------
            if (squad != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.md,
                ),
                child: _RecruitingSquadCard(squad: squad),
              ),

            const SizedBox(height: SportikaSpacing.md),

            // ---------------------------------------------------
            // SEARCH
            // ---------------------------------------------------
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SportikaSpacing.md,
              ),
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search athlete name or city',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: _clearSearch,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),

            const SizedBox(height: SportikaSpacing.sm),

            // ---------------------------------------------------
            // FILTERS
            // ---------------------------------------------------
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.md,
                ),
                itemCount: _RecruitFilter.values.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: SportikaSpacing.sm),
                itemBuilder: (context, index) {
                  final filter = _RecruitFilter.values[index];

                  return ChoiceChip(
                    label: Text(filter.label),
                    selected: _filter == filter,
                    onSelected: (_) {
                      setState(() {
                        _filter = filter;
                      });
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: SportikaSpacing.sm),

            // ---------------------------------------------------
            // DISCOVERY HEADER
            // ---------------------------------------------------
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SportikaSpacing.md,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_outline_rounded,
                    color: SportikaColors.mint,
                    size: 20,
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  const Expanded(
                    child: Text(
                      'Available Athletes',
                      style: SportikaType.bodyStrong,
                    ),
                  ),
                  _CountPill(label: '${candidates.length} found'),
                ],
              ),
            ),

            const SizedBox(height: SportikaSpacing.sm),

            // ---------------------------------------------------
            // SCROLLABLE RESULTS
            // ---------------------------------------------------
            Expanded(
              child: squad == null
                  ? const Center(
                      child: EmptyState(
                        title: 'Squad unavailable',
                        body: 'This squad no longer exists.',
                        icon: Icons.groups_outlined,
                      ),
                    )
                  : candidates.isEmpty
                  ? Center(
                      child: EmptyState(
                        title: _query.isNotEmpty
                            ? 'No matching athletes'
                            : 'No players available',
                        body: _query.isNotEmpty
                            ? 'Try another name or city.'
                            : 'Try changing your filters.',
                        icon: Icons.person_search_outlined,
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(
                        horizontal: SportikaSpacing.md,
                      ),
                      itemCount: candidates.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: SportikaSpacing.sm),
                      itemBuilder: (context, index) {
                        final player = candidates[index];

                        return _RecruitAthleteCard(
                          player: player,
                          busy: _busyAccounts.contains(player.id),
                          onProfile: () => _openProfile(player),
                          onInvite: () => _invite(player),
                        );
                      },
                    ),
            ),

            // ---------------------------------------------------
            // PENDING INVITATIONS
            // ---------------------------------------------------
            if (invited.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SportikaSpacing.md,
                  SportikaSpacing.sm,
                  SportikaSpacing.md,
                  0,
                ),
                child: _PendingInvitations(
                  invited: invited,
                  expanded: _pendingExpanded,
                  busyAccounts: _busyAccounts,
                  maxHeight: availableHeight * .25,
                  onToggle: () {
                    setState(() {
                      _pendingExpanded = !_pendingExpanded;
                    });
                  },
                  onCancel: _confirmCancel,
                ),
              ),

            // ---------------------------------------------------
            // PERSISTENT FOOTER
            // ---------------------------------------------------
            _RecruitmentFooter(
              pendingCount: invited.length,
              onDone: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// RECRUITMENT HEADER
// -----------------------------------------------------------------------------

class _RecruitmentHeader extends StatelessWidget {
  const _RecruitmentHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SPORTIKA / RECRUITMENT',
                style: SportikaType.label.copyWith(
                  color: colors.primary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: SportikaSpacing.xs),
              Text(
                'Recruit Athletes',
                style: SportikaType.title.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Build your squad with the right players.',
                style: SportikaType.caption,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close recruitment',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// RECRUITING SQUAD CARD
// -----------------------------------------------------------------------------

class _RecruitingSquadCard extends StatelessWidget {
  const _RecruitingSquadCard({required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: .14),
            colors.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        border: Border.all(color: colors.primary.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(SportikaRadius.md),
            ),
            child: Icon(Icons.shield_rounded, color: colors.primary, size: 28),
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
                const SizedBox(height: 4),
                Text(
                  '${squad.sport.label} · ${squad.type.label}',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: SportikaSpacing.xs),
          const Icon(
            Icons.person_add_alt_1_rounded,
            color: SportikaColors.mint,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ATHLETE RECRUITMENT CARD
// -----------------------------------------------------------------------------

class _RecruitAthleteCard extends StatelessWidget {
  const _RecruitAthleteCard({
    required this.player,
    required this.busy,
    required this.onProfile,
    required this.onInvite,
  });

  final Account player;
  final bool busy;
  final VoidCallback onProfile;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = context.watch<ProfileController>();

    final sports = profile.sportsPlayedBy(player.id);
    final appearances = profile.appearancesOf(player.id).length;

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              AccountAvatar(account: player, size: 52),
              const SizedBox(width: SportikaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.displayName,
                      style: SportikaType.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            player.city.isEmpty
                                ? 'Location not provided'
                                : player.city,
                            style: SportikaType.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (sports.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        sports.map((sport) => sport.label).join(' · '),
                        style: SportikaType.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            children: [
              Icon(
                Icons.sports_score_outlined,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text('$appearances appearances', style: SportikaType.caption),
              const Spacer(),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onProfile,
                  child: const Text('View Profile'),
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onInvite,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(busy ? 'Sending' : 'Invite'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PENDING INVITATIONS
// -----------------------------------------------------------------------------

class _PendingInvitations extends StatelessWidget {
  const _PendingInvitations({
    required this.invited,
    required this.expanded,
    required this.busyAccounts,
    required this.maxHeight,
    required this.onToggle,
    required this.onCancel,
  });

  final List<Account> invited;
  final bool expanded;
  final Set<String> busyAccounts;
  final double maxHeight;
  final VoidCallback onToggle;
  final ValueChanged<Account> onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(SportikaRadius.lg),
            child: Padding(
              padding: const EdgeInsets.all(SportikaSpacing.md),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_send_outlined,
                    color: SportikaColors.gold,
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  const Expanded(
                    child: Text(
                      'Pending invitations',
                      style: SportikaType.bodyStrong,
                    ),
                  ),
                  _CountPill(
                    label: '${invited.length} pending',
                    tone: SportikaColors.gold,
                  ),
                  const SizedBox(width: SportikaSpacing.xs),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    children: [
                      Divider(height: 1, color: colors.outlineVariant),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxHeight),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: invited.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: colors.outlineVariant),
                          itemBuilder: (context, index) {
                            final player = invited[index];
                            final busy = busyAccounts.contains(player.id);

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: SportikaSpacing.md,
                                vertical: SportikaSpacing.xs,
                              ),
                              child: Row(
                                children: [
                                  AccountAvatar(account: player, size: 38),
                                  const SizedBox(width: SportikaSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          player.displayName,
                                          style: SportikaType.bodyStrong,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          'Awaiting response',
                                          style: SportikaType.caption.copyWith(
                                            color: SportikaColors.gold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip:
                                        'Cancel invitation for '
                                        '${player.displayName}',
                                    onPressed: busy
                                        ? null
                                        : () => onCancel(player),
                                    icon: busy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// COUNT PILL
// -----------------------------------------------------------------------------

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, this.tone = SportikaColors.mint});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
      ),
      child: Text(label, style: SportikaType.caption.copyWith(color: tone)),
    );
  }
}

// -----------------------------------------------------------------------------
// PERSISTENT FOOTER
// -----------------------------------------------------------------------------

class _RecruitmentFooter extends StatelessWidget {
  const _RecruitmentFooter({required this.pendingCount, required this.onDone});

  final int pendingCount;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        SportikaSpacing.md,
        SportikaSpacing.sm,
        SportikaSpacing.md,
        SportikaSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$pendingCount pending', style: SportikaType.bodyStrong),
                const SizedBox(height: 3),
                const Text('Squad invitations', style: SportikaType.caption),
              ],
            ),
          ),
          SizedBox(
            width: 115,
            child: FilledButton(onPressed: onDone, child: const Text('Done')),
          ),
        ],
      ),
    );
  }
}
