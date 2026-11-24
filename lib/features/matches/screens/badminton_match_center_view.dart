import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/features/matches/widgets/match_result_card.dart';
import 'package:sportika/features/matches/widgets/match_roster_card.dart';
import 'package:sportika/features/matches/widgets/racket_match_report.dart';
import 'package:sportika/features/personal_games/scoring/badminton/badminton.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/module_media_panel.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Actions are owned by the parent match detail screen.
///
/// This view never writes directly to the scoring log.
class BadmintonMatchActions {
  const BadmintonMatchActions({
    this.onStart,
    this.onScore,
    this.onRecord,
    this.onRetire,
    this.onInviteSide,
    this.onRefresh,
    this.canManageMedia = false,
  });

  final Future<void> Function()? onStart;
  final VoidCallback? onScore;

  /// Retained for compatibility with existing callers.
  ///
  /// Official rally entry now lives in the scoring workspace.
  final void Function(String kind, int? side, Map<String, dynamic> data)?
  onRecord;

  final VoidCallback? onRetire;
  final ValueChanged<int>? onInviteSide;
  final Future<void> Function()? onRefresh;
  final bool canManageMedia;
}

/// Broadcast-inspired badminton match center.
///
/// Hierarchy:
/// 1. Match identity and scoreboard
/// 2. Current service and match situation
/// 3. Context-aware primary action
/// 4. Game-by-game scores
/// 5. Recent rallies
/// 6. Players and match details
/// 7. Official result
class BadmintonMatchCenterView extends StatefulWidget {
  const BadmintonMatchCenterView({
    super.key,
    required this.match,
    required this.progress,
    this.accountId,
    this.actions = const BadmintonMatchActions(),
    this.banners = const [],
  });

  final SportMatch match;
  final MatchProgress progress;
  final String? accountId;
  final BadmintonMatchActions actions;
  final List<Widget> banners;

  @override
  State<BadmintonMatchCenterView> createState() =>
      _BadmintonMatchCenterViewState();
}

class _BadmintonMatchCenterViewState extends State<BadmintonMatchCenterView> {
  final GlobalKey _gamesKey = GlobalKey();
  final GlobalKey _resultKey = GlobalKey();

  bool _historyExpanded = false;
  bool _playersExpanded = false;
  bool _detailsExpanded = false;

  String? _historySignature;
  List<_RallySnapshot> _history = const [];

  SportMatch get match => widget.match;
  MatchProgress get progress => widget.progress;

  int get _toWin => _positiveInt(match.rules['pointsToWinGame']) ?? 21;

  int get _cap => _positiveInt(match.rules['cap']) ?? 30;

  int get _gamesToWin => _positiveInt(match.rules['gamesToWin']) ?? 2;

  List<int>? get _points => _readPair(progress.state['points']);

  List<int>? get _gamesWon => _readPair(progress.state['gamesWon']);

  int? get _server {
    final value = _nonNegativeInt(progress.state['server']);
    return value == 0 || value == 1 ? value : null;
  }

  String _name(int side) {
    if (side < match.sideNames.length &&
        match.sideNames[side].trim().isNotEmpty) {
      return match.sideNames[side];
    }
    return 'Side ${side + 1}';
  }

  BadmintonSituation? get _situation {
    final points = _points;
    final games = _gamesWon;

    if (progress.isComplete || points == null || games == null) {
      return null;
    }

    return BadmintonEngine.situationFor(
      points: points,
      gamesWon: games,
      gamesToWin: _gamesToWin,
      toWin: _toWin,
      cap: _cap,
      sides: match.sideNames,
    );
  }

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  @override
  void didUpdateWidget(covariant BadmintonMatchCenterView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.match.id != widget.match.id) {
      _historyExpanded = false;
      _playersExpanded = false;
      _detailsExpanded = false;
      _historySignature = null;
    }

