import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/shared/models/match.dart';

/// An accepted player belonging to one match side.
///
/// Player IDs are the stable identity. Names are retained because
/// existing cricket delivery events record batter and bowler names.
class CricketPlayer {
  const CricketPlayer({required this.id, required this.name});

  final String id;
  final String name;
}

/// A projection of the cricket roster and delivery history.
///
/// All results are derived from non-voided match events. No mutable
/// scoring state is retained between calls.
///
/// Existing public methods remain available:
/// - playersOn
/// - lineupIds
/// - hasLineup
/// - order
/// - namesOn
/// - nameOf
/// - didNotBat
/// - strike
///
/// The delivery replay handles:
/// - legal-ball counting
/// - ordinary strike changes
/// - wides and no-balls
/// - optional completed-run information
/// - wickets and replacement batters
/// - over-end strike rotation
/// - bowler reset at the end of an over
///
/// It cannot infer information that was never recorded, such as
/// the exact ends occupied after an ambiguous run-out.
abstract final class CricketRoster {
  // ==========================================================
  // PLAYER DISCOVERY
  // ==========================================================

  static List<CricketPlayer> playersOn(SportMatch match, int side) {
    return [
      for (final player in match.participantsOnSide(side))
        CricketPlayer(id: player.profileId, name: player.displayName),
    ];
  }

  // ==========================================================
  // LINEUP
  // ==========================================================

