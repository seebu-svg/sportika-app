import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/live/widgets/my_match_card.dart';
import 'package:sportika/features/live/widgets/my_matches.dart';
import 'package:sportika/features/profile/widgets/sporting_record.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Premium Sportika My Matches dashboard.
///
/// Merges official matches and tournament fixtures through the
/// existing aggregation layer, without fabricating records or results.
class MatchHistoryScreen extends StatefulWidget {
  const MatchHistoryScreen({super.key});

  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  final TextEditingController _search = TextEditingController();

  MyMatchPhase _phase = MyMatchPhase.all;
  Sport? _sport;

  String _query = '';
  bool _searching = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadIfEmpty();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadIfEmpty() async {
    final matches = context.read<MatchController>();
    final fixtures = context.read<FixturesController>();

    if (matches.matches.isNotEmpty || fixtures.fixtures.isNotEmpty) {
      return;
    }

    await _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final fixtures = context.read<FixturesController>();
    final matches = context.read<MatchController>();

    try {
      // Existing application architecture uses fixture refresh
      // to synchronize the official match projections.
      await fixtures.refresh();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = fixtures.lastError ?? matches.lastError ?? '$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;

      if (!_searching) {
        _search.clear();
        _query = '';
      }
    });
  }

  void _clearFilters() {
    _search.clear();

    setState(() {
      _phase = MyMatchPhase.all;
      _sport = null;
      _query = '';
    });
  }

  void _open(MyMatchRecord record) {
    if (record.matchId != null) {
      pushRoute(
        context,
        AppRoute.matchDetail,
        args: MatchArgs(record.matchId!),
      );
      return;
    }

    if (record.fixtureId != null) {
      pushRoute(
        context,
        AppRoute.fixtureDetail,
        args: FixtureDetailArgs(record.fixtureId!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionController>().currentAccount;

    final matches = context.watch<MatchController>();
    final fixtures = context.watch<FixturesController>();
    final tournaments = context.watch<TournamentsController>();

    final all = myMatchesFor(
      accountId: me?.id,
      matches: matches,
      fixtures: fixtures,
      tournaments: tournaments,
    );

    final record = recordOf(all);

    final counts = {
      for (final phase in MyMatchPhase.values)
        phase: filterMyMatches(
          all,
          phase: phase,
          sport: _sport,
          query: _query,
        ).length,
    };

    final visible = filterMyMatches(
      all,
      phase: _phase,
      sport: _sport,
      query: _query,
    );

    final unfilteredLive = filterMyMatches(all, phase: MyMatchPhase.live);

    final unfilteredUpcoming = filterMyMatches(
      all,
      phase: MyMatchPhase.upcoming,
    );

    final featuredLive = unfilteredLive.isNotEmpty
        ? unfilteredLive.first
        : null;

    final sortedUpcoming = [...unfilteredUpcoming]
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final nextMatch = sortedUpcoming.isNotEmpty ? sortedUpcoming.first : null;

    final showFeatured =
        _phase == MyMatchPhase.all && _sport == null && _query.trim().isEmpty;

    final featuredKeys = <String>{
      if (showFeatured && featuredLive != null) featuredLive.key,
      if (showFeatured && nextMatch != null) nextMatch.key,
    };

    final listEntries = showFeatured
        ? visible.where((entry) => !featuredKeys.contains(entry.key)).toList()
        : visible;

    return Scaffold(
      appBar: sportikaAppBar(
        'My matches',
        subtitle: _subtitle(all),
        actions: [
          IconAction(
            icon: _searching ? Icons.search_off_rounded : Icons.search_rounded,
            label: _searching ? 'Close search' : 'Search matches',
            onPressed: _toggleSearch,
          ),
          IconAction(
            icon: Icons.add_rounded,
            label: 'Create a match',
            tone: SportikaColors.blueBright,
            onPressed: () => pushRoute(context, AppRoute.createMatch),
          ),
          const SizedBox(width: SportikaSpacing.sm),
        ],
      ),
      body: ClampedTextScale(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = constraints.maxWidth > sportikaMaxContentWidth
                  ? (constraints.maxWidth - sportikaMaxContentWidth) / 2 +
                        SportikaSpacing.md
                  : SportikaSpacing.md;

              return RefreshIndicator(
                onRefresh: _refresh,
                color: SportikaColors.mint,
                backgroundColor: SportikaColors.surface,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    inset,
                    SportikaSpacing.sm,
                    inset,
                    SportikaSpacing.xxl,
                  ),
                  children: [
                    // ====================================
                    // SEARCH
                    // ====================================

                    if (_searching) ...[
                      _searchField(),
                      const SizedBox(height: SportikaSpacing.md),
                    ],

                    // ====================================
                    // SYNC / REFRESH STATUS
                    // ====================================
                    if (_loading && all.isNotEmpty) ...[
                      const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: SportikaSpacing.sm),
                    ],

                    if (_error != null && all.isNotEmpty) ...[
                      const InlineBanner(
                        text:
                            'Could not refresh matches. Showing saved records.',
                        tone: SportikaColors.gold,
                        icon: Icons.warning_amber_rounded,
                      ),
                      const SizedBox(height: SportikaSpacing.md),
                    ],

                    if (matches.sync.isWarning) ...[
                      InlineBanner(
                        text: matches.sync == MatchSyncState.offline
                            ? 'You are offline. Matches will refresh when the connection returns.'
                            : 'The last change could not be saved.',
                        tone: SportikaColors.gold,
                        icon: matches.sync == MatchSyncState.offline
                            ? Icons.cloud_off_rounded
                            : Icons.error_outline_rounded,
                      ),
                      const SizedBox(height: SportikaSpacing.md),
                    ],

                    // ====================================
                    // CONTENT
                    // ====================================
                    ..._content(
                      all: all,
                      record: record,
                      counts: counts,
                      visible: visible,
                      listEntries: listEntries,
                      featuredLive: showFeatured ? featuredLive : null,
                      nextMatch: showFeatured ? nextMatch : null,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _content({
    required List<MyMatchRecord> all,
    required SportingRecord record,
    required Map<MyMatchPhase, int> counts,
    required List<MyMatchRecord> visible,
    required List<MyMatchRecord> listEntries,
    required MyMatchRecord? featuredLive,
    required MyMatchRecord? nextMatch,
  }) {
    if (all.isEmpty) {
      if (_loading) {
        return const [
          LoadingSkeleton(rows: 3, label: 'Loading matches', rowHeight: 108),
        ];
      }

      if (_error != null) {
        return [
          ErrorState(
            title: 'Matches did not load',
            message: _error,
            onRetry: _refresh,
          ),
        ];
      }

      return [
        EmptyState(
          icon: Icons.sports_score_rounded,
          title: 'No matches yet',
          body: 'Matches you play, organize, or score appear here. Official results are recorded after publication.',
          action: PrimaryButton(
            label: 'Create a match',
            icon: Icons.add_rounded,
            small: true,
            expand: false,
            onPressed: () => pushRoute(context, AppRoute.createMatch),
          ),
        ),
      ];
    }

    return [
      // ========================================
      // ATHLETE RECORD
      // ========================================

      Row(
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            color: SportikaColors.gold,
            size: SportikaIconSize.md,
          ),
          const SizedBox(width: SportikaSpacing.sm),
          const Expanded(
            child: Text('OFFICIAL ATHLETE RECORD', style: SportikaType.label),
          ),
          Text(
            '${all.length} ${all.length == 1 ? 'match' : 'matches'}',
            style: SportikaType.caption,
          ),
        ],
      ),

      const SizedBox(height: SportikaSpacing.sm),

      SportingRecordStrip(record: record),

      if (record.draws > 0 || record.isEmpty) ...[
        const SizedBox(height: SportikaSpacing.xs),
        Text(
          record.isEmpty
              ? 'Your record updates when an organizer publishes a result you played in.'
              : record.draws == 1
              ? '1 draw recorded'
              : '${record.draws} draws recorded',
          style: SportikaType.caption,
        ),
      ],

      // ========================================
      // FEATURED LIVE MATCH
      // ========================================
      if (featuredLive != null) ...[
        const SectionTitle('Live now'),

        _FeaturedMatchSection(
          record: featuredLive,
          icon: Icons.sensors_rounded,
          accent: SportikaColors.mint,
          onTap: () => _open(featuredLive),
        ),
      ],

      // ========================================
      // NEXT UPCOMING MATCH
      // ========================================
      if (nextMatch != null) ...[
        const SectionTitle('Next match'),

        _FeaturedMatchSection(
          record: nextMatch,
          icon: Icons.calendar_month_rounded,
          accent: SportikaColors.blueBright,
          onTap: () => _open(nextMatch),
        ),
      ],

      // ========================================
      // FILTERS
      // ========================================
      const SizedBox(height: SportikaSpacing.lg),

      MyMatchPhaseChips(
        selected: _phase,
        counts: counts,
        onChanged: (phase) {
          setState(() => _phase = phase);
        },
      ),

      const SizedBox(height: SportikaSpacing.xs),

      SportFilterRow(
        selected: _sport,
        onChanged: (sport) {
          setState(() => _sport = sport);
        },
        padding: EdgeInsets.zero,
      ),

      const SizedBox(height: SportikaSpacing.md),

      // ========================================
      // MATCH LIST
      // ========================================
      Row(
        children: [
          Expanded(child: Text(_listHeading(), style: SportikaType.label)),
          Text(
            '${listEntries.length} ${listEntries.length == 1 ? 'match' : 'matches'}',
            style: SportikaType.caption,
          ),
        ],
      ),

      const SizedBox(height: SportikaSpacing.sm),

      if (visible.isEmpty)
        _noResults()
      else if (listEntries.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: SportikaSpacing.md),
          child: Text(
            'Your matches are highlighted above.',
            style: SportikaType.caption,
          ),
        )
      else
        for (final entry in listEntries)
          Padding(
            padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
            child: MyMatchCard(record: entry, onTap: () => _open(entry)),
          ),
    ];
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: (value) {
        setState(() => _query = value);
      },
      decoration: InputDecoration(
        hintText: 'Search teams, tournaments, venues or sports',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
      ),
    );
  }

  Widget _noResults() {
    final query = _query.trim();

    return EmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: query.isEmpty
          ? 'No ${_filterDescription()} matches'
          : 'No matches for “$query”',
      body: query.isEmpty
          ? 'Nothing on record for this filter. Try another status or sport.'
          : 'Search covers teams, tournaments, venues, sports and match roles.',
      action: GhostButton(
        label: 'Clear filters',
        icon: Icons.close_rounded,
        onPressed: _clearFilters,
      ),
    );
  }

  String _filterDescription() {
    final sport = _sport?.label.toLowerCase();

    final phase = switch (_phase) {
      MyMatchPhase.all => '',
      MyMatchPhase.upcoming => 'upcoming',
      MyMatchPhase.live => 'live',
      MyMatchPhase.completed => 'history',
    };

    return [
      sport,
      phase,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' ');
  }

  String _listHeading() => switch (_phase) {
    MyMatchPhase.all => 'ALL MATCHES',
    MyMatchPhase.upcoming => 'UPCOMING',
    MyMatchPhase.live => 'LIVE NOW',
    MyMatchPhase.completed => 'HISTORY',
  };

  String _subtitle(List<MyMatchRecord> all) {
    if (all.isEmpty) return 'No official matches yet';

    final live = all.where((entry) => entry.phase == MyMatchPhase.live).length;

    final upcoming = all
        .where((entry) => entry.phase == MyMatchPhase.upcoming)
        .length;

    return [
      if (live > 0) '$live live',
      if (upcoming > 0) '$upcoming upcoming',
      '${all.length} ${all.length == 1 ? 'match' : 'matches'}',
    ].join(' · ');
  }
}

// ============================================================
// FEATURED MATCH SECTION
// ============================================================

class _FeaturedMatchSection extends StatelessWidget {
  const _FeaturedMatchSection({
    required this.record,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final MyMatchRecord record;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: accent, size: SportikaIconSize.md),
            const SizedBox(width: SportikaSpacing.sm),
            Expanded(
              child: Text(
                record.isLive
                    ? 'Match in progress'
                    : '${dateShort(record.scheduledAt)} · ${timeLabel(record.scheduledAt)}',
                style: SportikaType.caption,
              ),
            ),
          ],
        ),

        const SizedBox(height: SportikaSpacing.sm),

        MyMatchCard(record: record, onTap: onTap),
      ],
    );
  }
}
