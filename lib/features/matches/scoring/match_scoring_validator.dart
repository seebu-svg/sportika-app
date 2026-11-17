import 'package:sportika/features/personal_games/scoring/badminton/badminton.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/features/personal_games/scoring/padel/padel.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/features/matches/scoring/futsal_roster.dart';

/// Writes one scoring action from a workspace into the shared event log.
typedef RecordMatchEvent = void Function(
  String kind,
  int? side,
  Map<String, dynamic> data,
);

/// Pre-flight checks for a scoring tap.
///
/// The four engines are the rule books; they fold whatever they are given and
/// quietly ignore a payload they did not expect. That is right for a log, but
/// it is the wrong experience for a tap: a mistyped payload records an entry
/// that never changes the score. This validator refuses those taps in the
/// workspace, before an event is written, so every refusal is explainable and
/// the log only ever holds actions the sport understands.
///
/// It never decides *how* a sport is won — completion comes from the engine's
/// own fold, which is why each workspace passes the live [MatchProgress] in.
abstract final class MatchScoringValidator {
  static String? validate({
    required SportMatch match,
    required MatchProgress progress,
    required String kind,
    int? side,
    Map<String, dynamic> data = const {},
  }) {
    if (progress.isComplete) {
      return 'This match is complete. Submit the result instead.';
    }
    return switch (match.sport) {
      Sport.cricket => _cricket(kind, side, data),
      Sport.padel => _padel(kind, side),
      Sport.futsal => _futsalChecked(match, progress, kind, side, data),
      Sport.badminton => _badminton(kind, side),
    };
  }

  // ── Cricket ─────────────────────────────────────────────────────────────

  static String? _cricket(String kind, int? side, Map<String, dynamic> data) {
    switch (kind) {
      case CricketEngine.kInningsEnd:
        return null;
      case CricketEngine.kBall:
        if (side != 0 && side != 1) {
          return 'Pick the side that is batting.';
        }
        final runs = data['runs'];
        if (runs is! int || runs < 0 || runs > 6) {
          return 'Runs on a ball run from 0 to 6.';
        }
        final extra = data['extra'];
        if (extra != null &&
            extra != 'wide' &&
            extra != 'noball' &&
            extra != 'bye' &&
            extra != 'legbye') {
          return 'That extra is not one cricket understands.';
        }
        if (data['wicket'] != null && data['wicket'] is! bool) {
          return 'A wicket is recorded as a dismissal.';
        }
        return null;
      default:
        return 'Cricket only accepts a delivery or the end of an innings.';
    }
  }

  // ── Padel ───────────────────────────────────────────────────────────────

  static String? _padel(String kind, int? side) {
    if (kind != PadelEngine.kPoint) {
      return 'Padel scores point by point.';
    }
    if (side != 0 && side != 1) return 'Pick the pair that won the point.';
    return null;
  }

  // ── Futsal ──────────────────────────────────────────────────────────────