  /// Most recently recorded non-voided lineup.
  ///
  /// Duplicate and empty IDs are ignored.
  static List<String> lineupIds(SportMatch match, int side) {
    final events =
        match.events
            .where(
              (event) =>
                  !event.voided &&
                  event.kind == CricketEngine.kLineup &&
                  event.side == side,
            )
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));

    if (events.isEmpty) {
      return const [];
    }

    final raw = events.last.data['players'];

    if (raw is! List) {
      return const [];
    }

    final seen = <String>{};
    final result = <String>[];

    for (final value in raw) {
      if (value is! String || value.isEmpty) {
        continue;
      }

      if (seen.add(value)) {
        result.add(value);
      }
    }

    return result;
  }

  static bool hasLineup(SportMatch match, int side) {
    return lineupIds(match, side).isNotEmpty;
  }

  /// Players in the recorded lineup order.
  ///
  /// Falls back to the accepted roster for legacy matches.
  static List<CricketPlayer> order(SportMatch match, int side) {
    final accepted = playersOn(match, side);
    final ids = lineupIds(match, side);

    if (ids.isEmpty) {
      return accepted;
    }

    final byId = {for (final player in accepted) player.id: player};

    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  static List<String> namesOn(SportMatch match, int side) {
    return [for (final player in order(match, side)) player.name];
  }

  static String? nameOf(SportMatch match, int side, String id) {
    for (final player in order(match, side)) {
      if (player.id == id) {
        return player.name;
      }
    }

    return null;
  }

  // ==========================================================
  // DID NOT BAT
  // ==========================================================

  /// Returns players not represented in the recorded batting log.
  ///
  /// The existing API accepts recorded names, so duplicate-name
  /// ambiguity remains possible until ball events store player IDs.
  static List<String> didNotBat(
    SportMatch match,
    int side,
    Set<String> recorded,
  ) {
    if (!hasLineup(match, side)) {
      return const [];
    }

    return [
      for (final player in order(match, side))
        if (!recorded.contains(player.name)) player.name,
    ];
  }

  // ==========================================================
  // DELIVERY HISTORY
  // ==========================================================

  static List<MatchEvent> _deliveries(SportMatch match, int side) {
    return match.events
        .where(
          (event) =>
              !event.voided &&
              event.kind == CricketEngine.kBall &&
              event.side == side,
        )
        .toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
  }

  static bool _isLegal(MatchEvent event) {
    final extra = event.data['extra'];

    return extra != 'wide' &&
        extra != 'noball' &&
        extra != 'noBall' &&
        extra != 'no_ball';
  }

  static int _integer(Object? value, {int fallback = 0}) {
    if (value is num) {
      return value.toInt();
    }

    return fallback;
  }

  static String? _string(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }

    return null;
  }

  /// Number of completed runs used for strike rotation.
  ///
  /// Newer event formats may explicitly supply `runsCompleted`.
  /// Older logs fall back to the existing `runs` field.
  ///
  /// This fallback is not guaranteed to distinguish bat runs
  /// from total extras in every historical delivery.
  static int _completedRuns(MatchEvent event) {
    final explicit = event.data['runsCompleted'];

    if (explicit is num) {
      return explicit.toInt();
    }

    return _integer(event.data['runs']);
  }

  // ==========================================================
  // STRIKE PROJECTION
  // ==========================================================

  /// Reconstructs the state before the next delivery.
  ///
  /// The result uses the existing workspace-compatible record.
  ///
  /// Opening batters remain unset until the first recorded ball.
  /// This avoids incorrectly assuming the first two lineup members
  /// are the actual opening pair.
  ///
  /// For legacy events, the striker/non-striker/bowler values
  /// recorded on each delivery are treated as the authoritative
  /// starting positions for that delivery.
  static ({
    String? striker,
    String? nonStriker,
    String? bowler,
    int legalBalls,
    bool newOver,
  })
  strike(SportMatch match, int side) {
    final balls = _deliveries(match, side);
    final battingOrder = order(match, side);

    if (balls.isEmpty) {
      return (
        striker: null,
        nonStriker: null,
        bowler: null,
        legalBalls: 0,
        newOver: true,
      );
    }

    String? striker;
    String? nonStriker;
    String? bowler;

    var legalBalls = 0;
    var newOver = true;

    final usedBatters = <String>{};

    for (final ball in balls) {
      final recordedStriker = _string(ball.data['striker']);

      final recordedNonStriker = _string(ball.data['nonStriker']);

      final recordedBowler = _string(ball.data['bowler']);

      // Delivery snapshots identify the actual players at
      // the beginning of each recorded ball.
      if (recordedStriker != null) {
        striker = recordedStriker;
        usedBatters.add(recordedStriker);
      }

      if (recordedNonStriker != null) {
        nonStriker = recordedNonStriker;
        usedBatters.add(recordedNonStriker);
      }

      if (recordedBowler != null) {
        bowler = recordedBowler;
      }

      // A delivery has started, so the innings is no longer
      // waiting for its first ball.
      newOver = false;

      final legal = _isLegal(ball);

      if (legal) {
        legalBalls++;
      }

      // ------------------------------------------------------
      // RUNNING BETWEEN WICKETS
      // ------------------------------------------------------

      final completedRuns = _completedRuns(ball);

      if (completedRuns.isOdd) {
        final previous = striker;
        striker = nonStriker;
        nonStriker = previous;
      }

      // ------------------------------------------------------
      // WICKET
      // ------------------------------------------------------

      if (ball.data['wicket'] == true) {
        final dismissed =
            _string(ball.data['dismissedBatter']) ?? recordedStriker;

        if (dismissed != null) {
          usedBatters.add(dismissed);
        }

        // An explicit crossing flag may be recorded for
        // delivery formats that support it.
        //
        // Do not apply an additional swap merely because
        // `crossed` is true: completed-run parity already
        // determines ordinary strike changes.
        //
        // Precise run-out positioning requires the delivery
        // to record the end at which the wicket fell.

        final replacement = _nextBatter(
          battingOrder,
          usedBatters: usedBatters,
          excluded: {?striker, ?nonStriker},
        );

        if (dismissed == striker) {
          striker = replacement;
        } else if (dismissed == nonStriker) {
          nonStriker = replacement;
        } else if (dismissed == recordedStriker) {
          // The batter may have changed ends due to runs.
          // Without an explicit wicket-end field, retain
          // the best available legacy interpretation.
          striker = replacement;
        }

        if (replacement != null) {
          usedBatters.add(replacement);
        }
      }

      // ------------------------------------------------------
      // END OF OVER
      // ------------------------------------------------------

      final overEnded = legal && legalBalls > 0 && legalBalls % 6 == 0;

      if (overEnded) {
        final previous = striker;
        striker = nonStriker;
        nonStriker = previous;

        // Next over requires a different bowler to be
        // selected by the scorer.
        bowler = null;
        newOver = true;
      }
    }

    return (
      striker: striker,
      nonStriker: nonStriker,
      bowler: bowler,
      legalBalls: legalBalls,
      newOver: newOver,
    );
  }

  // ==========================================================
  // NEXT BATTER
  // ==========================================================

  /// Finds the next available batter in the named lineup.
  ///
  /// Existing delivery logs identify players by name, so this
  /// method cannot resolve two players sharing the same name.
  static String? _nextBatter(
    List<CricketPlayer> battingOrder, {
    required Set<String> usedBatters,
    required Set<String> excluded,
  }) {
    for (final player in battingOrder) {
      if (usedBatters.contains(player.name)) {
        continue;
      }

      if (excluded.contains(player.name)) {
        continue;
      }

      return player.name;
    }

    return null;
  }
}
