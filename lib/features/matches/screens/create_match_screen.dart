import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/widgets/match_vs_card.dart';
import 'package:sportika/features/matches/widgets/futsal_match_setup.dart';
import 'package:sportika/features/matches/scoring/match_scoring_shell.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Creates a standalone official match, or a tournament-linked match when
/// [tournamentId] and [fixtureId] are supplied (e.g. from a fixture workspace).
class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({super.key, this.tournamentId, this.fixtureId});

  final String? tournamentId;
  final String? fixtureId;

  bool get _isTournament => tournamentId != null && fixtureId != null;

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  final _title = TextEditingController();
  final _venue = TextEditingController();
  final _sideA = TextEditingController();
  final _sideB = TextEditingController();

  Sport _sport = Sport.cricket;
  late String _format = SportEngines.formatsFor(_sport).first;
  late MatchDiscipline _discipline = MatchDisciplineX.forSport(_sport).last;
  MatchVisibility _visibility = MatchVisibility.public;
  late DateTime _scheduledAt = _defaultStart();
  late int _capacity = _defaultCapacity(_sport);
  String? _scorerId;
  String? _scorerName;
  Map<String, dynamic> _futsal = {};
  int _customOvers = 20;
  int _firstServer = 0;
  int _badmintonTarget = 21;
  final List<List<ProfileSummary>> _badmintonPlayers = [[], []];
  Map<String, dynamic>? _fixtureRules;
  bool _initialized = false;
  bool _busy = false;
  String? _error;

  static DateTime _defaultStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 18);
  }

  static int _defaultCapacity(Sport sport) => switch (sport) {
    Sport.cricket => 22,
    Sport.futsal => 10,
    Sport.padel => 4,
    Sport.badminton => 2,
  };

  Map<String, dynamic> get _rules => {
    ...(_fixtureRules ?? SportEngines.rulesFor(_sport, _format)),
    ..._futsal,
    if (_sport == Sport.badminton) ...{
      'discipline': _discipline.key,
      if (!widget._isTournament) ...{
        'firstServer': _firstServer,
        'pointsToWinGame': _badmintonTarget,
        'cap': _badmintonTarget == 21 ? 30 : _badmintonTarget + 9,
      },
    },
    if (_sport == Sport.cricket &&
        _format == 'Custom overs' &&
        !widget._isTournament)
      'oversPerInnings': _customOvers,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (!widget._isTournament) return;
    final fixtures = context.read<FixturesController>();
    final fixture = fixtures.fixtureById(widget.fixtureId!);
    final tournaments = context.read<TournamentsController>();
    final tournament = tournaments.tournamentById(widget.tournamentId!);
    if (fixture == null || tournament == null) return;
    _sport = tournament.sport;
    _discipline = MatchDisciplineX.forSport(_sport).last;
    _capacity = _defaultCapacity(_sport);
    _format = tournament.matchRules.isNotEmpty
        ? tournament.matchRules
        : SportEngines.formatsFor(_sport).first;
    _fixtureRules = fixture.rules.isNotEmpty ? fixture.rules : tournament.rules;
    if (_sport == Sport.badminton) {
      _discipline = MatchDisciplineX.fromKey(
        (_fixtureRules?['discipline'] ?? 'doubles') as String,
      );
      _capacity = _discipline == MatchDiscipline.singles ? 2 : 4;
    }
    _title.text = '${tournament.name} · ${fixture.stage}'.substring(
      0,
      ('${tournament.name} · ${fixture.stage}').length.clamp(0, 80),
    );
    _sideA.text = fixtures.sideLabel(fixture, 0);
    _sideB.text = fixtures.sideLabel(fixture, 1);
    _venue.text = fixture.venue;
    _scheduledAt = fixture.scheduledAt;
    _scorerId = fixture.scorerAccountIds.firstOrNull;
    _scorerName = context
        .read<SessionController>()
        .accountById(_scorerId)
        ?.displayName;
    final entries = [
      tournaments.entriesById[fixture.home.entryId],
      tournaments.entriesById[fixture.away.entryId],
    ];
    _futsal = {
      'competitionName': tournament.name,
      'stage': fixture.stage,
      'teamIds': [for (final entry in entries) entry?.squadId],
      'rosters': [
        for (final entry in entries) entry?.memberAccountIds ?? <String>[],
      ],
    };
    final count = entries.fold<int>(
      0,
      (n, e) => n + (e?.memberAccountIds.length ?? 0),
    );
    if (count > _capacity) _capacity = count;
  }

  @override
  void dispose() {
    _title.dispose();
    _venue.dispose();
    _sideA.dispose();
    _sideB.dispose();
    super.dispose();
  }

  void _selectSport(Sport sport) {
    setState(() {
      _futsal = {};
      _sport = sport;
      _format = SportEngines.formatsFor(sport).first;
      _discipline = MatchDisciplineX.forSport(sport).last;
      _capacity = sport == Sport.badminton ? 4 : _defaultCapacity(sport);
      for (final players in _badmintonPlayers) {
        players.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionController>().currentAccount;
    final sides = MatchDisciplineX.forSport(_sport);

    return ScreenScaffold(
      title: widget._isTournament ? 'Tournament match' : 'Create match',
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(
            color: SportikaColors.deepest,
            border: Border(top: BorderSide(color: SportikaColors.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                InlineBanner(text: _error!, tone: SportikaColors.danger),
                const SizedBox(height: 8),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: sportikaMaxContentWidth,
                ),
                child: PrimaryButton(
                  label: 'Create match',
                  icon: Icons.arrow_forward_rounded,
                  busy: _busy,
                  onPressed: _busy ? null : _create,
                ),
              ),
            ],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget._isTournament)
            const Padding(
              padding: EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: InfoBanner(
                text:
                    'This match is linked to a tournament fixture. '
                    'The organizer assignment will be claimed automatically.',
                tone: SportikaColors.gold,
                icon: Icons.emoji_events_outlined,
              ),
            ),
          _CreationHero(tone: sportColor(_sport)),
          const SizedBox(height: SportikaSpacing.lg),
          _CreationSection(
            number: '01',
            title: 'Choose your game',
            subtitle: 'Set the sport and the rules of play.',
            children: [
              const Text('SPORT', style: SportikaType.label),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 480 ? 4 : 2;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 10) / columns;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final sport in Sport.values)
                        SizedBox(
                          width: width,
                          child: _SportTile(
                            sport: sport,
                            selected: sport == _sport,
                            onTap: _busy || widget._isTournament
                                ? null
                                : () => _selectSport(sport),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: SportikaSpacing.lg),
              const Text('FORMAT', style: SportikaType.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final format in [
                    ...SportEngines.formatsFor(_sport),
                    if (_sport == Sport.cricket) 'Custom overs',
                  ])
                    _Chip(
                      label: format,
                      active: format == _format,
                      tone: sportColor(_sport),
                      onTap: _busy || widget._isTournament
                          ? null
                          : () => setState(() {
                              _format = format;
                              if (_sport == Sport.badminton &&
                                  (format.contains('Singles') ||
                                      format.contains('Doubles'))) {
                                _discipline = format.contains('Singles')
                                    ? MatchDiscipline.singles
                                    : MatchDiscipline.doubles;
                                _capacity =
                                    _discipline == MatchDiscipline.singles
                                    ? 2
                                    : 4;
                                for (final players in _badmintonPlayers) {
                                  players.clear();
                                }
                              }
                            }),
                    ),
                ],
              ),
              if (_sport == Sport.cricket &&
                  _format == 'Custom overs' &&
                  !widget._isTournament)
                DropdownButtonFormField<int>(
                  initialValue: _customOvers,
                  decoration: const InputDecoration(
                    labelText: 'Overs per innings',
                  ),
                  items: [
                    for (var n = 1; n <= 50; n++)
                      DropdownMenuItem(value: n, child: Text('$n overs')),
                  ],
                  onChanged: _busy
                      ? null
                      : (n) => setState(() => _customOvers = n ?? 20),
                ),
              const SizedBox(height: SportikaSpacing.lg),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          _CreationSection(
            number: '02',
            title: 'Make it yours',
            subtitle: 'Name the occasion and bring both sides together.',
            children: [
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.words,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Match title',
                  hintText: 'e.g. Clifton T10 Night Cup',
                  counterText: '',
                ),
              ),
              const SizedBox(height: SportikaSpacing.md),
              TextField(
                controller: _venue,
                textCapitalization: TextCapitalization.words,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Venue',
                  hintText: 'e.g. Clifton Beach Ground',
                  counterText: '',
                ),
              ),
              const SizedBox(height: SportikaSpacing.lg),
              if ((_sport == Sport.futsal || _sport == Sport.cricket) &&
                  !widget._isTournament)
                FutsalMatchSetup(
                  key: ValueKey(_sport),
                  sport: _sport,
                  onChanged: (settings) => setState(() {
                    _futsal = settings;
                    final names = settings['teamNames'] as List;
                    if (names[0] != null) _sideA.text = names[0] as String;
                    if (names[1] != null) _sideB.text = names[1] as String;
                    final rosters = settings['rosters'] as List;
                    final count = rosters.fold<int>(
                      0,
                      (n, r) => n + (r as List).length,
                    );
                    if (count > _capacity) _capacity = count;
                  }),
                ),
              const SizedBox(height: SportikaSpacing.md),
              const Text('SIDES', style: SportikaType.label),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sideA,
                      readOnly:
                          widget._isTournament ||
                          (_futsal['teamIds'] is List &&
                              (_futsal['teamIds'] as List)[0] != null),
                      textCapitalization: TextCapitalization.words,
                      maxLength: 40,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Side A',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _sideB,
                      readOnly:
                          widget._isTournament ||
                          (_futsal['teamIds'] is List &&
                              (_futsal['teamIds'] as List)[1] != null),
                      textCapitalization: TextCapitalization.words,
                      maxLength: 40,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Side B',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              if (sides.length > 1) ...[
                const SizedBox(height: SportikaSpacing.md),
                const Text('DISCIPLINE', style: SportikaType.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final discipline in sides)
                      _Chip(
                        label: discipline.label,
                        active: discipline == _discipline,
                        tone: sportColor(_sport),
                        onTap: _busy || widget._isTournament
                            ? null
                            : () => setState(() {
                                _discipline = discipline;
                                if (_sport == Sport.badminton &&
                                    (_format.contains('Singles') ||
                                        _format.contains('Doubles'))) {
                                  _format = '${discipline.label} · best of 3';
                                }
                                _capacity = _sport == Sport.badminton
                                    ? (discipline == MatchDiscipline.singles
                                          ? 2
                                          : 4)
                                    : _defaultCapacity(_sport);
                                if (_sport == Sport.badminton) {
                                  for (final players in _badmintonPlayers) {
                                    players.clear();
                                  }
                                }
                              }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: SportikaSpacing.lg),
              if (_sport == Sport.badminton && !widget._isTournament) ...[
                const SectionTitle(
                  'Players & first service',
                  padding: EdgeInsets.zero,
                ),
                const HelperText(
                  'You occupy the first place on side A. Selected members receive invitations and must accept. Confirm the toss before creating the match.',
                ),
                for (var side = 0; side < 2; side++) ...[
                  Text(
                    'Side ${side == 0 ? 'A' : 'B'}',
                    style: SportikaType.bodyStrong,
                  ),
                  for (final player in _badmintonPlayers[side])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(player.label),
                      trailing: IconButton(
                        tooltip: 'Remove player',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(
                          () => _badmintonPlayers[side].remove(player),
                        ),
                      ),
                    ),
                  if (_badmintonPlayers[side].length <
                      (_discipline == MatchDiscipline.singles ? 1 : 2) -
                          (side == 0 ? 1 : 0))
                    GhostButton(
                      label: side == 0 ? 'Select partner' : 'Select opponent',
                      onPressed: _busy
                          ? null
                          : () => _pickBadmintonPlayer(side),
                    ),
                ],
                DropdownButtonFormField<int>(
                  initialValue: _firstServer,
                  decoration: const InputDecoration(
                    labelText: 'Toss confirmed · initial serving side',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 0,
                      child: Text('Side A serves · right court'),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text('Side B serves · right court'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _firstServer = value ?? 0),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _badmintonTarget,
                  decoration: const InputDecoration(
                    labelText: 'Points per game · win by two',
                  ),
                  items: [
                    for (final points in [11, 15, 21])
                      DropdownMenuItem(
                        value: points,
                        child: Text('$points points · cap ${points + 9}'),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _badmintonTarget = value ?? 21),
                ),
                HelperText(SportEngines.describeRules(_sport, _rules)),
                const SizedBox(height: SportikaSpacing.lg),
              ],
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          _CreationSection(
            number: '03',
            title: 'Matchday essentials',
            subtitle: 'Set the time, access and official scorer.',
            children: [
              const Text('SCHEDULE', style: SportikaType.label),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: _busy ? null : _pickSchedule,
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 18,
                      color: SportikaColors.blueBright,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dateShort(_scheduledAt),
                        style: SportikaType.bodyStrong,
                      ),
                    ),
                    const Text('Change', style: SportikaType.action),
                  ],
                ),
              ),
              const SizedBox(height: SportikaSpacing.lg),
              const Text('CAPACITY', style: SportikaType.label),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$_capacity players',
                        style: SportikaType.bodyStrong,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fewer places',
                      onPressed:
                          _busy || _sport == Sport.badminton || _capacity <= 2
                          ? null
                          : () => setState(() => _capacity -= 1),
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                    ),
                    IconButton(
                      tooltip: 'More places',
                      onPressed:
                          _busy || _sport == Sport.badminton || _capacity >= 100
                          ? null
                          : () => setState(() => _capacity += 1),
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SportikaSpacing.lg),
              const Text('WHO CAN SEE IT', style: SportikaType.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final visibility in MatchVisibility.values)
                    _Chip(
                      label: visibility.label,
                      active: visibility == _visibility,
                      tone: SportikaColors.blueBright,
                      onTap: _busy
                          ? null
                          : () => setState(() => _visibility = visibility),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              HelperText(_visibility.helper),
              const SizedBox(height: SportikaSpacing.lg),
              const Text('OFFICIAL SCORER', style: SportikaType.label),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: _busy
                    ? null
                    : () => _pickScorer(me?.displayName ?? 'Organizer'),
                child: Row(
                  children: [
                    const Icon(
                      Icons.assignment_ind_outlined,
                      size: 18,
                      color: SportikaColors.gold,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _scorerId == null
                                ? 'You score this match'
                                : _scorerName ?? 'Assigned scorer',
                            style: SportikaType.bodyStrong,
                          ),
                          Text(
                            _scorerId == null
                                ? 'You can hand it to another member any time'
                                : 'They record the log; you publish the result',
                            style: SportikaType.caption,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _scorerId == null ? 'Assign' : 'Change',
                      style: SportikaType.action,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.lg),
          const Text('YOUR MATCH PREVIEW', style: SportikaType.label),
          const SizedBox(height: SportikaSpacing.sm),
          MatchVsCard(match: _preview(me?.id ?? ''), progress: null),
          const SizedBox(height: SportikaSpacing.md),
          const HelperText(
            'You join as a player. Invite the rest of your roster after creating the match.',
          ),
        ],
      ),
    );
  }

  /// A throwaway match that only exists to feed the VS preview.
  SportMatch _preview(String me) {
    final a = _sideA.text.trim();
    final b = _sideB.text.trim();
    return SportMatch(
      id: 'preview',
      sport: _sport,
      formatLabel: _format,
      rules: _rules,
      title: _title.text.trim(),
      venue: _venue.text.trim(),
      scheduledAt: _scheduledAt,
      visibility: _visibility,
      organizerId: me,
      status: FixtureStatus.upcoming,
      sideNames: [a.isEmpty ? 'Side A' : a, b.isEmpty ? 'Side B' : b],
      discipline: _discipline,
      capacity: _capacity,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _pickBadmintonPlayer(int side) async {
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ScorerPickerSheet(
        organizerName: 'Keep this place open',
        playerSelection: true,
      ),
    );
    if (!mounted || picked is! ProfileSummary) return;
    final me = context.read<SessionController>().currentAccount?.id;
    if (picked.id == me ||
        _badmintonPlayers
            .expand((players) => players)
            .any((player) => player.id == picked.id)) {
      showSnack(
        context,
        'This player already has a place in the match.',
        error: true,
      );
      return;
    }
    setState(() => _badmintonPlayers[side].add(picked));
  }

  Future<void> _pickSchedule() async {
    final initial = _scheduledAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    setState(() {
      _scheduledAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time?.hour ?? initial.hour,
        time?.minute ?? initial.minute,
      );
    });
  }

  Future<void> _pickScorer(String organizerName) async {
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ScorerPickerSheet(organizerName: organizerName),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked is ProfileSummary) {
        _scorerId = picked.id;
        _scorerName = picked.label;
      } else {
        // 'organizer' keeps the whistle with the account creating the match.
        _scorerId = null;
        _scorerName = null;
      }
    });
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    final sideA = _sideA.text.trim();
    final sideB = _sideB.text.trim();
    final venue = _venue.text.trim();

    final problem = _validate(title, sideA, sideB, venue);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final confirmed = await scoringConfirm(
      context,
      title: 'Create this match?',
      body:
          '$sideA vs $sideB · $_format\n${SportEngines.describeRules(_sport, _rules)}\n${dateShort(_scheduledAt)} · $venue\nScorer: ${_scorerName ?? 'You'}\nSelected players receive invitations. You publish the official result.',
      confirmLabel: 'Create match',
    );
    if (!confirmed || !mounted) return;
    final matches = context.read<MatchController>();
    final selectedRosters = _sport == Sport.badminton && !widget._isTournament
        ? [
            for (final players in _badmintonPlayers)
              [for (final player in players) player.id],
          ]
        : _futsal['rosters'] as List? ?? [];
    setState(() {
      _busy = true;
      _error = null;
    });
    final created = await matches.createMatch(
      MatchDraft(
        sport: _sport,
        formatLabel: _format,
        rules: _rules,
        title: title,
        venue: venue,
        scheduledAt: _scheduledAt,
        visibility: _visibility,
        sideA: sideA,
        sideB: sideB,
        capacity: _capacity,
        discipline: _discipline,
        scorerId: _scorerId,
        tournamentId: widget.tournamentId,
        fixtureId: widget.fixtureId,
      ),
    );
    if (!mounted) return;
    if (created == null) {
      setState(() {
        _busy = false;
        _error = matches.lastError ?? 'The match could not be created.';
      });
      return;
    }
    final failedInvites = <String>[];
    if (_sport == Sport.futsal ||
        _sport == Sport.cricket ||
        _sport == Sport.badminton) {
      final rosters = selectedRosters;
      for (var side = 0; side < rosters.length; side++) {
        for (final id in rosters[side] as List) {
          if (id == created.organizerId) continue;
          if (!await matches.inviteParticipant(
            created.id,
            id as String,
            side: side,
          )) {
            failedInvites.add(id);
          }
        }
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    pushRoute(context, AppRoute.matchDetail, args: MatchArgs(created.id));
    showSnack(
      context,
      failedInvites.isEmpty
          ? '${created.title} is on the board'
          : 'Match created. ${failedInvites.length} invitations failed; retry from Manage players.',
      error: failedInvites.isNotEmpty,
    );
  }

  /// The same rules `create_match` enforces, checked before the round trip.
  String? _validate(String title, String sideA, String sideB, String venue) {
    if (widget._isTournament &&
        context
                .read<TournamentsController>()
                .tournamentById(widget.tournamentId!)
                ?.organizerId !=
            context.read<SessionController>().currentAccount?.id) {
      return 'Only the tournament organizer can set up this fixture.';
    }
    if (title.length < 2 || title.length > 80) {
      return 'Give the match a title between 2 and 80 characters.';
    }
    if (_sport == Sport.futsal && venue.isEmpty) {
      return 'Add the match location.';
    }
    if (_sport == Sport.futsal && !_scheduledAt.isAfter(DateTime.now())) {
      return 'Choose a future match date and time.';
    }
    if (_sport == Sport.futsal && _capacity < 10) {
      return 'Futsal needs space for at least ten players.';
    }
    final rosters = _futsal['rosters'] as List? ?? [];
    if (rosters.length == 2 &&
        (rosters[1] as List).contains(
          context.read<SessionController>().currentAccount?.id,
        )) {
      return 'The organizer joins the home side. Choose your team as the home team.';
    }
    if (rosters.length == 2 &&
        (rosters[0] as List).any((id) => (rosters[1] as List).contains(id))) {
      return 'A player cannot appear on both teams.';
    }
    if (venue.length > 80) {
      return 'Keep the venue to 80 characters or fewer.';
    }
    if (sideA.isEmpty || sideA.length > 40) {
      return 'Name side A with 1 to 40 characters.';
    }
    if (sideB.isEmpty || sideB.length > 40) {
      return 'Name side B with 1 to 40 characters.';
    }
    if (sideA.toLowerCase() == sideB.toLowerCase()) {
      return 'The two sides need different names.';
    }
    if (_format.trim().isEmpty) return 'Pick a format for the match.';
    if (!MatchDisciplineX.forSport(_sport).contains(_discipline)) {
      return '${_sport.label} is not played as ${_discipline.label.toLowerCase()}.';
    }
    if (_capacity < 2 || _capacity > 100) {
      return 'Capacity has to be between 2 and 100 players.';
    }
    return null;
  }
}

