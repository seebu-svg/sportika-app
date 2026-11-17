import 'package:sportika/shared/models/match.dart';

/// Match lineups use registered profile IDs; names are only display labels.
abstract final class FutsalRoster {
  static Set<String> starters(SportMatch match, int side) {
    final configured = match.rules['lineups'];
    var ids = configured is List && configured.length > side
        ? Set<String>.from(configured[side] as List)
        : <String>{};
    for (final event in match.events.where(
      (e) => !e.voided && e.side == side,
    )) {
      if (event.kind == 'lineup' && event.data['players'] is List) {
        ids = Set<String>.from(event.data['players'] as List);
      }
    }
    final accepted = match
        .participantsOnSide(side)
        .map((p) => p.profileId)
        .toSet();
    return ids.intersection(accepted);
  }

  static Set<String> onCourt(SportMatch match, int side) {
    final ids = starters(match, side);
    for (final event in match.events.where(
      (e) => !e.voided && e.side == side,
    )) {
      if (event.kind == 'substitution') {
        ids.remove(event.data['outId']);
        final incoming = event.data['inId'];
        if (incoming is String) ids.add(incoming);
      }
      if (event.kind == 'card' && event.data['colour'] == 'red') {
        ids.remove(event.data['playerId']);
      }
    }
    return ids;
  }
}
