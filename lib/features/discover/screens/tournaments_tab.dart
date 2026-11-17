import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/discover/widgets/tournament_card.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

enum _Sort { recommended, soonest, newest }

/// Account-aware tournament discovery using the existing tournament repository.
class TournamentsTab extends StatefulWidget {
  const TournamentsTab({super.key});
  @override
  State<TournamentsTab> createState() => _TournamentsTabState();
}

class _TournamentsTabState extends State<TournamentsTab> {
  final _search = TextEditingController();
  Sport? _sport;
  TournamentStatus? _status;
  int _scope = 0;
  _Sort _sort = _Sort.recommended;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await context.read<TournamentsController>().reload();
    } catch (_) {
      _failed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reset() => setState(() {
    _search.clear();
    _sport = null;
    _status = null;
    _sort = _Sort.recommended;
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    final me = context.watch<ProfileController>().currentAccount;
    final query = _search.text.trim().toLowerCase();
    final source = switch (_scope) {
      1 => state.myTournaments,
      2 => state.tournamentsForOrganizer(me?.id),
      _ =>
        state.tournaments
            .where((t) => t.status != TournamentStatus.draft)
            .toList(),
    };
    final items = source
        .where(
          (t) =>
              (_sport == null || t.sport == _sport) &&
              (_status == null || t.status == _status) &&
              (query.isEmpty ||
                  '${t.name} ${t.city} ${t.sport.label} ${t.format.label}'
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();
    int relevance(Tournament t) =>
        (t.status == TournamentStatus.inProgress
            ? 8
            : t.status == TournamentStatus.open
            ? 4
            : 0) +
        (me?.sports.contains(t.sport) == true ? 2 : 0) +
        (me != null &&
                me.city.isNotEmpty &&
                me.city.toLowerCase() == t.city.toLowerCase()
            ? 1
            : 0);
    items.sort((a, b) {
      if (_sort == _Sort.newest) return b.createdAt.compareTo(a.createdAt);
      if (_sort == _Sort.recommended) {
        final rank = relevance(b).compareTo(relevance(a));
        if (rank != 0) return rank;
      }
      return a.startsAt.compareTo(b.startsAt);
    });
    final featured =
        _scope == 0 &&
            query.isEmpty &&
            _status == null &&
            items.isNotEmpty &&
            items.first.status != TournamentStatus.completed
        ? items.first
        : null;
    final list = items.where((t) => t.id != featured?.id).toList();
    final filtered = query.isNotEmpty || _sport != null || _status != null;
    final width = MediaQuery.sizeOf(context).width;
    final inset = width > 760 ? (width - 720) / 2 : 20.0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const ValueKey('tournament-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(inset, 16, inset, 28),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THE COMPETITION STARTS HERE',
                    style: SportikaType.micro.copyWith(
                      color: SportikaColors.gold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Find your next challenge',
                    style: SportikaType.hero.copyWith(fontSize: 28),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => pushRoute(context, AppRoute.createTournament),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create tournament'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilterChipRow<int>(
            label: 'Tournament section',
            choices: const [
              FilterChoice(0, 'Discover'),
              FilterChoice(1, 'My Tournaments'),
              FilterChoice(2, 'Managing'),
            ],
            selected: _scope,
            onChanged: (v) => setState(() => _scope = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search tournaments, cities or sports',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _search.clear()),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          FilterChipRow<Sport?>(
            label: 'Tournament sport',
            choices: [
              const FilterChoice(null, 'All sports'),
              for (final sport in Sport.values)
                FilterChoice(sport, sport.label),
            ],
            selected: _sport,
            onChanged: (v) => setState(() => _sport = v),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<String>(
                tooltip: 'Filter registration and competition status',
                onSelected: (v) => setState(
                  () => _status = v == 'all'
                      ? null
                      : TournamentStatus.values.byName(v),
                ),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'all',
                    child: Text('All statuses'),
                  ),
                  for (final status in TournamentStatus.values)
                    if (status != TournamentStatus.draft || _scope == 2)
                      PopupMenuItem(
                        value: status.name,
                        child: Text(status.label),
                      ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tune, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _status?.label ?? 'All statuses',
                          style: SportikaType.caption,
                          maxLines: 2,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<_Sort>(
                tooltip: 'Sort tournaments',
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _Sort.recommended,
                    child: Text('Recommended'),
                  ),
                  PopupMenuItem(
                    value: _Sort.soonest,
                    child: Text('Starting soon'),
                  ),
                  PopupMenuItem(
                    value: _Sort.newest,
                    child: Text('Recently added'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          switch (_sort) {
                            _Sort.recommended => 'Recommended',
                            _Sort.soonest => 'Starting soon',
                            _Sort.newest => 'Recently added',
                          },
                          style: SportikaType.caption,
                          maxLines: 2,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
              ),
              if (filtered)
                TextButton(
                  onPressed: _reset,
                  child: const Text('Reset filters'),
                ),
            ],
          ),
          if (_loading)
            const LoadingSkeleton(
              rows: 2,
              rowHeight: 100,
              label: 'Loading tournaments',
            ),
          if (_failed)
            ErrorState(
              title: 'Tournaments could not refresh',
              message: 'Your last available competitions are shown below.',
              onRetry: _refresh,
            ),
          if (featured != null) ...[
            const SizedBox(height: 8),
            EditorialBanner(
              height: 226,
              sport: featured.sport,
              eyebrow: 'Featured · ${featured.status.label}',
              title: featured.name,
              subtitle:
                  '${featured.city} · ${dayLabel(featured.startsAt)} · ${featured.format.label}',
              action: 'Explore tournament',
              accent: SportikaColors.gold,
              onAction: () => pushRoute(
                context,
                AppRoute.tournamentDetail,
                args: TournamentDetailArgs(featured.id),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (items.isEmpty && !_loading)
            EmptyState(
              title: filtered
                  ? 'No tournaments match your search'
                  : _scope == 1
                  ? 'No tournament entries yet'
                  : _scope == 2
                  ? 'Your competition, your way'
                  : 'The next competition is coming',
              body: filtered
                  ? 'Try another sport, city or registration status.'
                  : _scope == 1
                  ? 'Discover a tournament and submit an entry to join the competition.'
                  : 'Create a tournament and bring players together.',
              icon: Icons.emoji_events_outlined,
              action: GhostButton(
                label: filtered
                    ? 'Reset filters'
                    : _scope == 1
                    ? 'Discover tournaments'
                    : 'Create tournament',
                onPressed: filtered
                    ? _reset
                    : _scope == 1
                    ? () => setState(() => _scope = 0)
                    : () => pushRoute(context, AppRoute.createTournament),
              ),
            ),
          if (list.isNotEmpty) ...[
            Text(
              '${list.length} ${_scope == 2 ? 'managed competitions' : 'competitions to explore'}',
              style: SportikaType.caption,
            ),
            const SizedBox(height: 10),
            for (final tournament in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TournamentCard(
                  tournament: tournament,
                  trailing: state.myEntryFor(tournament.id) != null
                      ? StatusPill(
                          state.myEntryFor(tournament.id)!.status.label,
                          color: statusColor(
                            state.myEntryFor(tournament.id)!.status.key,
                          ),
                        )
                      : null,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
