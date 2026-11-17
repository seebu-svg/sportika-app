import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/discover/screens/tournament_sections.dart';
import 'package:sportika/features/discover/widgets/tournament_cover.dart';
import 'package:sportika/features/monetization/widgets/billing_widgets.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The tournament hub.
///
/// One identity block, one participation strip that only appears when it means
/// something, four sections of competition content, and a single organizer
/// workspace at the end of Overview. Participant-facing content never sits
/// behind organizer chrome, and nothing here infers data the controllers did not
/// return.
class TournamentDetailScreen extends StatefulWidget {
  const TournamentDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

/// Owner-only lifecycle actions that belong to the app bar, not to a section.
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
    final state = context.read<TournamentsController>();
    final fixtures = context.read<FixturesController>();
    try {
      // Entries, the draw and the fixture results are all read again, so one
      // gesture leaves every section consistent.
      await Future.wait([state.refresh(), fixtures.refresh()]);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              state.lastError ??
              fixtures.lastError ??
              'This tournament could not be refreshed.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    final tournament = state.tournamentById(widget.id);
    if (tournament == null) return _unavailableBody(state);

    final session = context.watch<SessionController>();
    final me = session.currentAccount;
    final isOwner = me != null && tournament.organizerId == me.id;
    final fixturesState = context.watch<FixturesController>();
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
        'Tournament',
        subtitle: '${tournament.sport.label} · ${tournament.format.label}',
        actions: [
          if (isOwner)
            PopupMenuButton<_OwnerAction>(
              icon: const Icon(Icons.more_vert),
              color: SportikaColors.surfaceElevated,
              tooltip: 'Tournament settings',
              onSelected: (action) {
                switch (action) {
                  case _OwnerAction.openRegistration:
                    state.setTournamentStatus(
                      tournament.id,
                      TournamentStatus.open,
                    );
                    showSnack(context, 'Registration is open');
                  case _OwnerAction.markCompleted:
                    state.setTournamentStatus(
                      tournament.id,
                      TournamentStatus.completed,
                    );
                    showSnack(context, 'Tournament marked completed');
                }
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
                  padding: EdgeInsets.fromLTRB(inset, 10, inset, 36),
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
                    _HubHeader(
                      tournament: tournament,
                      confirmed: confirmed,
                      showProgress:
                          tournament.status == TournamentStatus.open &&
                          tournament.registrationLimit > 0,
                    ),
                    if (myEntry != null) ...[
                      const SizedBox(height: 10),
                      _MyEntryCard(entry: myEntry, tournament: tournament),
                    ] else if (canRegister) ...[
                      const SizedBox(height: 10),
                      PrimaryButton(
                        label: 'Register for this tournament',
                        icon: Icons.how_to_reg_outlined,
                        tone: SportikaColors.mint,
                        busy: _busy,
                        onPressed: () =>
                            _run(() => _register(context, tournament)),
                      ),
                    ] else if (tournament.status == TournamentStatus.open) ...[
                      const SizedBox(height: 10),
                      const InfoBanner(
                        icon: Icons.group_off_outlined,
                        tone: SportikaColors.gold,
                        text: 'Registration is full for this event.',
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilterChipRow<int>(
                      label: 'Tournament details',
                      selected: _tab,
                      onChanged: (value) => setState(() => _tab = value),
                      choices: [
                        const FilterChoice(0, 'Overview'),
                        FilterChoice(1, 'Fixtures', badge: fixtures.length),
                        FilterChoice(
                          2,
                          tournament.format == TournamentFormat.group
                              ? 'Standings'
                              : 'Bracket',
                        ),
                        FilterChoice(3, 'Participants', badge: confirmed),
                      ],
                    ),
                    const SizedBox(height: 14),
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
                      const SectionHeader('Competition'),
                      _competitionCard(
                        tournament: tournament,
                        organizer: organizer,
                        confirmed: confirmed,
                      ),
                      const SectionHeader('Rules'),
                      _rulesCard(tournament),
                      if (isOwner) ...[
                        const SectionHeader('Organizer workspace'),
                        _OrganizerWorkspace(
                          tournament: tournament,
                          fixtures: fixtures,
                          pending: pending,
                          review: review,
                          onOpenResults: () =>
                              _openResultsReview(fixturesState, tournament),
                          onPublishDraw: () =>
                              _generateDraw(context, state, tournament),
                          onOpenEntries: () => setState(() => _tab = 3),
                          onOpenFixtures: () => setState(() => _tab = 1),
                        ),
                        const SizedBox(height: 10),
                        TournamentPremiumCard(tournamentId: tournament.id),
                      ],
                    ],
                    if (_tab == 1) ...[
                      FilterChipRow<int>(
                        label: 'Fixture status',
                        selected: _fixtureScope,
                        onChanged: (value) =>
                            setState(() => _fixtureScope = value),
                        choices: const [
                          FilterChoice(0, 'All fixtures'),
                          FilterChoice(1, 'Live now'),
                          FilterChoice(2, 'Upcoming'),
                          FilterChoice(3, 'Official results'),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                    if (_tab == 2) TournamentBracket(tournament: tournament),
                    if (_tab == 3)
                      TournamentEntriesSection(
                        tournament: tournament,
                        canManage: isOwner,
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

  /// What a member should read first, derived only from the recorded status,
  /// entry counts and fixture rows.
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

    late final String title;
    late final String body;
    late final IconData icon;
    late final Color tone;
    final facts = <({String value, String label})>[];
    Widget? action;

    if (tournament.status == TournamentStatus.draft) {
      title = 'Draft event';
      body =
          'Registration opens once the organizer publishes this competition. '
          'Fixtures and results appear after the draw.';
      icon = Icons.edit_note_outlined;
      tone = SportikaColors.textMuted;
      facts.add((value: '$confirmed', label: 'Confirmed'));
    } else if (tournament.status == TournamentStatus.open) {
      title = fixtures.isEmpty
          ? 'Registration open · draw pending'
          : 'Registration open · scheduled';
      body = fixtures.isEmpty
          ? (limit > 0
                ? '$confirmed of $limit places confirmed. The draw appears once '
                      'enough entries are confirmed.'
                : '$confirmed entries confirmed. The draw appears once the '
                      'organizer publishes it.')
          : '${fixtures.length} fixtures scheduled'
                '${next == null ? '' : ' · next ${dayLabel(next.scheduledAt)}'}';
      icon = Icons.how_to_reg_outlined;
      tone = SportikaColors.mint;
      facts.add((value: '$confirmed', label: 'Confirmed'));
      facts.add((value: '${fixtures.length}', label: 'Fixtures'));
      if (fixtures.isNotEmpty) {
        action = _link(
          'View fixtures',
          Icons.calendar_month_outlined,
          () => setState(() {
            _tab = 1;
            _fixtureScope = 2;
          }),
        );
      }
    } else if (tournament.status == TournamentStatus.inProgress) {
      final champion = _champion(state, tournament);
      title = live.isNotEmpty
          ? '${live.length} ${live.length == 1 ? 'match' : 'matches'} live now'
          : 'In progress';
      body = <String>[
        if (champion != null) '$champion won the final',
        if (champion == null && next != null)
          'Next: ${next.stage} · ${dayLabel(next.scheduledAt)}',
        if (published.isNotEmpty)
          '${published.length} official '
              '${published.length == 1 ? 'result' : 'results'} published'
        else
          'Results appear as organizers publish them',
      ].join(' · ');
      icon = Icons.sensors_rounded;
      tone = SportikaColors.gold;
      facts.add((value: '${live.length}', label: 'Live'));
      facts.add((value: '${published.length}', label: 'Published'));
      facts.add((value: '$remaining', label: 'Remaining'));
      action = _link(
        live.isNotEmpty ? 'Watch live matches' : 'View fixtures',
        Icons.sports_outlined,
        () => setState(() {
          _tab = 1;
          _fixtureScope = live.isNotEmpty ? 1 : 0;
        }),
      );
    } else {
      final champion = _champion(state, tournament);
      // A knockout has no points table, so its placement only comes from the
      // published final.
      final standings = state.standingsFor(tournament);
      final leader =
          tournament.format == TournamentFormat.group && standings.isNotEmpty
          ? standings.first
          : null;
      title = champion != null
          ? 'Champion · $champion'
          : leader != null
          ? 'Table leader · ${leader.label}'
          : 'Competition complete';
      body = fixtures.isEmpty
          ? 'No draw or results were recorded for this event.'
          : published.isEmpty
          ? 'No result was published for this event.'
          : '${published.length} of ${fixtures.length} fixtures carry an '
                'official result.';
      icon = Icons.emoji_events_outlined;
      tone = SportikaColors.blueBright;
      facts.add((value: '${published.length}', label: 'Published'));
      facts.add((value: '${fixtures.length}', label: 'Fixtures'));
      if (leader != null) {
        facts.add((value: '${leader.points}', label: 'Leader pts'));
      }
      if (published.isNotEmpty) {
        action = _link(
          'View official results',
          Icons.fact_check_outlined,
          () => setState(() {
            _tab = 1;
            _fixtureScope = 3;
          }),
        );
      }
    }

    return SurfaceCard(
      borderColor: tone.withValues(alpha: 0.36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: tone.withValues(alpha: 0.32)),
                ),
                child: Icon(icon, size: 16, color: tone),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.xs + 2),
          Text(body, style: SportikaType.caption),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.md),
            _FactStrip(facts: facts),
          ],
          if (action != null) ...[const SizedBox(height: 2), action],
        ],
      ),
    );
  }

  /// The two fixtures worth surfacing above the fold: what is running, or what
  /// has just been settled.
  List<Widget> _highlights({
    required List<Fixture> live,
    required List<Fixture> published,
  }) {
    if (live.isNotEmpty) {
      final running = [...live]
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      return [
        SectionHeader(
          'Live now',
          action: 'All fixtures',
          onAction: () => setState(() {
            _tab = 1;
            _fixtureScope = 1;
          }),
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
        SectionHeader(
          'Latest results',
          action: 'All results',
          onAction: () => setState(() {
            _tab = 1;
            _fixtureScope = 3;
          }),
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
          KeyValueRow('Competition', tournament.format.label),
          if (tournament.formatLabel.trim().isNotEmpty)
            KeyValueRow('Match format', tournament.formatLabel),
          KeyValueRow('Participation', '${tournament.entryType.label} entry'),
          KeyValueRow('Entry fee', tournament.entryFee),
          KeyValueRow(
            'Confirmed entries',
            limit > 0 ? '$confirmed of $limit' : '$confirmed',
          ),
          const SizedBox(height: SportikaSpacing.sm),
          const Divider(color: SportikaColors.borderSubtle, height: 1),
          const SizedBox(height: SportikaSpacing.sm + 2),
          Row(
            children: [
              if (organizer != null)
                AccountAvatar(account: organizer, size: 36)
              else
                const Icon(
                  Icons.person_outline,
                  size: 30,
                  color: SportikaColors.textMuted,
                ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ORGANIZED BY', style: SportikaType.micro),
                    const SizedBox(height: 2),
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
                  icon: Icons.chevron_right_rounded,
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

  Widget _rulesCard(Tournament tournament) {
    return SurfaceCard(
      child: Text(
        tournament.matchRules.trim().isEmpty
            ? 'The organizer has not supplied match rules yet.'
            : tournament.matchRules,
        style: SportikaType.body,
      ),
    );
  }

  /// Inline text action with a full-height touch target.
  Widget _link(String label, IconData icon, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: SportikaType.action),
      style: TextButton.styleFrom(
        foregroundColor: SportikaColors.blueBright,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 4),
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

  /// The winning side of the final - only when an official result exists.
  String? _champion(TournamentsController state, Tournament tournament) {
    if (tournament.format != TournamentFormat.knockout) return null;
    final rounds = state.roundsFor(tournament);
    if (rounds.isEmpty || rounds.last.isEmpty) return null;
    final match = rounds.last.last;
    final result = match.result;
    if (result == null) return null;
    if (match.status != FixtureStatus.published &&
        match.status != FixtureStatus.walkover) {
      return null;
    }
    final winner = result.winnerIndex;
    if (winner != 0 && winner != 1) return null;
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
            'Your entry goes to the organizer for confirmation. You will be notified '
            'when they decide.',
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
      if (context.mounted) showSnack(context, 'Entry submitted for review');
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
              const SizedBox(height: 12),
              if (squads.isEmpty)
                Text(
                  'You have no ${tournament.entryType.label.toLowerCase()} for '
                  '${tournament.sport.label} yet.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: SportikaColors.textMuted,
                  ),
                )
              else
                for (final squad in squads)
                  InkWell(
                    onTap: () => setSheetState(() => selected = squad.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            selected == squad.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: selected == squad.id
                                ? SportikaColors.mint
                                : SportikaColors.textDim,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  squad.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: SportikaColors.text,
                                  ),
                                ),
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
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: SportikaColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                    openHomeTab(context, 3);
                  },
                )
              else
                PrimaryButton(
                  label: 'Submit entry',
                  icon: Icons.send_rounded,
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
    if (context.mounted) showSnack(context, 'Entry submitted for review');
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
            'This event may have been removed, or your account no longer has '
            'access to it.',
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

/// The only identity block on the page: one cover, the recorded status, the
/// name, where and when it runs, and - while registration is actually open -
/// how full it is.
class _HubHeader extends StatelessWidget {
  const _HubHeader({
    required this.tournament,
    required this.confirmed,
    required this.showProgress,
  });

  final Tournament tournament;
  final int confirmed;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final limit = tournament.registrationLimit;
    final tone = statusColor(tournament.status.key);
    final progress = limit <= 0 ? 0.0 : (confirmed / limit).clamp(0.0, 1.0);
    final city = tournament.city.trim();

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TournamentCover(tournament: tournament, height: 148),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    SportTag(tournament.sport),
                    StatusPill(
                      tournament.status.label,
                      color: tone,
                      icon: _tournamentIcon(tournament.status),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  tournament.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.title,
                ),
                const SizedBox(height: 8),
                if (city.isNotEmpty) ...[
                  _MetaLine(icon: Icons.place_outlined, text: city),
                  const SizedBox(height: 4),
                ],
                _MetaLine(
                  icon: Icons.event_outlined,
                  text:
                      '${dayLabel(tournament.startsAt)} – '
                      '${dayLabel(tournament.endsAt)}',
                ),
                if (showProgress) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    label:
                        '$confirmed of $limit places confirmed for '
                        '${tournament.name}',
                    excludeSemantics: true,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      color: SportikaColors.mint,
                      backgroundColor: SportikaColors.border,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$confirmed of $limit confirmed',
                          style: SportikaType.caption,
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: SportikaType.micro.copyWith(
                          color: SportikaColors.mint,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: SportikaColors.textDim),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.caption,
          ),
        ),
      ],
    );
  }
}

/// A row of recorded numbers separated by hairlines rather than nested cards.
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
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: SportikaColors.borderSubtle,
            ),
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    facts[i].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.scoreSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    facts[i].label.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.micro,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

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
      borderColor: tone.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your entry · ${entry.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong,
                ),
              ),
              const SizedBox(width: SportikaSpacing.xs),
              StatusPill(
                entry.status.label,
                color: tone,
                icon: statusIcon(entry.status.key),
              ),
            ],
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note, style: SportikaType.caption),
          ],
          if (canWithdraw) ...[
            const SizedBox(height: SportikaSpacing.sm),
            GhostButton(
              label: 'Withdraw entry',
              icon: Icons.logout,
              tone: SportikaColors.danger,
              expand: true,
              onPressed: () async {
                try {
                  await state.withdrawEntry(entry.id);
                  if (context.mounted) showSnack(context, 'Entry withdrawn');
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

/// The one management surface an organizer gets on this page.
class _OrganizerWorkspace extends StatelessWidget {
  const _OrganizerWorkspace({
    required this.tournament,
    required this.fixtures,
    required this.pending,
    required this.review,
    required this.onOpenResults,
    required this.onPublishDraw,
    required this.onOpenEntries,
    required this.onOpenFixtures,
  });

  final Tournament tournament;
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
      borderColor: SportikaColors.blueBright.withValues(alpha: 0.32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FactStrip(
            facts: [
              (value: '$pending', label: 'To review'),
              (value: '$review', label: 'To publish'),
              (value: '${fixtures.length}', label: 'Fixtures'),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          if (drawPending) ...[
            PrimaryButton(
              label: 'Publish draw & fixtures',
              icon: Icons.account_tree_outlined,
              small: true,
              tone: SportikaColors.mint,
              onPressed: onPublishDraw,
            ),
            const SizedBox(height: 8),
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
              small: true,
              tone: SportikaColors.mint,
              onPressed: onOpenResults,
            ),
            const SizedBox(height: 8),
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
                    label: 'Draw & fixtures',
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
