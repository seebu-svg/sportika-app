import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';

/// Turns a folded [MatchProgress] into the record an organizer publishes,
/// and resolves bracket placeholders from published results only.
class OfficialResults {
  OfficialResults._();

  static OfficialResult fromProgress(
    MatchProgress p, {
    required String publishedById,
    bool walkover = false,
    String? detailOverride,
  }) => OfficialResult(
    sideScores: List.of(p.scoreDisplay),
    sideValues: List.of(p.scoreValues),
    winnerIndex: p.winnerIndex,
    headline: p.resultLabel.isNotEmpty
        ? p.resultLabel
        : (p.winnerIndex >= 0 ? '${p.sides[p.winnerIndex]} won' : 'Drawn'),
    detail:
        detailOverride ??
        [
          if (p.completionReason.isNotEmpty) p.completionReason,
          ...p.detailRows,
        ].join(' · '),
    publishedAt: DateTime.now(),
    publishedById: publishedById,
    walkover: walkover,
  );

  /// Placeholder token used by a knockout draw for a slot that depends on an
  /// earlier fixture, e.g. `TBD:match:f-12`.
  static const String tbdPrefix = 'TBD:match:';

  static String tbdToken(String fixtureId) => '$tbdPrefix$fixtureId';

  static bool isPlaceholder(String entryId) => entryId.startsWith(tbdPrefix);

  static String? placeholderSource(String entryId) =>
      isPlaceholder(entryId) ? entryId.substring(tbdPrefix.length) : null;

  /// Resolves the display label and entry id of a fixture side. Knockout slots
  /// only resolve once the feeder fixture result is published (spec §6:
  /// brackets update when the organizer publishes).
  static ResolvedSide resolve(
    FixtureSide side,
    List<Fixture> allFixtures,
    Map<String, Entry> entriesById,
  ) {
    if (!isPlaceholder(side.entryId)) {
      final entry = entriesById[side.entryId];
      return ResolvedSide(
        entryId: side.entryId,
        label: entry?.label ?? side.label,
        resolved: true,
      );
    }
    final srcId = placeholderSource(side.entryId)!;
    final src = allFixtures.where((f) => f.id == srcId).toList();
    if (src.isEmpty || src.first.result == null) {
      return ResolvedSide(entryId: side.entryId, label: 'TBD', resolved: false);
    }
    final winner = src.first.result!.winnerIndex;
    if (winner < 0) {
      return ResolvedSide(
        entryId: side.entryId,
        label: 'TBD (tie)',
        resolved: false,
      );
    }
    final winnerSide = winner == 0 ? src.first.home : src.first.away;
    return resolve(winnerSide, allFixtures, entriesById);
  }

  static String describeOutcome(OfficialResult r, List<String> sides) {
    if (r.winnerIndex < 0) return 'Drawn ${_scoreText(r, sides)}';
    final s = r.winnerIndex < sides.length ? r.winnerIndex : 0;
    return '${sides[s]} won ${_scoreText(r, sides)}';
  }

  static String _scoreText(OfficialResult r, List<String> sides) {
    if (r.sideScores.length >= 2 &&
        r.sideScores[0].isNotEmpty &&
        !r.sideScores[0].contains('-')) {
      return r.sideScores.join(' : ');
    }
    return r.sideValues.join('-');
  }
}

class ResolvedSide {
  final String entryId;
  final String label;
  final bool resolved;
  const ResolvedSide({
    required this.entryId,
    required this.label,
    required this.resolved,
  });
}
