import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/personal_games/screens/personal_games_screen.dart';
import 'package:sportika/features/personal_games/screens/sport_scoring_screens.dart';
import 'package:sportika/app/routes.dart';

enum ScorecardMode { personal, official }

/// One scorecard screen for all four sports and both scoring modes.
///
/// The screen renders whatever the sport engine exposes: score lines, chips,
/// actions and completion state. Recording appends to the event log through
/// [LocalSportikaRepository], which is what makes undo exact and resume automatic.
class ScorecardScreen extends StatelessWidget {
  const ScorecardScreen({super.key, required this.id, required this.mode});

  final String id;
  final ScorecardMode mode;

  @override
  Widget build(BuildContext context) {
    context.watch<PersonalGamesController>();

    if (mode == ScorecardMode.personal) {
      final state = context.watch<PersonalGamesController>();
      final match = state.personalById(id);
      if (match == null ||
          match.ownerId !=
              context.read<ProfileController>().currentAccount?.id) {
        return Scaffold(
          appBar: sportikaAppBar('Scorecard'),
          body: const Padding(
            padding: EdgeInsets.all(20),
            child: EmptyState(
              title: 'Scorecard not found',
              icon: Icons.search_off,
            ),
          ),
        );
      }
      return _PersonalScorecard(match: match);
    }

    final fixture = context.read<FixturesController>().fixtureById(id);
    if (fixture == null) {
      return Scaffold(
        appBar: sportikaAppBar('Fixture'),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: EmptyState(title: 'Fixture not found', icon: Icons.search_off),
        ),
      );
    }
    return _OfficialScorecard(fixture: fixture);
  }
}

class _PersonalScorecard extends StatelessWidget {
  const _PersonalScorecard({required this.match});

  final PersonalMatch match;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PersonalGamesController>();
    context.watch<PersonalGamesController>();
    final progress = state.progressOfPersonal(match);
    final accent = sportColor(match.sport);

