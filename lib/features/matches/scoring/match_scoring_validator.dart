import 'package:sportika/features/matches/scoring/futsal_roster.dart';
import 'package:sportika/features/personal_games/scoring/badminton/badminton.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/features/personal_games/scoring/padel/padel.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';

/// Writes a scoring action into the shared official event log.
typedef RecordMatchEvent = void Function(
  String kind,
  int? side,
  Map<String, dynamic> data,
);

enum ScoringValidationCode {
  invalidMatchState,
  unauthorized,
  invalidSide,
  invalidPayload,
  invalidPlayer,
  invalidLineup,
  invalidSubstitution,
  dismissedPlayer,
  invalidClockAction,
  invalidShootout,
  inningsNotOpen,
  matchComplete,
  unsupportedAction,
}

class ScoringValidationResult {
  const ScoringValidationResult.valid() : code = null, message = null;

  const ScoringValidationResult.invalid(this.code, this.message);

  final ScoringValidationCode? code;
  final String? message;

  bool get isValid => code == null;
  bool get isInvalid => !isValid;
}

/// Client-side pre-flight validation.
///
/// The sport engines remain authoritative for scoring rules and completion.
/// The server must independently validate all official writes.
abstract final class MatchScoringValidator {
  static const _valid = ScoringValidationResult.valid();

  static ScoringValidationResult _reject(
    ScoringValidationCode code,
    String message,
  ) {
    return ScoringValidationResult.invalid(code, message);
  }

  /// Backward-compatible API used by existing scoring workspaces.
  ///
  /// Returns null for a valid action, otherwise a user-facing explanation.
  static String? validate({
    required SportMatch match,
    required MatchProgress progress,
    required String kind,
    int? side,
    Map<String, dynamic> data = const {},
    String? scorerId,
  }) {
    return validateDetailed(
      match: match,
      progress: progress,
      kind: kind,
      side: side,
      data: data,
      scorerId: scorerId,
    ).message;
  }

  /// Structured result for UI messages, analytics, and future validation.
  static ScoringValidationResult validateDetailed({
    required SportMatch match,
    required MatchProgress progress,
    required String kind,
    int? side,
    Map<String, dynamic> data = const {},
    String? scorerId,
  }) {
    if (progress.isComplete) {
      return _reject(
        ScoringValidationCode.matchComplete,
        'This match is complete. Submit the result instead.',
      );
    }

    // Permission checks remain optional here for compatibility.
    // The controller/server must enforce them for every write.
    if (scorerId != null && !match.canScore(scorerId)) {
      return _reject(
        ScoringValidationCode.unauthorized,
        'Only the organizer or assigned official scorer can record events.',
      );
    }

    if (kind.trim().isEmpty) {
      return _reject(
        ScoringValidationCode.invalidPayload,
        'Choose a scoring action.',
      );
    }

    return switch (match.sport) {
      Sport.cricket => _cricket(match, progress, kind, side, data),
      Sport.padel => _padel(kind, side, data),
      Sport.futsal => _futsal(match, progress, kind, side, data),
      Sport.badminton => _badminton(kind, side, data),
    };
  }

  // -----------------------------------------------------------------------
  // Shared helpers
  // -----------------------------------------------------------------------

  static bool _validSide(int? side) => side == 0 || side == 1;

