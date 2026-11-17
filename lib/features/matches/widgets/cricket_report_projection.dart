import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/shared/models/match.dart';

/// Presentation projections only. Team totals and outcomes remain engine-owned:
/// everything below is derived from the recorded deliveries so a scorecard row
/// can never disagree with what the scorer actually logged.
class CricketInningsReport {
  CricketInningsReport(this.balls);

  final List<MatchEvent> balls;

  static List<MatchEvent> deliveries(SportMatch match, int side) =>
      (match.events
          .where(
            (e) => !e.voided && e.kind == CricketEngine.kBall && e.side == side,
          )
          .toList()
        ..sort((a, b) => a.seq.compareTo(b.seq)));

  static bool legal(MatchEvent e) =>
      e.data['extra'] != 'wide' && e.data['extra'] != 'noball';

  static int runs(MatchEvent e) => (e.data['runs'] as num?)?.toInt() ?? 0;

  static int total(MatchEvent e) => runs(e) + (legal(e) ? 0 : 1);

  /// Bat runs only: byes and leg-byes are extras and a wide is never faced.
  static bool creditsBatter(MatchEvent e) {
    final extra = e.data['extra'];
    return extra != 'wide' && extra != 'bye' && extra != 'legbye';
  }

  /// Dismissals the bowler is credited with, identical to the previous report.
  static const Set<String> bowlerDismissals = {
    'Bowled',
    'Caught',
    'LBW',
    'Stumped',
    'Caught & bowled',
    'Hit wicket',
  };

  int get legalBalls => balls.where(legal).length;

  int extra(String type) => balls
      .where((e) => e.data['extra'] == type)
      .fold(
        0,
        (n, e) =>
            n +
            (type == 'wide'
                ? 1 + runs(e)
                : type == 'noball'
                ? 1
                : runs(e)),
      );

  Set<String> names(String field) => balls
      .map((e) => e.data[field] as String? ?? '')
      .where((s) => s.isNotEmpty)
      .toSet();

  bool get isEmpty => balls.isEmpty;

  int get extrasTotal =>
      extra('wide') + extra('noball') + extra('bye') + extra('legbye');

  late final List<CricketBattingLine> batting = _batting();
  late final List<CricketBowlingLine> bowling = _bowling();
  late final List<CricketFallOfWicket> wickets = _fallOfWickets();
  late final List<CricketPartnership> partnerships = _partnerships();
  late final List<CricketDelivery> timeline = _timeline();
  late final List<CricketOverSummary> overs = _overs();

  /// Most recent over first, which is how a commentary feed reads.
  late final List<CricketOverSummary> recentOvers = overs.reversed.toList();

  /// True when deliveries exist but none of them name a batter.
  bool get playersUnrecorded => balls.isNotEmpty && names('striker').isEmpty;

  List<CricketBattingLine> _batting() {
    final out = <CricketBattingLine>[];
    for (final name in names('striker')) {
      final faced = balls.where((e) => e.data['striker'] == name).toList();
      final scored = faced.where(creditsBatter).toList();
      final scoredRuns = scored.fold<int>(0, (n, e) => n + runs(e));
      final count = faced.where(legal).length;
      MatchEvent? dismissal;
      for (final e in balls) {
        if (e.data['wicket'] == true &&
            (e.data['dismissedBatter'] ?? e.data['striker']) == name) {
          dismissal = e;
          break;
        }
      }
      out.add(
        CricketBattingLine(
          name: name,
          dismissal: dismissal == null
              ? 'Not out'
              : dismissal.data['dismissal'] as String? ?? 'Out',
          notOut: dismissal == null,
          runs: scoredRuns,
          balls: count,
          fours: scored.where((e) => runs(e) == 4).length,
          sixes: scored.where((e) => runs(e) == 6).length,
        ),
      );
    }
    return out;
  }