    return Scaffold(
      appBar: sportikaAppBar(
        match.sideNames.join(' vs '),
        subtitle: 'Private scorecard · ${match.formatLabel}',
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: SportikaColors.surfaceElevated,
            onSelected: (value) async {
              if (value == 'details') {
                pushRoute(
                  context,
                  AppRoute.personalGameDetail,
                  args: PersonalMatchArgs(match.id),
                );
              }
              if (value == 'timeline') {
                pushRoute(
                  context,
                  AppRoute.personalTimeline,
                  args: PersonalMatchArgs(match.id),
                );
              }
              if (value == 'settings') {
                pushRoute(
                  context,
                  AppRoute.personalSettings,
                  args: PersonalMatchArgs(match.id),
                );
              }
              if (value == 'pause') {
                final paused = match.status == PersonalMatchStatus.paused;
                if (await confirmPersonal(
                  context,
                  paused ? 'Resume game?' : 'Pause game?',
                  paused ? 'Continue recording your private scorecard.' : 'Your score is saved. Resume from Saved / Paused Games.',
                  paused ? 'Resume' : 'Pause',
                )) {
                  if (!context.mounted) return;
                  final state = context.read<PersonalGamesController>();
                  state.setPersonalStatus(
                    match.id,
                    paused
                        ? PersonalMatchStatus.inProgress
                        : PersonalMatchStatus.paused,
                  );
                }
              }
              if (!context.mounted) return;
              if (value == 'end' &&
                  await confirmPersonal(
                    context,
                    'End game?',
                    'Keep the recorded score and mark this game completed. An unfinished match has no inferred winner.',
                    'End game',
                  )) {
                if (!context.mounted) return;
                final state = context.read<PersonalGamesController>();
                state.setPersonalStatus(
                  match.id,
                  PersonalMatchStatus.completed,
                );
              }
              if (!context.mounted) return;
              if (value == 'delete') {
                final ok = await _confirmDelete(context);
                if (ok == true) {
                  if (!context.mounted) return;
                  final state = context.read<PersonalGamesController>();
                  state.deletePersonalMatch(match.id);
                  if (context.mounted) Navigator.of(context).maybePop();
                }
              }
              if (value == 'rules') {
                if (context.mounted) _showRules(context, match);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'details',
                child: Text('Game details / results'),
              ),
              const PopupMenuItem(
                value: 'timeline',
                child: Text('Timeline / edit scores'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Scoring settings'),
              ),
              if (match.status != PersonalMatchStatus.completed) ...[
                PopupMenuItem(
                  value: 'pause',
                  child: Text(
                    match.status == PersonalMatchStatus.paused
                        ? 'Resume game'
                        : 'Pause game',
                  ),
                ),
                const PopupMenuItem(value: 'end', child: Text('End game')),
              ],
              const PopupMenuItem(
                value: 'rules',
                child: Text('Scoring help / sport rules'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete scorecard'),
              ),
            ],
          ),
        ],
      ),
      body: _ScorecardBody(
        header: SportLiveTools(match: match),
        skipSideChoice:
            match.sport == Sport.cricket && match.details['firstBat'] != null,
        sport: match.sport,
        progress: progress,
        accent: accent,
        rawEvents: match.events,
        statusLine: match.status == PersonalMatchStatus.completed
            ? 'Completed · ${match.autoCompletedReason ?? 'rules met'}'
            : '${match.status.label} · auto-saved',
        completedNote: match.status == PersonalMatchStatus.completed
            ? (match.autoCompletedReason ?? 'Game completed.')
            : null,
        onAction: match.status != PersonalMatchStatus.inProgress
            ? null
            : (action, side) {
                final state = context.read<PersonalGamesController>();
                final built = action.build(
                  ActionContext(
                    side:
                        match.sport == Sport.cricket &&
                            match.details['firstBat'] != null
                        ? (progress.statusLabel == 'Not started'
                              ? match.details['firstBat'] as int
                              : progress.statusLabel == 'Between innings'
                              ? 1 - (progress.state['batSide'] as int)
                              : side)
                        : side,
                    by:
                        context.read<ProfileController>().currentAccount?.id ??
                        '',
                  ),
                );
                state.recordPersonalEvent(
                  match.id,
                  ScoringEvent(
                    id: newId('ev'),
                    kind: built.kind,
                    side: built.side,
                    data: {
                      ...built.data,
                      if (match.sport == Sport.cricket &&
                          built.kind == 'ball') ...{
                        if ((match.details['batter${built.side}'] ?? '')
                            .toString()
                            .isNotEmpty)
                          'batter': match.details['batter${built.side}'],
                        if ((match.details['bowler${1 - (built.side ?? 0)}'] ??
                                '')
                            .toString()
                            .isNotEmpty)
                          'bowler':
                              match.details['bowler${1 - (built.side ?? 0)}'],
                        if (built.data['wicket'] == true &&
                            (match.details['dismissal'] ?? '')
                                .toString()
                                .isNotEmpty)
                          'dismissal': match.details['dismissal'],
                      },
                    },
                    at: built.at,
                    byAccountId: built.byAccountId,
                  ),
                );
              },
        onUndo: match.events.isEmpty
            ? null
            : () async {
                if (match.details['confirmUndo'] == false ||
                    await confirmPersonal(
                      context,
                      'Undo last score?',
                      'Remove the most recent entry and recalculate the score. This may reopen a completed game.',
                      'Undo',
                    )) {
                  if (!context.mounted) return;
                  final state = context.read<PersonalGamesController>();
                  state.undoPersonalEvent(match.id);
                }
              },
        footer: const InfoBanner(
          icon: Icons.lock_outline,
          text:
              'Personal scorecards are private to you. They are never shared, '
              'submitted, or linked to an official result.',
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this scorecard?'),
        content: const Text(
          'The recorded entries will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: SportikaColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  void _showRules(BuildContext context, PersonalMatch match) {
    showAppSheet(
      context,
      AppSheet(
        title: '${match.sport.label} · ${match.formatLabel}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoBanner(text: _rulesText(match.sport, match.rules)),
            const SizedBox(height: 12),
            KeyValueRow('Side A', match.sideNames[0]),
            KeyValueRow('Side B', match.sideNames[1]),
            KeyValueRow('Entries recorded', '${match.events.length}'),
            KeyValueRow('Status', match.status.label),
          ],
        ),
      ),
    );
  }
}

class _OfficialScorecard extends StatelessWidget {
  const _OfficialScorecard({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    context.watch<PersonalGamesController>();
    final tournament = context.read<FixturesController>().tournamentOf(fixture);
    final sport = tournament?.sport ?? Sport.cricket;
    final progress = context.read<FixturesController>().progressOfFixture(
      fixture,
    );
    final accent = sportColor(sport);

    final locked =
        fixture.status == FixtureStatus.published ||
        fixture.status == FixtureStatus.walkover;
    final canScore =
        !locked &&
        fixture.status != FixtureStatus.submitted &&
        context.read<SessionController>().hasRole(UserRole.scorer) &&
        fixture.scorerAccountIds.contains(
          context.read<ProfileController>().currentAccount?.id,
        );

    return Scaffold(
      appBar: sportikaAppBar(
        '${context.read<FixturesController>().sideLabel(fixture, 0)} vs ${context.read<FixturesController>().sideLabel(fixture, 1)}',
        subtitle:
            '${tournament?.name ?? 'Official fixture'} · ${fixture.stage}',
      ),
      body: _ScorecardBody(
        sport: sport,
        progress: progress,
        accent: accent,
        rawEvents: fixture.events,
        statusLine: locked
            ? 'Official result ${fixture.result?.walkover == true ? 'walkover' : 'published'}'
            : fixture.status == FixtureStatus.submitted
            ? 'Submitted · awaiting organizer review'
            : fixture.status == FixtureStatus.live
            ? 'Live · scorer ${context.read<SessionController>().accountById(fixture.scorerAccountIds.firstOrNull)?.displayName ?? 'unassigned'}'
            : 'Ready to score',
        completedNote: locked
            ? (fixture.result?.headline ?? 'Result published')
            : progress.isComplete
            ? 'Match rules are met. Submit so the organizer can publish it.'
            : null,
        onAction: canScore
            ? (action, side) {
                final built = action.build(
                  ActionContext(
                    side: side,
                    by:
                        context.read<ProfileController>().currentAccount?.id ??
                        '',
                  ),
                );
                context.read<FixturesController>().recordOfficialEvent(
                  fixture.id,
                  ScoringEvent(
                    id: newId('ev'),
                    kind: built.kind,
                    side: built.side,
                    data: built.data,
                    at: built.at,
                    byAccountId: built.byAccountId,
                  ),
                );
              }
            : null,
        onUndo: canScore && fixture.events.isNotEmpty
            ? () => context.read<FixturesController>().undoOfficialEvent(
                fixture.id,
              )
            : null,
        footer: _OfficialFooter(
          fixture: fixture,
          progress: progress,
          locked: locked,
        ),
      ),
    );
  }
}

class _OfficialFooter extends StatelessWidget {
  const _OfficialFooter({
    required this.fixture,
    required this.progress,
    required this.locked,
  });