  static String? _id(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Set<String> _registered(SportMatch match, int side) {
    return match
        .participantsOnSide(side)
        .map((participant) => participant.profileId)
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static bool _registeredPlayer(SportMatch match, int side, String playerId) {
    return _registered(match, side).contains(playerId);
  }

  static ScoringValidationResult? _validatePlayers({
    required SportMatch match,
    required int side,
    required Object? value,
    required int minimum,
    required int maximum,
  }) {
    if (value is! List) {
      return _reject(
        ScoringValidationCode.invalidLineup,
        'Select players from the registered team roster.',
      );
    }

    if (value.length < minimum || value.length > maximum) {
      return _reject(
        ScoringValidationCode.invalidLineup,
        'Select between $minimum and $maximum players.',
      );
    }

    final ids = <String>[];

    for (final item in value) {
      final playerId = _id(item);

      if (playerId == null) {
        return _reject(
          ScoringValidationCode.invalidPlayer,
          'Every selected player must have a valid profile ID.',
        );
      }

      ids.add(playerId);
    }

    if (ids.toSet().length != ids.length) {
      return _reject(
        ScoringValidationCode.invalidLineup,
        'The same player cannot appear twice in a lineup.',
      );
    }

    final accepted = _registered(match, side);

    if (!accepted.containsAll(ids)) {
      return _reject(
        ScoringValidationCode.invalidPlayer,
        'Select only accepted players registered for this team.',
      );
    }

    return null;
  }

  static int? _stateInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Cricket
  // -----------------------------------------------------------------------

  static const Set<String> _dismissals = {
    'Bowled',
    'Caught',
    'LBW',
    'Run out',
    'Stumped',
    'Caught & bowled',
    'Hit wicket',
  };

  static ScoringValidationResult _cricket(
    SportMatch match,
    MatchProgress progress,
    String kind,
    int? side,
    Map<String, dynamic> data,
  ) {
    final innings = _stateInt(progress.state['innings']) ?? 0;
    final open = progress.state['open'] == true;

    switch (kind) {
      case CricketEngine.kToss:
        if (innings > 0 || progress.state['toss'] != null) {
          return _reject(
            ScoringValidationCode.invalidMatchState,
            'The toss has already been recorded.',
          );
        }

        if (!_validSide(side)) {
          return _reject(
            ScoringValidationCode.invalidSide,
            'Choose the team that won the toss.',
          );
        }

        if (data['decision'] != 'bat' && data['decision'] != 'bowl') {
          return _reject(
            ScoringValidationCode.invalidPayload,
            'Choose whether the toss winner will bat or bowl.',
          );
        }

        return _valid;

      case CricketEngine.kLineup:
        if (innings > 0 || open) {
          return _reject(
            ScoringValidationCode.invalidMatchState,
            'Confirm the playing XI before the first innings.',
          );
        }

        if (!_validSide(side)) {
          return _reject(
            ScoringValidationCode.invalidSide,
            'Choose the team whose lineup you are setting.',
          );
        }

        return _validatePlayers(
              match: match,
              side: side!,
              value: data['players'],
              minimum: 2,
              maximum: 11,
            ) ??
            _valid;

      case CricketEngine.kInningsStart:
        if (open || innings >= 2) {
          return _reject(
            ScoringValidationCode.invalidMatchState,
            'The next innings cannot be started yet.',
          );
        }

        if (progress.state['toss'] == null) {
          return _reject(
            ScoringValidationCode.invalidMatchState,
            'Record the toss before starting the innings.',
          );
        }

        final next = _stateInt(progress.state['nextBatSide']);

        if (!_validSide(side) || next == null || side != next) {
          return _reject(
            ScoringValidationCode.invalidSide,
            'Select the team scheduled to bat next.',
          );
        }

        return _valid;

      case CricketEngine.kBall:
        if (!open) {
          return _reject(
            ScoringValidationCode.inningsNotOpen,
            'Start the innings before recording a delivery.',
          );
        }

        if (!_validSide(side)) {
          return _reject(
            ScoringValidationCode.invalidSide,
            'Choose the batting team.',
          );
        }

        final batSide = _stateInt(progress.state['batSide']);

        if (_validSide(batSide) && side != batSide) {
          return _reject(
            ScoringValidationCode.invalidSide,
            'Only ${match.sideNames[batSide!]} is batting.',
          );
        }

        final runs = data['runs'];

        if (runs is! int || runs < 0 || runs > 6) {
          return _reject(
            ScoringValidationCode.invalidPayload,
            'Runs from the bat must be between 0 and 6.',
          );
        }

        final extra = data['extra'];

        if (extra != null &&
            !const {'wide', 'noball', 'bye', 'legbye'}.contains(extra)) {
          return _reject(
            ScoringValidationCode.invalidPayload,
            'Choose a valid extra: wide, no-ball, bye, or leg-bye.',
          );
        }

        if (data['wicket'] != null && data['wicket'] is! bool) {
          return _reject(
            ScoringValidationCode.invalidPayload,
            'The wicket field must be true or false.',
          );
        }

        if (data['wicket'] == true) {
          if (!_dismissals.contains(data['dismissal'])) {
            return _reject(
              ScoringValidationCode.invalidPayload,
              'Select a valid dismissal type.',
            );
          }

          final dismissed = data['dismissedBatter'];

          if (dismissed != null &&
              dismissed != data['striker'] &&
              dismissed != data['nonStriker']) {
            return _reject(
              ScoringValidationCode.invalidPlayer,
              'The dismissed batter must be one of the batters at the crease.',
            );
          }

          if (extra == 'wide' &&
              const {
                'Bowled',
                'LBW',
                'Caught',
                'Caught & bowled',
                'Hit wicket',
              }.contains(data['dismissal'])) {
            return _reject(
              ScoringValidationCode.invalidPayload,
              'That dismissal is not valid on a wide delivery.',
            );
          }

          if (extra == 'noball' &&
              const {
                'Bowled',
                'Caught',
                'LBW',
                'Stumped',
                'Caught & bowled',
              }.contains(data['dismissal'])) {
            return _reject(
              ScoringValidationCode.invalidPayload,
              'That dismissal is not valid on a no-ball.',
            );
          }
        }

        return _valid;

      case CricketEngine.kInningsEnd:
        if (!open) {
          return _reject(
            ScoringValidationCode.inningsNotOpen,
            'There is no active innings to close.',
          );
        }

        if (!_validSide(side)) {
          return _reject(
            ScoringValidationCode.invalidSide,
            'Choose the team currently batting.',
          );
        }

        final batSide = _stateInt(progress.state['batSide']);

        if (_validSide(batSide) && side != batSide) {
          return _reject(
            ScoringValidationCode.invalidSide,
            'Only the current batting innings can be closed.',
          );
        }

        return _valid;

      case CricketEngine.kMatchEnd:
        if (innings == 0) {
          return _reject(
            ScoringValidationCode.invalidMatchState,
            'Start an innings before ending the match.',
          );
        }

        return _valid;

      default:
        return _reject(
          ScoringValidationCode.unsupportedAction,
          'This action is not supported by the cricket scoring engine.',
        );
    }
  }

  // -----------------------------------------------------------------------
  // Padel
  // -----------------------------------------------------------------------

  static ScoringValidationResult _padel(
    String kind,
    int? side,
    Map<String, dynamic> data,
  ) {
    if (kind != PadelEngine.kPoint) {
      return _reject(
        ScoringValidationCode.unsupportedAction,
        'Padel scoring records one point at a time.',
      );
    }

    if (!_validSide(side)) {
      return _reject(
        ScoringValidationCode.invalidSide,
        'Select the player or pair that won the point.',
      );
    }

    if (data.isNotEmpty) {
      return _reject(
        ScoringValidationCode.invalidPayload,
        'A padel point only requires the winning side.',
      );
    }

    return _valid;
  }

  // -----------------------------------------------------------------------
  // Futsal
  // -----------------------------------------------------------------------

  static ScoringValidationResult _futsal(
    SportMatch match,
    MatchProgress progress,
    String kind,
    int? side,
    Map<String, dynamic> data,
  ) {
    final phase = progress.state['phase'] as String? ?? 'pre';
    final half = _stateInt(progress.state['half']) ?? 1;

    if (kind == 'lineup') {
      if (phase != 'pre') {
        return _reject(
          ScoringValidationCode.invalidMatchState,
          'Set the starting lineup before kick-off.',
        );
      }

      if (!_validSide(side)) {
        return _reject(
          ScoringValidationCode.invalidSide,
          'Choose the team whose lineup you are setting.',
        );
      }

      final lineupError = _validatePlayers(
        match: match,
        side: side!,
        value: data['players'],
        minimum: 5,
        maximum: 5,
      );

      if (lineupError != null) return lineupError;

      final goalkeeper = _id(data['goalkeeperId']);

      if (data.containsKey('goalkeeperId') && goalkeeper == null) {
        return _reject(
          ScoringValidationCode.invalidPlayer,
          'Select a valid goalkeeper.',
        );
      }

      if (goalkeeper != null &&
          !(data['players'] as List).contains(goalkeeper)) {
        return _reject(
          ScoringValidationCode.invalidPlayer,
          'The goalkeeper must be part of the starting five.',
        );
      }

      return _valid;
    }

    if (kind == FutsalEngine.kClock) {
      if (side != null) {
        return _reject(
          ScoringValidationCode.invalidSide,
          'Clock events apply to the whole match.',
        );
      }

      final allowed = switch (phase) {
        'pre' => const {'start'},
        'running' => const {'stop', 'end_half', 'end_match'},
        'paused' => const {'resume', 'end_half', 'end_match'},
        'halfTime' => const {'resume', 'end_match'},
        _ => const <String>{},
      };

      if (!allowed.contains(data['action'])) {
        return _reject(
          ScoringValidationCode.invalidClockAction,
          'This clock action is unavailable in the current match phase.',
        );
      }

      return _valid;
    }

    if (kind == FutsalEngine.kPenalty) {
      if (!_validSide(side)) {
        return _reject(
          ScoringValidationCode.invalidSide,
          'Choose the team taking the penalty.',
        );
      }

      if (phase != 'shootout') {
        return _reject(
          ScoringValidationCode.invalidShootout,
          'Shootout kicks can only be recorded during a penalty shootout.',
        );
      }

      if (data['scored'] is! bool) {
        return _reject(
          ScoringValidationCode.invalidPayload,
          'Record whether the penalty was scored or missed.',
        );
      }

      final rawTaken = progress.state['shootoutTaken'];

      if (rawTaken is! List || rawTaken.length != 2) {
        return _reject(
          ScoringValidationCode.invalidShootout,
          'Shootout state is unavailable. Refresh the match.',
        );
      }

      final first = _stateInt(rawTaken[0]);
      final second = _stateInt(rawTaken[1]);

      if (first == null ||
          second == null ||
          first < 0 ||
          second < 0 ||
          (first - second).abs() > 1) {
        return _reject(
          ScoringValidationCode.invalidShootout,
          'Shootout kick counts are invalid. Refresh the match.',
        );
      }

      final taken = [first, second];

      if (taken[side!] > taken[1 - side]) {
        return _reject(
          ScoringValidationCode.invalidShootout,
          'Record the other team’s penalty kick next.',
        );
      }

      return _valid;
    }

    const matchEvents = {FutsalEngine.kGoal, 'foul', 'card', 'substitution'};

    if (!matchEvents.contains(kind)) {
      return _reject(
        ScoringValidationCode.unsupportedAction,
        'This event is not supported by the futsal scoring engine.',
      );
    }

    if (phase != 'running' && phase != 'paused') {
      return _reject(
        ScoringValidationCode.invalidMatchState,
        'Start the period before recording match events.',
      );
    }

    if (!_validSide(side)) {
      return _reject(
        ScoringValidationCode.invalidSide,
        'Choose the team responsible for this event.',
      );
    }

    if (data.containsKey('half') && data['half'] != half - 1) {
      return _reject(
        ScoringValidationCode.invalidPayload,
        'Record this event in the current period.',
      );
    }

    switch (kind) {
      case FutsalEngine.kGoal:
        if (data['goalType'] != null &&
            !const {
              'regular',
              'ownGoal',
              'penalty',
            }.contains(data['goalType'])) {
          return _reject(
            ScoringValidationCode.invalidPayload,
            'Choose open play, penalty goal, or own goal.',
          );
        }

        final playerId = _id(data['playerId']);

        if (data.containsKey('playerId') && playerId == null) {
          return _reject(
            ScoringValidationCode.invalidPlayer,
            'Select a valid scorer or leave the scorer unnamed.',
          );
        }

        if (playerId != null) {
          final playerSide = data['goalType'] == 'ownGoal' ? 1 - side! : side!;

          if (!_registeredPlayer(match, playerSide, playerId)) {
            return _reject(
              ScoringValidationCode.invalidPlayer,
              'The selected scorer does not belong to the correct team.',
            );
          }
        }

        return _valid;

      case 'foul':
        return _valid;

      case 'card':
        final colour = data['colour'];

        if (colour != 'yellow' && colour != 'red') {
          return _reject(
            ScoringValidationCode.invalidPayload,
            'Choose a yellow or red card.',
          );
        }

        final playerId = _id(data['playerId']);

        if (playerId == null || !_registeredPlayer(match, side!, playerId)) {
          return _reject(
            ScoringValidationCode.invalidPlayer,
            'Select an accepted player receiving the card.',
          );
        }

        final roster = FutsalRoster.resolve(match, side);

        if (roster.dismissed.contains(playerId)) {
          return _reject(
            ScoringValidationCode.dismissedPlayer,
            'This player has already been dismissed.',
          );
        }

        return _valid;

      case 'substitution':
        final incoming = _id(data['inId']);
        final outgoing = _id(data['outId']);

        if (incoming == null || outgoing == null) {
          return _reject(
            ScoringValidationCode.invalidSubstitution,
            'Select a player coming on and a player going off.',
          );
        }

        if (incoming == outgoing) {
          return _reject(
            ScoringValidationCode.invalidSubstitution,
            'A player cannot replace themselves.',
          );
        }

        if (!_registeredPlayer(match, side!, incoming) ||
            !_registeredPlayer(match, side, outgoing)) {
          return _reject(
            ScoringValidationCode.invalidPlayer,
            'Both players must belong to the registered team roster.',
          );
        }

        final roster = FutsalRoster.resolve(match, side);

        if (roster.dismissed.contains(incoming)) {
          return _reject(
            ScoringValidationCode.dismissedPlayer,
            'A dismissed player cannot return to the court.',
          );
        }

        if (!roster.onCourt.contains(outgoing)) {
          return _reject(
            ScoringValidationCode.invalidSubstitution,
            'Choose an on-court player to go off.',
          );
        }

        if (!roster.bench.contains(incoming)) {
          return _reject(
            ScoringValidationCode.invalidSubstitution,
            'Choose an eligible player from the bench.',
          );
        }

        final goalkeeper = _id(data['goalkeeperId']);

        if (goalkeeper != null &&
            goalkeeper != incoming &&
            goalkeeper != outgoing &&
            !roster.onCourt.contains(goalkeeper)) {
          return _reject(
            ScoringValidationCode.invalidPlayer,
            'The assigned goalkeeper must remain on the court.',
          );
        }

        return _valid;

      default:
        return _reject(
          ScoringValidationCode.unsupportedAction,
          'Unsupported futsal event.',
        );
    }
  }

  // -----------------------------------------------------------------------
  // Badminton
  // -----------------------------------------------------------------------

  static ScoringValidationResult _badminton(
    String kind,
    int? side,
    Map<String, dynamic> data,
  ) {
    if (kind != BadmintonEngine.kRally) {
      return _reject(
        ScoringValidationCode.unsupportedAction,
        'Badminton scoring records one rally at a time.',
      );
    }

    if (!_validSide(side)) {
      return _reject(
        ScoringValidationCode.invalidSide,
        'Select the player or team that won the rally.',
      );
    }

    if (data.isNotEmpty) {
      return _reject(
        ScoringValidationCode.invalidPayload,
        'A badminton rally only requires the winning side.',
      );
    }

    return _valid;
  }
}

/// Generates client event IDs for new scoring actions.
///
/// Generate once per intended action and reuse the same ID for retries.
class MatchEventIds {
  MatchEventIds._();

  static int _sequence = 0;

  static String next() {
    _sequence += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_sequence';
  }
}
