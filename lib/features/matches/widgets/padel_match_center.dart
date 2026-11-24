import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The one status vocabulary a Padel Match Center speaks.
///
/// Every Padel surface (detail screen, scoring shell, result panel) resolves
/// its badge through [padelMatchStatusOf] so the same published match can never
/// be labelled two different ways again. The label delegates to
/// [FixtureStatusX.label] on purpose: it is the app-wide status wording, and
/// only a paused live match overrides it.
enum PadelMatchPhase {
  scheduled,
  live,
  paused,
  review,
  published,
  walkover,
  cancelled,
}

class PadelMatchStatus {
  const PadelMatchStatus({
    required this.phase,
    required this.label,
    required this.tone,
    required this.icon,
  });

  final PadelMatchPhase phase;
  final String label;
  final Color tone;
  final IconData icon;

  /// The match has stopped producing points.
  bool get isClosed =>
      phase == PadelMatchPhase.published ||
      phase == PadelMatchPhase.walkover ||
      phase == PadelMatchPhase.cancelled;

  /// There is a recorded result to present, published or still under review.
  bool get showsResult =>
      phase == PadelMatchPhase.review ||
      phase == PadelMatchPhase.published ||
      phase == PadelMatchPhase.walkover;

  /// Play may still continue, so the strip tracks the live set rather than an
  /// endpoint.
  bool get isInPlay =>
      phase == PadelMatchPhase.live ||
      phase == PadelMatchPhase.paused ||
      phase == PadelMatchPhase.review;
}

PadelMatchStatus padelMatchStatusOf(SportMatch match, MatchProgress progress) {
  final tone = statusColor(match.status.key);
  final icon = statusIcon(match.status.key);
  if (match.status == FixtureStatus.cancelled) {
    return PadelMatchStatus(
      phase: PadelMatchPhase.cancelled,
      label: match.status.label,
      tone: tone,
      icon: icon,
    );
  }
  if (match.status == FixtureStatus.walkover) {
    return PadelMatchStatus(
      phase: PadelMatchPhase.walkover,
      label: match.status.label,
      tone: tone,
      icon: Icons.flag_outlined,
    );
  }
  if (match.status == FixtureStatus.published) {
    return PadelMatchStatus(
      phase: PadelMatchPhase.published,
      label: match.status.label,
      tone: tone,
      icon: Icons.verified_outlined,
    );
  }
  if (match.awaitingReview) {
    return PadelMatchStatus(
      phase: PadelMatchPhase.review,
      label: match.status.label,
      tone: tone,
      icon: Icons.hourglass_top_outlined,
    );
  }
  if (match.isLive) {
    return match.isPaused
        ? const PadelMatchStatus(
            phase: PadelMatchPhase.paused,
            label: 'Paused',
            tone: SportikaColors.gold,
            icon: Icons.pause_circle_outline,
          )
        : const PadelMatchStatus(
            phase: PadelMatchPhase.live,
            label: 'Live',
            tone: SportikaColors.mint,
            icon: Icons.sensors,
          );
  }
  return PadelMatchStatus(
    phase: PadelMatchPhase.scheduled,
    label: match.status.label,
    tone: tone,
    icon: Icons.schedule,
  );
}

/// Photography band shared by every Padel hero. The art is always present;
/// only the scrim treatment and the overlay strip change with the phase, so a
/// scheduled, live, completed and published match read as one screen.
class PadelHeroArt extends StatelessWidget {
  const PadelHeroArt({super.key, required this.status, this.overlay});

  final PadelMatchStatus status;

