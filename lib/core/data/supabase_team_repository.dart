import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sportika/core/data/profile_directory.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';

/// Teams, pairs and singles, read from PostgreSQL.
///
/// A squad is the entry a player registers a tournament with, so its roster is
/// the thing that matters: the nested read brings every member row, and the
/// accepted/invited split is restored from `status` exactly as the device store
/// keeps it in two lists.
///
/// Roster writes are RPCs from migrations 0016 and 0019. Only the captain may
/// invite, remove or transfer; a member may answer an invitation or leave. The
/// server enforces that, and this class only mirrors it optimistically so a tap
/// paints before the round trip finishes.
class SupabaseTeamRepository extends ChangeNotifier implements TeamRepository {
  SupabaseTeamRepository({
    required SupabaseClient client,
    required ProfileDirectory directory,
    AccountRepository? accounts,
    // Named parameters cannot be private initializing formals.
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _directory = directory,
       // ignore: prefer_initializing_formals
       _accounts = accounts;

  final SupabaseClient _client;

  /// Members of a squad are people, and a roster has to name them.
  final ProfileDirectory _directory;

  final AccountRepository? _accounts;

  /// One app-level channel over `teams` and `team_members`, so a second
  /// device sees invitations, answers and removals without a manual refresh.
  /// No filters: the publication already carries both tables (0019 added
  /// team_members) and RLS scopes the rows the socket receives. Created
  /// lazily on the first signed-in reload, torn down in [dispose].
  RealtimeChannel? _channel;

  /// A roster is public discovery, so the embed is allowed to name everyone.
  static const String _select =
      '*, team_members(profile_id, status, invited_by)';
  static const int _rowLimit = 200;

  List<Squad> _squads = <Squad>[];
  bool _loading = false;
  String? _lastError;

  @override
  bool get loading => _loading;

  @override
  String? get lastError => _lastError;

  @override
  Future<void> refresh() => reload();

  @override
  String? get currentAccountId =>
      _accounts?.currentAccount?.id ?? _client.auth.currentUser?.id;

  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<void> reload() async {
    if (_uid == null) {
      _squads = <Squad>[];
      notifyListeners();
      return;
    }
    _ensureRealtime();
    _loading = true;
    notifyListeners();
    try {
      final rows = await _client
          .from('teams')
          .select(_select)
          .order('created_at', ascending: false)
          .limit(_rowLimit);
      final squads = [
        for (final row in rows.cast<Map<String, dynamic>>()) _squadFromRow(row),
      ];
      _squads = squads;
      _lastError = null;
    } catch (error) {
      _lastError = error is PostgrestException
          ? 'Teams could not be loaded (${error.message})'
          : 'Teams could not be loaded.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Read ────────────────────────────────────────────────────────────────

  @override
  List<Squad> get squads => List<Squad>.unmodifiable(_squads);

  @override
  List<Squad> get mySquads {
    final id = currentAccountId;
    return _squads.where((s) => s.ownerId == id).toList();
  }

  @override
  List<Squad> squadsFor(Sport sport, EntryType type) =>
      mySquads.where((s) => s.sport == sport && s.type == type).toList();

  @override
  List<Squad> squadsOf(String accountId) =>
      _squads.where((s) => s.memberAccountIds.contains(accountId)).toList();

  @override
  Squad? squadById(String id) => _squads.where((s) => s.id == id).firstOrNull;

  /// The signed-in member plus the public directory. Roster screens search it.
  @override
  List<Account> get accounts => _accounts?.accounts ?? _directory.accounts;

  @override
  List<Account> get otherPlayers =>
      accounts.where((a) => a.id != currentAccountId).toList();

  // ── Write ───────────────────────────────────────────────────────────────

  @override
  Squad createSquad({
    required String name,
    required Sport sport,
    required EntryType type,
    required List<String> memberIds,
  }) {
    final owner = currentAccountId;
    if (owner == null) throw StateError('Sign in to create a team');

    // The server mints the real id; this local one only has to be unique until
    // the reload lands, and the id is what every screen keys off meanwhile.
    // The server turns picks into invitations (0019), so the optimistic
    // roster keeps only the captain and paints the picks as pending.
    final squad = Squad(
      id: 'team-${DateTime.now().microsecondsSinceEpoch}',
      ownerId: owner,
      name: name.trim(),
      sport: sport,
      type: type,
      memberAccountIds: [owner],
      invitedAccountIds: <String>[
        for (final id in memberIds)
          if (id != owner) id,
      ],
      createdAt: DateTime.now(),
    );
    _squads = <Squad>[squad, ..._squads];
    notifyListeners();
    unawaited(
      _write('create_team', {
        'p_name': squad.name,
        'p_sport_key': sport.key,
        'p_type': type.key,
        'p_member_ids': squad.memberAccountIds,
      }),
    );
    return squad;
  }

  @override
  void addSquadMember(String squadId, String accountId) =>
      inviteToSquad(squadId, accountId);

  @override
  void removeSquadMember(String squadId, String accountId) {
    _patch(squadId, (s) {
      s.memberAccountIds.remove(accountId);
      s.invitedAccountIds.remove(accountId);
    });
    unawaited(
      _write('remove_team_member', {
        'p_team_id': squadId,
        'p_profile_id': accountId,
      }),
    );
  }

  @override
  void inviteToSquad(String squadId, String accountId) {
    _patch(squadId, (s) {
      if (!s.memberAccountIds.contains(accountId) &&
          !s.invitedAccountIds.contains(accountId)) {
        s.invitedAccountIds.add(accountId);
      }
    });
    unawaited(
      _write('invite_team_member', {
        'p_team_id': squadId,
        'p_profile_id': accountId,
      }),
    );
  }

  @override
  void cancelSquadInvite(String squadId, String accountId) {
    _patch(squadId, (s) => s.invitedAccountIds.remove(accountId));
    unawaited(
      _write('remove_team_member', {
        'p_team_id': squadId,
        'p_profile_id': accountId,
      }),
    );
  }

  @override
  void respondToSquadInvite(
    String squadId,
    String accountId, {
    required bool accept,
  }) {
    _patch(squadId, (s) {
      s.invitedAccountIds.remove(accountId);
      if (accept && !s.memberAccountIds.contains(accountId)) {
        s.memberAccountIds.add(accountId);
      }
    });
    unawaited(
      _write('respond_team_invite', {'p_team_id': squadId, 'p_accept': accept}),
    );
  }

  @override
  void transferCaptain(String squadId, String accountId) {
    unawaited(
      _write('transfer_team_captain', {
        'p_team_id': squadId,
        'p_profile_id': accountId,
      }),
    );
  }

  @override
  void leaveSquad(String squadId) {
    unawaited(_write('leave_team', {'p_team_id': squadId}));
  }

  @override
  void deleteSquad(String squadId) {
    _squads = _squads.where((s) => s.id != squadId).toList();
    notifyListeners();
    unawaited(_write('delete_team', {'p_team_id': squadId}));
  }

  /// Paints one squad through [change], then re-reads. Used for roster edits so
  /// the list reacts to the tap instead of to the round trip.
  void _patch(String squadId, void Function(Squad squad) change) {
    final next = <Squad>[];
    for (final squad in _squads) {
      if (squad.id == squadId) change(squad);
      next.add(squad);
    }
    _squads = next;
    notifyListeners();
  }

  Future<void> _write(String function, Map<String, dynamic> params) async {
    try {
      await _client.rpc<void>(function, params: params);
      await reload();
    } catch (error) {
      _lastError = error is PostgrestException
          ? 'That team change was not saved (${error.message})'
          : 'That team change was not saved.';
      notifyListeners();
      // Put the roster back where the server says it is.
      await reload();
    }
  }

  // ── Realtime ────────────────────────────────────────────────────────

  /// Subscribes once, on the first signed-in read. Any change to either table
  /// re-reads the whole list: the server stays the source of truth and the
  /// callback only saves the manual pull-up.
  void _ensureRealtime() {
    if (_uid == null || _channel != null) return;
    final channel = _client
        .channel('teams')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'teams',
          callback: (_) => unawaited(reload()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'team_members',
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

  Squad _squadFromRow(Map<String, dynamic> row) {
    final members = <String>[];
    final invited = <String>[];
    for (final member in (row['team_members'] as List<dynamic>? ?? const [])) {
      final map = Map<String, dynamic>.from(member as Map);
      final id = map['profile_id'] as String?;
      if (id == null) continue;
      (map['status'] == 'invited' ? invited : members).add(id);
    }
    return Squad(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      sport: SportX.fromKey(row['sport_key'] as String? ?? 'cricket'),
      type: EntryTypeX.fromKey(row['type'] as String? ?? 'team'),
      memberAccountIds: members,
      invitedAccountIds: invited,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      isDemo: row['is_demo'] as bool? ?? false,
    );
  }
}
