import 'package:sportika/shared/models/match.dart';

/// Read-only roster diagnostics. Invalid historical events are not mutated.
enum FutsalRosterIssue {
  invalidSide,
  malformedLineup,
  duplicatePlayer,
  unregisteredPlayer,
  tooManyPlayers,
  invalidLineupChange,
  invalidSubstitution,
  dismissedPlayerReentry,
  invalidGoalkeeper,
  invalidCard,
}

/// Describes the reconstructed lineup, not official match eligibility.
enum FutsalLineupStatus {
  notConfigured,
  incomplete,
  ready,
  reducedByDismissal,
  invalid,
}

class FutsalRosterDiagnostic {
  const FutsalRosterDiagnostic({
    required this.issue,
    required this.message,
    this.sequence,
  });

  final FutsalRosterIssue issue;
  final String message;
  final int? sequence;
}

class FutsalSubstitutionRecord {
  const FutsalSubstitutionRecord({
    required this.outId,
    required this.inId,
    required this.sequence,
  });

  final String outId;
  final String inId;
  final int sequence;
}

/// Immutable snapshot derived from registered players and official events.
/// All identifiers are profile IDs, never display names.
class FutsalRosterState {
  FutsalRosterState({
    required Set<String> starters,
    required Set<String> onCourt,
    required Set<String> bench,
    required Set<String> dismissed,
    required Set<String> registered,
    required this.goalkeeperId,
    List<FutsalSubstitutionRecord> substitutions = const [],
    List<FutsalRosterDiagnostic> diagnostics = const [],
    required this.lineupConfirmed,
    required this.lineupStatus,
  }) : starters = Set.unmodifiable(starters),
       onCourt = Set.unmodifiable(onCourt),
       bench = Set.unmodifiable(bench),
       dismissed = Set.unmodifiable(dismissed),
       registered = Set.unmodifiable(registered),
       substitutions = List.unmodifiable(substitutions),
       diagnostics = List.unmodifiable(diagnostics);

  final Set<String> starters;
  final Set<String> onCourt;
  final Set<String> bench;
  final Set<String> dismissed;
  final Set<String> registered;
  final String? goalkeeperId;
  final List<FutsalSubstitutionRecord> substitutions;
  final List<FutsalRosterDiagnostic> diagnostics;
  final bool lineupConfirmed;
  final FutsalLineupStatus lineupStatus;

  /// Convenient issue codes for a compact Match Center warning indicator.
  Set<FutsalRosterIssue> get issues =>
      Set.unmodifiable(diagnostics.map((item) => item.issue));

  int get onCourtCount => onCourt.length;
  int get benchCount => bench.length;
  bool isOnCourt(String id) => onCourt.contains(id);
  bool isOnBench(String id) => bench.contains(id);
  bool isDismissed(String id) => dismissed.contains(id);
  bool isRegistered(String id) => registered.contains(id);
  bool get hasGoalkeeper =>
      goalkeeperId != null && onCourt.contains(goalkeeperId);
  bool get goalkeeperAssigned => hasGoalkeeper;
  bool get hasFullSide => onCourt.length == FutsalRoster.maxOnCourt;
  bool get hasValidCourtSize => onCourt.length <= FutsalRoster.maxOnCourt;

  /// Capacity alone is NOT authorization to replace a dismissed player.
  bool get canAddPlayer => onCourt.length < FutsalRoster.maxOnCourt;
}

/// Read-only futsal roster projection. The match engine remains responsible
/// for accepting events, kickoff state, and red-card replacement eligibility.
abstract final class FutsalRoster {
  static const int maxOnCourt = 5;