  /// The eyebrow, badge and phase extras laid over the bottom of the frame.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A tall band on a phone, and never a square on a wide tablet.
        final height = (constraints.maxWidth * .42).clamp(148.0, 216.0);
        return SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _PadelFrame(),
              // Top scrim keeps the eyebrow legible on a bright court frame; the
              // bottom fades into the page so the content below continues the
              // photograph rather than sitting under it.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      SportikaColors.deepest,
                      SportikaColors.transparent,
                      SportikaColors.background,
                    ],
                    stops: status.phase == PadelMatchPhase.scheduled
                        ? const [0, .38, 1]
                        : const [0, .52, 1],
                  ),
                ),
              ),
              if (status.isClosed || status.showsResult)
                // Closed frames read flatter: a cool veil over the action so the
                // result typography below is the loudest thing on the screen.
                ColoredBox(
                  color: SportikaColors.deepest.withValues(alpha: .25),
                ),
              Positioned(
                left: SportikaSpacing.lg,
                right: SportikaSpacing.lg,
                top: SportikaSpacing.md,
                bottom: SportikaSpacing.md,
                child: overlay ?? const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PadelFrame extends StatelessWidget {
  const _PadelFrame();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/sports/padel_match_action.jpg',
      fit: BoxFit.cover,
      alignment: const Alignment(0, -.2),
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, synchronous) =>
          frame == null && !synchronous
          ? const ColoredBox(color: SportikaColors.surfaceSunken)
          : child,
      errorBuilder: (context, error, stackTrace) => Image.asset(
        'assets/images/sports/padel.jpg',
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) =>
            const ColoredBox(color: SportikaColors.surfaceSunken),
      ),
    );
  }
}

/// The strip over the hero art: brand eyebrow, the one status badge, and the
/// extras that belong to the phase (kickoff for a scheduled match, the set
/// number in play, the endpoint once closed).
class PadelHeroStrip extends StatelessWidget {
  const PadelHeroStrip({super.key, required this.match, required this.status});

  final SportMatch match;
  final PadelMatchStatus status;

  /// Extras that belong to the phase: the kickoff for a scheduled match, and
  /// the recorded endpoint once one exists. The set number deliberately is
  /// not repeated here — the scoreboard owns in-play context, so one fact has
  /// exactly one owner on the screen.
  String? get _endpoint {
    if (status.phase == PadelMatchPhase.scheduled) {
      return dateShort(match.scheduledAt.toLocal());
    }
    final end = match.completedAt ?? match.submittedAt;
    final started = match.startedAt;
    if (started == null || end == null) return null;
    final elapsed = end.difference(started);
    if (elapsed.isNegative) return null;
    final hours = elapsed.inHours;
    return '${hours > 0 ? '${hours}h ' : ''}'
        '${elapsed.inMinutes.remainder(60)}m played';
  }

  @override
  Widget build(BuildContext context) {
    final extra = _endpoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'SPORTIKA · MATCH CENTER',
          style: SportikaType.micro.copyWith(color: SportikaColors.textDim),
        ),
        Row(
          children: [
            StatusPill(status.label, color: status.tone, icon: status.icon),
            if (extra != null) ...[
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  extra,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: SportikaType.caption.copyWith(
                    color: SportikaColors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A single Padel player face. This is the only avatar treatment on a Padel
/// Match Center: hero, lineup and winner row all build on it so a face is the
/// same shape, ring and fallback chain everywhere.
class PadelFace extends StatelessWidget {
  const PadelFace({
    super.key,
    required this.player,
    this.size,
    this.serving = false,
    this.isYou = false,
    this.winner = false,
    this.showName = true,
    this.role,
  });

  final MatchParticipant? player;
  final double? size;
  final bool serving;
  final bool isYou;
  final bool winner;
  final bool showName;

  /// Optional caption under the name, e.g. `Official scorer`.
  final String? role;

  static const double _singleSize = SportikaSpacing.xl * 2.5;
  static const double _pairSize = SportikaSpacing.xl * 2;
  static const double _compactSize = SportikaSpacing.xl * 1.5;

  @override
  Widget build(BuildContext context) {
    final person = player;
    final account = person == null
        ? null
        : context.watch<SessionController>().accountById(person.profileId);
    final name = person?.displayName.trim().isNotEmpty == true
        ? person!.displayName
        : 'Open place';
    final side = size ?? _singleSize;
    final label = serving ? '$name, serving' : name;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: label,
          child: Container(
            padding: const EdgeInsets.all(SportikaSpacing.xs / 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: serving
                    ? SportikaColors.mint
                    : winner
                    ? SportikaColors.gold
                    : SportikaColors.borderSubtle,
              ),
            ),
            child: PlayerAvatar(
              initials: person == null ? '—' : initialsOf(name),
              photoUrl: account?.photoUrl,
              photoPath: account?.photoPath,
              size: side,
              color: SportikaColors.textMuted,
              ring: SportikaColors.surfaceSunken,
            ),
          ),
        ),
        if (showName) ...[
          const SizedBox(height: SportikaSpacing.xs),
          SizedBox(
            width: side + SportikaSpacing.lg,
            child: Tooltip(
              message: name,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: winner
                    ? SportikaType.caption.copyWith(color: SportikaColors.gold)
                    : SportikaType.caption,
              ),
            ),
          ),
          if (isYou || role != null) ...[
            const SizedBox(height: SportikaSpacing.xs / 2),
            Text(
              [if (isYou) 'You', ?role].join(' · '),
              style: SportikaType.micro,
            ),
          ],
        ],
      ],
    );
  }
}

