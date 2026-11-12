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

  String? get currentAccountId => repo.currentAccountId;

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

  Squad? squadById(String id) => repo.squadById(id);

  /// Squads this account has been invited to and has not answered yet.
  List<Squad> get myInvites {
    final me = repo.currentAccountId;
    if (me == null) return const [];
    return repo.squads.where((s) => s.invitedAccountIds.contains(me)).toList();
  }

  void invite(String squadId, String accountId) =>
      repo.inviteToSquad(squadId, accountId);
  void cancelInvite(String squadId, String accountId) =>
      repo.cancelSquadInvite(squadId, accountId);
  void respondToInvite(String squadId, {required bool accept}) {
    final me = repo.currentAccountId;
    if (me == null) return;
    repo.respondToSquadInvite(squadId, me, accept: accept);
  }

  void transferCaptain(String squadId, String accountId) =>
      repo.transferCaptain(squadId, accountId);
  void leaveSquad(String squadId) => repo.leaveSquad(squadId);
  void deleteSquad(String squadId) => repo.deleteSquad(squadId);

  /// Players who are not on [squadId], filtered by a search term.
  List<Account> inviteCandidates(String squadId, String query) {
    final squad = repo.squadById(squadId);
    final known = {...?squad?.memberAccountIds, ...?squad?.invitedAccountIds};
    final term = query.trim().toLowerCase();
    return repo.accounts
        .where((a) => !known.contains(a.id))
        .where(
          (a) =>
              term.isEmpty ||
              '${a.displayName} ${a.city}'.toLowerCase().contains(term),
        )
        .toList();
  }
}
