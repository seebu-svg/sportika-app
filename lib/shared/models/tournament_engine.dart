import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/official_result.dart';

/// Draw generation and table math. Both are pure functions of the confirmed
/// entries plus the *published* fixtures, so a bracket or a standings table
/// can only move when an organizer publishes a result (spec §4.5, §6).
class TournamentEngine {
  TournamentEngine._();

  /// Builds a knockout bracket with byes for non-power-of-two entry counts.
  static List<Fixture> knockoutDraw({
    required Tournament tournament,
    required List<Entry> confirmed,
    List<String> scorerPool = const [],
  }) {
    final n = confirmed.length;
    if (n < 2) return [];
    final size = _nextPow2(n);
    final seedOrder = _bracketOrder(size);

    // Round 1 slots: an entry id, or null when that seed got a bye.
    var slots = <String?>[
      for (final seed in seedOrder) seed < n ? confirmed[seed].id : null,
    ];

    final totalRounds = _log2(size);
    final fixtures = <Fixture>[];
    var round = 1;

    while (slots.length > 1) {
      final next = <String?>[];
      for (var i = 0; i < slots.length; i += 2) {
        final a = slots[i], b = slots[i + 1];
        if (a == null && b == null) {
          next.add(null);
          continue;
        }
        if (a == null || b == null) {
          // Bye: the real entry advances without playing (spec §4.3 draw).
          next.add(a ?? b);
          continue;
        }
        final id = newId('fx');
        fixtures.add(
          _blankFixture(
            tournament: tournament,
            id: id,
            round: round,
            stage: _stageName(totalRounds - round),
            homeEntryId: a,
            awayEntryId: b,
            group: null,
            ordinal: (i ~/ 2) + 1,
            roundsTotal: totalRounds,
            scorerPool: scorerPool,
          ),
        );
        next.add(OfficialResults.tbdToken(id));
      }
      slots = next;
      round++;
    }
    return fixtures;
  }

  /// Round-robin within each group, seeded by snake distribution.
  static List<Fixture> groupDraw({
    required Tournament tournament,
    required List<Entry> confirmed,
    required int groupCount,
    List<String> scorerPool = const [],
  }) {
    final groups = _snakeGroups(confirmed, groupCount.clamp(2, 4));
    final fixtures = <Fixture>[];
    final letters = ['A', 'B', 'C', 'D'];

    for (var g = 0; g < groups.length; g++) {
      final members = groups[g];
      if (members.length < 2) continue;
      final pairings = _roundRobin(members);
      for (var m = 0; m < pairings.length; m++) {
        final (a, b) = pairings[m];
        fixtures.add(
          _blankFixture(
            tournament: tournament,
            id: newId('fx'),
            round: (m ~/ (members.length ~/ 2)) + 1,
            stage:
                'Group ${letters[g]} · Match ${(m % (members.length ~/ 2)) + 1}',
            homeEntryId: a.id,
            awayEntryId: b.id,
            group: letters[g],
            ordinal: m + 1,
            roundsTotal: 3,
            scorerPool: scorerPool,
          ),
        );
      }
    }
    return fixtures;
  }

  static List<StandingRow> standings({
    required List<Fixture> fixtures,
    required Map<String, Entry> entriesById,
    required int qualifyTop,
  }) {
    final rows = <String, _StandingBuilder>{};

    for (final f in fixtures) {
      // Only published results feed the table (spec §6).
      if (f.status != FixtureStatus.published &&
          f.status != FixtureStatus.walkover) {
        continue;
      }
      final r = f.result;
      if (r == null) continue;

      final home = entriesById[f.home.entryId];
      final away = entriesById[f.away.entryId];
      if (home == null || away == null) continue;

      final h = rows.putIfAbsent(home.id, () => _StandingBuilder(home.label));
      final a = rows.putIfAbsent(away.id, () => _StandingBuilder(away.label));

      final hf = r.sideValues.isNotEmpty ? r.sideValues[0] : 0;
      final af = r.sideValues.length > 1 ? r.sideValues[1] : 0;
      h.played++;
      a.played++;
      h.scored += hf;
      h.against += af;
      a.scored += af;
      a.against += hf;

      if (r.winnerIndex == 0) {
        h.won++;
        a.lost++;
        h.points += 3;
      } else if (r.winnerIndex == 1) {
        a.won++;
        h.lost++;
        a.points += 3;
      } else {
        h.drawn++;
        a.drawn++;
        h.points += 1;
        a.points += 1;
      }
    }

    final list =
        rows.entries
            .map(
              (e) => StandingRow(
                entryId: e.key,
                label: e.value.label,
                played: e.value.played,
                won: e.value.won,
                drawn: e.value.drawn,
                lost: e.value.lost,
                forScore: e.value.scored,
                against: e.value.against,
                points: e.value.points,
              ),
            )
            .toList()
          ..sort((x, y) {
            if (y.points != x.points) return y.points.compareTo(x.points);
            if (y.won != x.won) return y.won.compareTo(x.won);
            final dx = y.diff, dy = x.diff;
            if (dx != dy) return dx.compareTo(dy);
            if (y.forScore != x.forScore) {
              return y.forScore.compareTo(x.forScore);
            }
            return x.label.compareTo(y.label);
          });

    for (var i = 0; i < list.length; i++) {
      list[i] = list[i].copyWith(position: i + 1, qualifies: i < qualifyTop);
    }
    return list;
  }