/// One side's players, laid out as a row and stacked only when a pair cannot
/// sit side by side at the current text scale.
class PadelSideFaces extends StatelessWidget {
  const PadelSideFaces({
    super.key,
    required this.match,
    this.progress,
    required this.side,
    this.size,
    this.showNames = true,
    this.narrowStack = false,
    this.accountId,
    this.winnerIndex = -1,
  });

  final SportMatch match;

  /// The fold is only needed for the serving ring. A host that presents the
  /// recorded result has no live state to read and passes null.
  final MatchProgress? progress;
  final int side;
  final double? size;
  final bool showNames;

  /// Host has already decided the pair must stack; skips the measuring path.
  final bool narrowStack;
  final String? accountId;
  final int winnerIndex;

  @override
  Widget build(BuildContext context) {
    final doubles = match.discipline == MatchDiscipline.doubles;
    final slots = doubles ? 2 : 1;
    final members = match.participantsOnSide(side).take(slots).toList();
    final serving =
        match.isLive &&
        !match.isPaused &&
        progress != null &&
        !progress!.isComplete &&
        match.result == null &&
        match.corrections.isEmpty;
    final servingSide = _number(progress?.state['servingSide']);
    final servingMember = _number(progress?.state['servingMember']);
    final faceSize =
        size ??
        (showNames
            ? (doubles ? PadelFace._pairSize : PadelFace._singleSize)
            : PadelFace._compactSize);
    final faces = <Widget>[
      for (var i = 0; i < slots; i++)
        PadelFace(
          player: members.length > i ? members[i] : null,
          size: faceSize,
          showName: showNames,
          isYou: members.length > i && members[i].profileId == accountId,
          winner: winnerIndex == side,
          role: _roleOf(match, members, i),
          serving:
              serving &&
              servingSide == side &&
              (!doubles || servingMember == i) &&
              members.length > i,
        ),
    ];
    if (!doubles) return faces.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A pair only breaks into a column when the two faces genuinely
        // cannot sit side by side at the caller's own text scale.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stack =
            narrowStack ||
            constraints.maxWidth < (faceSize + SportikaSpacing.md) * 2 * scale;
        if (stack) {
          return Column(
            children: [
              for (var i = 0; i < faces.length; i++) ...[
                if (i > 0) const SizedBox(height: SportikaSpacing.sm),
                faces[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final face in faces) Expanded(child: face)],
        );
      },
    );
  }

  static String? _roleOf(
    SportMatch match,
    List<MatchParticipant> members,
    int index,
  ) {
    if (index >= members.length) return null;
    final id = members[index].profileId;
    if (id == match.scorerId) return 'Official scorer';
    if (id == match.organizerId) return 'Organizer';
    return null;
  }
}

/// Two sides facing each other with the shared VS marker. Used by the hero
/// (names hidden), the Players tab (full) and the result panel (winner only).
class PadelHeadToHead extends StatelessWidget {
  const PadelHeadToHead({
    super.key,
    required this.match,
    required this.progress,
    this.showNames = true,
    this.accountId,
    this.winnerIndex = -1,
    this.sideLabelStyle,
    this.onInviteSide,
  });

