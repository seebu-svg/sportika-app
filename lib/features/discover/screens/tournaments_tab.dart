import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/discover/widgets/tournament_card.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

enum _Sort { recommended, soonest, newest }

class TournamentsTab extends StatefulWidget {
  const TournamentsTab({super.key});

  @override
  State<TournamentsTab> createState() => _TournamentsTabState();
}

class _TournamentsTabState extends State<TournamentsTab> {
  final TextEditingController _search = TextEditingController();

  Timer? _searchDebounce;

  Sport? _sport;
  TournamentStatus? _status;

  int _scope = 0;

  _Sort _sort = _Sort.recommended;

  bool _loading = false;
  bool _failed = false;

  String _query = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;

      setState(() {
        _query = value.trim().toLowerCase();
      });
    });
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
      if (mounted) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _reset() {
    _searchDebounce?.cancel();
    _search.clear();

    setState(() {
      _query = '';
      _sport = null;
      _status = null;
      _sort = _Sort.recommended;
    });
  }

  void _changeScope(int value) {
    if (_scope == value) return;

    setState(() {
      _scope = value;

      // Draft status is only available in Managing.
      if (_scope != 2 && _status == TournamentStatus.draft) {
        _status = null;
      }
    });
  }

  void _openTournament(Tournament tournament) {
    pushRoute(
      context,
      AppRoute.tournamentDetail,
      args: TournamentDetailArgs(tournament.id),
    );
  }

  void _createTournament() {
    pushRoute(context, AppRoute.createTournament);
  }

  int _relevance(Tournament tournament, Account? me) {
    final now = DateTime.now();

    var score = 0;

    if (tournament.status == TournamentStatus.open) {
      score += 8;
    } else if (tournament.status == TournamentStatus.inProgress) {
      score += 6;
    }

    if (me?.sports.contains(tournament.sport) == true) {
      score += 3;
    }

    if (me != null &&
        me.city.isNotEmpty &&
        me.city.toLowerCase() == tournament.city.toLowerCase()) {
      score += 2;
    }

    if (tournament.startsAt.isAfter(now)) {
      score += 1;
    }

    return score;
  }

  void _sortTournaments(List<Tournament> tournaments, Account? me) {
    tournaments.sort((a, b) {
      if (_sort == _Sort.newest) {
        return b.createdAt.compareTo(a.createdAt);
      }

      if (_sort == _Sort.recommended) {
        final comparison = _relevance(b, me).compareTo(_relevance(a, me));

        if (comparison != 0) return comparison;
      }

      return a.startsAt.compareTo(b.startsAt);
    });
  }

  Future<void> _showFilters() async {
    Sport? selectedSport = _sport;
    TournamentStatus? selectedStatus = _status;
    _Sort selectedSort = _sort;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: SportikaColors.surface,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, updateSheet) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'REFINE YOUR DISCOVERY',
                        style: SportikaType.micro.copyWith(
                          color: SportikaColors.mint,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tournament filters',
                        style: SportikaType.title,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Find competitions that match your sport, '
                        'schedule and interests.',
                        style: SportikaType.caption,
                      ),
                      const SizedBox(height: 24),

                      const Text(
                        'Competition status',
                        style: SportikaType.bodyStrong,
                      ),
                      const SizedBox(height: 10),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All statuses'),
                            selected: selectedStatus == null,
                            onSelected: (_) {
                              updateSheet(() {
                                selectedStatus = null;
                              });
                            },
                          ),
                          for (final status in TournamentStatus.values)
                            if (status != TournamentStatus.draft || _scope == 2)
                              ChoiceChip(
                                label: Text(status.label),
                                selected: selectedStatus == status,
                                onSelected: (_) {
                                  updateSheet(() {
                                    selectedStatus = status;
                                  });
                                },
                              ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      const Text(
                        'Sort competitions',
                        style: SportikaType.bodyStrong,
                      ),
                      const SizedBox(height: 10),

                      RadioGroup<_Sort>(
                        groupValue: selectedSort,
                        onChanged: (value) {
                          if (value == null) return;

                          updateSheet(() {
                            selectedSort = value;
                          });
                        },
                        child: const Column(
                          children: [
                            RadioListTile<_Sort>(
                              value: _Sort.recommended,
                              title: Text('Recommended'),
                            ),
                            RadioListTile<_Sort>(
                              value: _Sort.soonest,
                              title: Text('Starting soon'),
                            ),
                            RadioListTile<_Sort>(
                              value: _Sort.newest,
                              title: Text('Recently added'),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            setState(() {
                              _sport = selectedSport;
                              _status = selectedStatus;
                              _sort = selectedSort;
                            });

                            Navigator.of(sheetContext).pop();
                          },
                          child: const Text('Apply filters'),
                        ),
                      ),

                      Center(
                        child: TextButton(
                          onPressed: () {
                            updateSheet(() {
                              selectedSport = null;
                              selectedStatus = null;
                              selectedSort = _Sort.recommended;
                            });
                          },
                          child: const Text('Clear filters'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    final fixturesState = context.watch<FixturesController>();
    final me = context.watch<ProfileController>().currentAccount;

    final source = switch (_scope) {
      1 => state.myTournaments,
      2 => state.tournamentsForOrganizer(me?.id),
      _ =>
        state.tournaments
            .where((tournament) => tournament.status != TournamentStatus.draft)
            .toList(),
    };

    final items = source.where((tournament) {
      final sportMatches = _sport == null || tournament.sport == _sport;

      final statusMatches = _status == null || tournament.status == _status;

      final queryMatches =
          _query.isEmpty ||
          '${tournament.name} '
                  '${tournament.city} '
                  '${tournament.sport.label} '
                  '${tournament.format.label}'
              .toLowerCase()
              .contains(_query);

      return sportMatches && statusMatches && queryMatches;
    }).toList();

    _sortTournaments(items, me);

    final live = items
        .where((tournament) => tournament.status == TournamentStatus.inProgress)
        .toList();

    final visibleIds = items.map((tournament) => tournament.id).toSet();

    final liveFixtures =
        fixturesState.fixtures
            .where(
              (fixture) =>
                  fixture.status == FixtureStatus.live &&
                  visibleIds.contains(fixture.tournamentId),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final registrationOpen = items
        .where((tournament) => tournament.status == TournamentStatus.open)
        .toList();

    final featuredCandidates = items.where((tournament) {
      return tournament.status == TournamentStatus.open ||
          tournament.status == TournamentStatus.inProgress;
    }).toList();

    final Tournament? featured =
        _scope == 0 &&
            _query.isEmpty &&
            _status == null &&
            featuredCandidates.isNotEmpty
        ? featuredCandidates.first
        : null;

    final remaining = items
        .where((tournament) => tournament.id != featured?.id)
        .toList();

    final liveRemaining = remaining
        .where((tournament) => tournament.status == TournamentStatus.inProgress)
        .toList();

    final openRemaining = remaining
        .where((tournament) => tournament.status == TournamentStatus.open)
        .toList();

    final otherRemaining = remaining
        .where(
          (tournament) =>
              tournament.status != TournamentStatus.open &&
              tournament.status != TournamentStatus.inProgress,
        )
        .toList();

    final filtered = _query.isNotEmpty || _sport != null || _status != null;

    final width = MediaQuery.sizeOf(context).width;

    final inset = width > 760 ? (width - 720) / 2 : 20.0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const ValueKey('tournament-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(inset, 18, inset, 32),
        children: [
          // ==================================================
          // EDITORIAL HEADER
          // ==================================================

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SPORTIKA / COMPETITIONS',
                      style: SportikaType.micro.copyWith(
                        color: SportikaColors.gold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(switch (_scope) {
                      1 => 'Your arena.',
                      2 => 'Lead the game.',
                      _ => 'The arena awaits.',
                    }, style: SportikaType.hero),
                    const SizedBox(height: 6),
                    Text(switch (_scope) {
                      1 => 'Your tournaments, entries and journey.',
                      2 => 'Create and manage your competitions.',
                      _ => 'Discover tournaments. Compete. Rise.',
                    }, style: SportikaType.caption),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Create tournament',
                child: Material(
                  color: SportikaColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(SportikaRadius.control),
                  child: InkWell(
                    onTap: _createTournament,
                    borderRadius: BorderRadius.circular(SportikaRadius.control),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.add_rounded,
                        color: SportikaColors.mint,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ==================================================
          // FEATURED COMPETITION
          // ==================================================
          if (featured != null) ...[
            const _SectionHeading(
              eyebrow: 'SPOTLIGHT',
              title: 'Featured competition',
              icon: Icons.auto_awesome_outlined,
            ),
            const SizedBox(height: 12),
            EditorialBanner(
              height: 248,
              sport: featured.sport,
              eyebrow: 'FEATURED · ${featured.status.label}',
              title: featured.name,
              subtitle:
                  '${featured.city} · '
                  '${dayLabel(featured.startsAt)} · '
                  '${featured.format.label}',
              action: 'Explore tournament',
              accent: SportikaColors.gold,
              onAction: () => _openTournament(featured),
            ),
            const SizedBox(height: 22),
          ],

          // ==================================================
          // SCOPE NAVIGATION
          // ==================================================
          _ScopeSelector(selected: _scope, onChanged: _changeScope),

          const SizedBox(height: 20),

          // ==================================================
          // SEARCH
          // ==================================================
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search competitions or cities',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchDebounce?.cancel();
                              _search.clear();

                              setState(() {
                                _query = '';
                              });
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'Advanced filters',
                child: Material(
                  color: SportikaColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(SportikaRadius.control),
                  child: InkWell(
                    onTap: _showFilters,
                    borderRadius: BorderRadius.circular(SportikaRadius.control),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Icon(
                        Icons.tune_rounded,
                        color: SportikaColors.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ==================================================
          // SPORT SELECTOR
          // ==================================================
          FilterChipRow<Sport?>(
            label: 'Tournament sport',
            choices: [
              const FilterChoice(null, 'All sports'),
              for (final sport in Sport.values)
                FilterChoice(sport, sport.label),
            ],
            selected: _sport,
            onChanged: (value) {
              setState(() {
                _sport = value;
              });
            },
          ),

          if (filtered) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset filters'),
              ),
            ),
          ],

          const SizedBox(height: 20),

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

          // ==================================================
          // EMPTY STATE
          // ==================================================
          if (items.isEmpty && !_loading)
            EmptyState(
              title: filtered
                  ? 'No tournaments match your search'
                  : _scope == 1
                  ? 'Your tournament journey starts here'
                  : _scope == 2
                  ? 'Your competition, your way'
                  : 'The next competition is coming',
              body: filtered
                  ? 'Try another sport, city or competition status.'
                  : _scope == 1
                  ? 'Discover a tournament and submit an entry.'
                  : _scope == 2
                  ? 'Create a tournament and bring players together.'
                  : 'Explore competitions as they become available.',
              icon: Icons.emoji_events_outlined,
              action: GhostButton(
                label: filtered
                    ? 'Reset filters'
                    : _scope == 1
                    ? 'Discover tournaments'
                    : _scope == 2
                    ? 'Create tournament'
                    : 'Refresh competitions',
                onPressed: filtered
                    ? _reset
                    : _scope == 1
                    ? () => _changeScope(0)
                    : _scope == 2
                    ? _createTournament
                    : _refresh,
              ),
            ),

          // ==================================================
          // DISCOVER
          // ==================================================
          if (_scope == 0 && items.isNotEmpty) ...[
            if (liveRemaining.isNotEmpty) ...[
              _SectionHeading(
                eyebrow: 'HAPPENING NOW',
                title: 'Live competitions',
                icon: Icons.sensors_rounded,
                count: live.length,
              ),
              const SizedBox(height: 12),
              for (final tournament in liveRemaining)
                _TournamentListItem(tournament: tournament, state: state),
              const SizedBox(height: 12),
            ],

            // Live scores belong to the fixture that owns them, so they are
            // shown here rather than in a separate Live feed.
            if (liveFixtures.isNotEmpty) ...[
              _SectionHeading(
                eyebrow: 'ON COURT NOW',
                title: 'Live fixtures',
                icon: Icons.sports_score_outlined,
                count: liveFixtures.length,
              ),
              const SizedBox(height: 12),
              for (final fixture in liveFixtures)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: officialFixtureTile(context, fixture),
                ),
              const SizedBox(height: 12),
            ],

            if (openRemaining.isNotEmpty) ...[
              _SectionHeading(
                eyebrow: 'JOIN THE ACTION',
                title: 'Registration open',
                icon: Icons.how_to_reg_outlined,
                count: registrationOpen.length,
              ),
              const SizedBox(height: 12),
              for (final tournament in openRemaining)
                _TournamentListItem(tournament: tournament, state: state),
              const SizedBox(height: 12),
            ],

            if (otherRemaining.isNotEmpty) ...[
              _SectionHeading(
                eyebrow: 'EXPLORE MORE',
                title: 'More competitions',
                icon: Icons.emoji_events_outlined,
                count: otherRemaining.length,
              ),
              const SizedBox(height: 12),
              for (final tournament in otherRemaining)
                _TournamentListItem(tournament: tournament, state: state),
            ],
          ],

          // ==================================================
          // MY TOURNAMENTS
          // ==================================================
          if (_scope == 1 && items.isNotEmpty) ...[
            _SectionHeading(
              eyebrow: 'YOUR COMPETITION JOURNEY',
              title: 'My tournaments',
              icon: Icons.workspace_premium_outlined,
              count: items.length,
            ),
            const SizedBox(height: 12),
            for (final tournament in items)
              _TournamentListItem(tournament: tournament, state: state),
          ],

          // ==================================================
          // MANAGING
          // ==================================================
          if (_scope == 2 && items.isNotEmpty) ...[
            _SectionHeading(
              eyebrow: 'ORGANIZER WORKSPACE',
              title: 'Managed competitions',
              icon: Icons.admin_panel_settings_outlined,
              count: items.length,
            ),
            const SizedBox(height: 12),
            for (final tournament in items)
              _TournamentListItem(tournament: tournament, state: state),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// PREMIUM SCOPE SELECTOR
// ============================================================

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (title: 'Discover', subtitle: 'Explore', icon: Icons.explore_outlined),
      (
        title: 'My tournaments',
        subtitle: 'Your entries',
        icon: Icons.emoji_events_outlined,
      ),
      (
        title: 'Managing',
        subtitle: 'Organize',
        icon: Icons.dashboard_customize_outlined,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: selected == i
                  ? SportikaColors.mintSubtle
                  : SportikaColors.surfaceElevated,
              borderRadius: BorderRadius.circular(SportikaRadius.control),
              child: InkWell(
                onTap: () => onChanged(i),
                borderRadius: BorderRadius.circular(SportikaRadius.control),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(SportikaRadius.control),
                    border: Border.all(
                      color: selected == i
                          ? SportikaColors.mint
                          : SportikaColors.borderSubtle,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        items[i].icon,
                        color: selected == i
                            ? SportikaColors.mint
                            : SportikaColors.textMuted,
                        size: 21,
                      ),
                      const SizedBox(height: 9),
                      Text(
                        items[i].title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.caption.copyWith(
                          color: selected == i
                              ? SportikaColors.text
                              : SportikaColors.textBody,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[i].subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.micro,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// SECTION HEADING
// ============================================================

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.icon,
    this.count,
  });

  final String eyebrow;
  final String title;
  final IconData icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: SportikaColors.mint, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: SportikaType.micro.copyWith(color: SportikaColors.mint),
              ),
              const SizedBox(height: 4),
              Text(title, style: SportikaType.title),
            ],
          ),
        ),
        if (count != null) Text('$count', style: SportikaType.caption),
      ],
    );
  }
}

// ============================================================
// TOURNAMENT LIST ITEM
// ============================================================

class _TournamentListItem extends StatelessWidget {
  const _TournamentListItem({required this.tournament, required this.state});

  final Tournament tournament;
  final TournamentsController state;

  @override
  Widget build(BuildContext context) {
    final entry = state.myEntryFor(tournament.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TournamentCard(
        tournament: tournament,
        trailing: entry == null
            ? null
            : StatusPill(
                entry.status.label,
                color: statusColor(entry.status.key),
              ),
      ),
    );
  }
}
