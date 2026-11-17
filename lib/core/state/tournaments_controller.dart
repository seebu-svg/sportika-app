import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/tournament_engine.dart';
import 'package:sportika/core/data/repositories.dart';

/// Tournaments, entries, draws and standings.
class TournamentsController extends FeatureController<TournamentRepository> {
  TournamentsController(super.repo);

  /// True while the server read is in flight, so a section can tell an empty
  /// list from one that has not arrived yet.
  bool get loading => repo.loading;

  /// Why the last read failed, or null while it is healthy.
  String? get lastError => repo.lastError;

  /// Re-reads the server rows. Pull-to-refresh and a section's retry both call
  /// this instead of each screen inventing its own path.
  Future<void> refresh() => repo.refresh();

  List<Tournament> get tournaments => repo.tournaments;
  List<Entry> get entries => repo.entries;
  Map<String, Entry> get entriesById => repo.entriesById;

  Tournament? tournamentById(String id) => repo.tournamentById(id);
  List<Entry> entriesFor(String tournamentId) => repo.entriesFor(tournamentId);
  List<Entry> confirmedEntriesFor(String tournamentId) =>
      repo.confirmedEntriesFor(tournamentId);
  List<Entry> pendingEntriesFor(String tournamentId) =>
      repo.pendingEntriesFor(tournamentId);
  Entry? myEntryFor(String tournamentId) => repo.myEntryFor(tournamentId);
  int confirmedCountFor(Tournament t) => repo.confirmedCountFor(t);
  bool canRegisterFor(Tournament t) => repo.canRegisterFor(t);

  List<Tournament> get liveTournaments => repo.liveTournaments;
  List<Tournament> get myTournaments => repo.myTournaments;
  List<Tournament> tournamentsForOrganizer(String? accountId) =>
      repo.tournamentsForOrganizer(accountId);
  List<Tournament> filterTournaments({
    Sport? sport,
    bool myEntriesOnly = false,
  }) => repo.filterTournaments(sport: sport, myEntriesOnly: myEntriesOnly);

  List<StandingRow> standingsFor(Tournament t) => repo.standingsFor(t);
  List<List<Fixture>> roundsFor(Tournament t) => repo.roundsFor(t);

  Future<void> createTournament({
    required String name,
    required String city,
    required Sport sport,
    required TournamentFormat format,
    required EntryType entryType,
    required DateTime startsAt,
    required DateTime endsAt,
    required int registrationLimit,
    required String entryFee,
    required String rulesSummary,
    required Map<String, dynamic> rules,
    required bool publishNow,
  }) => repo.createTournament(
    name: name,
    city: city,
    sport: sport,
    format: format,
    entryType: entryType,
    startsAt: startsAt,
    endsAt: endsAt,
    registrationLimit: registrationLimit,
    entryFee: entryFee,
    rulesSummary: rulesSummary,
    rules: rules,
    publishNow: publishNow,
  );

  void setTournamentStatus(String tournamentId, TournamentStatus status) =>
      repo.setTournamentStatus(tournamentId, status);

  Future<void> submitEntry({
    required String tournamentId,
    String? squadId,
    List<String>? memberIds,
  }) => repo.submitEntry(
    tournamentId: tournamentId,
    squadId: squadId,
    memberIds: memberIds,
  );

  Future<void> withdrawEntry(String entryId) => repo.withdrawEntry(entryId);

  Future<void> decideEntry(
    String entryId, {
    required bool approve,
    String? note,
  }) => repo.decideEntry(entryId, approve: approve, note: note);

  Future<int> generateDraw(String tournamentId) =>
      repo.generateDraw(tournamentId);
}