    _refreshHistory();
  }

  void _refreshHistory() {
    // Use event content rather than only event count so voids,
    // corrections and replacement events invalidate the cache.
    final signature = [
      match.id,
      match.sideNames.join('|'),
      match.rules.toString(),
      match.scoringLog.toString(),
    ].join('::');

    if (_historySignature == signature) return;

    _historySignature = signature;
    _history = _buildHistory(match);
  }

  static List<_RallySnapshot> _buildHistory(SportMatch match) {
    final events = <ScoringEvent>[];

    for (final raw in match.scoringLog) {
      events.add(ScoringEvent.fromJson(raw));
    }

    final rallies = events
        .where(
          (event) =>
              event.kind == BadmintonEngine.kRally &&
              (event.side == 0 || event.side == 1),
        )
        .toList();

    if (rallies.isEmpty) return const [];

    final engine = BadmintonEngine();
    final snapshots = <_RallySnapshot>[];

    // Compute snapshots once per log change, not on every widget build.
    // The existing engine remains authoritative.
    for (var i = 0; i < rallies.length; i++) {
      final state = engine.evaluate(
        sides: match.sideNames,
        rules: match.rules,
        events: rallies.sublist(0, i + 1),
      );

      snapshots.add(
        _RallySnapshot(
          number: i + 1,
          side: rallies[i].side!,
          game: _positiveInt(state.state['game']) ?? 1,
          points: _readPair(state.state['points']),
          complete: state.isComplete,
        ),
      );
    }

    return snapshots;
  }

  void _reveal(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;

    Scrollable.ensureVisible(
      target,
      duration: SportikaMotion.base,
      curve: SportikaMotion.standard,
      alignment: .1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = match.status == FixtureStatus.live;
    final canScore = match.canScore(widget.accountId);
    final situation = _situation;
    final points = _points;
    final server = _server;

    final serveCourt = server != null && points != null
        ? BadmintonEngine.serveCourtFor(points[server])
        : null;

    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      children: [
        _BadmintonBroadcastHero(
          match: match,
          progress: progress,
          points: points,
          gamesWon: _gamesWon,
          server: server,
          serveCourt: serveCourt,
          situation: situation,
          nameOf: _name,
        ),

        if (widget.banners.isNotEmpty) ...[
          const SizedBox(height: SportikaSpacing.md),
          ...widget.banners,
        ],

        if (match.isPaused && live) ...[
          const SizedBox(height: SportikaSpacing.md),
          InfoBanner(
            text: match.pauseReason?.isNotEmpty == true
                ? 'Scoring paused: ${match.pauseReason}'
                : 'Scoring is paused by the organizer or official scorer.',
            tone: SportikaColors.gold,
            icon: Icons.pause_circle_outline,
          ),
        ],

        const SizedBox(height: SportikaSpacing.md),

        _MatchActionPanel(
          match: match,
          progress: progress,
          canScore: canScore,
          actions: widget.actions,
          onViewResult: () => _reveal(_resultKey),
          onViewGames: () => _reveal(_gamesKey),
        ),

        const SizedBox(height: SportikaSpacing.lg),

        _SectionHeader(
          key: _gamesKey,
          title: 'GAME-BY-GAME',
          subtitle: 'Official game progression',
          icon: Icons.table_chart_outlined,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        _GameReportPanel(match: match, progress: progress, nameOf: _name),

        const SizedBox(height: SportikaSpacing.lg),

        const _SectionHeader(
          title: 'RALLY TIMELINE',
          subtitle: 'Latest scoring activity',
          icon: Icons.timeline,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        _RecentRallies(
          snapshots: _history,
          nameOf: _name,
          expanded: _historyExpanded,
          onToggle: () {
            setState(() {
              _historyExpanded = !_historyExpanded;
            });
          },
        ),

        const SizedBox(height: SportikaSpacing.lg),

        _ExpandableSection(
          title: 'PLAYERS & TEAMS',
          subtitle: match.discipline.label,
          icon: Icons.groups_outlined,
          expanded: _playersExpanded,
          onToggle: () {
            setState(() {
              _playersExpanded = !_playersExpanded;
            });
          },
          child: MatchRosterCard(
            match: match,
            accountId: widget.accountId,
            onInviteSide: widget.actions.onInviteSide,
          ),
        ),

        if (match.result != null) ...[
          const SizedBox(height: SportikaSpacing.lg),
          _SectionHeader(
            key: _resultKey,
            title: 'OFFICIAL RESULT',
            subtitle: 'Confirmed match outcome',
            icon: Icons.emoji_events_outlined,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          MatchResultCard(match: match),
        ],

        const SizedBox(height: SportikaSpacing.lg),

        _ExpandableSection(
          title: 'MATCH DETAILS',
          subtitle: 'Rules, competition and media',
          icon: Icons.info_outline,
          expanded: _detailsExpanded,
          onToggle: () {
            setState(() {
              _detailsExpanded = !_detailsExpanded;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RulesSummary(
                toWin: _toWin,
                cap: _cap,
                gamesToWin: _gamesToWin,
                doubles: match.discipline == MatchDiscipline.doubles,
              ),
              if (match.isTournamentMatch) ...[
                const SizedBox(height: SportikaSpacing.md),
                _TournamentLink(match: match),
              ],
              const SizedBox(height: SportikaSpacing.md),
              ModuleMediaPanel(
                bucket: 'match-media',
                entity: match.id,
                canEdit: widget.actions.canManageMedia,
                label: match.title,
                showEmptyArtwork: false,
              ),
            ],
          ),
        ),

        const SizedBox(height: SportikaSpacing.xl),
      ],
    );

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: sportikaMaxContentWidth),
          child: widget.actions.onRefresh == null
              ? content
              : RefreshIndicator(
                  onRefresh: widget.actions.onRefresh!,
                  child: content,
                ),
        ),
      ),
    );
  }
}