  final SportMatch match;
  final MatchProgress? progress;
  final bool showNames;
  final String? accountId;
  final int winnerIndex;
  final TextStyle? sideLabelStyle;
  final ValueChanged<int>? onInviteSide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final tight = constraints.maxWidth < PadelFace._pairSize * 7 * scale;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var side = 0; side < 2; side++) ...[
              if (side == 1)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tight ? SportikaSpacing.xs : SportikaSpacing.sm,
                    vertical: showNames
                        ? SportikaSpacing.xl
                        : SportikaSpacing.md,
                  ),
                  child: Text(
                    'VS',
                    style: SportikaType.micro.copyWith(
                      color: SportikaColors.textDim,
                    ),
                  ),
                ),
              Expanded(
                child: _LabelledSide(
                  match: match,
                  side: side,
                  showNames: showNames,
                  labelStyle: sideLabelStyle,
                  child: Column(
                    children: [
                      PadelSideFaces(
                        match: match,
                        progress: progress,
                        side: side,
                        showNames: showNames,
                        narrowStack: tight && showNames,
                        accountId: accountId,
                        winnerIndex: winnerIndex,
                      ),
                      if (onInviteSide != null)
                        TextButton.icon(
                          onPressed: () => onInviteSide!(side),
                          icon: const Icon(
                            Icons.person_add_alt,
                            size: SportikaSpacing.lg,
                          ),
                          label: const Text(
                            'Invite',
                            style: SportikaType.action,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LabelledSide extends StatelessWidget {
  const _LabelledSide({
    required this.match,
    required this.side,
    required this.showNames,
    required this.labelStyle,
    required this.child,
  });

  final SportMatch match;
  final int side;
  final bool showNames;
  final TextStyle? labelStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final name = match.sideLabels.length > side
        ? match.sideLabels[side]
        : 'Side ${side + 1}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showNames) ...[
          SizedBox(
            // Two lines at the title size, tracked to the text scale, so a long
            // pair name wraps instead of pushing the VS marker off screen.
            height:
                (labelStyle?.fontSize ?? SportikaType.title.fontSize!) *
                (labelStyle?.height ?? SportikaType.title.height!) *
                2 *
                MediaQuery.textScalerOf(context).scale(1),
            child: Tooltip(
              message: name,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: labelStyle ?? SportikaType.title,
              ),
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
        ],
        child,
      ],
    );
  }
}

/// Match details rows for the Summary tab. One widget so the detail screen and
/// the scoring shell can never show a different fact set for the same match.
class PadelMatchFacts extends StatelessWidget {
  const PadelMatchFacts({super.key, required this.match});

  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Scheduled', dateShort(match.scheduledAt.toLocal())),
      if (match.venue.isNotEmpty) ('Venue', match.venue),
      ('Format', match.formatLabel),
      ('Discipline', match.discipline.label),
      if (match.isTournamentMatch &&
          match.rules['stage'] is String &&
          (match.rules['stage'] as String).isNotEmpty)
        ('Stage', match.rules['stage'] as String),
      if (match.isPaused && match.pauseReason?.isNotEmpty == true)
        ('Pause reason', match.pauseReason!),
      if (match.result?.detail.isNotEmpty == true)
        ('Result detail', match.result!.detail),
    ];
    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'MATCH DETAILS',
            style: SportikaType.micro.copyWith(color: SportikaColors.textDim),
          ),
          const SizedBox(height: SportikaSpacing.md),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: KeyValueRow(row.$1, row.$2),
            ),
        ],
      ),
    );
  }
}

int? _number(dynamic value) =>
    value is num &&
        value.isFinite &&
        value >= 0 &&
        value == value.truncateToDouble()
    ? value.toInt()
    : null;

