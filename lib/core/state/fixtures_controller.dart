import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/core/data/repositories.dart';

/// Official fixtures: live board, scoring log, results and disputes.
class FixturesController extends FeatureController<FixtureRepository> {
  FixturesController(super.repo);

  /// True while the server read is in flight.
  bool get loading => repo.loading;

  /// Why the last read failed, or null while it is healthy.
  String? get lastError => repo.lastError;

  /// Re-reads the match rows the bracket is projected from.
  Future<void> refresh() => repo.refresh();

  List<Fixture> get fixtures => repo.fixtures;

  Fixture? fixtureById(String id) => repo.fixtureById(id);
  List<Fixture> fixturesFor(String tournamentId) =>
      repo.fixturesFor(tournamentId);
  Tournament? tournamentOf(Fixture f) => repo.tournamentOf(f);

  List<Fixture> get publicFixtures => repo.publicFixtures;
  List<Fixture> get liveFixtures => repo.liveFixtures;
  List<Fixture> get completedFixtures => repo.completedFixtures;
  List<Fixture> get scheduledFixtures => repo.scheduledFixtures;
  List<Fixture> get myScoringFixtures => repo.myScoringFixtures;
  List<Fixture> get myOrganizerFixtures => repo.myOrganizerFixtures;
  List<Fixture> get fixturesAwaitingReview => repo.fixturesAwaitingReview;
  List<Fixture> get myOrganizerDisputes => repo.myOrganizerDisputes;
  List<Fixture> get myFixtures => repo.myFixtures;
  List<Fixture> officialMatchesPlayed() => repo.officialMatchesPlayed();
  List<Fixture> appearancesOf(String accountId) =>
      repo.appearancesOf(accountId);

  List<Fixture> filterFixtures({Sport? sport, DateTime? day}) =>
      repo.filterFixtures(sport: sport, day: day);

  List<String> sideLabelsOf(Fixture f) => repo.sideLabelsOf(f);
  String sideLabel(Fixture f, int index) => repo.sideLabel(f, index);
  MatchProgress progressOfFixture(Fixture f) => repo.progressOfFixture(f);

  void assignScorer(String fixtureId, String accountId) =>
      repo.assignScorer(fixtureId, accountId);
  void replaceScorer(String fixtureId, String fromId, String toId) =>
      repo.replaceScorer(fixtureId, fromId, toId);
  void removeScorer(String fixtureId, String accountId) =>
      repo.removeScorer(fixtureId, accountId);

  void startOfficialScoring(String fixtureId) =>
      repo.startOfficialScoring(fixtureId);
  void recordOfficialEvent(String fixtureId, ScoringEvent event) =>
      repo.recordOfficialEvent(fixtureId, event);
  void undoOfficialEvent(String fixtureId) => repo.undoOfficialEvent(fixtureId);
  void submitOfficialResult(String fixtureId) =>
      repo.submitOfficialResult(fixtureId);
  void publishOfficialResult(String fixtureId, {String? correctionReason}) =>
      repo.publishOfficialResult(fixtureId, correctionReason: correctionReason);
  void recordWalkover(String fixtureId, int winnerIndex, String reason) =>
      repo.recordWalkover(fixtureId, winnerIndex, reason);

  void updateFixtureSchedule(
    String fixtureId, {
    DateTime? scheduledAt,
    String? venue,
    String? scorerId,
  }) => repo.updateFixtureSchedule(
    fixtureId,
    scheduledAt: scheduledAt,
    venue: venue,
    scorerId: scorerId,
  );

  void raiseDispute(String fixtureId, String note) =>
      repo.raiseDispute(fixtureId, note);
  void resolveDispute(
    String fixtureId, {
    required bool upholdResult,
    String? note,
  }) => repo.resolveDispute(fixtureId, upholdResult: upholdResult, note: note);
}
