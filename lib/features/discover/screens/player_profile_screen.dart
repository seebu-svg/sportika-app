import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Full player profile reached from Discover → Players. Promoted from the
/// bottom sheet so the sport stats, teams and history have room, and so a
/// notification or a squad roster can deep link straight to a player.
class PlayerProfileScreen extends StatelessWidget {
  const PlayerProfileScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context) {
    final account = context.watch<SessionController>().accountById(accountId);
    if (account == null) {
      return ScreenScaffold(
        title: 'Player',
        child: ErrorState(
          title: 'Player not found',
          message: 'This account is no longer part of the community.',
          retryLabel: 'Go back',
          onRetry: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    final profile = context.watch<ProfileController>();
    final teams = context.watch<TeamsController>().squadsOf(account.id);
    final appearances = profile.appearancesOf(account.id)
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    final sports = profile.sportsPlayedBy(account.id);

    // Win/loss is derived from the same published results the fixture tiles
    // show, so the numbers cannot disagree with the list underneath. An entry
    // carries the roster, and a fixture side carries the entry id.
    final myEntryIds = context
        .watch<TournamentsController>()
        .entries
        .where((e) => e.memberAccountIds.contains(account.id))
        .map((e) => e.id)
        .toSet();
    final decided = appearances
        .where((f) => f.result != null)
        .toList(growable: false);
    final wins = decided.where((fixture) {
      final winner = fixture.result!.winnerIndex;
      if (winner < 0) return false;
      final mySide = myEntryIds.contains(fixture.home.entryId) ? 0 : 1;
      return winner == mySide;
    }).length;

    return ScreenScaffold(
      title: account.displayName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AccountAvatar(account: account, size: 64),
              const SizedBox(width: SportikaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      style: SportikaType.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (account.handle.isNotEmpty)
                      Text('@${account.handle}', style: SportikaType.caption),
                    const SizedBox(height: 4),
                    Text(
                      account.city.isEmpty ? 'Karachi, Pakistan' : account.city,
                      style: SportikaType.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          const Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill('Sportika member', color: SportikaColors.blueBright),
            ],
          ),
          if (account.bio.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.md),
            Text(account.bio, style: SportikaType.body),
          ],
          const SectionHeader('Record'),
          Row(
            children: [
              Expanded(
                child: StatTile(value: '${decided.length}', label: 'Played'),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: StatTile(
                  value: '$wins',
                  label: 'Won',
                  tone: SportikaColors.mint,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: StatTile(
                  value: '${decided.length - wins}',
                  label: 'Lost or drawn',
                  tone: SportikaColors.textMuted,
                ),
              ),
            ],
          ),
          const SectionHeader('Plays'),
          if (sports.isEmpty)
            const EmptyState(
              title: 'No sports yet',
              body: 'This player has not picked a sport.',
              icon: Icons.sports_outlined,
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [for (final sport in sports) SportTag(sport)],
            ),
          const SectionHeader('Teams'),
          if (teams.isEmpty)
            const EmptyState(
              title: 'No squads',
              body: 'This player is not part of a team or pair yet.',
              icon: Icons.groups_outlined,
            )
          else
            for (final team in teams)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  onTap: () => pushRoute(
                    context,
                    AppRoute.teamDetail,
                    args: TeamDetailArgs(team.id),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sportGlyph(team.sport),
                        color: sportColor(team.sport),
                        size: 20,
                      ),
                      const SizedBox(width: SportikaSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(team.name, style: SportikaType.bodyStrong),
                            Text(
                              '${team.sport.label} · ${team.size} players',
                              style: SportikaType.caption,
                            ),
                          ],
                        ),
                      ),
                      if (team.ownerId == account.id)
                        const StatusPill('Captain', color: SportikaColors.gold),
                    ],
                  ),
                ),
              ),
          SectionHeader(
            'Official matches',
            action: appearances.isEmpty ? null : '${appearances.length}',
          ),
          if (appearances.isEmpty)
            const EmptyState(
              title: 'No official matches',
              body: 'Published fixtures involving this player appear here.',
              icon: Icons.history,
            )
          else
            for (final fixture in appearances.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: officialFixtureTile(
                  context,
                  fixture,
                  onTap: () => pushRoute(
                    context,
                    AppRoute.fixtureDetail,
                    args: FixtureDetailArgs(fixture.id),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