class _CreationHero extends StatelessWidget {
  const _CreationHero({required this.tone});
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tone.withValues(alpha: 0.22), SportikaColors.surfaceSunken],
      ),
      border: Border.all(color: tone.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.sports_score_rounded,
              color: SportikaColors.gold,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'SPORTIKA / MATCHDAY',
                style: SportikaType.label.copyWith(
                  color: SportikaColors.gold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Great games\nstart here.',
          style: SportikaType.hero.copyWith(height: 1.08),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your teams. Your stage. Every point recorded.',
          style: SportikaType.caption,
        ),
        const SizedBox(height: 20),
        const Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text('01  GAME', style: SportikaType.label),
            Text('02  SIDES', style: SportikaType.label),
            Text('03  MATCHDAY', style: SportikaType.label),
          ],
        ),
      ],
    ),
  );
}

class _CreationSection extends StatelessWidget {
  const _CreationSection({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String number;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: SportikaColors.surfaceSunken,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: SportikaColors.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SportikaColors.goldSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                number,
                style: SportikaType.action.copyWith(color: SportikaColors.gold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SportikaType.bodyStrong.copyWith(fontSize: 19),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: SportikaType.caption),
                ],
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Divider(height: 1, color: SportikaColors.borderSubtle),
        ),
        ...children,
      ],
    ),
  );
}

