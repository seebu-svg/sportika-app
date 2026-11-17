import 'package:sportika/shared/widgets/editorial.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Players discovery for the Team tab: the community directory, filtered
/// by sport and by name or city.
class PlayersTab extends StatefulWidget {
  const PlayersTab({super.key});

  @override
  State<PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<PlayersTab> {
  Sport? sport;
  String query = '';

  /// Typing debounce: the directory is rebuilt only after the athlete pauses,
  /// which keeps the list from re-filtering on every keystroke.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileController>();
    final needle = query.trim().toLowerCase();
    final players =
        context
            .read<SessionController>()
            .accounts
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
            onChanged: _onQueryChanged,
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
  final ProfileController state;

  @override
  Widget build(BuildContext context) {
    final sports = state.sportsPlayedBy(account.id);
    final appearances = state.appearancesOf(account.id).length;
    final teams = context.read<TeamsController>().squadsOf(account.id).length;
    final isMe = account.id == state.currentAccount?.id;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => pushRoute(
          context,
          AppRoute.playerProfile,
          args: PlayerProfileArgs(account.id),
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