/// One coherent scoreboard rather than multiple competing score cards.
class _BadmintonBroadcastHero extends StatelessWidget {
  const _BadmintonBroadcastHero({
    required this.match,
    required this.progress,
    required this.points,
    required this.gamesWon,
    required this.server,
    required this.serveCourt,
    required this.situation,
    required this.nameOf,
  });

  final SportMatch match;
  final MatchProgress progress;
  final List<int>? points;
  final List<int>? gamesWon;
  final int? server;
  final String? serveCourt;
  final BadmintonSituation? situation;
  final String Function(int) nameOf;

  @override
  Widget build(BuildContext context) {
    final complete = progress.isComplete;
    final result = match.result;

    final winner = result != null
        ? result.winnerIndex
        : complete
        ? progress.winnerIndex
        : -1;

    final officialGames = result != null && result.sideValues.length >= 2
        ? result.sideValues
        : progress.scoreValues;

    final gameScores = officialGames.length >= 2
        ? [officialGames[0].toString(), officialGames[1].toString()]
        : gamesWon != null
        ? ['${gamesWon![0]}', '${gamesWon![1]}']
        : ['—', '—'];

    final currentPoints = complete
        ? _lastCompletedGame(progress) ?? points
        : points;

    final gameNumber = _positiveInt(progress.state['game']) ?? 1;

    final situationColor = switch (situation?.kind) {
      BadmintonSituationKind.interval => SportikaColors.gold,
      BadmintonSituationKind.goldenPoint => SportikaColors.gold,
      BadmintonSituationKind.deuce => SportikaColors.textMuted,
      _ => SportikaColors.mint,
    };

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SportikaColors.scoreboardSurface,
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        border: Border.all(color: SportikaColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CourtHeader(match: match, complete: complete),

          Padding(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        match.discipline.label.toUpperCase(),
                        style: SportikaType.micro.copyWith(
                          color: SportikaColors.textMuted,
                        ),
                      ),
                    ),
                    Text(
                      complete ? 'FINAL SCORE' : 'GAME $gameNumber',
                      style: SportikaType.micro.copyWith(
                        color: SportikaColors.textMuted,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: SportikaSpacing.lg),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _BroadcastTeam(
                        match: match,
                        side: 0,
                        name: nameOf(0),
                        games: gameScores[0],
                        serving: !complete && server == 0,
                        winner: winner == 0,
                        accent: SportikaColors.mint,
                      ),
                    ),
                    const SizedBox(width: SportikaSpacing.xs),
                    Expanded(
                      flex: 2,
                      child: _BroadcastScore(
                        points: currentPoints,
                        complete: complete,
                      ),
                    ),
                    const SizedBox(width: SportikaSpacing.xs),
                    Expanded(
                      child: _BroadcastTeam(
                        match: match,
                        side: 1,
                        name: nameOf(1),
                        games: gameScores[1],
                        serving: !complete && server == 1,
                        winner: winner == 1,
                        accent: SportikaColors.gold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: SportikaSpacing.lg),

                if (complete)
                  _MatchSituationStrip(
                    icon: Icons.emoji_events_outlined,
                    label: progress.resultLabel.isNotEmpty
                        ? progress.resultLabel
                        : 'Match complete',
                    color: SportikaColors.gold,
                  )
                else if (situation != null)
                  _MatchSituationStrip(
                    icon: Icons.bolt_rounded,
                    label: situation!.label,
                    color: situationColor,
                  ),

                if (!complete && server != null && serveCourt != null) ...[
                  const SizedBox(height: SportikaSpacing.md),
                  _ServiceCourtPanel(
                    servingName: nameOf(server!),
                    receivingName: nameOf(1 - server!),
                    court: serveCourt!,
                    servingSide: server!,
                  ),
                ],

                if (!complete && (server == null || points == null)) ...[
                  const SizedBox(height: SportikaSpacing.md),
                  const Text(
                    'Live service information is unavailable.',
                    style: SportikaType.caption,
                  ),
                ],

                const SizedBox(height: SportikaSpacing.md),

                Row(
                  children: [
                    const Icon(
                      Icons.sports_tennis,
                      size: SportikaSpacing.lg,
                      color: SportikaColors.textMuted,
                    ),
                    const SizedBox(width: SportikaSpacing.sm),
                    Expanded(
                      child: Text(
                        [
                          match.formatLabel,
                          if (match.venue.isNotEmpty) match.venue,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.caption,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A court-inspired header using only existing design tokens.
///
/// This avoids requiring new image assets or unverified network URLs.
class _CourtHeader extends StatelessWidget {
  const _CourtHeader({required this.match, required this.complete});

  final SportMatch match;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: SportikaSpacing.xl * 5,
      decoration: const BoxDecoration(color: SportikaColors.surfaceAlt),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _BadmintonCourtPainter()),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    SportikaColors.scoreboardSurface.withValues(alpha: .08),
                    SportikaColors.scoreboardSurface.withValues(alpha: .94),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'SPORTIKA / BADMINTON',
                        style: SportikaType.micro.copyWith(
                          color: SportikaColors.text,
                        ),
                      ),
                    ),
                    StatusPill(
                      match.isPaused && match.isLive
                          ? 'Paused'
                          : match.status.label,
                      color: match.isPaused && match.isLive
                          ? SportikaColors.gold
                          : statusColor(match.status.key),
                      icon: match.isPaused && match.isLive
                          ? Icons.pause_circle_outline
                          : statusIcon(match.status.key),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  complete ? 'MATCH RESULT' : 'MATCH CENTER',
                  style: SportikaType.title,
                ),
                if (match.isTournamentMatch)
                  Text(
                    'OFFICIAL TOURNAMENT FIXTURE',
                    style: SportikaType.micro.copyWith(
                      color: SportikaColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Decorative badminton court geometry.
/// Colors are sourced exclusively from Sportika's theme.
class _BadmintonCourtPainter extends CustomPainter {
  const _BadmintonCourtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SportikaColors.mint.withValues(alpha: .23)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rect = Rect.fromLTWH(
      size.width * .08,
      size.height * .10,
      size.width * .84,
      size.height * .80,
    );

    canvas.drawRect(rect, paint);

    final center = rect.center.dx;
    final midY = rect.center.dy;

    canvas.drawLine(
      Offset(center, rect.top),
      Offset(center, rect.bottom),
      paint,
    );

    canvas.drawLine(Offset(rect.left, midY), Offset(rect.right, midY), paint);

    canvas.drawLine(
      Offset(rect.left, rect.top + rect.height * .25),
      Offset(rect.right, rect.top + rect.height * .25),
      paint,
    );

    canvas.drawLine(
      Offset(rect.left, rect.bottom - rect.height * .25),
      Offset(rect.right, rect.bottom - rect.height * .25),
      paint,
    );

    canvas.drawRect(
      Rect.fromLTRB(
        rect.left + rect.width * .08,
        rect.top,
        rect.right - rect.width * .08,
        rect.bottom,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BadmintonCourtPainter oldDelegate) => false;
}

class _BroadcastTeam extends StatelessWidget {
  const _BroadcastTeam({
    required this.match,
    required this.side,
    required this.name,
    required this.games,
    required this.serving,
    required this.winner,
    required this.accent,
  });

  final SportMatch match;
  final int side;
  final String name;
  final String games;
  final bool serving;
  final bool winner;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final players = [
      for (final participant in match.participantsOnSide(side))
        if (participant.status == MatchParticipantStatus.accepted)
          participant.displayName,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: SportikaSpacing.xl * 2,
          height: SportikaSpacing.xl * 2,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .12),
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: .4)),
          ),
          child: Icon(
            match.discipline == MatchDiscipline.doubles
                ? Icons.groups_rounded
                : Icons.person_outline_rounded,
            color: accent,
            size: SportikaSpacing.lg,
          ),
        ),

        const SizedBox(height: SportikaSpacing.sm),

        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: SportikaType.bodyStrong,
        ),

        if (players.isNotEmpty) ...[
          const SizedBox(height: SportikaSpacing.xs),
          Text(
            players.join(' / '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: SportikaType.micro.copyWith(color: SportikaColors.textMuted),
          ),
        ],

        const SizedBox(height: SportikaSpacing.sm),

        Text(
          '$games ${games == '1' ? 'GAME' : 'GAMES'}',
          style: SportikaType.micro.copyWith(color: accent),
        ),

        if (serving || winner) ...[
          const SizedBox(height: SportikaSpacing.xs),
          Text(
            winner ? 'WINNER' : 'SERVING',
            style: SportikaType.micro.copyWith(
              color: winner ? SportikaColors.gold : SportikaColors.mint,
            ),
          ),
        ],
      ],
    );
  }
}

class _BroadcastScore extends StatelessWidget {
  const _BroadcastScore({required this.points, required this.complete});

  final List<int>? points;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final scoreStyle = SportikaType.hero.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          complete ? 'FINAL GAME' : 'CURRENT GAME',
          textAlign: TextAlign.center,
          style: SportikaType.micro.copyWith(color: SportikaColors.textMuted),
        ),
        const SizedBox(height: SportikaSpacing.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(points == null ? '—' : '${points![0]}', style: scoreStyle),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.xs,
                ),
                child: Text(
                  ':',
                  style: SportikaType.title.copyWith(
                    color: SportikaColors.textDim,
                  ),
                ),
              ),
              Text(points == null ? '—' : '${points![1]}', style: scoreStyle),
            ],
          ),
        ),
      ],
    );
  }
}