class _SportTile extends StatelessWidget {
  const _SportTile({required this.sport, required this.selected, this.onTap});
  final Sport sport;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);
    final icon = switch (sport) {
      Sport.cricket => Icons.sports_cricket_rounded,
      Sport.futsal => Icons.sports_soccer_rounded,
      Sport.padel => Icons.sports_tennis_rounded,
      Sport.badminton => Icons.sports_tennis_rounded,
    };
    return Semantics(
      selected: selected,
      button: true,
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: SportikaMotion.base,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? tone.withValues(alpha: 0.14)
                  : SportikaColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? tone : SportikaColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      color: selected ? tone : SportikaColors.textMuted,
                      size: 26,
                    ),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle_rounded, color: tone, size: 18),
                  ],
                ),
                const SizedBox(height: 14),
                Text(sport.label, style: SportikaType.bodyStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.tone,
    this.onTap,
  });

  final String label;
  final bool active;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      button: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? tone.withValues(alpha: 0.18)
                : SportikaColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? tone.withValues(alpha: 0.65)
                  : SportikaColors.border,
            ),
          ),
          child: Text(
            label,
            style: SportikaType.action.copyWith(
              color: active ? tone : SportikaColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Searches registered members and returns the chosen id, or `'organizer'` when
/// the organizer keeps the whistle.
class _ScorerPickerSheet extends StatefulWidget {
  const _ScorerPickerSheet({
    required this.organizerName,
    this.playerSelection = false,
  });

  final bool playerSelection;

  final String organizerName;

  @override
  State<_ScorerPickerSheet> createState() => _ScorerPickerSheetState();
}

class _ScorerPickerSheetState extends State<_ScorerPickerSheet> {
  final TextEditingController _search = TextEditingController();
  List<ProfileSummary>? _results;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final profiles = context.read<ProfileModuleController>();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final found = await profiles.searchPlayers(_search.text);
      if (!mounted) return;
      setState(() => _results = found);
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: widget.playerSelection
          ? 'Select registered player'
          : 'Official scorer',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetOption(
            icon: Icons.person_outline,
            title: widget.organizerName,
            subtitle: widget.playerSelection
                ? 'Invite a player later from match details'
                : 'The organizer scores this match',
            tone: SportikaColors.mint,
            onTap: () => Navigator.of(context).pop('organizer'),
          ),
          if (_results != null && _results!.isEmpty)
            const HelperText(
              'No registered players found. Try another name or username.',
            ),
          if (_results != null && _results!.isNotEmpty)
            for (final player in _results!)
              SheetOption(
                icon: Icons.person_add_alt,
                title: player.label,
                subtitle: player.city.isEmpty
                    ? '@${player.username}'
                    : '${player.city} · @${player.username}',
                tone: SportikaColors.blueBright,
                onTap: () => Navigator.of(context).pop(player),
              ),
          const SizedBox(height: SportikaSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runSearch(),
                  decoration: const InputDecoration(
                    labelText: 'Find a registered player',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              GhostButton(
                label: 'Search',
                onPressed: _searching ? null : _runSearch,
              ),
            ],
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(text: _error!, tone: SportikaColors.danger),
          ],
        ],
      ),
    );
  }
}