/// The official Padel result, driven only by the recorded [OfficialResult].
///
/// This is the single Padel result presentation: both the detail screen and
/// the scoring shell reach it through [PadelMatchHero], so one published match
/// cannot show two result layouts again. The engine fold is never consulted
/// here — a correction stays visible verbatim rather than being reinterpreted.
class PadelResultPanel extends StatelessWidget {
  const PadelResultPanel({super.key, required this.match});

  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final result = match.result;
    if (result == null || match.status == FixtureStatus.cancelled) {
      return const SizedBox.shrink();
    }
    final published =
        match.status == FixtureStatus.published ||
        match.status == FixtureStatus.walkover;
    final names = [
      for (var side = 0; side < 2; side++)
        match.sideLabels.length > side
            ? match.sideLabels[side]
            : 'Side ${side + 1}',
    ];
    final winner = result.winnerIndex;
    final hasWinner = winner >= 0 && winner < 2;
    final sets = result.walkover ? const <List<String>>[] : _setsOf(result);
    final eyebrow = published
        ? result.walkover
              ? 'OFFICIAL RESULT · WALKOVER'
              : 'FINAL · OFFICIAL RESULT'
        : 'AWAITING REVIEW';
    return SurfaceCard(
      fillColor: SportikaColors.surfaceSunken,
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: SportikaSpacing.sm,
            runSpacing: SportikaSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                eyebrow,
                style: SportikaType.micro.copyWith(
                  color: published
                      ? SportikaColors.gold
                      : SportikaColors.textMuted,
                ),
              ),
              if (match.corrections.isNotEmpty)
                const StatusPill(
                  'Corrected',
                  color: SportikaColors.gold,
                  icon: Icons.edit_note_outlined,
                ),
            ],
          ),
          if (hasWinner) ...[
            const SizedBox(height: SportikaSpacing.md),
            // Winner faces use the same avatar treatment as the lineup, so a
            // player's face is never two different shapes on one screen.
            Align(
              alignment: Alignment.centerLeft,
              child: PadelSideFaces(
                match: match,
                side: winner,
                winnerIndex: winner,
              ),
            ),
          ],
          const SizedBox(height: SportikaSpacing.md),
          Text(
            hasWinner
                ? names[winner]
                : winner < 0
                ? 'Match drawn'
                : 'Result recorded',
            style: SportikaType.headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasWinner) ...[
            const SizedBox(height: SportikaSpacing.xs),
            Text(
              result.walkover ? 'Awarded by walkover' : 'Match winner',
              style: SportikaType.caption.copyWith(color: SportikaColors.gold),
            ),
          ],
          const SizedBox(height: SportikaSpacing.lg),
          Text(
            result.walkover ? 'AWARDED RESULT' : 'FINAL SETS',
            style: SportikaType.micro.copyWith(color: SportikaColors.textDim),
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ResultSide(match: match, side: 0)),
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.md,
                  vertical: SportikaSpacing.xs,
                ),
                child: Text('–', style: SportikaType.title),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _ResultSide(match: match, side: 1),
                ),
              ),
            ],
          ),
          if (!result.walkover) ...[
            const SizedBox(height: SportikaSpacing.md),
            const Divider(height: 1, color: SportikaColors.borderSubtle),
            if (sets.isNotEmpty)
              PadelSetMatrix(sets: sets, names: names)
            else
              // A custom correction is not a set matrix; show it verbatim
              // rather than inventing scores that were never recorded.
              for (var side = 0; side < 2; side++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: SportikaSpacing.sm,
                  ),
                  child: KeyValueRow(
                    names[side],
                    result.sideScores.length > side &&
                            result.sideScores[side].isNotEmpty
                        ? result.sideScores[side]
                        : '—',
                  ),
                ),
          ],
          if (result.headline.isNotEmpty || result.detail.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            if (result.headline.isNotEmpty)
              Text(result.headline, style: SportikaType.body),
            if (result.detail.isNotEmpty)
              Text(result.detail, style: SportikaType.caption),
          ],
          const SizedBox(height: SportikaSpacing.md),
          Text(
            published
                ? 'Published ${dateShort(result.publishedAt.toLocal())}'
                : 'Scoring is closed. The organizer reviews and publishes '
                      'this result.',
            style: SportikaType.caption,
          ),
          if (result.walkover) ...[
            const SizedBox(height: SportikaSpacing.xs),
            const Text(
              'Awarded without a played result.',
              style: SportikaType.caption,
            ),
          ],
        ],
      ),
    );
  }
}

/// One side's sets-won readout, taken only from the recorded result.
class _ResultSide extends StatelessWidget {
  const _ResultSide({required this.match, required this.side});
  final SportMatch match;
  final int side;

  @override
  Widget build(BuildContext context) {
    final result = match.result!;
    final winner = result.winnerIndex;
    final leading = side == 0;
    return Column(
      crossAxisAlignment: leading
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          result.walkover
              ? winner == side
                    ? 'W/O'
                    : '—'
              : result.sideValues.length > side
              ? '${result.sideValues[side]}'
              : '—',
          style: SportikaType.score.copyWith(
            color: winner == side
                ? SportikaColors.text
                : SportikaColors.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: SportikaSpacing.xs),
        Tooltip(
          message: match.sideLabels.length > side
              ? match.sideLabels[side]
              : 'Side ${side + 1}',
          child: Text(
            match.sideLabels.length > side
                ? match.sideLabels[side]
                : 'Side ${side + 1}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: winner == side
                ? SportikaType.bodyStrong.copyWith(color: SportikaColors.gold)
                : SportikaType.bodyStrong,
          ),
        ),
      ],
    );
  }
}