  List<CricketBowlingLine> _bowling() {
    final out = <CricketBowlingLine>[];
    for (final name in names('bowler')) {
      final bowled = balls
          .where((e) => e.data['bowler'] == name)
          .toList(growable: false);
      final count = bowled.where(legal).length;
      final conceded = bowled
          .where((e) => e.data['extra'] != 'bye' && e.data['extra'] != 'legbye')
          .fold<int>(0, (n, e) => n + total(e));
      final wickets = bowled
          .where(
            (e) =>
                e.data['wicket'] == true &&
                bowlerDismissals.contains(e.data['dismissal']),
          )
          .length;
      out.add(
        CricketBowlingLine(
          name: name,
          balls: count,
          runs: conceded,
          wickets: wickets,
        ),
      );
    }
    return out;
  }

  List<CricketFallOfWicket> _fallOfWickets() {
    final out = <CricketFallOfWicket>[];
    var score = 0, fallen = 0, legalCount = 0;
    for (final e in balls) {
      score += total(e);
      if (legal(e)) legalCount++;
      if (e.data['wicket'] != true) continue;
      fallen++;
      out.add(
        CricketFallOfWicket(
          wicket: fallen,
          score: '$score/$fallen',
          batter:
              e.data['dismissedBatter'] as String? ??
              e.data['striker'] as String? ??
              'Batter not recorded',
          overs: _oversLabel(legalCount),
        ),
      );
    }
    return out;
  }

  List<CricketPartnership> _partnerships() {
    final out = <CricketPartnership>[];
    var runs = 0, wicket = 0;
    for (final e in balls) {
      runs += total(e);
      if (e.data['wicket'] != true) continue;
      wicket++;
      out.add(CricketPartnership(wicket: wicket, runs: runs, unbroken: false));
      runs = 0;
    }
    out.add(CricketPartnership(wicket: wicket + 1, runs: runs, unbroken: true));
    return out;
  }

  List<CricketDelivery> _timeline() {
    final out = <CricketDelivery>[];
    final perOver = <int, int>{};
    var legalCount = 0;
    for (final e in balls) {
      final over = legalCount ~/ 6 + 1;
      final ball = (perOver[over] ?? 0) + 1;
      perOver[over] = ball;
      final extra = e.data['extra'] as String?;
      final scored = runs(e);
      final isWicket = e.data['wicket'] == true;
      final dismissal = e.data['dismissal'] as String?;
      out.add(
        CricketDelivery(
          over: over,
          ball: ball,
          label: _ballLabel(runs: scored, extra: extra, wicket: isWicket),
          bowler: _name(e.data['bowler'], 'Bowler not recorded'),
          striker: _name(e.data['striker'], 'Batter not recorded'),
          runs: total(e),
          batRuns: creditsBatter(e) ? scored : 0,
          extra: extra,
          isWicket: isWicket,
          dismissal: dismissal,
        ),
      );
      if (legal(e)) legalCount++;
    }
    return out;
  }

  List<CricketOverSummary> _overs() {
    final grouped = <int, List<CricketDelivery>>{};
    for (final delivery in timeline) {
      grouped.putIfAbsent(delivery.over, () => []).add(delivery);
    }
    return [
      for (final entry in grouped.entries)
        CricketOverSummary(
          number: entry.key,
          deliveries: entry.value,
          runs: entry.value.fold(0, (n, d) => n + d.runs),
          wickets: entry.value.where((d) => d.isWicket).length,
          legalBalls: entry.value.where(_isLegal).length,
        ),
    ];
  }

  static bool _isLegal(CricketDelivery delivery) =>
      delivery.extra != 'wide' && delivery.extra != 'noball';

  static String _oversLabel(int balls) => '${balls ~/ 6}.${balls % 6}';

  static String _name(Object? raw, String fallback) {
    final text = raw is String ? raw.trim() : '';
    return text.isEmpty ? fallback : text;
  }

