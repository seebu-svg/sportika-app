import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/tournament_engine.dart';

/// Why a tournament write was refused, worded for the organizer who triggered it.
class TournamentRepositoryException implements Exception {
  const TournamentRepositoryException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Tournaments and their entries, read from PostgreSQL.
///
/// One nested select brings a tournament and every entry in the same instant,
/// so an organizer approving an entry never sees a list that disagrees with the
/// card above it. Every write is one RPC from migration 0016: the server derives
/// the actor from `auth.uid()`, refuses a non-organizer and sends the
/// notification. The client never names a row it writes.
///
/// Standings and rounds are not read from anywhere: a tournament fixture is a
/// `matches` row owned by the match module. [fixturesOf] is injected once at
/// wiring time so a table can be folded from published results without a second
/// copy of the score log.
class SupabaseTournamentRepository extends ChangeNotifier
    implements TournamentRepository {
  SupabaseTournamentRepository({
    required SupabaseClient client,
    AccountRepository? accounts,
    // A named parameter cannot be a private initializing formal.
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _accounts = accounts;

  final SupabaseClient _client;

  /// Used only to name an entry when a player registers without a squad.
  final AccountRepository? _accounts;

  /// One app-level channel over `tournaments` and `tournament_entries`, so a
  /// second device sees joins, decisions and status changes without a manual
  /// refresh. No filters: the realtime publication already carries both tables
  /// and RLS scopes the rows the socket receives. Created lazily on the first
  /// signed-in reload, torn down in [dispose].
  RealtimeChannel? _channel;

  /// A tournament and its entries travel together. The limit keeps one read to
  /// what a season can hold instead of every row the project ever created.
  static const String _select = '*, tournament_entries(*)';
  static const int _rowLimit = 200;

  List<Tournament> _tournaments = <Tournament>[];
  List<Entry> _entries = <Entry>[];

  /// True while a read is in flight, so Home draws a skeleton rather than an
  /// "no tournaments yet" empty state.
  bool _loading = false;

  /// The last failure a reload hit. A write failure is thrown to its caller
  /// instead, because only that screen can show it in context.
  String? _lastError;

  /// Where a tournament's fixtures come from, for standings and rounds.
  List<Fixture> Function(String tournamentId)? fixturesOf;

  @override
  bool get loading => _loading;

  @override
  String? get lastError => _lastError;

  @override
  Future<void> refresh() => reload();

  String? get _uid => _client.auth.currentUser?.id;

  // ── Read ────────────────────────────────────────────────────────────────

  @override
  List<Tournament> get tournaments =>
      List<Tournament>.unmodifiable(_tournaments);

  @override
  List<Entry> get entries => List<Entry>.unmodifiable(_entries);

  @override
  Map<String, Entry> get entriesById => {for (final e in _entries) e.id: e};

  @override
  Future<void> reload() async {
    if (_uid == null) {
      _tournaments = <Tournament>[];
      _entries = <Entry>[];
      notifyListeners();
      return;
    }
    _ensureRealtime();
    _loading = true;
    notifyListeners();
    try {
      final rows = await _client
          .from('tournaments')
          .select(_select)
          .order('starts_at', ascending: true)
          .limit(_rowLimit);
      final tournaments = <Tournament>[];
      final entries = <Entry>[];
      for (final row in rows.cast<Map<String, dynamic>>()) {
        tournaments.add(_tournamentFromRow(row));
        for (final child in _embeddedList(row['tournament_entries'])) {
          entries.add(_entryFromRow(child, row['id'] as String));
        }
      }
      // One swap, so a half-replaced list is never visible.
      _tournaments = tournaments;
      _entries = entries;
      _lastError = null;
    } catch (error) {
      // The last good snapshot stays on screen; the banner says what happened.
      _lastError = _message(error, 'Tournaments could not be loaded.');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  Tournament? tournamentById(String id) =>
      _tournaments.where((t) => t.id == id).firstOrNull;

  @override
  List<Entry> entriesFor(String tournamentId) =>
      _entries.where((e) => e.tournamentId == tournamentId).toList();

  @override
  List<Entry> confirmedEntriesFor(String tournamentId) =>
      entriesFor(tournamentId)
          .where((e) => e.status == EntryStatus.confirmed)
          .toList();

  @override
  List<Entry> pendingEntriesFor(String tournamentId) =>
      entriesFor(tournamentId)
          .where((e) => e.status == EntryStatus.pending)
          .toList();

  @override
  Entry? myEntryFor(String tournamentId) {
    final id = _uid;
    if (id == null) return null;
    return entriesFor(tournamentId)
        .where(
          (e) =>
              e.memberAccountIds.contains(id) &&
              e.status != EntryStatus.withdrawn,
        )
        .firstOrNull;
  }

  @override
  int confirmedCountFor(Tournament t) => confirmedEntriesFor(t.id).length;

  @override
  bool canRegisterFor(Tournament t) =>
      t.status == TournamentStatus.open &&
      // The server limit counts pending and confirmed entries against
      // registration_limit; mirror that, so a full tournament never shows a
      // register button. The RPC stays the authority.
      confirmedEntriesFor(t.id).length + pendingEntriesFor(t.id).length <
          t.registrationLimit &&
      myEntryFor(t.id) == null;

  /// Everything a member may join or follow: registration, play and results.
  /// A draft belongs to its organizer's screen, not to a public list.
  @override
  List<Tournament> get liveTournaments {
    final uid = _uid;
    return _tournaments
        .where(
          (t) => t.status != TournamentStatus.draft || t.organizerId == uid,
        )
        .toList()
      ..sort(_byRelevance);
  }

  /// Open first (registration closes), then what is being played, then results.
  int _byRelevance(Tournament a, Tournament b) {
    const rank = <TournamentStatus, int>{
      TournamentStatus.open: 0,
      TournamentStatus.inProgress: 1,
      TournamentStatus.completed: 2,
      TournamentStatus.draft: 3,
    };
    final byStatus = rank[a.status]!.compareTo(rank[b.status]!);
    if (byStatus != 0) return byStatus;
    return a.startsAt.compareTo(b.startsAt);
  }

  @override
  List<Tournament> get myTournaments {
    final me = _uid;
    if (me == null) return <Tournament>[];
    final ids = _entries
        .where(
          (e) =>
              e.memberAccountIds.contains(me) &&
              e.status != EntryStatus.withdrawn,
        )
        .map((e) => e.tournamentId)
        .toSet();
    return _tournaments.where((t) => ids.contains(t.id)).toList();
  }

  @override
  List<Tournament> tournamentsForOrganizer(String? accountId) =>
      _tournaments.where((t) => t.organizerId == accountId).toList();

  @override
  List<Tournament> filterTournaments({
    Sport? sport,
    bool myEntriesOnly = false,
  }) {
    final me = _uid;
    return liveTournaments.where((t) {
      if (sport != null && t.sport != sport) return false;
      if (myEntriesOnly && myEntryFor(t.id) == null) {
        // An organizer still sees the tournament they run.
        return me != null && t.organizerId == me;
      }
      return true;
    }).toList();
  }

  @override
  List<StandingRow> standingsFor(Tournament t) => TournamentEngine.standings(
    fixtures: fixturesOf?.call(t.id) ?? const <Fixture>[],
    entriesById: entriesById,
    qualifyTop: 2,
  );

  @override
  List<List<Fixture>> roundsFor(Tournament t) =>
      TournamentEngine.roundsOf(fixturesOf?.call(t.id) ?? const <Fixture>[]);

  // ── Write ───────────────────────────────────────────────────────────────

  @override
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
  }) async {
    final short = rulesSummary.split('·').first.trim();
    await _call('create_tournament', {
      'p_name': name.trim(),
      'p_city': city.trim().isEmpty ? 'Karachi' : city.trim(),
      'p_sport_key': sport.key,
      'p_format': format.key,
      'p_format_label':
          '${format == TournamentFormat.knockout ? 'Knockout' : 'Group play'} · $short',
      'p_entry_type': entryType.key,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
      'p_registration_limit': registrationLimit,
      'p_entry_fee': entryFee,
      'p_match_rules': rulesSummary,
      'p_rules': rules,
      'p_publish_now': publishNow,
    }, fallback: 'The tournament could not be created.');
    await reload();
  }

  @override
  void setTournamentStatus(String tournamentId, TournamentStatus status) {
    // Screens call this synchronously; the RPC answers later and the list is
    // re-read, so the change appears without blocking the tap.
    unawaited(
      _call(
        'set_tournament_status',
        {'p_tournament_id': tournamentId, 'p_status': status.key},
        fallback: 'The tournament status could not be changed.',
      ).then((_) => reload()),
    );
  }

  @override
  Future<void> submitEntry({
    required String tournamentId,
    String? squadId,
    List<String>? memberIds,
  }) async {
    final me = _uid;
    if (me == null) {
      throw const TournamentRepositoryException(
        'Sign in to enter a tournament.',
      );
    }
    if (myEntryFor(tournamentId) != null) return;
    final members = <String>{me, ...?memberIds}.toList();
    await _call('register_tournament_entry', {
      'p_tournament_id': tournamentId,
      'p_label': _entryLabel(members),
      'p_member_ids': members,
      'p_squad_id': squadId,
    }, fallback: 'The entry could not be submitted.');
    await reload();
  }

  /// The same rule the device store uses: a solo entry is the player's name, a
  /// multi-player entry a slash list of first names.
  String _entryLabel(List<String> members) {
    final names = members
        .map((m) => _accounts?.accountById(m)?.displayName.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return 'Entry';
    if (names.length == 1) return names.first;
    return names.map((n) => n.split(' ').first).join(' / ');
  }

  @override
  Future<void> withdrawEntry(String entryId) async {
    await _call('withdraw_tournament_entry', {
      'p_entry_id': entryId,
    }, fallback: 'The entry could not be withdrawn.');
    await reload();
  }

  @override
  Future<void> decideEntry(
    String entryId, {
    required bool approve,
    String? note,
  }) async {
    await _call('decide_tournament_entry', {
      'p_entry_id': entryId,
      'p_approve': approve,
      'p_note': note,
    }, fallback: 'The entry could not be reviewed.');
    await reload();
  }

  @override
  Future<int> generateDraw(String tournamentId) async {
    final created = await _call<int>('generate_tournament_draw', {
      'p_tournament_id': tournamentId,
    }, fallback: 'The draw could not be published.');
    await reload();
    return created;
  }

  // ── Plumbing ────────────────────────────────────────────────────────────

  Future<T> _call<T>(
    String function,
    Map<String, dynamic> params, {
    required String fallback,
  }) async {
    try {
      return await _client.rpc<T>(function, params: params);
    } catch (error) {
      throw TournamentRepositoryException(
        _message(error, fallback),
        code: error is PostgrestException ? error.code : null,
      );
    }
  }

  /// Server guards read like `not_tournament_organizer`, which a member cannot
  /// act on: the fallback leads, the guard only helps support.
  String _message(Object error, String fallback) =>
      error is PostgrestException ? '$fallback (${error.message})' : fallback;

  // ── Realtime ────────────────────────────────────────────────────────────

  /// Subscribes once, on the first signed-in read. Any change to either table
  /// re-reads the whole list: the server stays the source of truth and the
  /// callback only saves the manual pull-up.
  void _ensureRealtime() {
    if (_uid == null || _channel != null) return;
    final channel = _client
        .channel('tournaments')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tournaments',
          callback: (_) => unawaited(reload()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tournament_entries',
          callback: (_) => unawaited(reload()),
        );
    _channel = channel;
    channel.subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _channel = null;
    super.dispose();
  }

  Tournament _tournamentFromRow(Map<String, dynamic> row) =>
      Tournament.fromJson({
        'id': row['id'],
        'organizerId': row['organizer_id'],
        'name': row['name'],
        'city': row['city'],
        'sport': row['sport_key'],
        'formatLabel': row['format_label'],
        'format': row['format'],
        'entryType': row['entry_type'],
        'startsAt': row['starts_at'],
        'endsAt': row['ends_at'],
        'registrationLimit': row['registration_limit'],
        'entryFee': row['entry_fee'],
        'matchRules': row['match_rules'],
        'rules': row['rules'] ?? const <String, dynamic>{},
        'bannerUrl': row['banner_url'],
        'status': row['status'],
        'createdAt': row['created_at'],
        'isDemo': row['is_demo'] ?? false,
      });

  Entry _entryFromRow(Map<String, dynamic> row, String tournamentId) =>
      Entry.fromJson({
        'id': row['id'],
        'tournamentId': row['tournament_id'] ?? tournamentId,
        'squadId': row['squad_id'],
        'captainAccountId': row['captain_id'],
        'label': row['label'],
        'memberAccountIds': (row['member_ids'] as List<dynamic>? ?? const [])
            .cast<String>(),
        'status': row['status'],
        'submittedAt': row['created_at'],
        'decisionNote': row['decision_note'],
        'isDemo': row['is_demo'] ?? false,
      });

  static List<Map<String, dynamic>> _embeddedList(Object? value) =>
      (value as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
}
