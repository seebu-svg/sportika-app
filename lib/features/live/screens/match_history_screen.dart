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
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// My Matches: every official match the signed-in member is part of, whether
/// they played it, organized it or were appointed to score it.
///
/// Two official sources are merged and de-duplicated: the match module's own
/// records and the tournament fixtures the member appeared in. Only rows those
/// controllers return are shown - nothing is inferred - and each row keeps its
/// exact status, so an unpublished result is never presented as a final one.
class MatchHistoryScreen extends StatefulWidget {
  const MatchHistoryScreen({super.key});

  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  final _search = TextEditingController();
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
    if (matches.matches.isNotEmpty || fixtures.fixtures.isNotEmpty) return;
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final fixtures = context.read<FixturesController>();
    final matches = context.read<MatchController>();
    try {
      // A live build projects fixtures from the match rows and a demo build
      // keeps both in one document, so this single reload refreshes both
      // sources of the list without reading either twice.
      await fixtures.refresh();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = fixtures.lastError ?? matches.lastError ?? '$error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (!_searching && _query.isNotEmpty) {
      _search.clear();
      setState(() => _query = '');
    }
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
    final matchId = record.matchId;
    if (matchId != null) {
      pushRoute(context, AppRoute.matchDetail, args: MatchArgs(matchId));
      return;
    }
    final fixtureId = record.fixtureId;
    if (fixtureId != null) {
      pushRoute(
        context,
        AppRoute.fixtureDetail,
        args: FixtureDetailArgs(fixtureId),
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
        phase: filterMyMatches(all, phase: phase).length,
    };
    final visible = filterMyMatches(
      all,
      phase: _phase,
      sport: _sport,
      query: _query,
    );

    return Scaffold(
      appBar: sportikaAppBar(
        'My matches',
        subtitle: _subtitle(all, counts),
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
          const SizedBox(width: 8),
        ],
      ),
      body: ClampedTextScale(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = constraints.maxWidth > sportikaMaxContentWidth
                  ? (constraints.maxWidth - sportikaMaxContentWidth) / 2 + 20
                  : 20.0;
              return RefreshIndicator(
                onRefresh: _refresh,
                color: SportikaColors.mint,
                backgroundColor: SportikaColors.surface,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(inset, 12, inset, 32),
                  children: [
                    if (_searching) ...[
                      _searchField(),
                      const SizedBox(height: 14),
                    ],
                    if (matches.sync.isWarning) ...[
                      InlineBanner(
                        text: matches.sync == MatchSyncState.offline
                            ? 'You are offline. Matches will refresh when the '
                                  'connection returns.'
                            : 'The last change could not be saved.',
                        tone: SportikaColors.gold,
                        icon: matches.sync == MatchSyncState.offline
                            ? Icons.cloud_off
                            : Icons.error_outline,
                      ),
                      const SizedBox(height: 14),
                    ],
                    ..._content(all, record, counts, visible),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    List<MyMatchRecord> all,
    SportingRecord record,
    Map<MyMatchPhase, int> counts,
    List<MyMatchRecord> visible,
  ) {
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
          icon: Icons.sports_score,
          title: 'No matches yet',
          body:
              'Matches you play, organize or score appear here with their '
              'official result the moment an organizer publishes one.',
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
      Row(
        children: [
          const Expanded(
            child: Text('OFFICIAL RECORD', style: SportikaType.label),
          ),
          Text(
            '${all.length} ${all.length == 1 ? 'match' : 'matches'}',
            style: SportikaType.caption,
          ),
        ],
      ),
      const SizedBox(height: SportikaSpacing.xs + 2),
      SportingRecordStrip(record: record),
      if (record.draws > 0 || record.isEmpty) ...[
        const SizedBox(height: SportikaSpacing.xs),
        Text(
          record.isEmpty
              ? 'Your record fills in once an organizer publishes a result '
                    'you played in.'
              : record.draws == 1
              ? '1 match drawn · a draw counts as neither a win nor a loss'
              : '${record.draws} matches drawn · a draw counts as neither a '
                    'win nor a loss',
          style: SportikaType.caption,
        ),
      ],
      const SizedBox(height: SportikaSpacing.md),
      MyMatchPhaseChips(
        selected: _phase,
        counts: counts,
        onChanged: (phase) => setState(() => _phase = phase),
      ),
      const SizedBox(height: 2),
      SportFilterRow(
        selected: _sport,
        onChanged: (sport) => setState(() => _sport = sport),
        padding: EdgeInsets.zero,
      ),
      const SizedBox(height: SportikaSpacing.xs),
      Row(
        children: [
          Expanded(child: Text(_listHeading(), style: SportikaType.label)),
          Text(
            '${visible.length} ${visible.length == 1 ? 'match' : 'matches'}',
            style: SportikaType.caption,
          ),
        ],
      ),
      const SizedBox(height: SportikaSpacing.sm),
      if (visible.isEmpty)
        _noResults()
      else
        for (final entry in visible)
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
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: 'Search teams, players, tournaments or venues',
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
          : 'Search covers teams, players, tournaments, venues and sports.',
      action: GhostButton(
        label: query.isEmpty ? 'Clear filters' : 'Clear search and filters',
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
      MyMatchPhase.completed => 'completed',
    };
    return [
      sport,
      phase,
    ].whereType<String>().where((p) => p.isNotEmpty).join(' ');
  }

  String _listHeading() => switch (_phase) {
    MyMatchPhase.all => 'ALL MATCHES',
    MyMatchPhase.upcoming => 'UPCOMING',
    MyMatchPhase.live => 'LIVE NOW',
    MyMatchPhase.completed => 'COMPLETED',
  };

  String _subtitle(List<MyMatchRecord> all, Map<MyMatchPhase, int> counts) {
    if (all.isEmpty) return 'No official matches yet';
    final live = counts[MyMatchPhase.live] ?? 0;
    final upcoming = counts[MyMatchPhase.upcoming] ?? 0;
    return [
      if (live > 0) '$live live',
      if (upcoming > 0) '$upcoming upcoming',
      '${all.length} ${all.length == 1 ? 'match' : 'matches'}',
    ].join(' · ');
  }
}
