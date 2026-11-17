import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/features/discover/screens/games_tab.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// One match feed, with official one-off matches and tournament fixtures.
class MatchesTab extends StatefulWidget {
  const MatchesTab({super.key, this.initialScope = 0});
  final int initialScope;

  @override
  State<MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<MatchesTab> {
  late int _scope = widget.initialScope;
  Sport? _sport;
  bool _mine = false;
  bool _searchOpen = false;
  bool _loading = false;
  String? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void didUpdateWidget(covariant MatchesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialScope != widget.initialScope) {
      _scope = widget.initialScope;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait([
        context.read<MatchController>().refresh(),
        context.read<FixturesController>().refresh(),
      ]);
      if (mounted) {
        setState(
          () => _error =
              context.read<MatchController>().lastError ??
              context.read<FixturesController>().lastError,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openGames() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: sportikaAppBar('Pickup games'),
        body: const SafeArea(child: GamesTab()),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final matches = context.watch<MatchController>();
    final fixtures = context.watch<FixturesController>();
    final needle = _search.text.trim().toLowerCase();
    bool accepts(Sport sport, String text) =>
        (_sport == null || _sport == sport) &&
        (needle.isEmpty || text.toLowerCase().contains(needle));
    final source = switch (_scope) {
      1 => matches.liveMatches,
      2 =>
        matches.discoverableMatches
            .where((m) => m.status == FixtureStatus.upcoming)
            .toList(),
      3 => matches.completedMatches,
      _ => matches.discoverableMatches,
    };
    final mine = matches.myMatches.map((m) => m.id).toSet();
    final visible = source
        .where(
          (m) =>
              (!_mine || mine.contains(m.id)) &&
              accepts(
                m.sport,
                '${m.title} ${m.venue} ${m.sideNames.join(' ')} ${m.sport.label}',
              ),
        )
        .toList();
    final fixtureSource = switch (_scope) {
      1 => fixtures.liveFixtures,
      2 => fixtures.scheduledFixtures,
      3 => fixtures.completedFixtures,
      _ => fixtures.publicFixtures,
    };
    final myFixtures = fixtures.myFixtures.map((f) => f.id).toSet();
    final tournamentFixtures = fixtureSource.where((f) {
      final tournament = fixtures.tournamentOf(f);
      return (!_mine || myFixtures.contains(f.id)) &&
          accepts(
            tournament?.sport ?? Sport.cricket,
            '${tournament?.name ?? ''} ${f.venue} ${fixtures.sideLabelsOf(f).join(' ')} ${tournament?.sport.label ?? ''}',
          );
    }).toList();
    final cards =
        <({DateTime date, Widget card})>[
          for (final m in visible)
            (
              date: m.scheduledAt,
              card: _FixtureCard(
                title: m.title,
                sport: m.sport,
                status: m.status,
                metadata: '${m.formatLabel} · ${dateShort(m.scheduledAt)}',
                scoreboard: MatchScoreboard(
                  compact: true,
                  sport: m.sport,
                  labels: [
                    for (var i = 0; i < 2; i++)
                      m.sideLabels.length > i
                          ? m.sideLabels[i]
                          : 'Side ${i + 1}',
                  ],
                  progress:
                      m.status != FixtureStatus.cancelled &&
                          (m.isLive || m.result != null)
                      ? matches.progressOf(m)
                      : null,
                  result: m.status == FixtureStatus.cancelled ? null : m.result,
                  finished: m.result != null,
                ),
                onTap: () => pushRoute(
                  context,
                  AppRoute.matchDetail,
                  args: MatchArgs(m.id),
                ),
              ),
            ),
          for (final f in tournamentFixtures)
            (
              date: f.scheduledAt,
              card: _FixtureCard(
                title: [
                  fixtures.tournamentOf(f)?.name ?? 'Tournament',
                  if (f.stage.isNotEmpty) f.stage,
                ].join(' · '),
                sport: fixtures.tournamentOf(f)?.sport ?? Sport.cricket,
                status: f.status,
                metadata: [
                  if (fixtures.tournamentOf(f)?.formatLabel.isNotEmpty == true)
                    fixtures.tournamentOf(f)!.formatLabel,
                  dateShort(f.scheduledAt),
                ].join(' · '),
                scoreboard: MatchScoreboard(
                  compact: true,
                  sport: fixtures.tournamentOf(f)?.sport ?? Sport.cricket,
                  labels: fixtures.sideLabelsOf(f),
                  progress:
                      f.status != FixtureStatus.cancelled && f.events.isNotEmpty
                      ? fixtures.progressOfFixture(f)
                      : null,
                  result: f.status == FixtureStatus.cancelled ? null : f.result,
                  finished: f.result != null,
                ),
                onTap: () => pushRoute(
                  context,
                  AppRoute.fixtureDetail,
                  args: FixtureDetailArgs(f.id),
                ),
              ),
            ),
        ]..sort(
          (a, b) =>
              _scope == 3 ? b.date.compareTo(a.date) : a.date.compareTo(b.date),
        );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: sportikaMaxContentWidth),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  SportikaSpacing.lg,
                  SportikaSpacing.md,
                  SportikaSpacing.lg,
                  SportikaSpacing.sm,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Matches', style: SportikaType.title),
                                SizedBox(height: SportikaSpacing.xs),
                                Text(
                                  'Fixtures, live scores & results',
                                  style: SportikaType.caption,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: _searchOpen
                                ? 'Close search'
                                : 'Search matches',
                            isSelected: _searchOpen,
                            onPressed: () => setState(() {
                              _searchOpen = !_searchOpen;
                              if (!_searchOpen) _search.clear();
                            }),
                            icon: Icon(
                              _searchOpen ? Icons.close : Icons.search,
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'More match options',
                            onSelected: (value) {
                              switch (value) {
                                case 'mine':
                                  setState(() => _mine = !_mine);
                                case 'personal':
                                  pushRoute(context, AppRoute.personalGames);
                                case 'games':
                                  _openGames();
                                case 'scorer':
                                  pushRoute(context, AppRoute.scorerWorkspace);
                              }
                            },
                            itemBuilder: (_) => [
                              CheckedPopupMenuItem(
                                value: 'mine',
                                checked: _mine,
                                child: const Text('My matches only'),
                              ),
                              const PopupMenuItem(
                                value: 'personal',
                                child: Text('Personal games'),
                              ),
                              const PopupMenuItem(
                                value: 'games',
                                child: Text('Pickup games'),
                              ),
                              const PopupMenuItem(
                                value: 'scorer',
                                child: Text('Scorer assignments'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: SportikaSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () =>
                              pushRoute(context, AppRoute.createMatch),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Create Match'),
                        ),
                      ),
                      if (_searchOpen) ...[
                        const SizedBox(height: SportikaSpacing.sm),
                        TextField(
                          controller: _search,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Search matches, teams or venues',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                      ],
                      const SizedBox(height: SportikaSpacing.sm),
                      FilterChipRow<int>(
                        label: 'Match status',
                        selected: _scope,
                        onChanged: (v) => setState(() => _scope = v),
                        choices: const [
                          FilterChoice(0, 'All'),
                          FilterChoice(1, 'Live'),
                          FilterChoice(2, 'Upcoming'),
                          FilterChoice(3, 'Results'),
                        ],
                      ),
                      const SizedBox(height: SportikaSpacing.xs),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: SportikaSpacing.sm,
                        children: [
                          Text(
                            _mine
                                ? 'My ${['matches', 'live matches', 'upcoming matches', 'results'][_scope]}'
                                : [
                                    'All matches',
                                    'Live now',
                                    'Upcoming matches',
                                    'Results',
                                  ][_scope],
                            style: SportikaType.bodyStrong,
                          ),
                          PopupMenuButton<int>(
                            tooltip: 'Filter by sport',
                            onSelected: (v) => setState(
                              () => _sport = v < 0 ? null : Sport.values[v],
                            ),
                            itemBuilder: (_) => [
                              const PopupMenuItem<int>(
                                value: -1,
                                child: Text('All sports'),
                              ),
                              for (final sport in Sport.values)
                                PopupMenuItem<int>(
                                  value: sport.index,
                                  child: Text(sport.label),
                                ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: SportikaSpacing.md,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _sport?.label ?? 'All sports',
                                    style: SportikaType.action,
                                  ),
                                  const Icon(Icons.expand_more, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${cards.length} ${cards.length == 1 ? 'match' : 'matches'}',
                        style: SportikaType.caption,
                      ),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(top: SportikaSpacing.sm),
                          child: LinearProgressIndicator(),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: SportikaSpacing.sm,
                          ),
                          child: ErrorState(
                            title: 'Matches could not refresh',
                            message: _error!,
                            onRetry: _refresh,
                          ),
                        ),
                      if (matches.sync.isWarning)
                        const Padding(
                          padding: EdgeInsets.only(top: SportikaSpacing.sm),
                          child: InlineBanner(
                            text: 'Matches may be out of date. Pull down to refresh.',
                            tone: SportikaColors.gold,
                            icon: Icons.cloud_off,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_loading && cards.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(SportikaSpacing.lg),
                    child: LoadingSkeleton(
                      rows: 3,
                      label: 'Loading matches',
                      rowHeight: 116,
                    ),
                  ),
                )
              else if (cards.isEmpty && _error == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: 'No matches here yet',
                    body: 'Try another sport, change the status filter or clear your search.',
                    icon: Icons.sports_score,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    SportikaSpacing.lg,
                    SportikaSpacing.xs,
                    SportikaSpacing.lg,
                    SportikaSpacing.xl,
                  ),
                  sliver: SliverList.separated(
                    itemCount: cards.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: SportikaSpacing.sm),
                    itemBuilder: (_, i) => cards[i].card,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FixtureCard extends StatelessWidget {
  const _FixtureCard({
    required this.title,
    required this.sport,
    required this.status,
    required this.metadata,
    required this.scoreboard,
    required this.onTap,
  });
  final String title;
  final Sport sport;
  final FixtureStatus status;
  final String metadata;
  final Widget scoreboard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: SportikaColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SportikaRadius.md),
      side: const BorderSide(color: SportikaColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(SportikaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: SportikaSpacing.sm,
              runSpacing: SportikaSpacing.xs,
              children: [
                Text(sport.label, style: SportikaType.caption),
                Text(
                  status.label,
                  style: SportikaType.caption.copyWith(
                    color: statusColor(status.key),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SportikaSpacing.xs),
            Text(title, style: SportikaType.bodyStrong),
            const SizedBox(height: SportikaSpacing.md),
            scoreboard,
            const SizedBox(height: SportikaSpacing.sm),
            Row(
              children: [
                Expanded(child: Text(metadata, style: SportikaType.caption)),
                const SizedBox(width: SportikaSpacing.sm),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  semanticLabel: 'Open match details',
                  color: SportikaColors.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
