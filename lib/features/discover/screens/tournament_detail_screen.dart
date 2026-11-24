import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/discover/screens/tournament_sections.dart';
import 'package:sportika/features/discover/widgets/tournament_cover.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Tournament competition hub.
///
/// Uses existing controllers and shared theme tokens.
/// No fabricated tournament data, backend changes, or new dependencies.
class TournamentDetailScreen extends StatefulWidget {
  const TournamentDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

enum _OwnerAction { openRegistration, markCompleted }

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  int _tab = 0;
  int _fixtureScope = 0;

  bool _busy = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (context.read<TournamentsController>().tournamentById(widget.id) ==
          null) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final tournaments = context.read<TournamentsController>();
    final fixtures = context.read<FixturesController>();

    try {
      await Future.wait([tournaments.refresh(), fixtures.refresh()]);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              tournaments.lastError ??
              fixtures.lastError ??
              'This tournament could not be refreshed.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await action();
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'The change could not be saved. Please try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _changeTab(int tab, {int? fixtureScope}) {
    setState(() {
      _tab = tab;
      if (fixtureScope != null) {
        _fixtureScope = fixtureScope;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    final tournament = state.tournamentById(widget.id);

    if (tournament == null) {
      return _unavailableBody(state);
    }

    final session = context.watch<SessionController>();
    final fixturesState = context.watch<FixturesController>();

    final me = session.currentAccount;
    final isOwner = me != null && tournament.organizerId == me.id;

    final fixtures = fixturesState.fixturesFor(tournament.id);
    final confirmed = state.confirmedCountFor(tournament);
    final pending = state.pendingEntriesFor(tournament.id).length;

    final review = fixturesState.fixturesAwaitingReview
        .where((fixture) => fixture.tournamentId == tournament.id)
        .length;

    final myEntry = state.myEntryFor(tournament.id);
    final organizer = session.accountById(tournament.organizerId);
    final canRegister = state.canRegisterFor(tournament);

    final live = fixtures
        .where((fixture) => fixture.status == FixtureStatus.live)
        .toList();

    final published = fixtures
        .where(
          (fixture) =>
              fixture.status == FixtureStatus.published ||
              fixture.status == FixtureStatus.walkover,
        )
        .toList();

    return Scaffold(
      appBar: sportikaAppBar(
        'Competition',
        subtitle: tournament.sport.label,
        actions: [
          if (isOwner)
            PopupMenuButton<_OwnerAction>(
              icon: const Icon(Icons.more_horiz_rounded),
              color: SportikaColors.surfaceElevated,
              tooltip: 'Tournament settings',
              onSelected: (action) {
                _run(() async {
                  switch (action) {
                    case _OwnerAction.openRegistration:
                      state.setTournamentStatus(
                        tournament.id,
                        TournamentStatus.open,
                      );
                      if (mounted) {
                        showSnack(context, 'Registration is open');
                      }
                      break;

                    case _OwnerAction.markCompleted:
                      state.setTournamentStatus(
                        tournament.id,
                        TournamentStatus.completed,
                      );
                      if (mounted) {
                        showSnack(context, 'Tournament marked completed');
                      }
                      break;
                  }
                });
              },
              itemBuilder: (_) => [
                if (tournament.status == TournamentStatus.draft)
                  const PopupMenuItem(
                    value: _OwnerAction.openRegistration,
                    child: Text('Open registration'),
                  ),
                if (tournament.status != TournamentStatus.completed)
                  const PopupMenuItem(
                    value: _OwnerAction.markCompleted,
                    child: Text('Mark completed'),
                  ),
              ],
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: ClampedTextScale(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = constraints.maxWidth > sportikaMaxContentWidth
                  ? (constraints.maxWidth - sportikaMaxContentWidth) / 2 + 20
                  : 18.0;

              return PullToRefresh(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(inset, 10, inset, 40),
                  children: [
                    if (_error != null) ...[
                      InlineBanner(
                        text: _error!,
                        tone: SportikaColors.danger,
                        icon: Icons.cloud_off_outlined,
                        action: TextButton(
                          onPressed: _refresh,
                          child: const Text('Retry'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // CINEMATIC TOURNAMENT HERO
                    _HubHeader(
                      tournament: tournament,
                      confirmed: confirmed,
                      fixtureCount: fixtures.length,
                      liveCount: live.length,
                    ),

                    const SizedBox(height: SportikaSpacing.md),

                    // PARTICIPATION
                    if (myEntry != null)
                      _MyEntryCard(entry: myEntry, tournament: tournament)
                    else if (canRegister)
                      PrimaryButton(
                        label: 'Join this tournament',
                        icon: Icons.arrow_forward_rounded,
                        tone: SportikaColors.mint,
                        busy: _busy,
                        onPressed: () =>
                            _run(() => _register(context, tournament)),
                      )
                    else if (tournament.status == TournamentStatus.open)
                      const InfoBanner(
                        icon: Icons.group_off_outlined,
                        tone: SportikaColors.gold,
                        text: 'Registration is currently unavailable.',
                      ),

                    const SizedBox(height: SportikaSpacing.lg),

                    // UNDERLINE NAVIGATION
                    _TournamentTabs(
                      selected: _tab,
                      fixtureCount: fixtures.length,
                      participantCount: confirmed,
                      format: tournament.format,
                      onChanged: _changeTab,
                    ),

                    const SizedBox(height: SportikaSpacing.lg),

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey(_tab),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_tab == 0) ...[
                              _focusCard(
                                state: state,
                                tournament: tournament,
                                fixtures: fixtures,
                                live: live,
                                published: published,
                                confirmed: confirmed,
                              ),

                              ..._highlights(live: live, published: published),

                              const SizedBox(height: 8),

                              const _EditorialSectionHeader(
                                eyebrow: 'EVENT INFORMATION',
                                title: 'Competition details',
                              ),

                              _competitionCard(
                                tournament: tournament,
                                organizer: organizer,
                                confirmed: confirmed,
                              ),

                              const SizedBox(height: SportikaSpacing.lg),

                              _RulesPanel(tournament: tournament),

                              if (isOwner) ...[
                                const SizedBox(height: SportikaSpacing.lg),
                                const _EditorialSectionHeader(
                                  eyebrow: 'MANAGEMENT',
                                  title: 'Organizer workspace',
                                ),
                                _OrganizerWorkspace(
                                  fixtures: fixtures,
                                  pending: pending,
                                  review: review,
                                  onOpenResults: () => _openResultsReview(
                                    fixturesState,
                                    tournament,
                                  ),
                                  onPublishDraw: () =>
                                      _generateDraw(context, state, tournament),
                                  onOpenEntries: () => _changeTab(3),
                                  onOpenFixtures: () => _changeTab(1),
                                ),
                              ],
                            ],

                            if (_tab == 1) ...[
                              const _EditorialSectionHeader(
                                eyebrow: 'MATCH CENTER',
                                title: 'Fixtures & results',
                              ),
                              _FixtureFilters(
                                selected: _fixtureScope,
                                onChanged: (value) {
                                  setState(() => _fixtureScope = value);
                                },
                              ),
                              const SizedBox(height: 14),
                              TournamentFixturesSection(
                                tournament: tournament,
                                status: switch (_fixtureScope) {
                                  1 => FixtureStatus.live,
                                  2 => FixtureStatus.upcoming,
                                  3 => FixtureStatus.published,
                                  _ => null,
                                },
                              ),
                            ],

                            if (_tab == 2) ...[
                              _EditorialSectionHeader(
                                eyebrow: 'COMPETITION PROGRESS',
                                title:
                                    tournament.format == TournamentFormat.group
                                    ? 'League standings'
                                    : 'Tournament bracket',
                              ),
                              TournamentBracket(tournament: tournament),
                            ],

                            if (_tab == 3) ...[
                              const _EditorialSectionHeader(
                                eyebrow: 'COMPETITORS',
                                title: 'Participants',
                              ),
                              TournamentEntriesSection(
                                tournament: tournament,
                                canManage: isOwner,
                              ),
                            ],
                          ],
                        ),
                      ),
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

  Widget _focusCard({
    required TournamentsController state,
    required Tournament tournament,
    required List<Fixture> fixtures,
    required List<Fixture> live,
    required List<Fixture> published,
    required int confirmed,
  }) {
    final limit = tournament.registrationLimit;

    final scheduled =
        fixtures.where((f) => f.status == FixtureStatus.upcoming).toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final next = scheduled.isEmpty ? null : scheduled.first;

    final remaining = fixtures
        .where(
          (f) =>
              f.status == FixtureStatus.upcoming ||
              f.status == FixtureStatus.live ||
              f.status == FixtureStatus.submitted,
        )
        .length;

    late final String eyebrow;
    late final String title;
    late final String body;
    late final IconData icon;
    late final Color tone;

    final facts = <({String value, String label})>[];
    Widget? action;

    if (tournament.status == TournamentStatus.draft) {
      eyebrow = 'COMING SOON';
      title = 'Competition in preparation';
      body =
          'The organizer is preparing this tournament. '
          'Registration and fixtures will appear when published.';
      icon = Icons.edit_calendar_outlined;
      tone = SportikaColors.textMuted;

      facts.add((value: '$confirmed', label: 'Confirmed'));
    } else if (tournament.status == TournamentStatus.open) {
      eyebrow = 'REGISTRATION OPEN';
      title = fixtures.isEmpty
          ? 'The competition starts here'
          : 'The draw is taking shape';

      body = fixtures.isEmpty
          ? limit > 0
                ? '$confirmed of $limit places confirmed. '
                      'The draw will appear when the organizer publishes it.'
                : '$confirmed entries confirmed. '
                      'The organizer will publish the draw.'
          : '${fixtures.length} fixtures recorded'
                '${next == null ? '' : ' · Next ${dayLabel(next.scheduledAt)}'}';

      icon = Icons.how_to_reg_rounded;
      tone = SportikaColors.mint;

      facts.add((value: '$confirmed', label: 'Confirmed'));
      facts.add((value: '${fixtures.length}', label: 'Fixtures'));

      if (fixtures.isNotEmpty) {
        action = _spotlightAction(
          'Explore fixtures',
          Icons.arrow_forward_rounded,
          () => _changeTab(1, fixtureScope: 0),
        );
      }
    } else if (tournament.status == TournamentStatus.inProgress) {
      final champion = _champion(state, tournament);

      eyebrow = live.isNotEmpty ? 'LIVE COMPETITION' : 'TOURNAMENT IN PROGRESS';

      title = live.isNotEmpty
          ? '${live.length} ${live.length == 1 ? 'match' : 'matches'} live now'
          : 'The competition is underway';

      body = [
        if (champion != null) '$champion won the final',
        if (champion == null && next != null)
          'Next: ${next.stage} · ${dayLabel(next.scheduledAt)}',
        if (published.isNotEmpty)
          '${published.length} official results published'
        else
          'Official results will appear when published',
      ].join(' · ');

      icon = Icons.sensors_rounded;
      tone = SportikaColors.gold;

      facts.add((value: '${live.length}', label: 'Live'));
      facts.add((value: '${published.length}', label: 'Results'));
      facts.add((value: '$remaining', label: 'Remaining'));

      action = _spotlightAction(
        live.isNotEmpty ? 'Explore live matches' : 'View match center',
        Icons.arrow_forward_rounded,
        () => _changeTab(1, fixtureScope: live.isNotEmpty ? 1 : 0),
      );
    } else {
      final champion = _champion(state, tournament);
      final standings = state.standingsFor(tournament);

      final leader =
          tournament.format == TournamentFormat.group && standings.isNotEmpty
          ? standings.first
          : null;

      eyebrow = 'FINAL RESULTS';

      title = champion != null
          ? 'Champion: $champion'
          : leader != null
          ? 'Table leader: ${leader.label}'
          : 'Competition completed';

      body = fixtures.isEmpty
          ? 'No draw or results were recorded for this tournament.'
          : published.isEmpty
          ? 'No official results have been published.'
          : '${published.length} of ${fixtures.length} fixtures '
                'have official results.';

      icon = Icons.emoji_events_rounded;
      tone = SportikaColors.blueBright;

      facts.add((value: '${published.length}', label: 'Results'));
      facts.add((value: '${fixtures.length}', label: 'Fixtures'));

      if (leader != null) {
        facts.add((value: '${leader.points}', label: 'Leader points'));
      }

      if (published.isNotEmpty) {
        action = _spotlightAction(
          'View official results',
          Icons.arrow_forward_rounded,
          () => _changeTab(1, fixtureScope: 3),
        );
      }
    }

    return _CompetitionSpotlight(
      eyebrow: eyebrow,
      title: title,
      description: body,
      icon: icon,
      tone: tone,
      facts: facts,
      action: action,
    );
  }

  Widget _spotlightAction(String label, IconData icon, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: SportikaType.action),
      style: TextButton.styleFrom(
        foregroundColor: SportikaColors.mint,
        minimumSize: const Size(0, 44),
        padding: EdgeInsets.zero,
      ),
    );
  }

  List<Widget> _highlights({
    required List<Fixture> live,
    required List<Fixture> published,
  }) {
    if (live.isNotEmpty) {
      final running = [...live]
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      return [
        const SizedBox(height: SportikaSpacing.lg),
        _EditorialSectionHeader(
          eyebrow: 'HAPPENING NOW',
          title: 'Live matches',
          action: 'View all',
          onAction: () => _changeTab(1, fixtureScope: 1),
        ),
        for (final fixture in running.take(2))
          Padding(
            padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
            child: officialFixtureTile(context, fixture),
          ),
      ];
    }

    if (published.isNotEmpty) {
      final settled = [...published]
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

      return [
        const SizedBox(height: SportikaSpacing.lg),
        _EditorialSectionHeader(
          eyebrow: 'MATCH CENTER',
          title: 'Latest results',
          action: 'View all',
          onAction: () => _changeTab(1, fixtureScope: 3),
        ),
        for (final fixture in settled.take(2))
          Padding(
            padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
            child: officialFixtureTile(context, fixture),
          ),
      ];
    }

    return const [];
  }

  Widget _competitionCard({
    required Tournament tournament,
    required Account? organizer,
    required int confirmed,
  }) {
    final limit = tournament.registrationLimit;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(
            icon: Icons.account_tree_outlined,
            label: 'Competition format',
            value: tournament.format.label,
          ),
          if (tournament.formatLabel.trim().isNotEmpty)
            _DetailRow(
              icon: Icons.sports_outlined,
              label: 'Match format',
              value: tournament.formatLabel,
            ),
          _DetailRow(
            icon: Icons.groups_2_outlined,
            label: 'Participation',
            value: '${tournament.entryType.label} entry',
          ),
          _DetailRow(
            icon: Icons.payments_outlined,
            label: 'Entry fee',
            value: tournament.entryFee,
          ),
          _DetailRow(
            icon: Icons.how_to_reg_outlined,
            label: 'Confirmed entries',
            value: limit > 0 ? '$confirmed / $limit' : '$confirmed',
            showDivider: false,
          ),
          const SizedBox(height: SportikaSpacing.md),
          const Divider(color: SportikaColors.borderSubtle, height: 1),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            children: [
              if (organizer != null)
                AccountAvatar(account: organizer, size: 44)
              else
                const BrandedDefaultAvatar(size: 44),
              const SizedBox(width: SportikaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ORGANIZED BY', style: SportikaType.micro),
                    const SizedBox(height: 4),
                    Text(
                      organizer?.displayName ?? 'Organizer details unavailable',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.bodyStrong,
                    ),
                  ],
                ),
              ),
              if (organizer != null)
                IconAction(
                  icon: Icons.arrow_forward_rounded,
                  label: 'View organizer',
                  onPressed: () => pushRoute(
                    context,
                    AppRoute.playerProfile,
                    args: PlayerProfileArgs(organizer.id),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openResultsReview(FixturesController fixtures, Tournament tournament) {
    String? highlight;

    for (final fixture in fixtures.fixturesAwaitingReview) {
      if (fixture.tournamentId == tournament.id) {
        highlight = fixture.id;
        break;
      }
    }

    pushRoute(
      context,
      AppRoute.resultsReview,
      args: ResultsReviewArgs(
        tournamentId: tournament.id,
        highlightId: highlight,
      ),
    );
  }

  Future<void> _generateDraw(
    BuildContext context,
    TournamentsController state,
    Tournament tournament,
  ) async {
    int count;

    try {
      count = await state.generateDraw(tournament.id);
    } catch (_) {
      if (context.mounted) {
        showSnack(
          context,
          'The draw could not be published. Please try again.',
          error: true,
        );
      }
      return;
    }

    if (!context.mounted) return;

    showSnack(
      context,
      count == 0
          ? 'Confirm at least two entries before publishing a draw'
          : 'Draw published · $count fixtures created and scorers notified',
      error: count == 0,
    );
  }

  String? _champion(TournamentsController state, Tournament tournament) {
    if (tournament.format != TournamentFormat.knockout) {
      return null;
    }

    final rounds = state.roundsFor(tournament);

    if (rounds.isEmpty || rounds.last.isEmpty) {
      return null;
    }

    final match = rounds.last.last;
    final result = match.result;

    if (result == null) return null;

    if (match.status != FixtureStatus.published &&
        match.status != FixtureStatus.walkover) {
      return null;
    }

    final winner = result.winnerIndex;

    if (winner != 0 && winner != 1) {
      return null;
    }

    final labels = context.read<FixturesController>().sideLabelsOf(match);

    if (labels.length <= winner) return null;

    final name = labels[winner].trim();

    return name.isEmpty ? null : name;
  }

  Future<void> _register(BuildContext context, Tournament tournament) async {
    final state = context.read<TournamentsController>();

    if (tournament.entryType == EntryType.individual) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Register for ${tournament.name}?'),
          content: const Text(
            'Your entry goes to the organizer for confirmation. '
            'You will be notified when they decide.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Register'),
            ),
          ],
        ),
      );

      if (ok != true) return;

      await state.submitEntry(tournamentId: tournament.id);

      if (context.mounted) {
        showSnack(context, 'Entry submitted for review');
      }

      return;
    }

    final squads = context.read<TeamsController>().squadsFor(
      tournament.sport,
      tournament.entryType,
    );

    String? selected = squads.isEmpty ? null : squads.first.id;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SportikaRadius.xl),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => AppSheet(
          title: 'Register ${tournament.entryType.label.toLowerCase()}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const InfoBanner(
                icon: Icons.info_outline,
                text: 'Entries are reviewed by the organizer before they appear in the draw.',
              ),
              const SizedBox(height: 16),
              if (squads.isEmpty)
                Text(
                  'You have no '
                  '${tournament.entryType.label.toLowerCase()} '
                  'for ${tournament.sport.label} yet.',
                  style: SportikaType.caption,
                )
              else
                for (final squad in squads)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: selected == squad.id
                          ? SportikaColors.mint.withValues(alpha: 0.08)
                          : SportikaColors.surface,
                      borderRadius: BorderRadius.circular(
                        SportikaRadius.control,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          SportikaRadius.control,
                        ),
                        onTap: () {
                          setSheetState(() => selected = squad.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(
                                selected == squad.id
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: selected == squad.id
                                    ? SportikaColors.mint
                                    : SportikaColors.textDim,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      squad.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: SportikaType.bodyStrong,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      squad.memberAccountIds
                                          .map(
                                            (id) => context
                                                .read<SessionController>()
                                                .accountById(id)
                                                ?.displayName
                                                .split(' ')
                                                .first,
                                          )
                                          .whereType<String>()
                                          .join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: SportikaType.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 14),
              if (squads.isEmpty)
                GhostButton(
                  label: 'Open Teams to create one',
                  icon: Icons.groups_outlined,
                  expand: true,
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    openHomeTab(context, HomeTabIndex.teams);
                  },
                )
              else
                PrimaryButton(
                  label: 'Submit entry',
                  icon: Icons.arrow_forward_rounded,
                  tone: SportikaColors.mint,
                  onPressed: selected == null
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || selected == null) return;

    await state.submitEntry(tournamentId: tournament.id, squadId: selected);

    if (context.mounted) {
      showSnack(context, 'Entry submitted for review');
    }
  }

  Widget _unavailableBody(TournamentsController state) {
    final Widget child;

    if (_loading || state.loading) {
      child = const LoadingSkeleton(
        rows: 3,
        label: 'Loading tournament',
        rowHeight: 96,
      );
    } else if (_error != null) {
      child = ErrorState(
        title: 'Tournament did not load',
        message: _error,
        onRetry: _refresh,
      );
    } else {
      child = const EmptyState(
        title: 'Tournament not found',
        body:
            'This event may have been removed, or your account '
            'no longer has access to it.',
        icon: Icons.search_off,
      );
    }

    return Scaffold(
      appBar: sportikaAppBar('Tournament'),
      body: ClampedTextScale(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [child],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CINEMATIC TOURNAMENT HERO
// ============================================================

class _HubHeader extends StatelessWidget {
  const _HubHeader({
    required this.tournament,
    required this.confirmed,
    required this.fixtureCount,
    required this.liveCount,
  });

  final Tournament tournament;
  final int confirmed;
  final int fixtureCount;
  final int liveCount;

  @override
  Widget build(BuildContext context) {
    final limit = tournament.registrationLimit;
    final progress = limit <= 0 ? 0.0 : (confirmed / limit).clamp(0.0, 1.0);

    final tone = statusColor(tournament.status.key);
    final city = tournament.city.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(SportikaRadius.xl),
      child: Container(
        decoration: BoxDecoration(
          color: SportikaColors.surface,
          border: Border.all(color: SportikaColors.borderSubtle),
          borderRadius: BorderRadius.circular(SportikaRadius.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Existing TournamentCover supplies sport artwork.
            // A theme-based gradient creates the cinematic treatment.
            SizedBox(
              height: 218,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TournamentCover(tournament: tournament, height: 218),
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            SportikaColors.surface.withValues(alpha: 0.02),
                            SportikaColors.surface.withValues(alpha: 0.22),
                            SportikaColors.surface.withValues(alpha: 0.94),
                          ],
                          stops: const [0.0, 0.48, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 16,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SportTag(tournament.sport),
                        StatusPill(
                          tournament.status.label,
                          color: tone,
                          icon: _tournamentIcon(tournament.status),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SPORTIKA COMPETITION',
                          style: SportikaType.micro.copyWith(
                            color: SportikaColors.mint,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          tournament.name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: SportikaType.title.copyWith(
                            fontSize: 27,
                            height: 1.08,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (city.isNotEmpty)
                        _MetaLine(icon: Icons.location_on_outlined, text: city),
                      _MetaLine(
                        icon: Icons.calendar_month_outlined,
                        text:
                            '${dayLabel(tournament.startsAt)} – '
                            '${dayLabel(tournament.endsAt)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: SportikaSpacing.lg),

                  _FactStrip(
                    facts: [
                      (
                        value: limit > 0 ? '$confirmed/$limit' : '$confirmed',
                        label: 'Entries',
                      ),
                      (value: '$fixtureCount', label: 'Fixtures'),
                      (value: '$liveCount', label: 'Live now'),
                    ],
                  ),

                  if (tournament.status == TournamentStatus.open &&
                      limit > 0) ...[
                    const SizedBox(height: SportikaSpacing.lg),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'REGISTRATION CAPACITY',
                            style: SportikaType.micro,
                          ),
                        ),
                        Text(
                          '${(progress * 100).round()}%',
                          style: SportikaType.bodyStrong.copyWith(
                            color: SportikaColors.mint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Semantics(
                      label: '$confirmed of $limit places confirmed',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          SportikaRadius.badge,
                        ),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          color: SportikaColors.mint,
                          backgroundColor: SportikaColors.border,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MODERN TOURNAMENT NAVIGATION
// ============================================================

class _TournamentTabs extends StatelessWidget {
  const _TournamentTabs({
    required this.selected,
    required this.fixtureCount,
    required this.participantCount,
    required this.format,
    required this.onChanged,
  });

  final int selected;
  final int fixtureCount;
  final int participantCount;
  final TournamentFormat format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('Overview', 0, null),
      ('Fixtures', 1, fixtureCount),
      (format == TournamentFormat.group ? 'Standings' : 'Bracket', 2, null),
      ('Players', 3, participantCount),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 22),
              child: InkWell(
                onTap: () => onChanged(tab.$2),
                borderRadius: BorderRadius.circular(SportikaRadius.control),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tab.$1,
                            style: SportikaType.bodyStrong.copyWith(
                              color: selected == tab.$2
                                  ? SportikaColors.text
                                  : SportikaColors.textMuted,
                            ),
                          ),
                          if (tab.$3 != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${tab.$3}',
                              style: SportikaType.micro.copyWith(
                                color: selected == tab.$2
                                    ? SportikaColors.mint
                                    : SportikaColors.textDim,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 3,
                      width: selected == tab.$2 ? 42 : 0,
                      decoration: BoxDecoration(
                        color: SportikaColors.mint,
                        borderRadius: BorderRadius.circular(
                          SportikaRadius.badge,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// COMPETITION SPOTLIGHT
// ============================================================

class _CompetitionSpotlight extends StatelessWidget {
  const _CompetitionSpotlight({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.tone,
    required this.facts,
    this.action,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Color tone;
  final List<({String value, String label})> facts;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tone.withValues(alpha: 0.12),
            SportikaColors.surfaceElevated,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(SportikaRadius.control),
                ),
                child: Icon(icon, color: tone, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  eyebrow,
                  style: SportikaType.micro.copyWith(
                    color: tone,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: SportikaType.title.copyWith(fontSize: 23, height: 1.12),
          ),
          const SizedBox(height: 9),
          Text(description, style: SportikaType.body),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(color: SportikaColors.borderSubtle, height: 1),
            const SizedBox(height: 18),
            _FactStrip(facts: facts),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

// ============================================================
// EDITORIAL SECTION HEADING
// ============================================================

class _EditorialSectionHeader extends StatelessWidget {
  const _EditorialSectionHeader({
    required this.eyebrow,
    required this.title,
    this.action,
    this.onAction,
  });

  final String eyebrow;
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: SportikaType.micro.copyWith(
                    color: SportikaColors.mint,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(title, style: SportikaType.title),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                action!,
                style: SportikaType.action.copyWith(
                  color: SportikaColors.blueBright,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// EDITORIAL METRICS
// ============================================================

class _FactStrip extends StatelessWidget {
  const _FactStrip({required this.facts});

  final List<({String value, String label})> facts;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < facts.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: SportikaColors.borderSubtle,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  facts[i].value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.scoreSmall.copyWith(fontSize: 23),
                ),
                const SizedBox(height: 5),
                Text(
                  facts[i].label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.micro,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// METADATA
// ============================================================

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: SportikaColors.textMuted),
        const SizedBox(width: 6),
        Text(text, style: SportikaType.caption),
      ],
    );
  }
}

// ============================================================
// COMPETITION DETAILS
// ============================================================

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 19, color: SportikaColors.textMuted),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: SportikaType.caption)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: SportikaType.bodyStrong,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(color: SportikaColors.borderSubtle, height: 1),
      ],
    );
  }
}

// ============================================================
// EXPANDABLE RULES
// ============================================================

class _RulesPanel extends StatefulWidget {
  const _RulesPanel({required this.tournament});

  final Tournament tournament;

  @override
  State<_RulesPanel> createState() => _RulesPanelState();
}

class _RulesPanelState extends State<_RulesPanel> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final rules = widget.tournament.matchRules.trim();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() => expanded = !expanded);
            },
            child: Row(
              children: [
                const Icon(
                  Icons.gavel_outlined,
                  color: SportikaColors.mint,
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Rules & regulations',
                    style: SportikaType.bodyStrong,
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                rules.isEmpty
                    ? 'The organizer has not supplied match rules yet.'
                    : rules,
                style: SportikaType.body,
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PARTICIPATION TICKET
// ============================================================

class _MyEntryCard extends StatelessWidget {
  const _MyEntryCard({required this.entry, required this.tournament});

  final Entry entry;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final state = context.read<TournamentsController>();
    final tone = statusColor(entry.status.key);
    final note = entry.decisionNote;

    final canWithdraw =
        entry.status == EntryStatus.pending ||
        (entry.status == EntryStatus.confirmed &&
            tournament.status == TournamentStatus.open);

    return SurfaceCard(
      borderColor: tone.withValues(alpha: 0.30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SportikaRadius.control),
                ),
                child: Icon(Icons.confirmation_number_outlined, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('YOUR PARTICIPATION', style: SportikaType.micro),
                    const SizedBox(height: 4),
                    Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.bodyStrong,
                    ),
                  ],
                ),
              ),
              StatusPill(
                entry.status.label,
                color: tone,
                icon: statusIcon(entry.status.key),
              ),
            ],
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(note, style: SportikaType.caption),
          ],
          if (canWithdraw) ...[
            const SizedBox(height: 14),
            GhostButton(
              label: 'Withdraw entry',
              icon: Icons.logout_rounded,
              tone: SportikaColors.danger,
              expand: true,
              onPressed: () async {
                try {
                  await state.withdrawEntry(entry.id);

                  if (context.mounted) {
                    showSnack(context, 'Entry withdrawn');
                  }
                } catch (_) {
                  if (context.mounted) {
                    showSnack(
                      context,
                      'Your entry could not be withdrawn. Please try again.',
                      error: true,
                    );
                  }
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// FIXTURE FILTERS
// ============================================================

class _FixtureFilters extends StatelessWidget {
  const _FixtureFilters({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final filters = [('All', 0), ('Live', 1), ('Upcoming', 2), ('Results', 3)];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter.$1),
                selected: selected == filter.$2,
                onSelected: (_) => onChanged(filter.$2),
                selectedColor: SportikaColors.mint.withValues(alpha: 0.16),
                backgroundColor: SportikaColors.surface,
                side: BorderSide(
                  color: selected == filter.$2
                      ? SportikaColors.mint
                      : SportikaColors.borderSubtle,
                ),
                labelStyle: SportikaType.caption.copyWith(
                  color: selected == filter.$2
                      ? SportikaColors.mint
                      : SportikaColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// ORGANIZER WORKSPACE
// ============================================================

class _OrganizerWorkspace extends StatelessWidget {
  const _OrganizerWorkspace({
    required this.fixtures,
    required this.pending,
    required this.review,
    required this.onOpenResults,
    required this.onPublishDraw,
    required this.onOpenEntries,
    required this.onOpenFixtures,
  });

  final List<Fixture> fixtures;
  final int pending;
  final int review;

  final VoidCallback onOpenResults;
  final VoidCallback onPublishDraw;
  final VoidCallback onOpenEntries;
  final VoidCallback onOpenFixtures;

  @override
  Widget build(BuildContext context) {
    final drawPending = fixtures.isEmpty;

    return SurfaceCard(
      borderColor: SportikaColors.blueBright.withValues(alpha: 0.30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                color: SportikaColors.blueBright,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Competition management',
                  style: SportikaType.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _FactStrip(
            facts: [
              (value: '$pending', label: 'To review'),
              (value: '$review', label: 'To publish'),
              (value: '${fixtures.length}', label: 'Fixtures'),
            ],
          ),
          const SizedBox(height: 20),
          if (drawPending) ...[
            PrimaryButton(
              label: 'Publish draw & fixtures',
              icon: Icons.account_tree_outlined,
              tone: SportikaColors.mint,
              onPressed: onPublishDraw,
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'Manage entries',
              icon: Icons.people_outline,
              expand: true,
              onPressed: onOpenEntries,
            ),
          ] else ...[
            PrimaryButton(
              label: review > 0 ? 'Review results · $review' : 'Review results',
              icon: Icons.fact_check_outlined,
              tone: SportikaColors.mint,
              onPressed: onOpenResults,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'Entries',
                    icon: Icons.people_outline,
                    expand: true,
                    onPressed: onOpenEntries,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton(
                    label: 'Fixtures',
                    icon: Icons.account_tree_outlined,
                    expand: true,
                    onPressed: onOpenFixtures,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

IconData _tournamentIcon(TournamentStatus status) => switch (status) {
  TournamentStatus.draft => Icons.edit_note_outlined,
  TournamentStatus.open => Icons.how_to_reg_outlined,
  TournamentStatus.inProgress => Icons.sensors_rounded,
  TournamentStatus.completed => Icons.emoji_events_outlined,
};
