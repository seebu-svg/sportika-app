import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// How one published fixture ended for the member whose passport is open.
enum SportingOutcome { win, loss, draw, unrecorded }

extension SportingOutcomeX on SportingOutcome {
  String get letter => switch (this) {
    SportingOutcome.win => 'W',
    SportingOutcome.loss => 'L',
    SportingOutcome.draw => 'D',
    SportingOutcome.unrecorded => '—',
  };

  String get label => switch (this) {
    SportingOutcome.win => 'Won',
    SportingOutcome.loss => 'Lost',
    SportingOutcome.draw => 'Drawn',
    SportingOutcome.unrecorded => 'No published result',
  };

  Color get tone => switch (this) {
    SportingOutcome.win => SportikaColors.mint,
    SportingOutcome.loss => SportikaColors.danger,
    SportingOutcome.draw => SportikaColors.gold,
    SportingOutcome.unrecorded => SportikaColors.textDim,
  };
}

/// The member's official playing record.
///
/// Only published fixtures that carry a result are counted: a submitted,
/// cancelled or unpublished match never reaches this number, and a draw is
/// neither a win nor a loss. A walkover counts, because the organizer published
/// a real outcome for it.
@immutable
class SportingRecord {
  const SportingRecord({
    required this.played,
    required this.wins,
    required this.losses,
    required this.draws,
  });

  static const SportingRecord empty = SportingRecord(
    played: 0,
    wins: 0,
    losses: 0,
    draws: 0,
  );

  final int played;
  final int wins;
  final int losses;
  final int draws;

  bool get isEmpty => played == 0;

  /// Null while no match has been completed, so the screen shows a dash
  /// instead of a misleading 0%.
  int? get winRate => played == 0 ? null : (wins * 100 / played).round();

  String get winRateLabel => winRate == null ? '—' : '$winRate%';
}

/// A fixture whose outcome is final: the organizer published a result, either
/// from live scoring or as a walkover.
bool _isOfficial(Fixture fixture) =>
    fixture.status == FixtureStatus.published ||
    fixture.status == FixtureStatus.walkover;

/// The member's side of a fixture, or null when the fixture is not theirs.
int? _mySideOf(Fixture fixture, Set<String> myEntryIds) {
  if (myEntryIds.contains(fixture.home.entryId)) return 0;
  if (myEntryIds.contains(fixture.away.entryId)) return 1;
  return null;
}

SportingOutcome outcomeOf(Fixture fixture, Set<String> myEntryIds) {
  final side = _mySideOf(fixture, myEntryIds);
  final result = fixture.result;
  if (side == null || result == null) return SportingOutcome.unrecorded;
  if (result.winnerIndex == side) return SportingOutcome.win;
  if (result.winnerIndex != 0 && result.winnerIndex != 1) {
    return SportingOutcome.draw;
  }
  return SportingOutcome.loss;
}

/// Finished fixtures the member appeared in, newest first.
List<Fixture> memberOfficialFixtures({
  required Iterable<Fixture> fixtures,
  required Set<String> myEntryIds,
}) {
  final mine = fixtures
      .where(
        (fixture) =>
            _isOfficial(fixture) && _mySideOf(fixture, myEntryIds) != null,
      )
      .toList();
  mine.sort(
    (a, b) => (b.completedAt ?? b.scheduledAt).compareTo(
      a.completedAt ?? a.scheduledAt,
    ),
  );
  return mine;
}

SportingRecord sportingRecordOf({
  required Iterable<Fixture> fixtures,
  required Set<String> myEntryIds,
}) {
  var played = 0, wins = 0, losses = 0, draws = 0;
  for (final fixture in fixtures) {
    // A finished match without a result proves nothing, so it is left out
    // rather than counted as a defeat.
    if (!_isOfficial(fixture) || fixture.result == null) continue;
    switch (outcomeOf(fixture, myEntryIds)) {
      case SportingOutcome.win:
        played++;
        wins++;
      case SportingOutcome.loss:
        played++;
        losses++;
      case SportingOutcome.draw:
        played++;
        draws++;
      case SportingOutcome.unrecorded:
        break;
    }
  }
  return SportingRecord(
    played: played,
    wins: wins,
    losses: losses,
    draws: draws,
  );
}

/// One compact strip: played, wins, losses and win rate.
class SportingRecordStrip extends StatelessWidget {
  const SportingRecordStrip({super.key, required this.record});

  final SportingRecord record;

  @override
  Widget build(BuildContext context) {
    final cells = <({String value, String label, Color tone})>[
      (value: '${record.played}', label: 'Matches', tone: SportikaColors.text),
      (value: '${record.wins}', label: 'Wins', tone: SportikaColors.mint),
      (value: '${record.losses}', label: 'Losses', tone: SportikaColors.gold),
      (
        value: record.winRateLabel,
        label: 'Win rate',
        tone: SportikaColors.blueBright,
      ),
    ];

    return Semantics(
      container: true,
      label:
          'Official record: ${record.played} '
          '${record.played == 1 ? 'match' : 'matches'}, ${record.wins} won, '
          '${record.losses} lost, ${record.draws} drawn, win rate '
          '${record.winRateLabel}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: SportikaColors.surfaceSunken,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SportikaColors.borderSubtle),
          ),
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 30,
                    width: 1,
                    color: SportikaColors.borderSubtle,
                  ),
                Expanded(
                  child: _RecordCell(
                    value: cells[i].value,
                    label: cells[i].label,
                    tone: cells[i].tone,
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

class _RecordCell extends StatelessWidget {
  const _RecordCell({
    required this.value,
    required this.label,
    required this.tone,
  });

  final String value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A narrow phone at the 1.3 text ceiling must scale the readout
          // down rather than clip it.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: SportikaType.score.copyWith(fontSize: 30, color: tone),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              style: SportikaType.micro,
            ),
          ),
        ],
      ),
    );
  }
}

/// The first-match experience shown while the record is still empty.
class FirstMatchCard extends StatelessWidget {
  const FirstMatchCard({super.key, required this.onFindTournament});

  final VoidCallback onFindTournament;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      fillColor: SportikaColors.surfaceSunken,
      borderColor: SportikaColors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: SportikaColors.mint.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.flag_outlined,
              size: 19,
              color: SportikaColors.mint,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your journey starts here',
            style: SportikaType.bodyStrong.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Play your first official match to start building your sporting '
            'record.',
            style: SportikaType.caption,
          ),
          const SizedBox(height: 14),
          GhostButton(
            label: 'Find a tournament',
            icon: Icons.emoji_events_outlined,
            tone: SportikaColors.mint,
            onPressed: onFindTournament,
          ),
        ],
      ),
    );
  }
}
