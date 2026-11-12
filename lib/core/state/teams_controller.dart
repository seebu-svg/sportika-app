import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/data/repositories.dart';

/// Squads (teams and pairs) plus the player directory used to fill them.
class TeamsController extends FeatureController<TeamRepository> {
  TeamsController(super.repo);

  List<Squad> get squads => repo.squads;
  List<Squad> get mySquads => repo.mySquads;
  List<Squad> squadsFor(Sport sport, EntryType type) =>
      repo.squadsFor(sport, type);
  List<Squad> squadsOf(String accountId) => repo.squadsOf(accountId);

  List<Account> get accounts => repo.accounts;
  List<Account> get otherPlayers => repo.otherPlayers;

  Squad createSquad({
    required String name,
    required Sport sport,
    required EntryType type,
    required List<String> memberIds,
  }) => repo.createSquad(
    name: name,
    sport: sport,
    type: type,
    memberIds: memberIds,
  );

  void addSquadMember(String squadId, String accountId) =>
      repo.addSquadMember(squadId, accountId);
  void removeSquadMember(String squadId, String accountId) =>
      repo.removeSquadMember(squadId, accountId);
}