  /// Fixtures grouped into rounds, oldest round first, for bracket rendering.
  static List<List<Fixture>> roundsOf(List<Fixture> fixtures) {
    final byRound = <int, List<Fixture>>{};
    for (final f in fixtures) {
      (byRound[f.round] ??= []).add(f);
    }
    final keys = byRound.keys.toList()..sort();
    return [
      for (final k in keys)
        byRound[k]!..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)),
    ];
  }

  static String stageName(Fixture f) => f.stage;

  static int _nextPow2(int n) {
    var p = 1;
    while (p < n) {
      p *= 2;
    }
    return p;
  }

  static int _log2(int v) {
    var n = 0;
    while ((1 << n) < v) {
      n++;
    }
    return n;
  }

  /// Standard bracket seed ordering, e.g. size 8 → 0,7,3,4,1,6,2,5.
  static List<int> _bracketOrder(int size) {
    var r = <int>[0, 1];
    while (r.length < size) {
      final n = r.length * 2;
      final out = <int>[];
      for (final x in r) {
        out
          ..add(x)
          ..add(n - 1 - x);
      }
      r = out;
    }
    return r;
  }

  static List<List<Entry>> _snakeGroups(List<Entry> entries, int groupCount) {
    final groups = List.generate(groupCount, (_) => <Entry>[]);
    for (var i = 0; i < entries.length; i++) {
      final cycle = i ~/ groupCount;
      final slot = cycle.isEven
          ? i % groupCount
          : groupCount - 1 - (i % groupCount);
      groups[slot].add(entries[i]);
    }
    return groups;
  }

  /// Circle-method round robin; returns (home, away) pairs. An odd group size
  /// gets a phantom pass, which is dropped.
  static List<(Entry, Entry)> _roundRobin(List<Entry> members) {
    final list = List<Entry?>.from(members);
    if (list.length.isOdd) list.add(null);
    final n = list.length;
    final rounds = n - 1;
    final half = n ~/ 2;
    final pairs = <(Entry, Entry)>[];

    for (var r = 0; r < rounds; r++) {
      for (var i = 0; i < half; i++) {
        final a = list[i];
        final b = list[n - 1 - i];
        if (a == null || b == null) continue;
        pairs.add(r.isOdd ? (b, a) : (a, b));
      }
      list.insert(1, list.removeAt(n - 1));
    }
    return pairs;
  }

  static String _stageName(int roundsFromFinal) => switch (roundsFromFinal) {
    0 => 'Final',
    1 => 'Semi-final',
    2 => 'Quarter-final',
    3 => 'Round of 16',
    _ => 'Round of ${(1 << (roundsFromFinal + 1))}',
  };

  static Fixture _blankFixture({
    required Tournament tournament,
    required String id,
    required int round,
    required String stage,
    required String homeEntryId,
    required String awayEntryId,
    required String? group,
    required int ordinal,
    required int roundsTotal,
    required List<String> scorerPool,
  }) {
    final daySpan = tournament.endsAt
        .difference(tournament.startsAt)
        .inDays
        .clamp(1, 60);
    final total = (1 << (roundsTotal - 1));
    final offset = ((ordinal / total) * daySpan).floor().clamp(0, daySpan);

    return Fixture(
      id: id,
      tournamentId: tournament.id,
      stage: stage,
      round: round,
      group: group,
      home: FixtureSide(entryId: homeEntryId, label: '', group: group),
      away: FixtureSide(entryId: awayEntryId, label: '', group: group),
      scheduledAt: tournament.startsAt
          .add(Duration(days: offset))
          .add(
            Duration(hours: 9 + (ordinal % 6), minutes: (ordinal * 15) % 60),
          ),
      venue: group != null ? 'Court $group$ordinal' : 'Court $ordinal',
      status: FixtureStatus.upcoming,
      scorerAccountIds: scorerPool.isEmpty
          ? <String>[]
          : [scorerPool[ordinal % scorerPool.length]],
      // Growable: official scoring, transfers and corrections append here.
      events: [],
      rules: Map<String, dynamic>.from(tournament.rules),
      corrections: [],
    );
  }
}

class StandingRow {
  final String entryId;
  final String label;
  final int played, won, drawn, lost, forScore, against, points;
  int position;
  bool qualifies;

  StandingRow({
    required this.entryId,
    required this.label,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.forScore,
    required this.against,
    required this.points,
    this.position = 0,
    this.qualifies = false,
  });

  int get diff => forScore - against;

  StandingRow copyWith({int? position, bool? qualifies}) => StandingRow(
    entryId: entryId,
    label: label,
    played: played,
    won: won,
    drawn: drawn,
    lost: lost,
    forScore: forScore,
    against: against,
    points: points,
    position: position ?? this.position,
    qualifies: qualifies ?? this.qualifies,
  );
}

class _StandingBuilder {
  final String label;
  int played = 0,
      won = 0,
      drawn = 0,
      lost = 0,
      scored = 0,
      against = 0,
      points = 0;
  _StandingBuilder(this.label);
}
