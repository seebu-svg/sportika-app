import 'package:sportika/shared/widgets/editorial.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Players discovery for the Discover tab: the community directory, filtered
/// by sport and by name or city.
class PlayersTab extends StatefulWidget {
  const PlayersTab({super.key});

  @override
  State<PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<PlayersTab> {
  Sport? sport;
  String query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final needle = query.trim().toLowerCase();
    final players =
        state.accounts
            .where((a) => a.has(UserRole.player))
            .where(
              (a) =>
                  sport == null || state.sportsPlayedBy(a.id).contains(sport),
            )
            .where(
              (a) =>
                  needle.isEmpty ||
                  a.displayName.toLowerCase().contains(needle) ||
                  a.city.toLowerCase().contains(needle),
            )
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return Column(
      children: [
        SportFilterBar(
          selected: sport,
          onChanged: (s) => setState(() => sport = s),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: TextField(
            onChanged: (v) => setState(() => query = v),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search players by name or city',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: players.isEmpty
              ? const EmptyState(
                  title: 'No players found',
                  body:
                      'Clear the search or pick another sport to see the whole '
                      'community.',
                  icon: Icons.people_outline,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  itemCount: players.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      _PlayerCard(account: players[i], state: state),
                ),
        ),
      ],
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.account, required this.state});

  final Account account;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final sports = state.sportsPlayedBy(account.id);
    final appearances = state.appearancesOf(account.id).length;
    final teams = state.squadsOf(account.id).length;
    final isMe = account.id == state.currentAccount?.id;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAppSheet(
          context,
          AppSheet(
            title: account.displayName,
            child: _PlayerSheet(account: account, state: state),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AccountAvatar(account: account, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 8),
                          const StatusPill('You', color: SportikaColors.mint),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${account.city.isEmpty ? 'Karachi' : account.city} · '
                      '$appearances matches · $teams teams',
                      style: const TextStyle(
                        fontSize: 12,
                        color: SportikaColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (sports.isEmpty)
                          const _Tag('New to Sportika')
                        else
                          for (final s in sports) _SportTag(sport: s),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SportikaColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerSheet extends StatelessWidget {
  const _PlayerSheet({required this.account, required this.state});

  final Account account;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final sports = state.sportsPlayedBy(account.id);
    final appearances = state.appearancesOf(account.id)
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    final teams = state.squadsOf(account.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AccountAvatar(account: account, size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.city.isEmpty ? 'Karachi, Pakistan' : account.city,
                    style: const TextStyle(
                      fontSize: 13,
                      color: SportikaColors.textBody,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final role in account.roles)
                        StatusPill(
                          role.label,
                          color: role == UserRole.organizer
                              ? SportikaColors.mint
                              : role == UserRole.scorer
                              ? SportikaColors.blueBright
                              : SportikaColors.gold,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _Stat(value: appearances.length.toString(), label: 'Matches'),
            _Stat(value: sports.length.toString(), label: 'Sports'),
            _Stat(value: teams.length.toString(), label: 'Teams'),
          ],
        ),
        if (sports.isNotEmpty) ...[
          const SectionTitle('Plays'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [for (final s in sports) _SportTag(sport: s)],
          ),
        ],
        if (teams.isNotEmpty) ...[
          const SectionTitle('Teams'),
          for (final team in teams)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                sportGlyph(team.sport),
                color: SportikaColors.mint,
                size: 18,
              ),
              title: Text(team.name),
              subtitle: Text(
                '${team.sport.label} · ${team.memberAccountIds.length} players',
              ),
            ),
        ],
        if (appearances.isNotEmpty) ...[
          const SectionTitle('Recent official matches'),
          for (final fixture in appearances.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AppearanceRow(fixture: fixture, state: state),
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow({required this.fixture, required this.state});

  final Fixture fixture;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final sides = state.sideLabelsOf(fixture);
    final tournament = state.tournamentOf(fixture);
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sides[0]}  vs  ${sides[1]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${tournament?.name ?? 'Community match'} · '
                  '${dayLabel(fixture.scheduledAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(
            fixture.status.label,
            color: statusColor(fixture.status.key),
          ),
        ],
      ),
    );
  }
}

class _SportTag extends StatelessWidget {
  const _SportTag({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) =>
      _Tag(sport.label, icon: sportGlyph(sport));
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: SportikaColors.surfaceSunken,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: SportikaColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: SportikaColors.mint),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: SportikaColors.textBody,
          ),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: SportikaColors.textMuted,
          ),
        ),
      ],
    ),
  );
}
