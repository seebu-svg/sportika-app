import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/models/enums.dart';

/// Community pickup games, read from PostgreSQL.
///
/// A game is a lightweight object whose only write paths are "publish" and
/// "join/leave" (migration 0016), so this repository stays small: one bounded
/// read of the coming week, and two RPCs. The list is painted optimistically
/// and rolled back if the server refuses, because both call sites are taps that
/// must answer immediately.
class SupabaseGameRepository extends ChangeNotifier implements GameRepository {
  SupabaseGameRepository({
    required SupabaseClient client,
    // A named parameter cannot be a private initializing formal.
    // ignore: prefer_initializing_formals
  }) : _client = client;

  final SupabaseClient _client;

  /// The roster rides along, so a rail can show "8/10 joined" without a second
  /// query per card.
  static const String _select = '*, community_game_members(profile_id, status)';

  /// Games older than this are history, not discovery.
  static const Duration _window = Duration(days: 2);
  static const int _rowLimit = 100;

  List<CommunityGame> _games = <CommunityGame>[];
  bool _loading = false;
  String? _lastError;

  @override
  bool get loading => _loading;

  @override
  String? get lastError => _lastError;

  @override
  Future<void> refresh() => reload();

  @override
  List<CommunityGame> get games => List<CommunityGame>.unmodifiable(_games);

  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<void> reload() async {
    if (_uid == null) {
      _games = <CommunityGame>[];
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final rows = await _client
          .from('community_games')
          .select(_select)
          .gte('at', DateTime.now().subtract(_window).toUtc().toIso8601String())
          .order('at', ascending: true)
          .limit(_rowLimit);
      _games = [
        for (final row in rows.cast<Map<String, dynamic>>()) _gameFromRow(row),
      ];
      _lastError = null;
    } catch (error) {
      _lastError = error is PostgrestException
          ? 'Pickup games could not be loaded (${error.message})'
          : 'Pickup games could not be loaded.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void publishGame(CommunityGame game) {
    // The organizer sees their game immediately; the server row replaces the
    // optimistic one on the reload that follows.
    _games = <CommunityGame>[game, ..._games];
    notifyListeners();
    unawaited(
      _write(
        'create_community_game',
        {
          'p_title': game.title,
          'p_sport_key': game.sport.key,
          'p_venue': game.venue,
          'p_at': game.at.toUtc().toIso8601String(),
          'p_capacity': game.capacity,
          'p_category': game.category,
          'p_format': game.format,
          'p_description': game.description,
          'p_visibility': game.visibility,
        },
        rollback: () => _games = _games.where((g) => g.id != game.id).toList(),
      ),
    );
  }

  @override
  void toggleGameJoin(CommunityGame game) {
    final me = _uid;
    if (me == null) return;
    final joined = game.members.contains(me);
    if (!joined && game.full) return;

    // Optimistic membership, then the RPC decides for real: it re-checks the
    // capacity under a row lock, which is what stops two taps taking one seat.
    final next = CommunityGame(
      id: game.id,
      title: game.title,
      sport: game.sport,
      venue: game.venue,
      at: game.at,
      capacity: game.capacity,
      organizerId: game.organizerId,
      category: game.category,
      format: game.format,
      description: game.description,
      visibility: game.visibility,
      isDemo: game.isDemo,
      members: joined
          ? (List<String>.from(game.members)..remove(me))
          : (List<String>.from(game.members)..add(me)),
    );
    _games = [for (final g in _games) g.id == game.id ? next : g];
    notifyListeners();
    unawaited(
      _write(
        'toggle_game_join',
        {'p_game_id': game.id},
        rollback: () =>
            _games = [for (final g in _games) g.id == game.id ? game : g],
      ),
    );
  }

  /// Runs one RPC, then re-reads. A refusal restores the painted list so a
  /// member never keeps a seat the server never granted.
  Future<void> _write(
    String function,
    Map<String, dynamic> params, {
    required void Function() rollback,
  }) async {
    try {
      await _client.rpc<void>(function, params: params);
      await reload();
    } catch (error) {
      rollback();
      _lastError = error is PostgrestException
          ? 'That change was not saved (${error.message})'
          : 'That change was not saved.';
      notifyListeners();
    }
  }

  CommunityGame _gameFromRow(Map<String, dynamic> row) => CommunityGame(
    id: row['id'] as String,
    title: row['title'] as String? ?? '',
    sport: SportX.fromKey(row['sport_key'] as String? ?? 'cricket'),
    venue: row['venue'] as String? ?? '',
    at: DateTime.tryParse(row['at'] as String? ?? '') ?? DateTime.now(),
    capacity: (row['capacity'] as num?)?.toInt() ?? 10,
    organizerId: row['organizer_id'] as String? ?? '',
    category: row['category'] as String? ?? 'Friendly',
    format: row['format'] as String? ?? 'Standard',
    description: row['description'] as String? ?? '',
    visibility: row['visibility'] as String? ?? 'Public',
    isDemo: row['is_demo'] as bool? ?? false,
    members: [
      for (final member
          in (row['community_game_members'] as List<dynamic>? ?? const []))
        if ((member as Map)['status'] != 'invited')
          member['profile_id'] as String,
    ],
  );
}