  final Fixture fixture;
  final MatchProgress progress;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    context.watch<PersonalGamesController>();
    if (locked) {
      final result = fixture.result;
      return SurfaceCard(
        borderColor: SportikaColors.mint.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.verified,
                  size: 16,
                  color: SportikaColors.mint,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    result?.headline ?? 'Result published',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: SportikaColors.mint,
                    ),
                  ),
                ),
              ],
            ),
            if (result != null && result.detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                result.detail,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: SportikaColors.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const InfoBanner(
              icon: Icons.lock_outline,
              tone: SportikaColors.textMuted,
              text:
                  'Published results are read-only. Bracket and table changes come '
                  'from the organizer publishing a correction.',
            ),
          ],
        ),
      );
    }

    if (fixture.status == FixtureStatus.submitted) {
      return SurfaceCard(
        borderColor: SportikaColors.gold.withValues(alpha: 0.35),
        child: Row(
          children: [
            const Icon(
              Icons.hourglass_top,
              size: 17,
              color: SportikaColors.gold,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Submitted ${fixture.events.length} entries. The organizer reviews '
                'and publishes - scoring is locked until then.',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: SportikaColors.textBody,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!context.read<SessionController>().hasRole(UserRole.scorer) ||
        !fixture.scorerAccountIds.contains(
          context.read<ProfileController>().currentAccount?.id,
        )) {
      return const InfoBanner(
        icon: Icons.lock_outline,
        text: 'Official match center · scoring is managed by the assigned scorer.',
      );
    }

    return Column(
      children: [
        PrimaryButton(
          label: progress.isComplete
              ? 'Submit for review'
              : 'Submit for review anyway',
          icon: Icons.send_rounded,
          tone: progress.isComplete
              ? SportikaColors.mint
              : SportikaColors.surfaceElevated,
          onPressed: () async {
            final fixtures = context.read<FixturesController>();
            final ok = await _confirmSubmit(context);
            if (ok == true) {
              fixtures.submitOfficialResult(fixture.id);
              if (context.mounted) Navigator.of(context).maybePop();
            }
          },
        ),
        const SizedBox(height: 10),
        const InfoBanner(
          icon: Icons.gavel,
          text:
              'Only the organizer can publish. Submitting locks the log so the '
              'reviewed score cannot change underneath them.',
        ),
      ],
    );
  }

  Future<bool?> _confirmSubmit(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit this score?'),
        content: Text(
          progress.isComplete
              ? 'The result will be sent to the organizer for review and publication.'
              : 'The match rules are not met yet. Submitting now flags the fixture as '
                    'awaiting review anyway.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

/// The shared body: score readout, context, action grid, undo and recent events.
class _ScorecardBody extends StatelessWidget {
  const _ScorecardBody({
    required this.sport,
    required this.progress,
    required this.accent,
    required this.rawEvents,
    required this.statusLine,
    required this.onAction,
    required this.onUndo,
    required this.footer,
    this.completedNote,
    this.header,
    this.skipSideChoice = false,
  });

  final Sport sport;
  final MatchProgress progress;
  final Color accent;
  final List<Map<String, dynamic>> rawEvents;
  final String statusLine;
  final String? completedNote;
  final void Function(ScoreAction action, int? side)? onAction;
  final VoidCallback? onUndo;
  final Widget footer;
  final Widget? header;
  final bool skipSideChoice;

  @override
  Widget build(BuildContext context) {
    final recent = rawEvents.reversed.take(6).toList();

    return _SideScope(
      sides: progress.sides,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ?header,
          Row(
            children: [
              SportTag(sport),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < progress.lines.length; i++) ...[
            ScoreLineTile(
              line: progress.lines[i],
              color: accent,
              highlight: i == 0,
            ),
            if (i != progress.lines.length - 1) const SizedBox(height: 7),
          ],
          if (progress.headline.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              progress.headline,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: progress.isComplete
                    ? SportikaColors.mint
                    : SportikaColors.text,
              ),
            ),
          ],
          if (progress.contextChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in progress.contextChips)
                  StatusPill(chip, color: accent),
              ],
            ),
          ],
          if (progress.detailRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in progress.detailRows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        row,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (completedNote != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SportikaColors.mintSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: SportikaColors.mint.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.flag_rounded,
                    size: 16,
                    color: SportikaColors.mint,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      completedNote!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: SportikaColors.textBody,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (onAction != null && progress.actions.isNotEmpty) ...[
            const SectionTitle('Record the next entry'),
            _ActionGrid(
              actions: progress.actions,
              skipSideChoice: skipSideChoice,
              accent: accent,
              onAction: onAction!,
            ),
          ],
          if (progress.isComplete && onAction != null) ...[
            const SizedBox(height: 10),
            const InfoBanner(
              icon: Icons.emoji_events_outlined,
              tone: SportikaColors.mint,
              text:
                  'Match complete under the rules. Undo the last entry if you need to '
                  'correct the finish.',
            ),
          ],
          if (onUndo != null) ...[
            const SizedBox(height: 14),
            GhostButton(
              label: 'Undo last entry',
              icon: Icons.undo_rounded,
              tone: SportikaColors.textBody,
              expand: true,
              onPressed: onUndo,
            ),
          ],
          if (recent.isNotEmpty) ...[
            const SectionTitle('Last entries'),
            for (final raw in recent)
              _EventRow(
                label: _eventLabel(raw, progress.sides),
                side: (raw['side'] as num?)?.toInt(),
                at:
                    DateTime.tryParse(raw['at'] as String? ?? '') ??
                    DateTime.now(),
                accent: accent,
              ),
          ],
          const SizedBox(height: 18),
          footer,
        ],
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.actions,
    required this.accent,
    required this.onAction,
    this.skipSideChoice = false,
  });

  final bool skipSideChoice;
  final List<ScoreAction> actions;
  final Color accent;
  final void Function(ScoreAction action, int? side) onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 380 ? 3 : 2;
        const gap = 8.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: _ActionButton(
                  action: action,
                  accent: accent,
                  onTap: () => _tap(context, action),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _tap(BuildContext context, ScoreAction action) async {
    if (!action.pickSide || skipSideChoice) {
      onAction(action, null);
      return;
    }
    final side = await _pickSide(context, action);
    if (side == null) return;
    onAction(action, side);
  }

  Future<int?> _pickSide(BuildContext context, ScoreAction action) {
    final sides = _SideScope.of(context).sides;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AppSheet(
        title: action.label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action.hint != null) ...[
              InfoBanner(text: action.hint!),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < sides.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: sides[i],
                    icon: Icons.sports_score,
                    small: true,
                    tone: i == 0 ? SportikaColors.blue : SportikaColors.mint,
                    onPressed: () => Navigator.pop(ctx, i),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Provides side names to action buttons without threading them through every
/// constructor.
class _SideScope extends InheritedWidget {
  const _SideScope({required this.sides, required super.child});

  final List<String> sides;

  static _SideScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SideScope>() ??
      const _SideScope(sides: ['Side A', 'Side B'], child: SizedBox.shrink());

  @override
  bool updateShouldNotify(_SideScope oldWidget) => oldWidget.sides != sides;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.accent,
    required this.onTap,
  });

  final ScoreAction action;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = styleColors(action.style);
    final fill = action.style == ActionStyle.neutral
        ? SportikaColors.surfaceAlt
        : colors.fill;
    final fg = action.style == ActionStyle.neutral
        ? SportikaColors.text
        : colors.fg;
    final border = action.style == ActionStyle.neutral
        ? SportikaColors.border
        : colors.border.withValues(alpha: 0.7);

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: action.label.length <= 2 ? 20 : 13.5,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              if (action.hint != null) ...[
                const SizedBox(height: 2),
                Text(
                  action.hint!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: fg.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.label,
    required this.side,
    required this.at,
    required this.accent,
  });

  final String label;
  final int? side;
  final DateTime at;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: side == null
                  ? SportikaColors.textDim
                  : (side == 0 ? accent : SportikaColors.mint),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: SportikaColors.textBody,
              ),
            ),
          ),
          Text(
            timeLabel(at),
            style: const TextStyle(
              fontSize: 10.5,
              color: SportikaColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

String _eventLabel(Map<String, dynamic> raw, List<String> sides) {
  final kind = raw['kind'] as String? ?? '';
  final side = (raw['side'] as num?)?.toInt();
  final name = side == null || side >= sides.length ? null : sides[side];
  final data = Map<String, dynamic>.from(raw['data'] as Map? ?? const {});

  switch (kind) {
    case 'ball':
      final runs = (data['runs'] as num?)?.toInt() ?? 0;
      final extra = data['extra'] as String?;
      if (data['wicket'] == true) return '$name · wicket';
      if (extra != null) return '$name · $extra +$runs';
      return '$name · $runs run${runs == 1 ? '' : 's'}';
    case 'innings_end':
      return 'Innings closed${data['reason'] == null ? '' : ' · ${data['reason']}'}';
    case 'point':
      return '$name · point';
    case 'goal':
      return '$name · goal';
    case 'penalty':
      return '$name · penalty ${data['scored'] == true ? 'scored' : 'missed'}';
    case 'rally':
      return '$name · rally';
    case 'clock':
      return 'Clock · ${data['action']}';
    default:
      return '$kind${name == null ? '' : ' · $name'}';
  }
}

String _rulesText(Sport sport, Map<String, dynamic> rules) {
  final entries = rules.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
  return entries.isEmpty
      ? SportEngines.rulesFor(
          sport,
          SportEngines.formatsFor(sport).first,
        ).entries.map((e) => '${e.key}: ${e.value}').join(' · ')
      : entries;
}
