import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';

/// Private, account-scoped scorecards. Never feeds official standings.
class PersonalGamesController extends FeatureController {
  PersonalGamesController(super.repo);

  List<PersonalMatch> get personal => repo.personal;
  List<PersonalMatch> get myPersonal => repo.myPersonal;
  List<PersonalMatch> get myPersonalInProgress => repo.myPersonalInProgress;
  PersonalMatch? personalById(String id) => repo.personalById(id);

  PersonalMatch startPersonalMatch({
    required Sport sport,
    required String format,
    required String sideA,
    required String sideB,
  }) => repo.startPersonalMatch(
    sport: sport,
    format: format,
    sideA: sideA,
    sideB: sideB,
  );

  void recordPersonalEvent(String matchId, ScoringEvent event) =>
      repo.recordPersonalEvent(matchId, event);
  void undoPersonalEvent(String matchId) => repo.undoPersonalEvent(matchId);
  void replacePersonalEvent(String id, int index, ScoringEvent event) =>
      repo.replacePersonalEvent(id, index, event);
  void updatePersonalDetails(
    String id,
    Map<String, dynamic> details, {
    List<String>? sides,
  }) => repo.updatePersonalDetails(id, details, sides: sides);
  void setPersonalStatus(String id, PersonalMatchStatus status) =>
      repo.setPersonalStatus(id, status);
  void deletePersonalMatch(String matchId) => repo.deletePersonalMatch(matchId);
  MatchProgress progressOfPersonal(PersonalMatch m) =>
      repo.progressOfPersonal(m);
}