  /// Lineup events can revise the configured lineup before any match activity.
  /// Set [allowLineupRevision] to false if the authoritative match lifecycle
  /// has already locked the lineup. This helper cannot infer kickoff reliably.
  static FutsalRosterState resolve(
    SportMatch match,
    int side, {
    bool allowLineupRevision = true,
  }) {
    if (side != 0 && side != 1) {
      return _emptyState(
        const FutsalRosterDiagnostic(
          issue: FutsalRosterIssue.invalidSide,
          message: 'Side must be 0 or 1.',
        ),
      );
    }

    final registered = match
        .participantsOnSide(side)
        .map((participant) => participant.profileId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final diagnostics = <FutsalRosterDiagnostic>[];
    final substitutions = <FutsalSubstitutionRecord>[];
    final dismissed = <String>{};
    final onCourt = <String>{};
    var starters = <String>{};
    String? goalkeeperId;
    var lineupConfirmed = false;
    var hadInvalidLineup = false;

    void issue(FutsalRosterIssue kind, String message, [int? sequence]) {
      diagnostics.add(
        FutsalRosterDiagnostic(
          issue: kind,
          message: message,
          sequence: sequence,
        ),
      );
    }

    bool applyLineup(Object? raw, {int? sequence, String? keeper}) {
      if (raw is! List) {
        issue(
          FutsalRosterIssue.malformedLineup,
          'Lineup players must be a list.',
          sequence,
        );
        hadInvalidLineup = true;
        return false;
      }
      final players = <String>{};
      var malformed = false;
      var duplicate = false;
      for (final item in raw) {
        final id = _readId(item);
        if (id == null) {
          malformed = true;
        } else if (!players.add(id)) {
          duplicate = true;
        }
      }
      if (malformed) {
        issue(
          FutsalRosterIssue.malformedLineup,
          'Lineup contains a missing or malformed profile ID.',
          sequence,
        );
      }
      if (duplicate) {
        issue(
          FutsalRosterIssue.duplicatePlayer,
          'A player appears more than once in the lineup.',
          sequence,
        );
      }
      if (players.isEmpty || players.length > maxOnCourt) {
        issue(
          FutsalRosterIssue.tooManyPlayers,
          'Lineup must contain between one and five players.',
          sequence,
        );
      }
      if (!registered.containsAll(players)) {
        issue(
          FutsalRosterIssue.unregisteredPlayer,
          'Lineup contains a player not registered on this side.',
          sequence,
        );
      }
      if (players.any(dismissed.contains)) {
        issue(
          FutsalRosterIssue.dismissedPlayerReentry,
          'A dismissed player cannot re-enter through a lineup.',
          sequence,
        );
      }
      if (malformed ||
          duplicate ||
          players.isEmpty ||
          players.length > maxOnCourt ||
          !registered.containsAll(players) ||
          players.any(dismissed.contains)) {
        hadInvalidLineup = true;
        return false;
      }

      starters = Set<String>.from(players);
      onCourt
        ..clear()
        ..addAll(players);
      lineupConfirmed = true;
      if (keeper != null && !onCourt.contains(keeper)) {
        issue(
          FutsalRosterIssue.invalidGoalkeeper,
          'Goalkeeper must be in the active lineup.',
          sequence,
        );
        goalkeeperId = null;
      } else {
        goalkeeperId = keeper;
      }
      return true;
    }

    final configured = match.rules['lineups'];
    if (configured is List &&
        side < configured.length &&
        configured[side] != null) {
      applyLineup(configured[side]);
    }

    final events =
        match.events
            .where((event) => !event.voided && event.side == side)
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));

