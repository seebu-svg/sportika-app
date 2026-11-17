import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';

enum ProfileModuleStatus { idle, loading, ready, error }

/// Owns the Me module's one server read and every section write.
///
/// The repository already answers each call in isolation; this controller adds
/// the shared lifecycle the screens need — loading, retryable failure, a busy
/// flag that stops a double submit, and the assignment list the scorer screen
/// watches. It never decides permission: the database does, and a refusal comes
/// back as a [ProfileModuleException] to show as-is.
class ProfileModuleController extends ChangeNotifier {
  ProfileModuleController(this._repo) {
    _repo.addListener(_onRepositoryChanged);
  }

  final ProfileModuleRepository _repo;

  ProfileModuleStatus _status = ProfileModuleStatus.idle;
  ProfileModuleSnapshot? _snapshot;
  String? _error;
  bool _busy = false;
  bool _disposed = false;

  List<ScorerAssignment> _assignments = const <ScorerAssignment>[];
  bool _assignmentsLoading = false;
  String? _assignmentsError;

  // ── Reads ───────────────────────────────────────────────────────────────

  ProfileModuleStatus get status => _status;
  bool get loading => _status == ProfileModuleStatus.loading;
  bool get ready => _status == ProfileModuleStatus.ready;
  ProfileModuleSnapshot? get snapshot => _snapshot;
  String? get error => _error;

  /// True while a write is in flight, so buttons can show their progress and
  /// refuse a second tap.
  bool get busy => _busy;

  bool get supportsIdentityDocuments => _repo.supportsIdentityDocuments;

  List<ScorerAssignment> get assignments => _assignments;
  bool get assignmentsLoading => _assignmentsLoading;
  String? get assignmentsError => _assignmentsError;

  /// One load per session unless something failed; the overview calls this on
  /// every build and pays nothing after the first.
  Future<void> ensureLoaded() async {
    if (_status == ProfileModuleStatus.ready ||
        _status == ProfileModuleStatus.loading) {
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    _status = ProfileModuleStatus.loading;
    _error = null;
    _notify();
    try {
      _snapshot = await _repo.load();
      _status = ProfileModuleStatus.ready;
    } catch (error) {
      _error = messageFor(error);
      _status = ProfileModuleStatus.error;
    }
    _notify();
  }

  Future<void> loadAssignments() async {
    _assignmentsLoading = true;
    _assignmentsError = null;
    _notify();
    try {
      _assignments = await _repo.loadAssignments();
    } catch (error) {
      _assignmentsError = messageFor(error);
    } finally {
      _assignmentsLoading = false;
      _notify();
    }
  }

  Future<List<ProfileSummary>> searchPlayers(String query) =>
      _repo.searchPlayers(query);

  // ── Writes ──────────────────────────────────────────────────────────────

  Future<void> savePersonalInformation({
    required String displayName,
    required String city,
    required String bio,
    required DateTime dateOfBirth,
    required ProfileGender? gender,
    required PlayStyle playStyle,
  }) => _mutate(
    () => _repo.savePersonalInformation(
      displayName: displayName,
      city: city,
      bio: bio,
      dateOfBirth: dateOfBirth,
      gender: gender,
      playStyle: playStyle,
    ),
  );

  Future<void> changeUsername(String username) =>
      _mutate(() => _repo.changeUsername(username));

  Future<void> saveSportsPreferences(List<ProfileSportPreference> sports) =>
      _mutate(() => _repo.saveSportsPreferences(sports));

  Future<void> submitIdentityDocument(IdentitySubmission submission) =>
      _mutate(() => _repo.submitIdentityDocument(submission));

  Future<void> deleteIdentityDocument() =>
      _mutate(() => _repo.deleteIdentityDocument());

  Future<void> claimOrganizer(String tournamentId) =>
      _mutate(() => _repo.claimOrganizer(tournamentId));

  Future<ScorerAssignment> assignScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  }) async {
    final assignment = await _repo.assignScorer(
      tournamentId: tournamentId,
      fixtureId: fixtureId,
      scorerId: scorerId,
    );
    await loadAssignments();
    return assignment;
  }

  Future<void> revokeScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  }) async {
    await _repo.revokeScorer(
      tournamentId: tournamentId,
      fixtureId: fixtureId,
      scorerId: scorerId,
    );
    await loadAssignments();
  }

  Future<void> respondToAssignment({
    required String assignmentId,
    required bool accept,
  }) async {
    await _repo.respondToAssignment(assignmentId: assignmentId, accept: accept);
    await loadAssignments();
  }

  // ── Plumbing ────────────────────────────────────────────────────────────

  /// Runs a write, then re-reads the card so every screen that watches this
  /// controller shows the stored truth. The error is rethrown: screens decide
  /// whether it becomes a field error, a banner or a snack.
  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _notify();
    try {
      await action();
      await _reloadSilently();
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _reloadSilently() async {
    try {
      _snapshot = await _repo.load();
      _status = ProfileModuleStatus.ready;
      _error = null;
    } catch (_) {
      // The write already succeeded. A failed follow-up read must not turn a
      // saved change into an error; the next refresh repairs the card.
    }
  }

  void _onRepositoryChanged() => _notify();

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// A message that is safe to show: the repository's own sentence when it has
  /// one, and a neutral fallback otherwise.
  static String messageFor(Object error) {
    if (error is ProfileModuleException) return error.message;
    if (error is StateError) return error.message;
    return 'Something went wrong. Check your connection and try again.';
  }

  @override
  void dispose() {
    _disposed = true;
    _repo.removeListener(_onRepositoryChanged);
    super.dispose();
  }
}