class _MatchSituationStrip extends StatelessWidget {
  const _MatchSituationStrip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.md,
        vertical: SportikaSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          Icon(icon, size: SportikaSpacing.lg, color: color),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: SportikaType.bodyStrong.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Visualizes the side and service court without inventing
/// individual doubles server/receiver assignments.
class _ServiceCourtPanel extends StatelessWidget {
  const _ServiceCourtPanel({
    required this.servingName,
    required this.receivingName,
    required this.court,
    required this.servingSide,
  });

  final String servingName;
  final String receivingName;
  final String court;
  final int servingSide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(color: SportikaColors.borderSubtle),
      ),
      child: Row(
        children: [
          SizedBox(
            width: SportikaSpacing.xl * 3,
            height: SportikaSpacing.xl * 2,
            child: CustomPaint(
              painter: _ServiceCourtPainter(
                rightCourt: court.toLowerCase() == 'right',
                servingSide: servingSide,
              ),
            ),
          ),
          const SizedBox(width: SportikaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SERVICE',
                  style: SportikaType.micro.copyWith(
                    color: SportikaColors.mint,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.xs),
                Text(
                  servingName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong,
                ),
                Text('$court court', style: SportikaType.caption),
                const SizedBox(height: SportikaSpacing.xs),
                Text(
                  'Receiving: $receivingName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.micro.copyWith(
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCourtPainter extends CustomPainter {
  const _ServiceCourtPainter({
    required this.rightCourt,
    required this.servingSide,
  });

  final bool rightCourt;
  final int servingSide;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);

    final lines = Paint()
      ..color = SportikaColors.textMuted.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final highlighted = Paint()
      ..color = SportikaColors.mint.withValues(alpha: .24)
      ..style = PaintingStyle.fill;

    final halfWidth = bounds.width / 2;
    final halfHeight = bounds.height / 2;

    // Illustrative service-side highlight, not an individual
    // doubles service-rotation diagram.
    final x = rightCourt ? bounds.left + halfWidth : bounds.left;

    final y = servingSide == 0 ? bounds.top : bounds.top + halfHeight;

    canvas.drawRect(Rect.fromLTWH(x, y, halfWidth, halfHeight), highlighted);

    canvas.drawRect(bounds, lines);

    canvas.drawLine(
      Offset(bounds.center.dx, bounds.top),
      Offset(bounds.center.dx, bounds.bottom),
      lines,
    );

    canvas.drawLine(
      Offset(bounds.left, bounds.center.dy),
      Offset(bounds.right, bounds.center.dy),
      lines,
    );
  }

  @override
  bool shouldRepaint(covariant _ServiceCourtPainter oldDelegate) {
    return rightCourt != oldDelegate.rightCourt ||
        servingSide != oldDelegate.servingSide;
  }
}

/// Clear single primary action, with retirement moved into
/// a secondary menu.
class _MatchActionPanel extends StatelessWidget {
  const _MatchActionPanel({
    required this.match,
    required this.progress,
    required this.canScore,
    required this.actions,
    required this.onViewResult,
    required this.onViewGames,
  });

  final SportMatch match;
  final MatchProgress progress;
  final bool canScore;
  final BadmintonMatchActions actions;
  final VoidCallback onViewResult;
  final VoidCallback onViewGames;

  @override
  Widget build(BuildContext context) {
    final live = match.status == FixtureStatus.live;
    final hasResult = match.result != null;

    if (hasResult) {
      return PrimaryButton(
        label: 'View official result',
        icon: Icons.emoji_events_outlined,
        tone: SportikaColors.mint,
        onPressed: onViewResult,
      );
    }

    if (!canScore) {
      return SurfaceCard(
        child: Row(
          children: [
            const Icon(
              Icons.visibility_outlined,
              color: SportikaColors.textMuted,
            ),
            const SizedBox(width: SportikaSpacing.md),
            const Expanded(
              child: Text(
                'Spectator view · Official scores update as rallies are recorded.',
                style: SportikaType.caption,
              ),
            ),
            IconButton(
              tooltip: 'View game scores',
              onPressed: onViewGames,
              icon: const Icon(Icons.table_chart_outlined),
            ),
          ],
        ),
      );
    }

    String label;
    IconData icon;
    VoidCallback? callback;

    if (match.status == FixtureStatus.upcoming) {
      label = 'Start badminton match';
      icon = Icons.play_arrow_rounded;
      callback = actions.onStart == null
          ? null
          : () {
              actions.onStart!();
            };
    } else if (progress.isComplete) {
      label = 'Review and submit result';
      icon = Icons.fact_check_outlined;
      callback = actions.onScore;
    } else if (match.isPaused) {
      label = 'Open scoring controls';
      icon = Icons.pause_circle_outline;
      callback = actions.onScore;
    } else if (live) {
      label = 'Open official scoring';
      icon = Icons.sports_score;
      callback = actions.onScore;
    } else {
      label = 'View game scores';
      icon = Icons.table_chart_outlined;
      callback = onViewGames;
    }

    final canRetire = live && !progress.isComplete && actions.onRetire != null;

    return Row(
      children: [
        Expanded(
          child: PrimaryButton(
            label: label,
            icon: icon,
            tone: SportikaColors.mint,
            onPressed: callback,
          ),
        ),
        if (canRetire) ...[
          const SizedBox(width: SportikaSpacing.sm),
          PopupMenuButton<String>(
            tooltip: 'More match actions',
            icon: const Icon(Icons.more_vert, color: SportikaColors.textMuted),
            onSelected: (value) {
              if (value == 'retire') {
                actions.onRetire?.call();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'retire',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, color: SportikaColors.danger),
                    SizedBox(width: SportikaSpacing.sm),
                    Text('Retire / concede'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: SportikaColors.mint, size: SportikaSpacing.lg),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SportikaType.bodyStrong),
              Text(subtitle, style: SportikaType.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class _GameReportPanel extends StatelessWidget {
  const _GameReportPanel({
    required this.match,
    required this.progress,
    required this.nameOf,
  });

  final SportMatch match;
  final MatchProgress progress;
  final String Function(int) nameOf;

  @override
  Widget build(BuildContext context) {
    final completed = _completedGames(progress);
    final active = _readPair(progress.state['points']);
    final current =
        _positiveInt(progress.state['game']) ?? completed.length + 1;

    final columns = completed.length + (progress.isComplete ? 0 : 1);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (columns > 0)
            LayoutBuilder(
              builder: (context, constraints) {
                final teamWidth = SportikaSpacing.xl * 4;
                final gameWidth = SportikaSpacing.xl * 2.5;

                final minimum = teamWidth + columns * gameWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: minimum > constraints.maxWidth
                        ? minimum
                        : constraints.maxWidth,
                    child: Table(
                      columnWidths: {0: FixedColumnWidth(teamWidth)},
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: const TableBorder(
                        horizontalInside: BorderSide(
                          color: SportikaColors.borderSubtle,
                        ),
                      ),
                      children: [
                        TableRow(
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(SportikaSpacing.sm),
                              child: Text('TEAM', style: SportikaType.micro),
                            ),
                            for (var i = 0; i < columns; i++)
                              _GameCell(
                                text: 'G${i + 1}',
                                active:
                                    !progress.isComplete &&
                                    i == completed.length,
                                header: true,
                              ),
                          ],
                        ),
                        for (var side = 0; side < 2; side++)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(
                                  SportikaSpacing.sm,
                                ),
                                child: Text(
                                  nameOf(side),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: SportikaType.bodyStrong,
                                ),
                              ),
                              for (var i = 0; i < columns; i++)
                                _GameCell(
                                  text: i < completed.length
                                      ? '${completed[i][side]}'
                                      : active == null
                                      ? '—'
                                      : '${active[side]}',
                                  active:
                                      !progress.isComplete &&
                                      i == completed.length,
                                  winner:
                                      i < completed.length &&
                                      completed[i][side] >
                                          completed[i][1 - side],
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            )
          else
            const Text(
              'Game scores will appear when scoring begins.',
              style: SportikaType.caption,
            ),

          const SizedBox(height: SportikaSpacing.sm),

          Text(
            progress.isComplete
                ? 'Match complete'
                : 'Game $current in progress',
            style: SportikaType.caption.copyWith(
              color: SportikaColors.textMuted,
            ),
          ),

          // Preserve the existing detailed racket report.
          const SizedBox(height: SportikaSpacing.md),
          RacketMatchReport(match: match, progress: progress),
        ],
      ),
    );
  }
}

class _GameCell extends StatelessWidget {
  const _GameCell({
    required this.text,
    this.active = false,
    this.header = false,
    this.winner = false,
  });

  final String text;
  final bool active;
  final bool header;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: SportikaSpacing.xl * 2),
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.xs,
        vertical: SportikaSpacing.sm,
      ),
      color: active ? SportikaColors.mintSubtle : null,
      child: Text(
        text,
        style: header
            ? SportikaType.micro.copyWith(
                color: active ? SportikaColors.mint : SportikaColors.textMuted,
              )
            : SportikaType.scoreSmall.copyWith(
                color: active
                    ? SportikaColors.mint
                    : winner
                    ? SportikaColors.text
                    : SportikaColors.textMuted,
                fontWeight: winner
                    ? SportikaFontWeight.extraBold
                    : SportikaFontWeight.medium,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
      ),
    );
  }
}

class _RallySnapshot {
  const _RallySnapshot({
    required this.number,
    required this.side,
    required this.game,
    required this.points,
    required this.complete,
  });

  final int number;
  final int side;
  final int game;
  final List<int>? points;
  final bool complete;
}

class _RecentRallies extends StatelessWidget {
  const _RecentRallies({
    required this.snapshots,
    required this.nameOf,
    required this.expanded,
    required this.onToggle,
  });

  final List<_RallySnapshot> snapshots;
  final String Function(int) nameOf;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (snapshots.isEmpty) {
      return const SurfaceCard(
        child: Text(
          'No rallies recorded yet. The official rally timeline will appear here.',
          style: SportikaType.caption,
        ),
      );
    }

    final visible = expanded
        ? snapshots.reversed.toList()
        : snapshots.reversed.take(5).toList();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0)
              const Divider(
                height: SportikaSpacing.lg,
                color: SportikaColors.borderSubtle,
              ),
            _RallyRow(snapshot: visible[i], name: nameOf(visible[i].side)),
          ],
          if (snapshots.length > 5) ...[
            const SizedBox(height: SportikaSpacing.md),
            TextButton.icon(
              onPressed: onToggle,
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                expanded
                    ? 'Show recent rallies'
                    : 'View all ${snapshots.length} rallies',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RallyRow extends StatelessWidget {
  const _RallyRow({required this.snapshot, required this.name});

  final _RallySnapshot snapshot;
  final String name;

  @override
  Widget build(BuildContext context) {
    final accent = snapshot.side == 0
        ? SportikaColors.mint
        : SportikaColors.gold;

    final score = snapshot.points == null
        ? '—'
        : '${snapshot.points![0]}–${snapshot.points![1]}';

    return Row(
      children: [
        Container(
          width: SportikaSpacing.xl * 1.5,
          height: SportikaSpacing.xl * 1.5,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(SportikaRadius.control),
          ),
          child: Icon(
            Icons.sports_tennis,
            color: accent,
            size: SportikaSpacing.lg,
          ),
        ),

        const SizedBox(width: SportikaSpacing.md),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SportikaType.bodyStrong,
              ),
              Text(
                'Rally ${snapshot.number} · Game ${snapshot.game}',
                style: SportikaType.caption,
              ),
            ],
          ),
        ),

        const SizedBox(width: SportikaSpacing.sm),

        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              score,
              style: SportikaType.bodyStrong.copyWith(
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (snapshot.complete)
              Text(
                'MATCH END',
                style: SportikaType.micro.copyWith(color: SportikaColors.gold),
              ),
          ],
        ),
      ],
    );
  }
}

