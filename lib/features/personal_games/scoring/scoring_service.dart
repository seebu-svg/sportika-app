import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/badminton/badminton.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/features/personal_games/scoring/padel/padel.dart';

/// Single entry point to the scoring engines, so every screen and the state
/// layer can stay sport-agnostic.
///
/// Personal scoring (Match History) and official scoring (Scorer Workspace)
/// both go through here, which is what keeps the rules identical while the
/// match records stay completely separate (spec §3).
class SportEngines {
  SportEngines._();

  static final Map<Sport, SportEngine> _all = {
    Sport.cricket: CricketEngine(),
    Sport.padel: PadelEngine(),
    Sport.futsal: FutsalEngine(),
    Sport.badminton: BadmintonEngine(),
  };

  static SportEngine forSport(Sport sport) => _all[sport]!;

  static List<String> formatsFor(Sport sport) => _all[sport]!.formats;

  static Map<String, dynamic> rulesFor(Sport sport, String format) =>
      _all[sport]!.rulesForFormat(format);

  static String describeRules(Sport sport, Map<String, dynamic> rules) =>
      _all[sport]!.describeRules(rules);

  /// Decodes a persisted event log and folds it through the sport engine.
  static MatchProgress progressOf({
    required Sport sport,
    required List<String> sides,
    required Map<String, dynamic> rules,
    required List<Map<String, dynamic>> rawEvents,
  }) => forSport(sport).evaluate(
    sides: sides,
    rules: rules,
    events: rawEvents.map(ScoringEvent.fromJson).toList(growable: false),
  );

  /// Formats already recorded with, falling back to the first format.
  static Map<String, dynamic> rulesOr(
    Sport sport,
    Map<String, dynamic> rules,
  ) => rules.isNotEmpty ? rules : rulesFor(sport, formatsFor(sport).first);

  /// Entry type a sport implies for tournament setup (spec §4.2).
  static EntryType defaultEntryType(Sport sport) => switch (sport) {
    Sport.cricket => EntryType.team,
    Sport.futsal => EntryType.team,
    Sport.padel => EntryType.pair,
    Sport.badminton => EntryType.pair,
  };
}
