import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Me → Tournament history.
///
/// Every event the member is entered in or organizes, read from the same
/// tournament store the rest of the app uses. The relationship, not an account
/// type, decides the badge.
class TournamentHistoryScreen extends StatelessWidget {
  const TournamentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tournaments = context.watch<TournamentRepository>();
    final me = context.watch<ProfileRepository>().currentAccount;
    if (me == null) {
      return const ScreenScaffold(
        title: 'Tournament history',
        child: ErrorState(
          title: 'Signed out',
          message: 'Sign in again to see your tournaments.',
        ),
      );
    }

    final enteredIds = tournaments.entries
        .where((entry) => entry.memberAccountIds.contains(me.id))
        .map((entry) => entry.tournamentId)
        .toSet();
    final rows = <({Tournament tournament, bool organizing})>[];
    for (final tournament in tournaments.tournaments) {
      final organizing = tournament.organizerId == me.id;
      if (!organizing && !enteredIds.contains(tournament.id)) continue;
      rows.add((tournament: tournament, organizing: organizing));
    }
    rows.sort((a, b) => b.tournament.startsAt.compareTo(a.tournament.startsAt));
    final organizingCount = rows.where((row) => row.organizing).length;

    return ScreenScaffold(
      title: 'Tournament history',
      onRefresh: () async {
        final profile = context.read<ProfileRepository>();
        final store = context.read<TournamentRepository>();
        await profile.reload();
        await store.reload();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            eyebrow: 'Me',
            title: 'Tournament history',
            subtitle: 'Every event you played in or organized, newest first.',
          ),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${rows.length}',
                  label: 'Tournaments',
                  tone: SportikaColors.blueBright,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '$organizingCount',
                  label: 'Organized',
                  tone: SportikaColors.mint,
                ),
              ),
            ],
          ),
          const SectionTitle('Your events'),
          if (rows.isEmpty)
            EmptyState(
              title: 'No tournaments yet',
              body:
                  'Join an event from Discover, or create one, and it will '
                  'appear here.',
              icon: Icons.emoji_events_outlined,
              action: GhostButton(
                label: 'Browse tournaments',
                icon: Icons.search,
                onPressed: () => openHomeTab(context, HomeTabIndex.tournaments),
              ),
            ),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: SurfaceCard(
                onTap: () => pushRoute(
                  context,
                  AppRoute.tournamentDetail,
                  args: TournamentDetailArgs(row.tournament.id),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.tournament.name,
                            style: SportikaType.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${row.tournament.city} · '
                            '${dayLabel(row.tournament.startsAt)} · '
                            '${row.tournament.formatLabel}',
                            style: SportikaType.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              SportTag(row.tournament.sport, compact: true),
                              StatusPill(
                                row.organizing ? 'You organize' : 'Entered',
                                color: row.organizing
                                    ? SportikaColors.mint
                                    : SportikaColors.blueBright,
                              ),
                              StatusPill(
                                row.tournament.status.name,
                                color: statusColor(row.tournament.status.name),
                              ),
                            ],
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
                'Official results are published by the tournament organizer. '
                'Personal scorecards never appear in this list.',
          ),
        ],
      ),
    );
  }
}