class _ExpandableSection extends StatelessWidget {
  const _ExpandableSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(SportikaRadius.md),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: SportikaSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: SportikaColors.mint),
                    const SizedBox(width: SportikaSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: SportikaType.bodyStrong),
                          Text(subtitle, style: SportikaType.caption),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: SportikaColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(color: SportikaColors.borderSubtle),
            const SizedBox(height: SportikaSpacing.sm),
            child,
          ],
        ],
      ),
    );
  }
}

class _RulesSummary extends StatelessWidget {
  const _RulesSummary({
    required this.toWin,
    required this.cap,
    required this.gamesToWin,
    required this.doubles,
  });

  final int toWin;
  final int cap;
  final int gamesToWin;
  final bool doubles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MATCH RULES',
          style: SportikaType.micro.copyWith(color: SportikaColors.mint),
        ),
        const SizedBox(height: SportikaSpacing.sm),
        Text(
          'Best of ${gamesToWin * 2 - 1} games · '
          '$toWin points per game · '
          'Win by 2 · '
          'Point cap $cap',
          style: SportikaType.bodyStrong,
        ),
        const SizedBox(height: SportikaSpacing.sm),
        const Text(
          'Every rally scores. The rally winner serves next. '
          'The service court is right on an even serving score '
          'and left on an odd serving score.',
          style: SportikaType.caption,
        ),
        if (doubles) ...[
          const SizedBox(height: SportikaSpacing.sm),
          const Text(
            'Doubles service is tracked by side and court. '
            'Individual server and receiver rotation is not '
            'available in the current official match data.',
            style: SportikaType.caption,
          ),
        ],
      ],
    );
  }
}