  /// Same shorthand the scoring workspace prints: 4, W, Wd, Nb + 1, B2, Lb1.
  static String _ballLabel({
    required int runs,
    required String? extra,
    required bool wicket,
  }) {
    if (wicket) {
      return switch (extra) {
        'wide' => 'W + Wd',
        'noball' => 'W + Nb',
        _ => 'W',
      };
    }
    return switch (extra) {
      'wide' => runs == 0 ? 'Wd' : 'Wd + $runs',
      'noball' => runs == 0 ? 'Nb' : 'Nb + $runs',
      'bye' => 'B$runs',
      'legbye' => 'Lb$runs',
      _ => '$runs',
    };
  }
}

/// One batter's line, derived from the deliveries they faced.
class CricketBattingLine {
  const CricketBattingLine({
    required this.name,
    required this.dismissal,
    required this.notOut,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
  });

  final String name;
  final String dismissal;
  final bool notOut;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;

  String get strikeRate =>
      balls == 0 ? '—' : (runs * 100 / balls).toStringAsFixed(1);
}

/// One bowler's line for the innings.
class CricketBowlingLine {
  const CricketBowlingLine({
    required this.name,
    required this.balls,
    required this.runs,
    required this.wickets,
  });

  final String name;
  final int balls;
  final int runs;
  final int wickets;

  String get overs => '${balls ~/ 6}.${balls % 6}';

  String get economy =>
      balls == 0 ? '—' : (runs * 6 / balls).toStringAsFixed(2);
}

/// A wicket in the order it fell.
class CricketFallOfWicket {
  const CricketFallOfWicket({
    required this.wicket,
    required this.score,
    required this.batter,
    required this.overs,
  });

  final int wicket;
  final String score;
  final String batter;
  final String overs;
}

/// Runs added between two wickets; the last one is still unbroken.
class CricketPartnership {
  const CricketPartnership({
    required this.wicket,
    required this.runs,
    required this.unbroken,
  });

  final int wicket;
  final int runs;
  final bool unbroken;
}

/// A single delivery as the scorecard presents it.
class CricketDelivery {
  const CricketDelivery({
    required this.over,
    required this.ball,
    required this.label,
    required this.bowler,
    required this.striker,
    required this.runs,
    required this.batRuns,
    required this.extra,
    required this.isWicket,
    required this.dismissal,
  });

  final int over;
  final int ball;
  final String label;
  final String bowler;
  final String striker;
  final int runs;
  final int batRuns;
  final String? extra;
  final bool isWicket;
  final String? dismissal;

  String get position => '$over.$ball';

  bool get isExtra => extra != null;

  bool get isBoundary => batRuns == 4 || batRuns == 6;

  String get headline => '$bowler to $striker';

  /// Plain description built from recorded fields only — no invented detail.
  String get summary {
    final total = runs == 0 ? 'no run' : _runs(runs);
    if (isWicket) {
      final how = (dismissal ?? '').isEmpty ? 'Wicket' : dismissal!;
      return extra == null ? '$how · $total' : '$how · ${_extra()} · $total';
    }
    if (extra != null) return '${_extra()} · $total';
    if (batRuns == 4) return 'Four runs';
    if (batRuns == 6) return 'Six runs';
    return runs == 0 ? 'No run' : total;
  }

  String _extra() => switch (extra) {
    'wide' => 'Wide',
    'noball' => 'No ball',
    'bye' => 'Byes',
    'legbye' => 'Leg byes',
    _ => 'Extra',
  };

  static String _runs(int value) => value == 1 ? '1 run' : '$value runs';
}

/// One over with its deliveries, for the overs tab.
class CricketOverSummary {
  const CricketOverSummary({
    required this.number,
    required this.deliveries,
    required this.runs,
    required this.wickets,
    required this.legalBalls,
  });

  final int number;
  final List<CricketDelivery> deliveries;
  final int runs;
  final int wickets;
  final int legalBalls;

  String get runsLabel => runs == 1 ? '1 run' : '$runs runs';
}