    // A lineup revision after match activity is never treated as a new
    // starting five. The match engine should reject such events at write time.
    var matchActivitySeen = false;
    for (final event in events) {
      switch (event.kind) {
        case 'lineup':
          if (matchActivitySeen || (lineupConfirmed && !allowLineupRevision)) {
            issue(
              FutsalRosterIssue.invalidLineupChange,
              'Starting lineup cannot be replaced at this stage.',
              event.seq,
            );
            break;
          }
          applyLineup(
            event.data['players'],
            sequence: event.seq,
            keeper: _readId(event.data['goalkeeperId']),
          );

        case 'substitution':
          matchActivitySeen = true;
          final outgoing = _readId(event.data['outId']);
          final incoming = _readId(event.data['inId']);
          if (outgoing == null ||
              incoming == null ||
              outgoing == incoming ||
              !registered.contains(outgoing) ||
              !registered.contains(incoming) ||
              !onCourt.contains(outgoing) ||
              onCourt.contains(incoming)) {
            issue(
              FutsalRosterIssue.invalidSubstitution,
              'Substitution requires an on-court outgoing player and '
              'an eligible registered incoming player.',
              event.seq,
            );
            break;
          }
          if (dismissed.contains(incoming)) {
            issue(
              FutsalRosterIssue.dismissedPlayerReentry,
              'Dismissed player cannot be substituted back in.',
              event.seq,
            );
            break;
          }
          onCourt
            ..remove(outgoing)
            ..add(incoming);
          substitutions.add(
            FutsalSubstitutionRecord(
              outId: outgoing,
              inId: incoming,
              sequence: event.seq,
            ),
          );
          if (goalkeeperId == outgoing) {
            final keeper = _readId(event.data['goalkeeperId']);
            if (keeper != null && !onCourt.contains(keeper)) {
              issue(
                FutsalRosterIssue.invalidGoalkeeper,
                'Replacement goalkeeper is not on court.',
                event.seq,
              );
            }
            goalkeeperId = keeper != null && onCourt.contains(keeper)
                ? keeper
                : null;
          } else if (event.data.containsKey('goalkeeperId')) {
            final keeper = _readId(event.data['goalkeeperId']);
            if (keeper != null && onCourt.contains(keeper)) {
              goalkeeperId = keeper;
            } else {
              issue(
                FutsalRosterIssue.invalidGoalkeeper,
                'Goalkeeper assignment is not an on-court player.',
                event.seq,
              );
            }
          }

        case 'card':
          matchActivitySeen = true;
          if (event.data['colour'] != 'red') break;
          final player = _readId(event.data['playerId']);
          if (player == null || !registered.contains(player)) {
            issue(
              FutsalRosterIssue.invalidCard,
              'Red card references an unregistered player.',
              event.seq,
            );
            break;
          }
          dismissed.add(player);
          onCourt.remove(player);
          if (goalkeeperId == player) goalkeeperId = null;

        case 'goalkeeper':
          matchActivitySeen = true;
          final keeper = _readId(event.data['playerId']);
          if (keeper != null &&
              onCourt.contains(keeper) &&
              !dismissed.contains(keeper)) {
            goalkeeperId = keeper;
          } else {
            issue(
              FutsalRosterIssue.invalidGoalkeeper,
              'Goalkeeper must be an eligible on-court player.',
              event.seq,
            );
          }

        default:
          // Other match events can establish that play has begun, but this
          // projection does not interpret their sport-specific payloads.
          if (event.kind != 'lineup') matchActivitySeen = true;
      }
    }

    onCourt.removeWhere(
      (id) => !registered.contains(id) || dismissed.contains(id),
    );
    if (goalkeeperId != null && !onCourt.contains(goalkeeperId)) {
      goalkeeperId = null;
    }
    final bench = registered.difference(onCourt.union(dismissed));

    final FutsalLineupStatus status;
    if (!lineupConfirmed) {
      status = hadInvalidLineup
          ? FutsalLineupStatus.invalid
          : FutsalLineupStatus.notConfigured;
    } else if (dismissed.isNotEmpty && onCourt.length < maxOnCourt) {
      status = FutsalLineupStatus.reducedByDismissal;
    } else if (onCourt.length < maxOnCourt) {
      status = FutsalLineupStatus.incomplete;
    } else {
      status = FutsalLineupStatus.ready;
    }

    return FutsalRosterState(
      starters: starters,
      onCourt: onCourt,
      bench: bench,
      dismissed: dismissed,
      registered: registered,
      goalkeeperId: goalkeeperId,
      substitutions: substitutions,
      diagnostics: diagnostics,
      lineupConfirmed: lineupConfirmed,
      lineupStatus: status,
    );
  }

  static Set<String> starters(SportMatch match, int side) =>
      resolve(match, side).starters;
  static Set<String> onCourt(SportMatch match, int side) =>
      resolve(match, side).onCourt;
  static Set<String> bench(SportMatch match, int side) =>
      resolve(match, side).bench;
  static Set<String> dismissed(SportMatch match, int side) =>
      resolve(match, side).dismissed;
  static Set<String> registered(SportMatch match, int side) =>
      resolve(match, side).registered;
  static String? goalkeeper(SportMatch match, int side) =>
      resolve(match, side).goalkeeperId;

  /// Checks a standard one-for-one substitution, not disciplinary permission.
  static bool canSubstitute({
    required FutsalRosterState roster,
    required String outId,
    required String inId,
  }) =>
      outId != inId &&
      roster.onCourt.contains(outId) &&
      roster.bench.contains(inId) &&
      !roster.dismissed.contains(inId);

  static String? _readId(Object? raw) {
    if (raw is! String) return null;
    final id = raw.trim();
    return id.isEmpty ? null : id;
  }

  static FutsalRosterState _emptyState(FutsalRosterDiagnostic diagnostic) =>
      FutsalRosterState(
        starters: <String>{},
        onCourt: <String>{},
        bench: <String>{},
        dismissed: <String>{},
        registered: <String>{},
        goalkeeperId: null,
        diagnostics: [diagnostic],
        lineupConfirmed: false,
        lineupStatus: FutsalLineupStatus.invalid,
      );
}