/// Set-by-set grid for a published result. Scrolls rather than squeezes, so a
/// five-set match stays readable on a narrow phone at a large text scale.
class PadelSetMatrix extends StatelessWidget {
  const PadelSetMatrix({super.key, required this.sets, required this.names});

  final List<List<String>> sets;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    if (sets.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final minimumWidth =
            (SportikaSpacing.xl * 4 + sets.length * SportikaSpacing.xl * 2) *
            scale;
        Widget cell(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(
            vertical: SportikaSpacing.sm,
            horizontal: SportikaSpacing.xs,
          ),
          child: child,
        );
        Widget head(String text, {int? set}) => Text(
          text,
          textAlign: set == null ? TextAlign.start : TextAlign.center,
          style: SportikaType.micro.copyWith(color: SportikaColors.textDim),
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minimumWidth > constraints.maxWidth
                ? minimumWidth
                : constraints.maxWidth,
            child: Table(
              columnWidths: {
                0: FixedColumnWidth(SportikaSpacing.xl * 4 * scale),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    cell(head('TEAM')),
                    for (var i = 0; i < sets.length; i++)
                      cell(head('S${i + 1}', set: i)),
                  ],
                ),
                for (var side = 0; side < 2; side++)
                  TableRow(
                    children: [
                      cell(Text(names[side], style: SportikaType.bodyStrong)),
                      for (final set in sets)
                        cell(
                          Text(
                            set[side],
                            textAlign: TextAlign.center,
                            style: SportikaType.scoreSmall.copyWith(
                              color:
                                  int.parse(set[side]) >
                                      int.parse(set[1 - side])
                                  ? SportikaColors.text
                                  : SportikaColors.textDim,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Validates that both official score strings describe the same sets and
/// returns the matrix. A custom correction returns empty so the panel can show
/// it verbatim instead of reinterpreting it.
List<List<String>> _setsOf(OfficialResult result) {
  final scores = result.sideScores;
  if (scores.length != 2) return const [];
  final pattern = RegExp(r'^(\d+)\s*[-–]\s*(\d+)$');
  final first = scores[0].split(',');
  final second = scores[1].split(',');
  if (first.length != second.length) return const [];
  final sets = <List<String>>[];
  for (var i = 0; i < first.length; i++) {
    final a = pattern.firstMatch(first[i].trim());
    final b = pattern.firstMatch(second[i].trim());
    if (a == null || b == null || a[1] != b[2] || a[2] != b[1]) return const [];
    if (int.tryParse(a[1]!) == null || int.tryParse(a[2]!) == null) {
      return const [];
    }
    sets.add([a[1]!, a[2]!]);
  }
  return sets;
}

/// The one Padel hero. Every Padel surface renders its match through this
/// widget: the photo band, the status strip, the identity block, the shared
/// head-to-head faces, and then either the live scoreboard or the official
/// result panel — never both, and never a sport-generic substitute.
class PadelMatchHero extends StatelessWidget {
  const PadelMatchHero({
    super.key,
    required this.match,
    required this.progress,
    this.accountId,
  });

  final SportMatch match;
  final MatchProgress progress;
  final String? accountId;

  @override
  Widget build(BuildContext context) {
    final status = padelMatchStatusOf(match, progress);
    final cancelled = status.phase == PadelMatchPhase.cancelled;
    final result = cancelled ? null : match.result;
    final winner =
        result?.winnerIndex ??
        (progress.isComplete ? progress.winnerIndex : -1);
    final names = [
      for (var i = 0; i < 2; i++)
        match.sideLabels.length > i ? match.sideLabels[i] : 'Side ${i + 1}',
    ];
    final competition = match.rules['competitionName'];
    final round = match.rules['stage'];
    final outcome = cancelled
        ? 'No official result was awarded.'
        : result?.headline.isNotEmpty == true
        ? result!.headline
        : result != null
        ? (result.walkover
              ? 'Awarded by walkover'
              : result.winnerIndex < 0
              ? 'Match drawn'
              : '')
        : progress.isComplete
        ? progress.resultLabel
        : '';
    final setsToWin = progress.state['setsToWin'];
    final format = setsToWin is num && setsToWin > 0
        ? 'Best of ${setsToWin.toInt() * 2 - 1}'
        : match.formatLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PadelHeroArt(
          status: status,
          overlay: PadelHeroStrip(match: match, status: status),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SportikaSpacing.lg,
            SportikaSpacing.xs,
            SportikaSpacing.lg,
            SportikaSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                match.title,
                style: SportikaType.hero,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: SportikaSpacing.sm),
              Text(
                [
                  match.isTournamentMatch ? 'Tournament' : 'Friendly',
                  if (match.discipline != MatchDiscipline.team)
                    match.discipline == MatchDiscipline.doubles
                        ? 'Doubles'
                        : 'Singles',
                  if (format.isNotEmpty) format,
                ].join(' · '),
                style: SportikaType.caption,
              ),
              if ((competition is String && competition.isNotEmpty) ||
                  (round is String && round.isNotEmpty)) ...[
                const SizedBox(height: SportikaSpacing.xs),
                Text(
                  [
                    if (competition is String && competition.isNotEmpty)
                      competition,
                    if (round is String && round.isNotEmpty) round,
                  ].join(' · '),
                  style: SportikaType.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: SportikaSpacing.md),
              // The pairing reads first. Names stay hidden here because the
              // scoreboard and the result panel both repeat them below.
              PadelHeadToHead(
                match: match,
                progress: progress,
                showNames: false,
                accountId: accountId,
                winnerIndex: result != null ? winner : -1,
              ),
              const SizedBox(height: SportikaSpacing.md),
              const Divider(height: 1, color: SportikaColors.borderSubtle),
              const SizedBox(height: SportikaSpacing.md),
              if (result != null)
                PadelResultPanel(match: match)
              else
                // The scoreboard keeps the fold only while it agrees with the
                // recorded result; that arbitration lives inside it.
                MatchScoreboard(
                  sport: match.sport,
                  labels: names,
                  compact: true,
                  showDetails: false,
                  showOutcome: false,
                  progress:
                      !cancelled &&
                          (match.isLive ||
                              match.awaitingReview ||
                              result != null)
                      ? progress
                      : null,
                  result: result,
                  finished: match.isFinished,
                ),
              if (result == null &&
                  !cancelled &&
                  winner >= 0 &&
                  winner < names.length) ...[
                const SizedBox(height: SportikaSpacing.sm),
                Text(
                  '${names[winner]} · Winner',
                  style: SportikaType.bodyStrong.copyWith(
                    color: SportikaColors.gold,
                  ),
                ),
              ],
              if (result == null && outcome.isNotEmpty) ...[
                const SizedBox(height: SportikaSpacing.xs),
                Text(outcome, style: SportikaType.body),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The Match Center tab strip. One definition so the detail screen and the
/// scoring shell offer the same navigation for the same match.
class PadelMatchTabBar extends StatelessWidget implements PreferredSizeWidget {
  const PadelMatchTabBar({super.key});

  static const List<String> labels = [
    'Summary',
    'Scorecard',
    'Players',
    'Timeline',
  ];

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelStyle: SportikaType.action,
      indicatorColor: SportikaColors.mint,
      labelColor: SportikaColors.text,
      unselectedLabelColor: SportikaColors.textMuted,
      dividerColor: SportikaColors.transparent,
      tabs: [for (final label in labels) Tab(text: label)],
    );
  }
}

/// The Match Center chrome. One definition so the eyebrow, the sport title and
/// the status badge cannot drift between the detail screen and the scoring
/// shell. Status always resolves through [padelMatchStatusOf]; the host only
/// supplies its own trailing actions.
AppBar padelMatchAppBar({
  required SportMatch match,
  required MatchProgress progress,
  List<Widget> actions = const [],
}) {
  final status = padelMatchStatusOf(match, progress);
  return AppBar(
    titleSpacing: SportikaSpacing.lg,
    backgroundColor: SportikaColors.background,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SPORTIKA · MATCH CENTER', style: SportikaType.micro),
        const SizedBox(height: SportikaSpacing.xs / 2),
        Flexible(
          // A tournament stage appended to the sport name can outgrow the
          // title slot; scale it down rather than ellipsising the brand.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(match.sport.label, style: SportikaType.title),
          ),
        ),
      ],
    ),
    actions: [
      StatusPill(status.label, color: status.tone, icon: status.icon),
      ...actions,
    ],
  );
}