class _TournamentLink extends StatelessWidget {
  const _TournamentLink({required this.match});

  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final competition = match.rules['competitionName'];
    final stage = match.rules['stage'];
    final id = match.tournamentId;

    return TextButton.icon(
      style: TextButton.styleFrom(alignment: Alignment.centerLeft),
      onPressed: id == null
          ? null
          : () => pushRoute(
              context,
              AppRoute.tournamentDetail,
              args: TournamentDetailArgs(id),
            ),
      icon: const Icon(Icons.emoji_events_outlined, size: SportikaSpacing.lg),
      label: Text(
        [
          competition is String && competition.isNotEmpty
              ? competition
              : 'View tournament',
          if (stage is String && stage.isNotEmpty) stage,
        ].join(' · '),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Defensive score readers
// ---------------------------------------------------------------------------

int? _nonNegativeInt(Object? value) {
  if (value is int && value >= 0) return value;

  if (value is num &&
      value.isFinite &&
      value >= 0 &&
      value == value.truncateToDouble()) {
    return value.toInt();
  }

  return null;
}

int? _positiveInt(Object? value) {
  final parsed = _nonNegativeInt(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

List<int>? _readPair(Object? raw) {
  if (raw is! List || raw.length < 2) {
    return null;
  }

  final first = _nonNegativeInt(raw[0]);
  final second = _nonNegativeInt(raw[1]);

  if (first == null || second == null) {
    return null;
  }

  return [first, second];
}

List<List<int>> _completedGames(MatchProgress progress) {
  final raw = progress.state['completedGames'];

  if (raw is! List) return const [];

  final games = <List<int>>[];

  for (final item in raw) {
    final pair = _readPair(item);

    if (pair != null) {
      games.add(pair);
    }
  }

  return games;
}

List<int>? _lastCompletedGame(MatchProgress progress) {
  final games = _completedGames(progress);
  return games.isEmpty ? null : games.last;
}