  static String? _futsalChecked(
    SportMatch match,
    MatchProgress progress,
    String kind,
    int? side,
    Map<String, dynamic> data,
  ) {
    if (kind == 'lineup') {
      if (progress.state['phase'] != 'pre') {
        return 'Set lineups before kick-off.';
      }
      if (side != 0 && side != 1) return 'Choose the team.';
      final players = data['players'];
      final accepted = match
          .participantsOnSide(side!)
          .map((p) => p.profileId)
          .toSet();
      if (players is! List ||
          players.length != 5 ||
          players.toSet().length != 5 ||
          !players.every(accepted.contains)) {
        return 'Choose five different accepted players.';
      }
      return null;
    }
    final basic = _futsal(kind, side, data);
    if (basic != null) return basic;
    final phase = progress.state['phase'] ?? 'pre';
    final half = (progress.state['half'] as num?)?.toInt() ?? 1;
    if (kind == FutsalEngine.kClock) {
      final allowed = switch (phase) {
        'pre' => {'start'},
        'running' => {'stop', 'end_half', 'end_match'},
        'paused' => {'resume', 'end_half', 'end_match'},
        'halfTime' => {'resume', 'end_match'},
        _ => <String>{},
      };
      if (!allowed.contains(data['action'])) {
        return 'That clock control is unavailable in this period.';
      }
    } else if (kind == FutsalEngine.kPenalty) {
      if (phase != 'shootout') {
        return 'Penalty kicks are available during the shootout.';
      }
      final taken = progress.state['shootoutTaken'] as List? ?? [0, 0];
      if ((taken[side!] as num) > (taken[1 - side] as num)) {
        return 'Record the other team’s kick next.';
      }
    } else {
      if (phase != 'running' && phase != 'paused') {
        return 'Start the period before recording match events.';
      }
      if (data['half'] != null && data['half'] != half - 1) {
        return 'Record events in the current period.';
      }
      if (kind == 'goal' &&
          data['goalType'] != null &&
          !{'regular', 'ownGoal', 'penalty'}.contains(data['goalType'])) {
        return 'Choose a valid goal type.';
      }
      if (kind == 'substitution' && side != 0 && side != 1) {
        return 'Pick the team making the substitution.';
      }
    }
    if (kind == 'card' &&
        data['playerId'] != null &&
        !match
            .participantsOnSide(side!)
            .any((p) => p.profileId == data['playerId'])) {
      return 'Select an accepted player from this team.';
    }
    if (kind == 'substitution' && data['inId'] != null) {
      final roster = match
          .participantsOnSide(side!)
          .map((p) => p.profileId)
          .toSet();
      if (!roster.contains(data['inId']) ||
          !roster.contains(data['outId']) ||
          data['inId'] == data['outId']) {
        return 'Choose two different accepted players from this team.';
      }
      final court = FutsalRoster.onCourt(match, side);
      if (FutsalRoster.starters(match, side).isNotEmpty &&
          (!court.contains(data['outId']) || court.contains(data['inId']))) {
        return 'Choose a substitute coming on and an on-court player going off.';
      }
    }
    return null;
  }

  static String? _futsal(String kind, int? side, Map<String, dynamic> data) {
    switch (kind) {
      case FutsalEngine.kGoal:
        if (side != 0 && side != 1) return 'Pick the side that scored.';
        final half = data['half'];
        if (half != null && (half is! int || half < 0)) {
          return 'That half does not exist.';
        }
        return null;
      case FutsalEngine.kClock:
        const actions = {'start', 'resume', 'stop', 'end_half', 'end_match'};
        final action = data['action'];
        if (action is! String || !actions.contains(action)) {
          return 'That clock action is not one futsal understands.';
        }
        return null;
      case FutsalEngine.kPenalty:
        if (side != 0 && side != 1) return 'Pick the side taking the kick.';
        if (data['scored'] is! bool) {
          return 'A penalty is either scored or missed.';
        }
        return null;
      // Fouls, cards and substitutions are recorded for the match report. The
      // engine ignores them, which is exactly why the payload is checked here.
      case 'foul':
        if (side != 0 && side != 1) return 'Pick the side that committed it.';
        return null;
      case 'card':
        final colour = data['colour'];
        if (colour != 'yellow' && colour != 'red') {
          return 'Cards are yellow or red.';
        }
        if (side != 0 && side != 1) return 'Pick the side shown the card.';
        return null;
      case 'substitution':
        final incoming = data['in'];
        final outgoing = data['out'];
        if (incoming is! String || incoming.trim().isEmpty) {
          return 'Name the player coming on.';
        }
        if (outgoing is! String || outgoing.trim().isEmpty) {
          return 'Name the player going off.';
        }
        if (incoming.trim() == outgoing.trim()) {
          return 'A player cannot replace themselves.';
        }
        return null;
      default:
        return 'Futsal does not record that action.';
    }
  }

  // ── Badminton ───────────────────────────────────────────────────────────

  static String? _badminton(String kind, int? side) {
    if (kind != BadmintonEngine.kRally) {
      return 'Badminton scores rally by rally.';
    }
    if (side != 0 && side != 1) return 'Pick the side that won the rally.';
    return null;
  }
}

/// A stable, unique client event id for one tap.
///
/// It is the idempotency key of `record_match_event`: a retried tap reuses the
/// same value and the server returns the original row instead of a second
/// score. Two taps never share one because of the monotonic suffix.
class MatchEventIds {
  MatchEventIds._();

  static int _sequence = 0;

  static String next() {
    _sequence += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_sequence';
  }
}
